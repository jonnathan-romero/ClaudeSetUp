# Production hardening

Read this when taking a container setup beyond the daily-driver basics in `SKILL.md` toward a production deployment. The essentials (non-root, no `:latest`, no secrets in `ENV`, healthchecks, resource limits) are already covered in `SKILL.md` — this file is the next layer: runtime confinement, supply-chain integrity, and scanning.

Apply controls by need, not by reflex — each has a real cost (debuggability, setup). The fully hardened compose service at the end combines all of them.

## Contents
- [Runtime confinement](#runtime-confinement)
- [Non-root, deeper](#non-root-deeper)
- [Secrets recap](#secrets-recap)
- [Supply chain: digest pinning, scanning, SBOM, signing](#supply-chain)
- [Network exposure](#network-exposure)
- [Fully hardened compose service](#fully-hardened-compose-service)
- [Sources](#sources)

## Runtime confinement

### Drop all capabilities, add back only what's needed
A container starts with a set of Linux capabilities it almost never fully uses. Drop them all and re-add the few required (e.g. `NET_BIND_SERVICE` only if binding a port < 1024).

```yaml
cap_drop:
  - ALL
cap_add:
  - NET_BIND_SERVICE   # only if it actually binds a privileged port
```
CLI: `docker run --cap-drop ALL --cap-add NET_BIND_SERVICE myimage`.

**Never `--privileged`.** It bypasses capability, seccomp, and device restrictions — effectively unrestricted host kernel access.

### no-new-privileges
Blocks `setuid`/`setgid` binaries from escalating privileges inside the container.
```yaml
security_opt:
  - no-new-privileges:true
```

### Read-only root filesystem
If the app doesn't write to its own filesystem, make the root read-only and give it explicit `tmpfs` for the few writable paths. Stops an attacker from dropping a binary or modifying code at runtime.
```yaml
read_only: true
tmpfs:
  - /tmp
  - /run
```

### seccomp and AppArmor
Docker applies a **default seccomp profile** that blocks ~44 dangerous syscalls (e.g. `mount`, `ptrace`, `reboot`, `unshare`) and a default AppArmor profile (`docker-default`). Keep them on — do **not** run `--security-opt seccomp=unconfined`. Only supply a custom profile if you have a specific syscall need:
```yaml
security_opt:
  - seccomp:/etc/docker/seccomp/custom-profile.json
  - apparmor:docker-default
```

## Non-root, deeper

`SKILL.md` covers the `USER` directive. Beyond that:

- **Assign an explicit numeric UID/GID.** Auto-assigned UIDs are non-deterministic across rebuilds; pin them so volume permissions stay stable. `user: "1001:1001"` in compose, or a fixed UID in `useradd -u 1001`.
- **Make executables root-owned and not world-writable** — prevents a compromised process from rewriting its own binary.
- **Rootless Docker** runs the daemon and containers as an unprivileged host user inside a user namespace, removing root from the daemon itself. Set up with `dockerd-rootless-setuptool.sh install` (needs `uidmap` and subordinate UID/GID ranges). `userns-remap` is a lighter middle ground but the daemon still runs as root.

## Secrets recap

Covered in `SKILL.md`; the rule, restated for completeness:
- **Build time:** `RUN --mount=type=secret,id=…` (BuildKit) — never written to a layer.
- **Run time:** Compose `secrets` → mounted at `/run/secrets/<name>`; pair with the `_FILE` env convention many official images support (`POSTGRES_PASSWORD_FILE`, `MYSQL_PASSWORD_FILE`).
- For strong compliance needs, a real secret manager (Vault, AWS/GCP Secrets Manager) beats file-based Compose secrets.
- Note: `DOCKER_CONTENT_TRUST` / Notary v1 is being retired — use cosign/Sigstore (below) for signing.

## Supply chain

### Pin base images by digest
A tag can be repointed upstream; a digest can't. For anything deployed:
```dockerfile
FROM python:3.12-slim@sha256:<digest>
```
Tradeoff: digests don't auto-receive security patches — pair pinning with a tool (Docker Scout, Dependabot) that raises a PR when a newer digest ships.

### Scan images for vulnerabilities
Run a scanner in CI and on a schedule (CVEs land daily, not only at build time).

```bash
trivy image --severity HIGH,CRITICAL --ignore-unfixed myapp:1.0.0
trivy image --exit-code 1 --severity CRITICAL myapp:1.0.0   # CI gate
grype myapp:1.0.0 --fail-on high
docker scout cves myapp:1.0.0
```
Start gating on CRITICAL+HIGH only to avoid alert fatigue. Trivy and Grype use different databases — for high-stakes images, run both and reconcile.

### SBOM + signing
Generate a Software Bill of Materials at build, attach it as an attestation, and sign the image so consumers can verify provenance:
```bash
syft myapp:1.0.0 -o spdx-json > sbom.spdx.json
cosign sign myregistry/myapp:1.0.0
cosign verify --certificate-identity "$ID" --certificate-oidc-issuer "$ISSUER" myapp@sha256:<digest>
```
cosign keyless signing (Sigstore/Fulcio/Rekor) uses short-lived keys; the signature is stored alongside the image in the OCI registry.

## Network exposure

- **Never mount the Docker socket** (`/var/run/docker.sock`) into a container, and never expose the daemon over unauthenticated TCP — both grant effective host root.
- **Bind published ports to `127.0.0.1`** unless the port must be public — Docker's port publishing bypasses host UFW/iptables rules.
- **Custom networks over the default bridge**; mark internal-only networks `internal: true` to block outbound routing for databases/caches.

## Fully hardened compose service

```yaml
name: myapp

services:
  api:
    image: myregistry/api:1.0.0@sha256:<digest>
    user: "1001:1001"
    read_only: true
    tmpfs:
      - /tmp:size=64m,mode=1777
      - /run:size=10m
    cap_drop:
      - ALL
    # nothing added back — 8080 is unprivileged; add e.g. NET_BIND_SERVICE only to bind a port < 1024
    security_opt:
      - no-new-privileges:true
      - apparmor:docker-default
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
    secrets:
      - db_password
    networks:
      - backend
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
    healthcheck:
      # assumes curl is in the image; on slim/distroless probe with the language runtime instead
      test: ["CMD", "curl", "-f", "http://127.0.0.1:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s

secrets:
  db_password:
    file: ./secrets/db_password.txt

networks:
  backend:
    internal: true
```

## Sources

- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [Docker: Build best practices](https://docs.docker.com/build/building/best-practices/)
- [Docker: Engine security](https://docs.docker.com/engine/security/) (seccomp, AppArmor, rootless, userns-remap)
- [Docker: Build secrets](https://docs.docker.com/build/building/secrets/)
- [Docker Scout](https://docs.docker.com/scout/) · [Trivy](https://trivy.dev/) · [Sigstore/cosign](https://docs.sigstore.dev/)
