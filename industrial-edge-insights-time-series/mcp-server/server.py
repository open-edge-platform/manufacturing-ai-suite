# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

"""Authenticated MCP access to wind-turbine analytics and stored results."""

import asyncio
import base64
import binascii
import copy
import io
import json
import logging
import math
import os
import secrets
import tarfile
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated, Any, Literal
from urllib.parse import urlsplit

import httpx
from fastmcp import FastMCP
from fastmcp.exceptions import ToolError
from pydantic import BaseModel, ConfigDict, Field
from starlette.datastructures import Headers
from starlette.middleware import Middleware
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

LOGGER = logging.getLogger(__name__)
APP_NAME = "wind-turbine-anomaly-detection"
RAW_MEASUREMENT = "wind-turbine-data"
RESULT_MEASUREMENT = "wind-turbine-anomaly-data"
SEVERITIES = {"normal": 0.0, "low": 0.3, "medium": 0.6, "high": 1.0}
Page = Annotated[int, Field(ge=1, le=10000)]
PageSize = Annotated[int, Field(ge=1, le=100)]
Severity = Literal["all", "anomaly", "normal", "low", "medium", "high"]
Source = Annotated[str, Field(min_length=1, max_length=128, pattern=r"^[A-Za-z0-9_.:-]+$")]


@dataclass(frozen=True)
class Settings:  # pylint: disable=too-many-instance-attributes
    """Operator-controlled backend addresses and credentials."""

    username: str
    password: str = field(repr=False)
    influx_username: str
    influx_password: str = field(repr=False)
    public_url: str
    analytics_url: str = "http://ia-time-series-analytics-microservice:5000"
    kapacitor_url: str = "http://ia-time-series-analytics-microservice:9092"
    influx_url: str = "http://ia-influxdb:8086"
    config_dir: Path = (
        Path(__file__).resolve().parents[1] / "apps" / APP_NAME / "time-series-analytics-config"
    )
    mode: Literal["stream", "batch"] = "stream"
    ready_timeout: float = 120

    def __post_init__(self):
        if not all((self.username, self.password, self.influx_username, self.influx_password)):
            raise ValueError(
                "MCP_USERNAME, MCP_PASSWORD, INFLUXDB_USERNAME and INFLUXDB_PASSWORD are required"
            )
        if ":" in self.username or len(self.username) > 128 or not 10 <= len(self.password) <= 1024:
            raise ValueError(
                "MCP username must exclude ':'; password length must be 10-1024 characters"
            )
        public = urlsplit(self.public_url)
        if public.scheme != "https" or not public.netloc or public.path not in ("", "/"):
            raise ValueError("MCP_PUBLIC_URL must be an HTTPS origin without a path")
        if public.username or public.password or public.query or public.fragment:
            raise ValueError("MCP_PUBLIC_URL must not include credentials, a query or a fragment")
        for url in (self.analytics_url, self.kapacitor_url, self.influx_url):
            parsed = urlsplit(url)
            if (
                parsed.scheme not in ("http", "https")
                or not parsed.netloc
                or parsed.username
                or parsed.password
            ):
                raise ValueError("Backend URLs must be HTTP(S) addresses without credentials")
        if self.mode not in ("stream", "batch"):
            raise ValueError("MCP_PROCESSING_MODE must be stream or batch")

    @classmethod
    def from_env(cls):
        """Read secrets only from the process environment."""
        mode = os.getenv("MCP_PROCESSING_MODE", "stream")
        if mode not in ("stream", "batch"):
            raise ValueError("MCP_PROCESSING_MODE must be stream or batch")
        return cls(
            username=os.getenv("MCP_USERNAME", ""),
            password=os.getenv("MCP_PASSWORD", ""),
            influx_username=os.getenv("INFLUXDB_USERNAME", ""),
            influx_password=os.getenv("INFLUXDB_PASSWORD", ""),
            public_url=os.getenv("MCP_PUBLIC_URL", "https://127.0.0.1:3000").rstrip("/"),
            analytics_url=os.getenv(
                "TIME_SERIES_API_URL", "http://ia-time-series-analytics-microservice:5000"
            ).rstrip("/"),
            kapacitor_url=os.getenv(
                "KAPACITOR_API_URL", "http://ia-time-series-analytics-microservice:9092"
            ).rstrip("/"),
            influx_url=os.getenv("INFLUXDB_URL", "http://ia-influxdb:8086").rstrip("/"),
            config_dir=Path(os.getenv("MCP_CONFIG_DIR", str(cls.config_dir))),
            mode=mode,
        )

    @property
    def task_id(self) -> str:
        """Return the task selected at deployment, not by an MCP caller."""
        return "windturbine_anomaly_detector" + ("_batch" if self.mode == "batch" else "")


