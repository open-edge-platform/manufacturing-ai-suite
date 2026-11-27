# Example prompt: quick Docker Compose deploy + smoke test

> Quickly build and deploy the weld defect detection app with Docker Compose
> (default variant), then run a smoke test and report whether it's healthy.

Expected agent flow:
1. Resolve app root, check `.env` (credentials + IPv4 `HOST_IP`), run Docker preflight.
2. `make build`
3. `make up`
4. `<skill-dir>/scripts/smoke-check.sh`
5. Report real command output and a clear PASS/FAIL summary.
6. Offer `make down` for cleanup.
