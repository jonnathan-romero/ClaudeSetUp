---
name: docker
description: Author and debug Docker and docker-compose setups — write Dockerfiles, compose.yaml, .dockerignore, and .env files, scaffold a container setup from scratch, or fix a broken build / container / compose stack. ALWAYS trigger when the user mentions Docker, Dockerfile, `docker build`/`docker run`, docker compose / docker-compose, compose.yaml, "containerize"/"dockerize", multi-stage build, image size, layer cache, HEALTHCHECK, depends_on, named volumes, or symptoms like "build is slow", "image is huge", "container won't start", "service can't reach the database". Do NOT use for Kubernetes/Helm, Docker Swarm, or cloud runtimes (ECS, Cloud Run, Fly). Python/uv is the primary worked example; all templates are otherwise language-agnostic.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(docker *), Bash(hadolint *)
---

# Docker

Write and debug Dockerfiles and docker-compose stacks that are small, reproducible, and safe by default. This skill carries the rules and copy-paste templates for the day-to-day 80%: building images, composing a multi-service stack, running and debugging containers.

## When to use this skill

Use it when the task involves any of:
- Writing or reviewing a **Dockerfile** (or asking why an image is huge / a build is slow).
- Setting up or fixing a **docker-compose** stack (services, volumes, networks, `.env`, secrets).
- **Scaffolding** a container setup — when asked to "containerize"/"dockerize", generate the full set: `Dockerfile`, `compose.yaml`, `.dockerignore`, `.env.example`, then run the [Generation checklist](#generation-checklist).
- **Debugging** a container that won't start, a service that can't reach another, an OOM kill, or a cache that won't hold.

**When NOT to use it** (different tool is the right call):
- **Kubernetes / Helm / k8s manifests** — Compose files don't translate directly; this skill stops at single-host Compose.
- **Docker Swarm** orchestration, or cloud-specific runtimes (ECS, Cloud Run, Fly) — platform-specific, out of scope.
- **Testcontainers / integration-test harnesses** — that's a testing-library concern, not image/compose authoring.

For production hardening beyond the basics here, read `references/security-hardening.md`. For CI/CD pipelines, read `references/ci-cd.md`.

## Quick reference

### Dockerfile instructions

| Instruction | New layer? | Use it for |
|---|---|---|
| `FROM` | — | Base image. Pin `name:tag`; pin by `@sha256:…` digest for production. |
| `RUN` | yes | Build commands. Combine related commands + clean up in **one** `RUN`. |
| `COPY` | yes | Copy local files in. Prefer over `ADD`. |
| `ADD` | yes | Only for a remote URL or auto-extracting a local tar. Otherwise use `COPY`. |
| `WORKDIR` | — | Set an **absolute** working dir (don't `RUN cd`). |
| `ENV` | — | Runtime environment values. **Never secrets.** |
| `ARG` | — | Build-time variable. **Never secrets** (visible in `docker history`). |
| `USER` | — | Drop to a non-root user before the app runs. |
| `EXPOSE` | — | Document a port (does not publish it). |
| `HEALTHCHECK` | — | Liveness probe (see table below). |
| `ENTRYPOINT` | — | Fixed executable. **Exec form** `["…"]`. |
| `CMD` | — | Default args / command. **Exec form** `["…"]`. |

### `docker run` essential flags

| Flag | Meaning |
|---|---|
| `-d` | Detached (background). |
| `-p 127.0.0.1:8000:8000` | Publish a port **to localhost only** (drop the IP only when it must be public). |
| `--env-file .env` / `-e K=V` | Environment. |
| `-v name:/path` | Mount a **named volume**. |
| `--rm` | Remove container on exit (one-shot runs). |
| `--restart unless-stopped` | Restart policy for long-running services. |
| `-m 512m --cpus 1.5` | Memory + CPU limits. |
| `--init` | Proper PID 1 (reaps zombies, forwards signals). |
| `-it` | Interactive + TTY (shells). |

### `docker compose` cheat-sheet

| Command | Purpose |
|---|---|
| `docker compose up -d` | Start the stack detached. |
| `docker compose up --build` | Rebuild images, then start. |
| `docker compose watch` | Live-reload dev mode (uses `develop.watch`). |
| `docker compose down` | Stop + remove containers/networks (`-v` also drops named volumes). |
| `docker compose ps` | Service status (look at the State column). |
| `docker compose logs -f <svc>` | Tail a service's logs. |
| `docker compose exec <svc> sh` | Shell into a running service. |
| `docker compose config` | Render the merged, interpolated config (debug overrides/`.env`). |
| `docker compose --profile <p> up` | Start including services in profile `<p>`. |

Note: `docker compose` (v2, with a space). The legacy `docker-compose` (hyphen) binary is end-of-life.

### Healthcheck `test` by service

| Service | `test` |
|---|---|
| PostgreSQL | `["CMD-SHELL", "pg_isready -U $POSTGRES_USER"]` |
| MySQL / MariaDB | `["CMD", "mysqladmin", "ping", "-h", "127.0.0.1"]` |
| Redis | `["CMD", "redis-cli", "ping"]` |
| MongoDB | `["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]` |
| HTTP app | `["CMD", "curl", "-f", "http://127.0.0.1:8000/health"]` |

> `curl`/`wget` are **not** in `-slim` or distroless images. Install one deliberately, or probe with the language runtime — e.g. `["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"]`. A Compose `healthcheck` **overrides** the image's `HEALTHCHECK`. Note: `mysqladmin ping` returns success even on auth failure (it only proves the server responds); add `-u`/`-p` or use `SELECT 1` for a stricter check.

## Critical rules

These are the mistakes that bite hardest. Each has a one-line reason — the reason is the point, not the imperative.

- **Pin images; never deploy `:latest`.** Tags are mutable (a publisher can repoint them); use a version tag, and pin base images by digest (`FROM python:3.12-slim@sha256:…`) where reproducibility matters. `latest` means "whatever was pushed last", not "newest".
- **Run as a non-root `USER`.** The container shares the host kernel; root inside is a much shorter hop to root outside. Create a user and switch to it before the app starts.
- **Keep secrets out of `ENV` and `ARG`.** Both persist in image layers and show up in `docker history`. Use BuildKit `--mount=type=secret` at build time and Compose `secrets` (mounted at `/run/secrets/<name>`) at runtime.
- **Use exec-form `ENTRYPOINT`/`CMD`** (`["python","-m","app"]`). Shell form runs the app under `/bin/sh -c`, so it never becomes PID 1 — `SIGTERM` from `docker stop` hits the shell, not your app, and you get a 10s hang then `SIGKILL` with no graceful shutdown.
- **Copy dependency manifests and install before copying the rest of the source.** Otherwise any source edit busts the dependency-install layer and every build reinstalls from scratch.
- **Never depend on a service with bare `depends_on: [db]`.** That only waits for "started", not "ready to accept connections". Give the dependency a `healthcheck` and depend with `condition: service_healthy`.
- **Set resource limits and `restart: unless-stopped`** on long-running services. One unbounded container can OOM the whole host; `unless-stopped` survives reboots but respects an intentional stop.
- **No top-level `version:` in compose.yaml.** It's obsolete in the Compose Specification and only earns a warning.
- **Ship a `.dockerignore`.** It shrinks the build context (faster builds) and stops `.env`, `.git`, keys, and `node_modules`/`.venv` from leaking into the image.

## Decision trees

### What shape should the Dockerfile be?

```
Does the app need a build/compile step or build-only tools?
├─ no  → single stage on a slim base (e.g. python:3.12-slim)
└─ yes → MULTI-STAGE: a build stage + a clean runtime stage
         what does the runtime actually need?
         ├─ one static binary (Go/Rust)      → runtime = scratch or distroless/static
         ├─ an interpreter (Python/Node)      → runtime = language -slim image; copy the venv / node_modules
         └─ a shell or system libs at runtime → runtime = debian:slim
```

### A compose service won't start — what's wrong?

```
docker compose ps   →   read the State column
├─ Exited                  → docker compose logs <svc>   (the app crashed; read the actual error)
├─ stuck "Created"/waiting → a depends_on condition isn't satisfied → is the dependency healthy?
│                            (a depends_on: service_healthy needs a healthcheck ON the dependency)
├─ "unhealthy"             → the healthcheck command is failing → run it by hand:
│                            docker compose exec <svc> <the test command>
└─ restart loop            → check the exit code: 137 = OOM (raise the memory limit);
                             otherwise read the logs for an app error
```

## Dockerfile patterns

### Multi-stage structure (generic template)

```dockerfile
# syntax=docker/dockerfile:1
FROM <base>:<version> AS build
WORKDIR /src
COPY <dependency-manifest> ./           # e.g. package.json+lock, go.mod+go.sum, pyproject+lock
RUN <install dependencies>              # cached until the manifest changes
COPY . .
RUN <build the app>

FROM <slim-or-distroless-base>:<version>
RUN <create a non-root user>            # e.g. groupadd/useradd, or adduser -D
WORKDIR /app
COPY --from=build --chown=app:app /src/<artifact> ./
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD <probe http://127.0.0.1:8000/health> || exit 1
ENTRYPOINT ["<executable>", "<arg>"]
```

The shape is always the same: **build stage** (has the toolchain) → copy only the built artifact into a **slim runtime stage** (no toolchain, non-root, health-checked).

### Per-language specifics

Fill the generic template's placeholders per language — copy the manifest first (for cache), install, then run on a minimal runtime base:

| Language | Dependency manifest | Install | Runtime base |
|---|---|---|---|
| Python (uv) | `pyproject.toml` + `uv.lock` | `uv sync --frozen --no-dev` | `python:3.12-slim` |
| Python (pip) | `requirements.txt` | `pip install --no-cache-dir -r requirements.txt` | `python:3.12-slim` |
| Node | `package.json` + lockfile | `npm ci --omit=dev` | `node:22-slim` / distroless `nodejs` |
| Go | `go.mod` + `go.sum` | `go mod download` → `CGO_ENABLED=0 go build` | `scratch` / `distroless/static` |
| Rust | `Cargo.toml` + `Cargo.lock` | `cargo build --release` | `debian:bookworm-slim` |
| Java | `pom.xml` / `build.gradle` | `mvn -o package` / `gradle build` | `eclipse-temurin:21-jre` |
| .NET | `*.csproj` | `dotnet restore` → `dotnet publish -c Release` | `mcr.microsoft.com/dotnet/aspnet:8.0` |

### Python (uv) — primary worked example

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.12-slim AS build
# uv as a static binary; pin the uv version (e.g. :0.5.18) in production
COPY --from=ghcr.io/astral-sh/uv:0.5.18 /uv /uvx /bin/
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
WORKDIR /app

# 1) install ONLY dependencies first, from the lockfile → this layer caches
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

# 2) now copy the source and install the project itself
COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

FROM python:3.12-slim
RUN groupadd -r app && useradd -r -g app app
WORKDIR /app
COPY --from=build --chown=app:app /app /app
ENV PATH="/app/.venv/bin:$PATH"
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" || exit 1
ENTRYPOINT ["python", "-m", "myapp"]
```

Why this is fast and small: `uv sync` runs against a cache mount (no wheels baked into a layer), dependencies install in their own cached step, and the runtime stage is a fresh `-slim` image with only the `.venv` copied in — none of `uv`, build caches, or dev dependencies ship.

### Layer-cache ordering

Order instructions stable-first, volatile-last — a change invalidates that layer and every layer after it:

```
FROM            ← changes rarely
system packages ← changes rarely
dep manifest    ← changes occasionally   ── install deps HERE
dependency install
app source COPY ← changes constantly      ── keep this LAST
build / entrypoint
```

Persist package-manager caches across builds with BuildKit cache mounts instead of baking them in:
`RUN --mount=type=cache,target=/root/.cache/uv uv sync …` (npm → `/root/.npm`, pip → `/root/.cache/pip`, go → `/root/.cache/go-build`, apt → `/var/cache/apt` with `sharing=locked`).

### .dockerignore

```gitignore
.git/
.gitignore
**/__pycache__/
.venv/
node_modules/
dist/
build/
*.log
.env
.env.*
*.pem
*.key
*.crt
.DS_Store
```

## Docker Compose patterns

### Canonical compose.yaml

```yaml
name: myapp                      # explicit project name; NO top-level version:

services:
  app:
    build: .
    image: myapp:1.0.0           # pin a version; not :latest
    restart: unless-stopped
    init: true                   # real PID 1: reaps zombies + forwards SIGTERM
    stop_grace_period: 30s       # drain time before SIGKILL (default 10s)
    env_file: .env
    ports:
      - "127.0.0.1:8000:8000"    # localhost-only unless it must be public
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      # curl/wget aren't in slim/distroless images; probe with the runtime instead
      # (this overrides the Dockerfile's HEALTHCHECK — keep the two consistent)
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
    logging:                     # json-file is unbounded by default — cap it
      driver: json-file
      options: { max-size: "10m", max-file: "3" }

  db:
    image: postgres:16.3
    restart: unless-stopped
    environment:
      POSTGRES_USER: app
      POSTGRES_DB: app
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password   # _FILE convention, not a plaintext value
    secrets:
      - db_password
    volumes:
      - pgdata:/var/lib/postgresql/data                  # named volume for state
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

volumes:
  pgdata:

secrets:
  db_password:
    file: ./secrets/db_password.txt
```

### Development override

Compose auto-merges `compose.override.yaml` on top of `compose.yaml`. Keep dev-only changes here and **git-ignore it** (commit a `compose.override.yaml.example`):

```yaml
services:
  app:
    build:
      target: build              # stop at the build stage (has the toolchain)
    # the build stage has no ENTRYPOINT/CMD of its own — give it a dev run command
    command: ["uv", "run", "uvicorn", "myapp.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
    environment:
      DEBUG: "1"
    develop:
      watch:
        - path: ./myapp          # sync source changes into the container live
          target: /app/myapp
          action: sync
        - path: pyproject.toml   # dependency change → full rebuild
          action: rebuild
        - path: ./config         # config change → sync then restart the process
          target: /app/config
          action: sync+restart
  db:
    ports:
      - "127.0.0.1:5432:5432"    # expose the db to the host in dev only
```

Run it with `docker compose watch`.

### .env.example

Commit `.env.example`; git-ignore the real `.env`. Two mechanisms people conflate: the project-root `.env` is read automatically and **interpolated into `compose.yaml`** at parse time (`${VAR}`); a service's `env_file:` instead injects variables **into the container's runtime environment**. They're independent.

```bash
# Copy to .env and fill in. .env is git-ignored; this file is committed.
APP_PORT=8000
# DB password is a Compose secret (/run/secrets/db_password) — deliberately NOT in this URL.
# Read it in the app to assemble the DSN, or use a client that supports a password file.
DATABASE_URL=postgresql://app@db:5432/app
LOG_LEVEL=info
```

### Optional services (profiles)

A service with a `profiles:` key only starts when that profile is requested — keep debug tools, admin UIs, and one-shot seed jobs out of the default `up`:

```yaml
services:
  adminer:                     # db UI, only when asked for
    image: adminer:4
    ports: ["127.0.0.1:8080:8080"]
    profiles: [debug]
```

Start it with `docker compose --profile debug up`, or target it directly (`docker compose up adminer`) to auto-activate its profile.

### Network segmentation

The default network lets every service reach every other. At 3+ tiers, split them so the edge can't touch the data tier directly, and mark data-tier networks `internal: true` (no route to or from outside the compose network):

```yaml
services:
  proxy:
    image: caddy:2
    ports: ["127.0.0.1:443:443"]
    networks: [edge]
  app:
    build: .
    networks: [edge, backend]    # the only service on both tiers
  db:
    image: postgres:16.3
    networks: [backend]          # unreachable from the proxy or the host

networks:
  edge:
  backend:
    internal: true
```

## Container operations

### Debug workflow (in order)

```bash
docker compose logs -f <svc>     # 1. what is it actually saying?
docker compose exec <svc> sh     # 2. get a shell inside and look around
docker inspect <container>       # 3. the mounts / env / ports that were ACTUALLY applied
docker stats --no-stream         # 4. cpu/mem pressure (exit code 137 == OOM kill)
```

### Lifecycle & cleanup

```bash
docker compose up -d --build         # (re)build and start
docker compose restart <svc>         # restart one service
docker compose down                  # stop + remove (add -v to also delete named volumes)
docker system prune -f               # reclaim dangling images/containers/networks
docker builder prune -f              # reclaim build cache
```

### Log rotation

The default `json-file` driver is **unbounded** — container logs grow until they fill the host disk. Cap them globally in `/etc/docker/daemon.json` (applies to every new container):

```json
{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }
```

…or per service in compose (the `logging:` block shown in the canonical file above).

## Validate

Lint the files before shipping — cheap checks that enforce most of the rules above:

```bash
hadolint Dockerfile                  # Dockerfile linter (DL3008 unpinned apt, last-USER-root, COPY>ADD, …)
docker build --check .               # BuildKit's built-in checks — reports problems, builds nothing
docker compose config -q             # parse + validate compose.yaml (catches obsolete version:, bad refs)
```

No install needed for hadolint: `docker run --rm -i hadolint/hadolint < Dockerfile`. Add `# check=error=true` beneath the `# syntax` line to make `docker build` fail on check violations.

## Generation checklist

After scaffolding container files, verify:

- [ ] Dockerfile starts with `# syntax=docker/dockerfile:1`
- [ ] Multi-stage if there's a build step; runtime stage is slim/distroless
- [ ] Base images pinned (version tag; digest for production)
- [ ] Dependency manifest copied + installed **before** the app source
- [ ] Non-root `USER`; copied artifacts `--chown`ed to it
- [ ] Exec-form `ENTRYPOINT`/`CMD`
- [ ] `HEALTHCHECK` present, probes `127.0.0.1`, has a `start_period`
- [ ] `.dockerignore` present (`.git`, `.env`, secrets, deps, build output)
- [ ] No secrets in `ENV`/`ARG` — BuildKit secret or compose `secrets` instead
- [ ] compose.yaml: no `version:`, `name:` set, `depends_on` uses `condition: service_healthy`
- [ ] Named volumes for state; ports bound to `127.0.0.1` unless public; `restart: unless-stopped`; resource limits set
- [ ] Long-running services set `init: true` and a `stop_grace_period` covering drain time
- [ ] Log rotation configured (`json-file` `max-size`/`max-file`, daemon- or service-level)
- [ ] `.env.example` committed; real `.env` git-ignored
- [ ] Lints clean: `hadolint`, `docker build --check`, `docker compose config -q`

## Going deeper

- **Anti-patterns** → `references/anti-patterns.md`: WRONG/CORRECT code for the mistakes the *Critical rules* warn against — cache-busting COPY order, split apt, shell-form CMD, secrets in `ARG`/`ENV`, bare `depends_on`, publishing to every interface.
- **Production hardening** → `references/security-hardening.md`: dropping capabilities, read-only root filesystem, `no-new-privileges`, seccomp/AppArmor, digest pinning, image scanning (Trivy / Docker Scout), SBOM + signing (cosign), rootless Docker, and a fully hardened compose service.
- **CI/CD** → `references/ci-cd.md`: multi-arch builds with `buildx` + QEMU, the GitHub Actions build-and-push flow, registry build cache, scan-as-a-gate, and tagging strategy.

## Reference links

- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [Compose file / specification](https://docs.docker.com/reference/compose-file/)
- [Build best practices](https://docs.docker.com/build/building/best-practices/)
- [Compose: use secrets](https://docs.docker.com/compose/how-tos/use-secrets/)