class AccessMiddleware:  # pylint: disable=too-few-public-methods
    """Authenticate HTTP connections and restrict browser origins and hosts."""

    def __init__(self, app: ASGIApp, settings: Settings):
        self.app = app
        self.settings = settings

    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        headers = Headers(scope=scope)
        origin = headers.get("origin")
        public_host = urlsplit(self.settings.public_url).netloc
        if headers.get("host") not in (
            public_host,
            "127.0.0.1:8000",
            "time-series-mcp-server:8000",
        ):
            await JSONResponse({"error": "Invalid Host"}, status_code=403)(scope, receive, send)
            return
        if origin is not None and origin != self.settings.public_url:
            await JSONResponse({"error": "Invalid Origin"}, status_code=403)(scope, receive, send)
            return
        if scope["path"] != "/health":
            authorization = headers.get("authorization", "")
            valid = False
            if len(authorization) <= 8192:
                scheme, _, encoded = authorization.partition(" ")
                if scheme.lower() == "basic":
                    try:
                        username, password = base64.b64decode(encoded, validate=True).split(b":", 1)
                        valid_user = secrets.compare_digest(
                            username, self.settings.username.encode()
                        )
                        valid_password = secrets.compare_digest(
                            password, self.settings.password.encode()
                        )
                        valid = valid_user and valid_password
                    except (ValueError, binascii.Error):
                        valid = False
            if not valid:
                await JSONResponse(
                    {"error": "Authentication required"},
                    status_code=401,
                    headers={"WWW-Authenticate": 'Basic realm="time-series-mcp", charset="UTF-8"'},
                )(scope, receive, send)
                return
        await self.app(scope, receive, send)


class AnalyticsError(ToolError):
    """Carry status codes for bounded retries during task activation."""

    def __init__(self, message: str, status_code: int | None = None):
        super().__init__(message)
        self.status_code = status_code


class Window(BaseModel):
    """Validated, absolute query window shared by all data tools."""

    model_config = ConfigDict(extra="forbid")
    start_time: datetime
    end_time: datetime
    source: Source | None = None

    @classmethod
    def resolve(cls, start_time: datetime | None, end_time: datetime | None, source: str | None):
        """Use a 30-minute default and cap all queries at 24 hours."""
        end = end_time if end_time is not None else datetime.now(timezone.utc)
        start = start_time if start_time is not None else end - timedelta(minutes=30)
        if start.tzinfo is None or end.tzinfo is None:
            raise ToolError("Use timezone-aware timestamps, for example 2026-10-24T12:00:00Z")
        if not timedelta(0) < end - start <= timedelta(hours=24):
            raise ToolError("The time window must be positive and no longer than 24 hours")
        return cls(
            start_time=start.astimezone(timezone.utc),
            end_time=end.astimezone(timezone.utc),
            source=source,
        )

    @property
    def clause(self) -> str:
        """Only validated timestamps enter the fixed InfluxQL templates."""
        return f"time >= '{self.start_time.isoformat()}' AND time < '{self.end_time.isoformat()}'"

    @property
    def bindings(self) -> dict[str, str]:
        """Bind source values separately from query text."""
        return {"source": self.source} if self.source is not None else {}

    @property
    def where(self) -> str:
        """Use InfluxDB bind parameters for external string values."""
        return self.clause + (' AND "source" = $source' if self.source is not None else "")


