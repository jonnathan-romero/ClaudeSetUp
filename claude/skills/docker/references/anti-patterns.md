# Anti-patterns

The WRONG/CORRECT contrasts behind the *Critical rules* in `SKILL.md`. Each rule there has a one-line reason; this file shows the failing code and its fix side by side. Read it when reviewing an existing Dockerfile/compose stack for the mistakes that bite hardest.

## Dockerfile

**Copying source before installing deps** (busts the cache on every code edit):
```dockerfile
# WRONG
COPY . .
RUN uv sync
# CORRECT
COPY pyproject.toml uv.lock ./
RUN uv sync --no-install-project
COPY . .
RUN uv sync
```

**Splitting apt update/install** (stale cache → install fails; cache not cleaned → bigger image):
```dockerfile
# WRONG
RUN apt-get update
RUN apt-get install -y git
# CORRECT
RUN apt-get update && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/*
```

**Shell-form entrypoint** (breaks signal delivery / graceful shutdown):
```dockerfile
# WRONG
CMD python -m myapp
# CORRECT
CMD ["python", "-m", "myapp"]
```

**Secret as a build arg** (persists in image layers + `docker history`):
```dockerfile
# WRONG
ARG API_KEY
RUN curl -H "Authorization: $API_KEY" https://api.example.com
# CORRECT — BuildKit secret, never written to a layer
RUN --mount=type=secret,id=api_key \
    curl -H "Authorization: $(cat /run/secrets/api_key)" https://api.example.com
#   build with: docker build --secret id=api_key,src=./api_key.txt .
```

## Compose

**`version:` + bare `depends_on`** (obsolete key; starts before the db is ready):
```yaml
# WRONG
version: "3.8"
services:
  app:
    depends_on: [db]
# CORRECT
services:
  app:
    depends_on:
      db:
        condition: service_healthy
```

**Hardcoded secret** (lands in source control and image inspection):
```yaml
# WRONG
environment:
  POSTGRES_PASSWORD: hunter2
# CORRECT
environment:
  POSTGRES_PASSWORD_FILE: /run/secrets/db_password
secrets:
  - db_password
```

**Publishing to every interface** (exposes a DB to the network):
```yaml
# WRONG
ports: ["5432:5432"]
# CORRECT
ports: ["127.0.0.1:5432:5432"]
```
