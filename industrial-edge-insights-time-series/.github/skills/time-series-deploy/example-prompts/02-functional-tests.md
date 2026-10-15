# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Example prompt: functional tests

> Run the wind turbine anomaly detection functional tests and tell me if
> anything failed.

Expected agent flow:
1. Resolve app root, run Docker preflight.
2. Warn that the tests overwrite the `.env` credentials; offer to back up
   `.env` first (`cp .env .env.bak`).
3. `.github/skills/time-series-deploy/scripts/run-functional-tests.sh default`
4. Summarize pytest PASS/FAIL counts and name any failing tests.
5. Offer `make down` for cleanup and restoring the `.env` backup.