class Backend:
    """Fixed application workflows; no arbitrary query or package interface."""

    def __init__(self, settings: Settings, client: httpx.AsyncClient):
        self.settings = settings
        self.client = client
        self.control_lock = asyncio.Lock()

    async def request(
        self,
        method: str,
        path: str,
        *,
        kapacitor: bool = False,
        accepted_statuses: tuple[int, ...] = (),
        **kwargs: Any,
    ) -> dict[str, Any]:
        """Call the analytics API and expose actionable, sanitized failures."""
        try:
            base_url = self.settings.kapacitor_url if kapacitor else self.settings.analytics_url
            response = await self.client.request(method, base_url + path, **kwargs)
            if response.status_code not in accepted_statuses:
                response.raise_for_status()
            payload = response.json()
        except httpx.HTTPStatusError as error:
            code = error.response.status_code
            LOGGER.warning("Analytics %s %s returned HTTP %s", method, path, code)
            if code == 404:
                raise AnalyticsError(
                    "Analytics endpoint or task unavailable; "
                    "verify the microservice image and deployed UDF task",
                    code,
                ) from error
            raise AnalyticsError(
                f"Analytics request failed (HTTP {code}); "
                "check microservice health and configuration",
                code,
            ) from error
        except httpx.RequestError as error:
            LOGGER.warning("Analytics %s %s unavailable (%s)", method, path, type(error).__name__)
            raise AnalyticsError(
                "Analytics service unavailable; check connectivity and retry"
            ) from error
        except ValueError as error:
            raise ToolError("Analytics service returned invalid JSON") from error
        if not isinstance(payload, dict):
            raise ToolError("Analytics service returned an invalid response")
        return payload

    async def query(self, statements: list[str], window: Window) -> list[list[dict[str, Any]]]:
        """Execute fixed read-only queries and reject InfluxDB error payloads."""
        try:
            response = await self.client.get(
                self.settings.influx_url + "/query",
                params={
                    "db": "datain",
                    "q": ";".join(statements),
                    "params": json.dumps(window.bindings),
                },
                auth=(self.settings.influx_username, self.settings.influx_password),
            )
            response.raise_for_status()
            payload = response.json()
        except httpx.HTTPError as error:
            LOGGER.warning("InfluxDB query failed (%s)", type(error).__name__)
            raise ToolError(
                "InfluxDB query failed; check database connectivity and credentials"
            ) from error
        except ValueError as error:
            raise ToolError("InfluxDB returned invalid JSON") from error
        if not isinstance(payload, dict) or payload.get("error"):
            raise ToolError("InfluxDB rejected the query; check database availability")
        results = payload.get("results")
        if not isinstance(results, list) or len(results) != len(statements):
            raise ToolError("InfluxDB returned an unexpected statement count")
        output = []
        for result in results:
            if not isinstance(result, dict) or result.get("error"):
                raise ToolError("InfluxDB rejected a query; check the application schema")
            rows = []
            for series in result.get("series", []):
                columns = series.get("columns", [])
                for values in series.get("values", []):
                    if len(columns) != len(values):
                        raise ToolError("InfluxDB returned malformed rows")
                    rows.append({**series.get("tags", {}), **dict(zip(columns, values))})
            output.append(rows)
        return output

    async def get_pipeline_status(self) -> dict[str, Any]:
        """Get daemon health and the deployment-selected task state; not hardware utilization."""
        health = await self.request("GET", "/health", accepted_statuses=(503,))
        config = await self.request("GET", "/config", params={"restart": "false"})
        if not config.get("udfs", {}).get("name"):
            return {"health": health, "task_id": self.settings.task_id, "status": "not_configured"}
        self.check_task(config)
        status = await self.task_status()
        return {"health": health, **status}

    def check_task(self, config: dict[str, Any]) -> None:
        """Guard native Kapacitor operations with the configured application task."""
        if config.get("udfs", {}).get("name") != self.settings.task_id:
            raise ToolError(
                "A different UDF task is configured; reconcile it before controlling this task"
            )

    async def task_status(self) -> dict[str, Any]:
        """Use Kapacitor's stable task API, including with older microservice images."""
        task = await self.request(
            "GET", f"/kapacitor/v1/tasks/{self.settings.task_id}", kapacitor=True, timeout=10
        )
        if task.get("id") != self.settings.task_id or task.get("status") not in (
            "enabled",
            "disabled",
        ):
            raise ToolError("Kapacitor returned an unexpected task identity or state")
        return {
            "task_id": task["id"],
            "status": task["status"],
            "execution_error": bool(task.get("error")),
        }

    def package(self) -> bytes:
        """Archive trusted, read-only app assets and alias the batch model in memory."""
        config_dir = self.settings.config_dir
        with io.BytesIO() as buffer:
            with tarfile.open(fileobj=buffer, mode="w", dereference=True) as archive:
                total_size = 0
                for folder in ("udfs", "tick_scripts", "models"):
                    root = config_dir / folder
                    if root.is_symlink() or not root.is_dir():
                        raise ToolError(
                            f"Required application asset directory is missing: {folder}"
                        )
                    for path in sorted(root.rglob("*")):
                        if path.is_symlink():
                            raise ToolError("Application packages must not contain symbolic links")
                        if path.is_file():
                            total_size += path.stat().st_size
                            if total_size > 95 * 1024 * 1024:
                                raise ToolError(
                                    "Application assets exceed the package size budget of 95 MiB"
                                )
                            archive.add(
                                path, arcname=str(path.relative_to(config_dir)), recursive=False
                            )
                if self.settings.mode == "batch":
                    source = config_dir / "models/windturbine_anomaly_detector.pkl"
                    archive.add(
                        source,
                        arcname="models/windturbine_anomaly_detector_batch.pkl",
                        recursive=False,
                    )
            if buffer.tell() > 100 * 1024 * 1024:
                raise ToolError(
                    "Application package exceeds the microservice's 100 MiB upload limit"
                )
            return buffer.getvalue()

    async def start_pipeline(
        self, time_series_inf_device: Literal["CPU", "GPU"] = "CPU"
    ) -> dict[str, Any]:
        """Enable trusted wind-turbine analytics on CPU or GPU. Ingestion is unchanged."""
        async with self.control_lock:
            filename = "config-batch.json" if self.settings.mode == "batch" else "config.json"
            try:
                baseline = json.loads(
                    (self.settings.config_dir / filename).read_text(encoding="utf-8")
                )
                package = await asyncio.to_thread(self.package)
            except (OSError, ValueError, tarfile.TarError) as error:
                LOGGER.error("Application package could not be prepared (%s)", type(error).__name__)
                raise ToolError(
                    "Cannot prepare application assets; verify the read-only configuration mount"
                ) from error
            active = await self.request("GET", "/config", params={"restart": "false"})
            active_task = active.get("udfs", {}).get("name")
            if active_task and active_task != self.settings.task_id:
                raise ToolError(
                    "A different UDF task is configured; "
                    "stop and reconcile it before deploying this task"
                )
            config = copy.deepcopy(baseline)
            if active_task:
                config = copy.deepcopy(active)
                state = await self.task_status()
                if (
                    state.get("status") == "enabled"
                    and not state["execution_error"]
                    and config["udfs"].get("device") == time_series_inf_device
                ):
                    return {"task_id": self.settings.task_id, "status": "enabled", "changed": False}
            config["udfs"]["device"] = time_series_inf_device
            completed = []
            try:
                await self.request(
                    "POST",
                    "/udfs/package",
                    files={"file": (f"{APP_NAME}.tar", package, "application/x-tar")},
                )
                completed.append("package_uploaded")
                await self.request("POST", "/config", json=config)
                completed.append("configuration_applied")
                deadline = asyncio.get_running_loop().time() + self.settings.ready_timeout
                while True:
                    try:
                        state = await self.task_status()
                        if state["execution_error"]:
                            raise ToolError(
                                "The task reports an execution error; check UDF and Kapacitor logs"
                            )
                        if state.get("status") == "enabled":
                            return {
                                **state,
                                "device": time_series_inf_device,
                                "mode": self.settings.mode,
                                "changed": True,
                            }
                    except AnalyticsError as error:
                        if error.status_code not in (None, 404, 502, 503):
                            raise
                        LOGGER.info("Waiting for analytics task activation")
                    if asyncio.get_running_loop().time() >= deadline:
                        raise ToolError("Task did not become enabled before the readiness timeout")
                    await asyncio.sleep(2)
            except ToolError as error:
                raise ToolError(
                    f"Start incomplete; completed stages: {', '.join(completed) or 'none'}. {error}"
                ) from error

    async def stop_pipeline(self) -> dict[str, Any]:
        """Disable analytics only. Containers and ingestion keep running; no replay occurs."""
        async with self.control_lock:
            config = await self.request("GET", "/config", params={"restart": "false"})
            if not config.get("udfs", {}).get("name"):
                return {
                    "task_id": self.settings.task_id,
                    "status": "not_configured",
                    "changed": False,
                }
            self.check_task(config)
            state = await self.task_status()
            if state.get("status") == "disabled":
                return {**state, "changed": False}
            await self.request(
                "PATCH",
                f"/kapacitor/v1/tasks/{self.settings.task_id}",
                kapacitor=True,
                json={"status": "disabled"},
            )
            state = await self.task_status()
            if state.get("status") != "disabled":
                raise ToolError(
                    "Stop requested but the task is not disabled; "
                    "check pipeline status before retrying"
                )
            return {**state, "changed": True}

    async def list_sources(
        self,
        start_time: datetime | None = None,
        end_time: datetime | None = None,
        page: Page = 1,
        page_size: PageSize = 20,
    ) -> dict[str, Any]:
        """List sources observed in a UTC window (default 30 minutes, maximum 24 hours)."""
        window = Window.resolve(start_time, end_time, None)
        rows = (
            await self.query(
                [
                    # Constants, normalized UTC times, integer limits; source uses bind parameters.
                    f'SELECT last("wind_speed") AS "last_wind_speed" '  # nosec B608
                    f'FROM "{RAW_MEASUREMENT}" '
                    f'WHERE {window.clause} GROUP BY "source" '
                    f"SLIMIT {page_size + 1} SOFFSET {(page - 1) * page_size}"
                ],
                window,
            )
        )[0]
        return self.page_result(rows, window, page, page_size)

    @staticmethod
    def page_result(
        rows: list[dict[str, Any]], window: Window, page: int, page_size: int
    ) -> dict[str, Any]:
        """Use a look-ahead row instead of an unbounded total-count query."""
        return {
            "window": window.model_dump(mode="json"),
            "items": rows[:page_size],
            "page": page,
            "page_size": page_size,
            "has_more": len(rows) > page_size,
            "next_page": page + 1 if len(rows) > page_size else None,
        }

    # Explicit arguments keep each filter discoverable in the MCP input schema.
    # pylint: disable-next=too-many-arguments,too-many-positional-arguments
    async def list_insights_data(
        self,
        start_time: datetime | None = None,
        end_time: datetime | None = None,
        source: Source | None = None,
        severity: Severity = "all",
        page: Page = 1,
        page_size: PageSize = 20,
    ) -> dict[str, Any]:
        """List processed points. Classification codes: normal=0, low=.3, medium=.6, high=1."""
        window = Window.resolve(start_time, end_time, source)
        where = window.where
        if severity == "anomaly":
            where += " AND anomaly_status > 0"
        elif severity in SEVERITIES:
            where += f" AND anomaly_status = {SEVERITIES[severity]}"
        rows = (
            await self.query(
                [
                    # Constant fields and validated filters/times/limits; source uses bindings.
                    f'SELECT "source","wind_speed","grid_active_power",'  # nosec B608
                    '"anomaly_status","analytic",'
                    f'"processing_time","end_end_time" FROM "{RESULT_MEASUREMENT}" WHERE {where} '
                    f"ORDER BY time DESC LIMIT {page_size + 1} OFFSET {(page - 1) * page_size}"
                ],
                window,
            )
        )[0]
        for row in rows:
            code = row.get("anomaly_status")
            row["severity"] = next(
                (name for name, value in SEVERITIES.items() if code == value), "unknown"
            )
            row["analysis_performed"] = (
                None if row.get("analytic") is None else bool(row["analytic"])
            )
            row["processing_time_seconds"] = self.seconds(row.pop("processing_time", None))
            row["end_to_end_time_seconds"] = self.seconds(row.pop("end_end_time", None))
        return self.page_result(rows, window, page, page_size)

    @staticmethod
    def seconds(value: float | None) -> float | None:
        """Preserve missing timing values instead of substituting zero."""
        return value / 1_000_000_000 if value is not None and math.isfinite(value) else None

    async def get_anomaly_summary(
        self,
        start_time: datetime | None = None,
        end_time: datetime | None = None,
        source: Source | None = None,
    ) -> dict[str, Any]:
        """Count classifications in a UTC window, separating unanalysed from analysed points."""
        window = Window.resolve(start_time, end_time, source)
        predicates = ["", " AND analytic = 1", " AND anomaly_status > 0"]
        predicates.extend(f" AND anomaly_status = {code}" for code in (0.3, 0.6, 1.0))
        results = await self.query(
            [
                # Constant identifiers/predicates, normalized times; source uses bindings.
                f'SELECT count("wind_speed") AS "count" '  # nosec B608
                f'FROM "{RESULT_MEASUREMENT}" '
                f"WHERE {window.where}{predicate}"
                for predicate in predicates
            ],
            window,
        )
        counts = [int(rows[0].get("count") or 0) if rows else 0 for rows in results]
        processed, analysed, anomalous, low, medium, high = counts
        return {
            "window": window.model_dump(mode="json"),
            "processed_points": processed,
            "analysed_points": analysed,
            "unanalysed_points": processed - analysed,
            "anomalous_points": anomalous,
            "low": low,
            "medium": medium,
            "high": high,
            "anomaly_percentage": 100 * anomalous / analysed if analysed else None,
            "percentage_denominator": "analysed_points",
            "has_data": processed > 0,
        }

    async def get_processing_metrics(
        self,
        start_time: datetime | None = None,
        end_time: datetime | None = None,
        source: Source | None = None,
    ) -> dict[str, Any]:
        """Get counts, window-average points/minute, mean seconds, and last-observed UTC times."""
        window = Window.resolve(start_time, end_time, source)
        results = await self.query(
            [
                # Measurement is from a constant tuple; times normalized, source bound.
                f'SELECT count("wind_speed") AS "count" '  # nosec B608
                f'FROM "{measurement}" WHERE {window.where}'
                for measurement in (RAW_MEASUREMENT, RESULT_MEASUREMENT)
            ]
            + [
                # Constant identifiers, normalized times; source uses bindings.
                'SELECT mean("processing_time") AS "processing",'  # nosec B608
                'mean("end_end_time") AS "e2e" '
                f'FROM "{RESULT_MEASUREMENT}" WHERE {window.where} AND analytic = 1',
                *[
                    # Constant measurement; source bound, times normalized.
                    f'SELECT "wind_speed" FROM "{measurement}" '  # nosec B608
                    f"WHERE {window.where} ORDER BY time DESC LIMIT 1"
                    for measurement in (RAW_MEASUREMENT, RESULT_MEASUREMENT)
                ],
            ],
            window,
        )
        ingested, processed = [
            int(rows[0].get("count") or 0) if rows else 0 for rows in results[:2]
        ]
        latency = results[2][0] if results[2] else {}
        minutes = (window.end_time - window.start_time).total_seconds() / 60
        return {
            "window": window.model_dump(mode="json"),
            "ingested_points": ingested,
            "processed_points": processed,
            "ingestion_points_per_minute": ingested / minutes,
            "processing_points_per_minute": processed / minutes,
            "rate_definition": "count divided by requested window duration in minutes",
            "mean_processing_seconds": self.seconds(latency.get("processing")),
            "mean_end_to_end_seconds": self.seconds(latency.get("e2e")),
            "last_ingested_time": results[3][0]["time"] if results[3] else None,
            "last_processed_time": results[4][0]["time"] if results[4] else None,
            "has_data": ingested > 0 or processed > 0,
            "retention_note": (
                "Counts cover retained data only; the stack defaults to one-hour retention."
            ),
        }


