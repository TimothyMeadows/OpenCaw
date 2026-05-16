# DOCKER.md

This repository follows a **Docker container architecture** optimized for reproducible builds, secure images, fast local development, and predictable deployment artifacts.

The architecture is optimized for:

- Dockerfiles
- Docker Compose
- BuildKit
- multi-stage builds
- container image provenance
- secure runtime configuration
- local development parity
- CI/CD image build and promotion workflows
- Kubernetes or other orchestrated runtime targets

The goal is to keep containerization:

- reproducible
- minimal
- secure by default
- easy to debug locally
- fast enough for daily development
- reviewable in pull requests
- compatible with enterprise build and release controls

---

# Core Architecture Rule

**Separate image construction, runtime configuration, and deployment environment concerns.**

Prefer:

```text
source + Dockerfile -> immutable image -> environment configuration -> runtime
```

Avoid:

```text
one image -> hidden environment branching -> mutable runtime patching
```

The image should answer:

- what code and dependencies are packaged
- how the process starts
- what filesystem and user permissions exist
- what ports or health signals are exposed

The runtime environment should answer:

- which configuration values are supplied
- which secrets are mounted or injected
- which networks, volumes, and resources are attached
- how the container is observed, restarted, and promoted

---

# Repository Structure

Use a layout that makes ownership and build context obvious.

Preferred single-service layout:

```text
.
  Dockerfile
  .dockerignore
  compose.yaml
  src/
  tests/
```

Preferred multi-service layout:

```text
.
  compose.yaml
  services/
    api/
      Dockerfile
      .dockerignore
      src/
    worker/
      Dockerfile
      .dockerignore
      src/
  deploy/
    docker/
      compose.dev.yaml
      compose.test.yaml
```

Alternative when deployment assets are centralized:

```text
.
  deploy/
    docker/
      api.Dockerfile
      worker.Dockerfile
      compose.yaml
      compose.override.yaml
```

Rules:

- Keep the Docker build context as small as practical.
- Put `.dockerignore` next to each Dockerfile when build contexts differ.
- Name multi-service Dockerfiles clearly when they are not colocated with service source.
- Keep development Compose files separate from production deployment manifests.
- Do not mix Kubernetes, Helm, or Terraform concerns into Dockerfiles.

---

# Dockerfile Architecture

Dockerfiles should be:

- deterministic
- readable top to bottom
- multi-stage where build tooling is not needed at runtime
- explicit about working directory, user, exposed port, and entrypoint
- designed for cache efficiency without hiding build behavior

Recommended high-level shape:

```dockerfile
# syntax=docker/dockerfile:1

FROM <runtime-base> AS base
WORKDIR /app

FROM <sdk-or-build-base> AS build
WORKDIR /src
COPY <manifest-files> ./
RUN <restore-dependencies>
COPY . .
RUN <build-or-publish>

FROM base AS final
COPY --from=build /out /app
USER <non-root-user>
EXPOSE <port>
ENTRYPOINT ["<process>"]
```

Rules:

- Use multi-stage builds for compiled apps, package managers, and asset pipelines.
- Copy dependency manifests before full source to improve cache reuse.
- Pin base images by stable version tags; use digests where supply-chain controls require them.
- Prefer exec-form `ENTRYPOINT` and `CMD`.
- Use `ARG` only for build-time values.
- Use `ENV` only for safe defaults that are not secrets.
- Keep build tools out of runtime images.
- Keep generated artifacts out of source stages unless they are intentionally part of the build.
- Avoid package manager cache bloat in runtime layers.

---

# Base Image Rules

Base image selection should balance:

- security patch availability
- runtime compatibility
- image size
- debugging needs
- enterprise registry policy
- multi-architecture support

Preferred order:

1. Official language or platform runtime images.
2. Organization-approved hardened base images.
3. Minimal distro images when debugging and compatibility remain acceptable.
4. Distroless or scratch images only when the operational tradeoffs are understood.

Rules:

- Do not use `latest` for production-sensitive images.
- Keep OS family consistent across build and runtime stages when native dependencies matter.
- Document why a nonstandard base image is required.
- Rebuild images regularly to receive base image security updates.
- Avoid mixing package ecosystems unless needed for the application.

---

# Build Context and .dockerignore Rules

Every meaningful Docker build context should have a `.dockerignore`.

Common exclusions:

```text
.git
.github
.vs
.vscode
node_modules
bin
obj
dist
coverage
TestResults
*.user
*.suo
.env
.env.*
```

Rules:

- Exclude source control metadata unless the build explicitly needs it.
- Exclude local secrets, local environment files, and user-specific IDE files.
- Exclude dependency folders that are restored inside the image.
- Exclude build outputs that are regenerated inside the image.
- Do not exclude manifests required for dependency restore.
- Keep `.dockerignore` reviewable; avoid broad patterns that accidentally omit source.

---

# BuildKit and Cache Rules

Prefer BuildKit features when they improve speed or security without reducing portability.

Useful patterns:

- cache mounts for package manager caches
- secret mounts for private package feeds
- SSH mounts for private source dependencies
- target builds for development or debugging stages

Rules:

- Use BuildKit secret mounts instead of copying secrets into images.
- Keep cache mounts scoped to dependency restore steps.
- Do not depend on local developer cache state for correctness.
- CI builds must be reproducible from a clean cache.
- If advanced BuildKit features are required, document the minimum Docker/BuildKit version.

Example:

```dockerfile
RUN --mount=type=cache,target=/root/.nuget/packages \
    dotnet restore
```

---

# Dependency and Package Rules

Dependencies should be restored, installed, and locked in a predictable way.

Rules:

- Use lock files where the ecosystem supports them.
- Use deterministic restore/install commands in CI.
- Avoid installing unnecessary runtime packages.
- Clean package manager metadata from runtime layers when using distro packages.
- Keep private feed credentials out of layers and logs.
- Separate dependency restore from source copy where cache efficiency matters.

Avoid:

- floating dependency installs in production builds
- curl-pipe-shell installation without checksum or provenance controls
- build steps that mutate dependency manifests without review
- copying host dependency folders into images

---

# Runtime Image Rules

Runtime images should include only what the process needs.

Rules:

- Run as a non-root user whenever the application allows it.
- Set `WORKDIR` explicitly.
- Use explicit `ENTRYPOINT` and optional `CMD` defaults.
- Expose documented ports with `EXPOSE`.
- Prefer read-only filesystem compatibility for production workloads where practical.
- Write logs to stdout/stderr.
- Store mutable state in declared volumes or external services, not image layers.
- Avoid long-running shell wrapper scripts unless they add clear value.

Recommended runtime defaults:

```dockerfile
WORKDIR /app
USER app
EXPOSE 8080
ENTRYPOINT ["./app"]
```

---

# Configuration Rules

Configuration must be environment-driven and explicit.

Rules:

- Use environment variables for non-secret runtime configuration.
- Use mounted secrets, secret stores, or orchestrator-native secret injection for secrets.
- Keep defaults safe for local development but not silently production-like.
- Document required environment variables near the container entrypoint or deployment docs.
- Fail fast when required configuration is missing.
- Do not bake environment-specific configuration into images.

Avoid:

- copying `.env` files into images
- hardcoding cloud account, tenant, subscription, registry, or database names
- changing runtime behavior based on ambiguous environment names without documentation

---

# Secret Handling Rules

Secrets must never become image layers, logs, or committed Compose defaults.

Rules:

- Use BuildKit `--secret` for build-time secrets.
- Use Docker Compose `secrets`, mounted files, or host environment injection for local secrets.
- Use cloud or orchestrator secret managers for deployed environments.
- Rotate secrets independently from image rebuilds.
- Keep secret names explicit and least-privilege.

Avoid:

- `ARG NUGET_TOKEN` followed by `RUN` commands that expose token history
- `ENV PASSWORD=...`
- `COPY .env .`
- checking sample files with real-looking credentials

---

# Security Rules

Containers should be secure by construction.

Rules:

- Run as non-root by default.
- Keep runtime images minimal.
- Scan base images and final images for vulnerabilities.
- Generate and preserve image provenance where supported.
- Prefer signed images for production promotion.
- Use least-privilege Linux capabilities.
- Avoid privileged containers unless the workload truly requires it.
- Avoid mounting the Docker socket into application containers.
- Treat image rebuilds as part of patch management.

Recommended controls:

- vulnerability scanning in CI
- dependency scanning before image publish
- SBOM generation for released images
- image signing or attestations for production images
- registry retention and tag immutability policy

---

# Image Tagging and Registry Rules

Image tags must support traceability and promotion.

Prefer tagging with:

- immutable commit SHA
- semantic version or release version
- environment promotion metadata only outside the immutable artifact contract

Recommended pattern:

```text
registry.example.com/team/service:<git-sha>
registry.example.com/team/service:<semver>
```

Rules:

- Do not use mutable tags as the only deployment reference.
- Use `latest` only for local development or clearly non-production workflows.
- Keep image repository ownership aligned with service ownership.
- Prefer promotion of the same image digest across environments.
- Record source commit, build workflow, and build timestamp as labels.

Recommended labels:

```dockerfile
LABEL org.opencontainers.image.source="<repo-url>"
LABEL org.opencontainers.image.revision="<git-sha>"
LABEL org.opencontainers.image.version="<version>"
```

---

# Docker Compose Architecture

Compose is preferred for local development, integration tests, and lightweight demos.

Compose should define:

- service graph
- local build targets or image references
- ports for developer access
- volumes for local persistence
- health checks where dependency readiness matters
- networks that model service boundaries
- non-secret defaults

Suggested layout:

```text
compose.yaml
compose.override.yaml
compose.test.yaml
```

Rules:

- Keep `compose.yaml` stable and reviewable.
- Use override files for developer-specific or environment-specific changes.
- Avoid making Compose the hidden production source of truth when Kubernetes, Helm, or another platform owns deployment.
- Use named volumes for local state that should persist.
- Use anonymous or temporary volumes for disposable dependency data.
- Use health checks and `depends_on` conditions when startup order matters.
- Keep host port mappings explicit and collision-aware.

Example:

```yaml
services:
  api:
    build:
      context: .
      target: final
    ports:
      - "8080:8080"
    environment:
      ASPNETCORE_URLS: http://+:8080
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
```

---

# Networking Rules

Container networking should be explicit and minimal.

Rules:

- Prefer service names for container-to-container communication in Compose.
- Expose only ports needed by developers or upstream services.
- Keep internal-only dependencies off host port bindings unless needed.
- Use separate networks when isolation helps clarify trust boundaries.
- Document externally reachable ports.
- Do not rely on localhost assumptions inside containers; use service names or injected URLs.

Avoid:

- broad host networking without a strong reason
- exposing databases to the host by default in shared demos
- undocumented magic ports

---

# Volume and Filesystem Rules

Filesystem behavior should be intentional.

Rules:

- Treat containers as ephemeral unless a volume is declared.
- Use named volumes for local dependency state such as databases.
- Avoid bind-mounting source into production-like containers.
- Keep writable paths explicit.
- Make uploaded files, caches, and generated reports external or disposable by design.
- Do not store business-critical data only inside a container writable layer.

For production-sensitive workloads:

- prefer immutable image contents
- use external storage for durable data
- consider read-only root filesystem
- mount temporary writable paths explicitly

---

# Health, Lifecycle, and Shutdown Rules

Containers should be observable and graceful.

Rules:

- Define health checks for services used by Compose or orchestration workflows.
- Ensure the main process receives signals directly.
- Handle `SIGTERM` gracefully.
- Keep startup idempotent.
- Avoid backgrounding the main process in shell scripts.
- Use init handling only when needed and documented.

Health checks should verify meaningful readiness, not only process existence.

Examples:

- HTTP health endpoint for web APIs
- database readiness command for local dependencies
- queue connection check for workers when feasible

---

# Logging and Observability Rules

Containers should emit useful runtime evidence without custom host setup.

Rules:

- Write application logs to stdout/stderr.
- Use structured logs where supported.
- Include correlation IDs when services communicate.
- Keep health, startup, shutdown, and configuration errors clear.
- Avoid logging secrets or full connection strings.
- Expose metrics endpoints only when the runtime platform expects them.

Avoid:

- writing primary logs only to files inside the container
- swallowing startup exceptions in wrapper scripts
- noisy logs that hide readiness or dependency failures

---

# Development Workflow Rules

Docker should improve local onboarding without hiding important system behavior.

Rules:

- Provide a small set of documented commands for build, run, test, and cleanup.
- Prefer Compose profiles for optional dependencies.
- Keep local defaults safe and low-friction.
- Make rebuild vs restart expectations clear.
- Keep local database or broker initialization deterministic.
- Avoid requiring cloud credentials for basic local development unless the application truly requires them.

Recommended local workflow:

```bash
docker compose build
docker compose up
docker compose down
```

For test dependencies:

```bash
docker compose -f compose.test.yaml up --abort-on-container-exit --exit-code-from tests
```

---

# CI/CD Rules

Container CI should separate validation, build, scan, publish, and deployment promotion.

Recommended pipeline:

```text
lint Dockerfile/Compose -> build image -> run tests -> scan image -> publish immutable tag -> promote digest
```

Rules:

- Build with a clean context in CI.
- Run tests before publishing production images.
- Scan final runtime images, not only source dependencies.
- Publish immutable tags tied to commit SHA or release version.
- Promote image digests across environments instead of rebuilding per environment when artifact promotion is required.
- Store registry credentials in CI secrets with minimum required permissions.
- Keep cloud project, registry, and environment names externalized.

For GitHub Actions, prefer explicit job permissions and artifact/image provenance controls.

---

# Testing and Validation

Recommended checks:

- Dockerfile linting where tooling exists.
- Compose configuration validation.
- Image build from a clean checkout.
- Container startup smoke test.
- Health check verification.
- Dependency and image vulnerability scans.
- SBOM generation for release images.
- Tests run against containerized dependencies when that matches production integration risk.

Example checks:

```bash
docker build --target final -t local/app:test .
docker run --rm local/app:test --version
docker compose config
docker compose up --build --abort-on-container-exit
```

Rules:

- Do not call a container build validated until the image starts.
- Do not call a Compose setup validated until dependencies become healthy or fail clearly.
- Keep tests deterministic and independent from developer-local container state.

---

# Multi-Architecture Rules

Multi-architecture images are required when runtime platforms use mixed CPU architectures.

Rules:

- Use `docker buildx` for multi-platform builds.
- Test at least the primary deployment architecture.
- Ensure native dependencies support every target architecture.
- Tag and promote multi-arch manifests intentionally.
- Document any architecture exclusions.

Example:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag registry.example.com/team/service:<version> \
  --push .
```

---

# Language-Specific Guidance

Use language-specific architecture templates together with this Docker template.

For .NET:

- use `DOTNET` and `DOCKER`
- publish in a build stage
- run from ASP.NET or runtime base images
- set `ASPNETCORE_URLS` or equivalent explicitly
- avoid copying `bin/` and `obj/` from the host

For Node:

- use `NODE` and `DOCKER`
- install dependencies from lock files
- prune dev dependencies for runtime images when appropriate
- avoid copying host `node_modules`
- distinguish build-time frontend assets from runtime server dependencies

For Python:

- use `PYTHON` and `DOCKER`
- pin dependencies with lock or constraints files
- prefer virtual environment or user installs inside build stages
- avoid leaking local virtual environments into images
- install native build dependencies only in build stages when possible

For frontend SPAs:

- use `SPA`, framework-specific templates, and `DOCKER`
- build static assets in a Node stage
- serve assets from a minimal web server or platform-specific runtime
- keep runtime configuration strategy explicit

---

# Relationship to Deployment Templates

Docker defines the image artifact. Other templates define where and how that artifact runs.

Use with:

- `GITHUB_ACTIONS` for CI/CD image build, scan, publish, and promotion.
- `KUBERNETES` for cluster runtime manifests.
- `HELM` for reusable Kubernetes packaging.
- `TERRAFORM` for registry, infrastructure, and cloud resource provisioning.
- `AZURE`, `GCP`, or `AWS` guidance when cloud-specific registry or runtime details apply.

Rules:

- Keep image build concerns in Dockerfiles and CI.
- Keep deployment concerns in Kubernetes, Helm, Compose, or platform manifests.
- Keep infrastructure provisioning outside Dockerfiles.
- Do not make Docker Compose the only production deployment contract unless the repository explicitly targets Compose-based production.

---

# Anti-Patterns

Never introduce:

- production Dockerfiles based on `latest`
- secrets copied into images
- root runtime containers without justification
- giant Dockerfiles that build multiple unrelated services
- Dockerfiles that depend on uncommitted local files
- host dependency folders copied into images
- Compose files with real credentials
- hidden production configuration baked into images
- manual shell commands inside running containers as the normal deployment process
- image rebuilds per environment when artifact promotion is required
- privileged containers or Docker socket mounts without explicit security review

---

# Code Generation Rules for Agents

When generating Docker assets:

1. Start with the service boundary and runtime target.
2. Choose a safe, versioned base image.
3. Use a multi-stage Dockerfile when build tooling is not needed at runtime.
4. Add or update `.dockerignore` with build-context safety in mind.
5. Keep secrets out of images, args, env defaults, and Compose files.
6. Run containers as non-root when practical.
7. Make ports, health checks, entrypoints, and required configuration explicit.
8. Keep Compose focused on local development, integration tests, or the explicitly chosen runtime.
9. Preserve image traceability through tags, labels, and CI metadata.
10. Pair Docker changes with validation commands and clear local run instructions.

When in doubt:

**Build one immutable, minimal, non-root image per service, configure it at runtime, and promote the same image digest through environments.**
