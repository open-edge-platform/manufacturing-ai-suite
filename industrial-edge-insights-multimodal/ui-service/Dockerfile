# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

FROM python:3.14-slim

LABEL org.opencontainers.image.title="Multimodal Weld Defect Detection UI"
LABEL org.opencontainers.image.description="Fusion insights workbench and agentic weld quality analysis UI"
LABEL org.opencontainers.image.vendor="Intel Corporation"

WORKDIR /app

RUN apt-get update && \
  apt-get install -y --no-install-recommends --only-upgrade zlib1g libc-bin libc6 && \
  rm -rf /var/lib/apt/lists/*

RUN groupadd -r appuser && useradd -r -g appuser -u 1001 appuser

COPY requirements.txt .
RUN pip install --no-cache-dir --no-compile -r requirements.txt && \
    python -m pip uninstall -y pip

COPY src/ ./src/

RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 5003

CMD ["uvicorn", "src.app:app", "--host", "0.0.0.0", "--port", "5003", "--workers", "1"]
