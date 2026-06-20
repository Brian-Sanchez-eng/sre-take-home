# Canary deployment strategy (Argo Rollouts)

The base manifests ship a plain `Deployment` with a zero-downtime rolling
update, so they apply on any cluster (including the CI kind cluster). This
directory layers a **canary** strategy on top for production, where a bad
release should be caught and rolled back automatically instead of rolling all
pods at once.

## How it works

- `rollout.yaml` is an Argo Rollouts `Rollout` that reuses the base Deployment's
  pod template via `workloadRef`. The controller scales the Deployment down as
  the Rollout takes ownership, so there is no duplicated pod spec.
- Traffic is shifted 20% → 50% → 80% → 100% through ingress-nginx, pausing
  between steps.
- At every step an `AnalysisTemplate` queries Prometheus for the canary's
  success rate and p95 latency (measured at the ingress, not in the app). If
  either breaches the SLO, the analysis fails and the Rollout **aborts and
  shifts all traffic back to the stable version** — automated rollback.

## Why canary over blue-green

Blue-green flips 100% of traffic at once after a smoke test, which doubles
resource usage during cutover and exposes every user simultaneously if the
smoke test missed something. Canary limits blast radius to a traffic slice and
ties promotion to live SLIs, which matters more for an always-on API. The
tradeoff is a longer rollout and a hard dependency on a traffic router
(ingress-nginx) plus a metrics source (Prometheus).

## Prerequisites

- Argo Rollouts controller installed in the cluster.
- ingress-nginx as the ingress controller.
- Prometheus reachable at the `address` in `analysistemplate.yaml` (adjust to
  your cluster), scraping ingress-nginx metrics.

## Apply

```bash
# environment overlay first (Deployment, ConfigMap, SA, NetworkPolicy, etc.)
kubectl apply -k k8s/overlays/development
# then the canary layer
kubectl apply -k k8s/rollouts
kubectl argo rollouts get rollout candidate-api -n candidate-api-dev --watch
```

Not exercised in the CI kind run, which has no Argo Rollouts/Prometheus; it is
validated by `kustomize build`.