def create_server(settings: Settings, client: httpx.AsyncClient | None = None) -> FastMCP:
    """Create the MCP application with one shared, bounded HTTP client."""
    http_client = client or httpx.AsyncClient(
        timeout=httpx.Timeout(180, connect=5),
        trust_env=False,
        follow_redirects=False,
    )
    backend = Backend(settings, http_client)

    @asynccontextmanager
    async def lifespan(_server):
        try:
            yield {}
        finally:
            if client is None:
                await http_client.aclose()

    server = FastMCP(
        "Time-series Wind Turbine Analytics",
        lifespan=lifespan,
        strict_input_validation=True,
        mask_error_details=True,
    )
    for name in (
        "get_pipeline_status",
        "start_pipeline",
        "stop_pipeline",
        "list_sources",
        "list_insights_data",
        "get_anomaly_summary",
        "get_processing_metrics",
    ):
        read_only = name not in ("start_pipeline", "stop_pipeline")
        server.tool(
            getattr(backend, name),
            annotations={
                "readOnlyHint": read_only,
                "destructiveHint": not read_only,
                "idempotentHint": True,
                "openWorldHint": True,
            },
        )

    @server.tool(
        annotations={
            "readOnlyHint": True,
            "idempotentHint": True,
            "openWorldHint": False,
        }
    )
    async def describe() -> dict[str, Any]:
        """Describe tools, data semantics, processing mode, and operational limitations."""
        tools = await server.list_tools()
        return {
            "name": "Wind Turbine Anomaly Detection",
            "app": APP_NAME,
            "processing_mode": settings.mode,
            "task_id": settings.task_id,
            "tools": [
                {
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.parameters,
                }
                for tool in tools
            ],
            "severity_codes": SEVERITIES,
            "guidance": [
                "All MCP connections require HTTP Basic authentication over verified HTTPS.",
                "Stopping analytics does not stop ingestion; streaming data is not replayed.",
                "Batch results use a 20-minute window.",
                "Severity codes are not confidence scores. Model predictions are advisory.",
                "No vision, fusion, LLM explanation, host control, "
                "or arbitrary queries are exposed.",
            ],
        }

    @server.custom_route("/health", methods=["GET"])
    async def health(_request):
        return JSONResponse({"status": "ok"})

    return server


def create_http_app(settings: Settings):
    """Expose authenticated Streamable HTTP; leave liveness internal to Compose."""
    return create_server(settings).http_app(
        path="/mcp",
        stateless_http=True,
        middleware=[Middleware(AccessMiddleware, settings=settings)],
    )


if __name__ == "__main__":
    import uvicorn

    logging.basicConfig(level=logging.INFO)
    # Container-only port, not published; nginx provides authenticated HTTPS.
    uvicorn.run(
        create_http_app(Settings.from_env()),
        host="0.0.0.0",  # nosec B104
        port=8000,
        access_log=False,
    )
