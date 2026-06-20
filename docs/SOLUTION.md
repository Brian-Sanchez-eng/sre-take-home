# Solution overview

This documents the SRE work wrapped around the provided .NET API: how it is
built, containerized, deployed to development and test on Kubernetes, and
operated. No application code was changed; everything lives in the Dockerfile,
Kubernetes manifests, CI/CD workflows, and platform-layer observability.

## What was delivered

Phase 1, build and PR pipeline:
- `Dockerfile` — multi-stage build on the SDK image pinned to the `global.json`
  feature band, producing a chiseled, non-root runtime image on port 8080.
- `.github/workflows/pr-validation.yml` — on pull requests: restore, build,
  test, pack the Contracts NuGet, build the image, Trivy-scan it, and an e2e
  job that deploys to a throwaway kind cluster.

Phase 2, Kubernetes and deploy/promote:
- `k8s/base` — hardened Deployment plus Service, ServiceAccount, ConfigMap, HPA,
  PodDisruptionBudget, and NetworkPolicy.
- `k8s/overlays/development` and `k8s/overlays/test` — the same base with
  per-environment namespace, replicas, and config.
- `.github/workflows/deploy.yml` — on push to main: build and test, push the
  image to GHCR and the NuGet to GitHub Packages, deploy development, then
  promote the same build to test.

Phase 3, senior extensions:
- `k8s/rollouts` — Argo Rollouts canary with automated, metric-driven rollback.
- `observability/` — SLO definition, blackbox probe, multi-window burn-rate
  alerts, and a Grafana dashboard, all measured at the platform edge.
- `docs/` — this overview, the deployment guide, and a runbook.

## How to validate

Pull request pipeline:
- Open a PR against main. `build-test`, `package`, `image`, and `e2e` should all
  pass. The `e2e` job is the strongest signal: it stands up kind, applies both
  overlays, waits for the rollouts, and curls `/health/ready` in each namespace.

Manifests locally:
- `kustomize build k8s/overlays/development`
- `kustomize build k8s/overlays/test`
- `kustomize build k8s/rollouts`

Deploy pipeline:
- Merge to main. `deploy.yml` publishes the image and NuGet, then runs
  development and test. Without `KUBE_CONFIG_*` secrets it renders manifests in
  dry-run; with them it applies and waits for rollout, then smoke-tests
  `/health/ready`. See `docs/DEPLOYMENT.md`.

## Key tradeoffs

- Kustomize over Helm: the base-plus-overlays model maps directly to "one set of
  manifests, per-environment config" without templating indirection. Helm would
  win if this became a redistributable chart.
- Plain Deployment in base, canary layered separately: the base applies on any
  cluster (including CI kind), while the production canary strategy and its
  controller/metrics dependencies stay opt-in under `k8s/rollouts`.
- SLIs at the platform layer, not in the app: keeps a clean ownership boundary
  and avoids forcing a metrics library on the app team. The cost is coarser,
  per-route signals instead of per-handler.
- Gated deploy with dry-run fallback: the pipeline is real and apply-ready but
  does not require a standing cluster to stay green.

## Assumptions and incomplete pieces

- A real cluster is not wired in; deploy jobs run in dry-run until
  `KUBE_CONFIG_DEV` / `KUBE_CONFIG_TEST` secrets exist.
- The canary and observability manifests assume ingress-nginx, Argo Rollouts,
  and kube-prometheus-stack are installed; they are validated by `kustomize
  build`, not exercised in CI.
- NetworkPolicy is applied in the kind e2e but not enforced there (kindnet does
  not enforce policies); it is enforced on a CNI that supports it.
