# SPDX-FileCopyrightText: (C) 2026 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

# Example prompt: functional tests

> Run the multimodal weld defect detection functional tests on CPU and tell
> me if anything failed.

Expected agent flow:
1. Resolve app root, run Docker preflight.
2. Warn that the tests overwrite `.env` credentials and `HOST_IP`; offer to
   back up `.env` first (`cp .env .env.bak`).
3. `.github/skills/multimodal-deploy/scripts/run-functional-tests.sh cpu`
4. Summarize pytest PASS/FAIL counts and name any failing tests.
5. Offer `make down` for cleanup and restoring the `.env` backup.
