# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

FROM python:3.14-slim

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/tmp

RUN apt-get update && \
  apt-get install -y --no-install-recommends --only-upgrade zlib1g libc-bin libc6 && \
  rm -rf /var/lib/apt/lists/*

RUN groupadd --system appuser && useradd --system --gid appuser --uid 1001 appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && python -m pip uninstall -y pip

COPY server.py /app/mcp-server/server.py

USER appuser
EXPOSE 8000
CMD ["python", "/app/mcp-server/server.py"]
