# open-design (Dokploy)

Custom image based on `docker.io/vanjayak/open-design:latest` with ARM64 compat
(`libc6-compat`, `gcompat`) plus global `vela` and `opencode` CLIs on the system PATH.

## Deploy (Dokploy Compose)

1. Create a **Compose** service pointed at this repo (`docker-compose.yml` at root), branch `main`.
2. In Dokploy > Application > Environment set:
   - `OD_ALLOWED_ORIGINS=https://spidmax.win`
   - `OD_API_TOKEN=<secret>`
3. Attach domain + deploy. TLS is terminated by Dokploy/Traefik.

Local build: `docker compose build` (requires Docker; not available in this sandbox).
