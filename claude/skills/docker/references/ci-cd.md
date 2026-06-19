# Building, scanning, and pushing in CI

Read this when wiring Docker image builds into a CI/CD pipeline. The golden rule: **build the image once, scan it, push it to a registry, then deploy that exact image** — never `docker compose up --build` on a production host (it gives that host inbound access to your source and produces a different image per environment).

## Contents
- [BuildKit / buildx](#buildkit--buildx)
- [Multi-architecture builds](#multi-architecture-builds)
- [GitHub Actions: build and push](#github-actions-build-and-push)
- [Registry build cache](#registry-build-cache)
- [Scan as a gate](#scan-as-a-gate)
- [Tagging strategy](#tagging-strategy)
- [Build secrets in CI](#build-secrets-in-ci)
- [Reproducible builds](#reproducible-builds)
- [Sources](#sources)

## BuildKit / buildx

BuildKit is the default builder (Docker 23+) and powers everything below: cache mounts, build secrets, parallel multi-stage graphs, and multi-platform output. `docker buildx` is the CLI front-end. No `DOCKER_BUILDKIT=1` toggle is needed on current Docker.

## Multi-architecture builds

Build one image that runs on both `amd64` and `arm64` (e.g. Apple Silicon dev, Graviton prod). `buildx` + QEMU emulates the foreign arch:

```bash
docker buildx create --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t myorg/myapp:1.0.0 --push .
```

## GitHub Actions: build and push

```yaml
name: build
on:
  push:
    tags: ["v*"]
jobs:
  docker:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write          # push to GHCR
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=semver,pattern={{version}}
            type=sha,prefix=,format=short

      - uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: true       # SLSA build provenance attestation
          sbom: true             # attach an SBOM attestation
```

`docker/metadata-action` handles the [tagging strategy](#tagging-strategy); `provenance`/`sbom` produce supply-chain attestations consumed downstream.

## Registry build cache

Share layer cache across CI runners and machines so cold builds aren't from scratch:

```bash
docker buildx build \
  --cache-from type=registry,ref=myorg/myapp:buildcache \
  --cache-to   type=registry,ref=myorg/myapp:buildcache,mode=max \
  -t myorg/myapp:1.0.0 --push .
```

In GitHub Actions, `type=gha` (shown above) uses the Actions cache backend instead. `mode=max` caches intermediate stages too (better hit rate, larger cache).

## Scan as a gate

Fail the pipeline on critical findings before the image is allowed to deploy:

```yaml
      - name: Scan image
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ghcr.io/${{ github.repository }}:${{ github.sha }}
          severity: CRITICAL,HIGH
          ignore-unfixed: true
          exit-code: "1"
```

Scan on a schedule too (a nightly job), not only on push — new CVEs apply to images you already shipped. See `security-hardening.md` for scanner choice and SBOM/signing.

## Tagging strategy

Layer several tags on each build:

| Tag | Example | Role |
|---|---|---|
| Semantic version | `myapp:1.3.8` | Stable, human-readable, rollback target |
| Git short SHA | `myapp:16af2b` | Lossless trace from a deployed image back to the commit |
| Major.minor float | `myapp:1.3` | Convenience pointer; never for pinned deploys |
| (never) `latest` | — | Mutable; non-reproducible deploys |

Reference the **digest** (`myapp@sha256:…`) in deployment manifests for reliable, immutable rollbacks.

## Build secrets in CI

Pass secrets to the build without baking them into a layer (covered in `SKILL.md`):

```bash
docker buildx build --secret id=npm_token,env=NPM_TOKEN .
docker buildx build --ssh default .     # forward the SSH agent for private git deps
```
In Actions, expose the secret as an env var on the `build-push-action` step's `secrets:` input.

## Reproducible builds

For bit-for-bit reproducible images, set `SOURCE_DATE_EPOCH` so timestamps are deterministic:

```bash
SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct) docker buildx build .
```
buildx propagates the variable automatically (BuildKit ≥ 0.13 rewrites file timestamps in the exported image).

## Sources

- [Docker: Multi-platform builds in GitHub Actions](https://docs.docker.com/build/ci/github-actions/multi-platform/)
- [docker/build-push-action](https://github.com/docker/build-push-action) · [docker/metadata-action](https://github.com/docker/metadata-action)
- [Docker: Build cache](https://docs.docker.com/build/cache/) · [Optimize cache](https://docs.docker.com/build/cache/optimize/)
- [Docker: Reproducible builds](https://docs.docker.com/build/ci/github-actions/reproducible-builds/)
- [aquasecurity/trivy-action](https://github.com/aquasecurity/trivy-action)
