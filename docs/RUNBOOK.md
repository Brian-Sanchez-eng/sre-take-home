# Runbook: candidate-api readiness failure

Scope: `/health/ready` is failing, so pods are not receiving traffic. Readiness
returns 503 when any configured dependency is unhealthy, so this usually means a
dependency problem rather than the app being down.

## Detection

- Page from `CandidateApiProbeDown` (blackbox probe of `/health/ready`) or an
  error-budget burn alert.
- Symptom: Service has no ready endpoints; ingress returns 503; pods Running but
  not Ready.

## Triage

Identify the environment and namespace (`candidate-api-dev` or
`candidate-api-test`), then:

```bash
kubectl -n <ns> get pods -l app.kubernetes.io/name=candidate-api
kubectl -n <ns> get endpoints candidate-api
kubectl -n <ns> describe pod <pod>        # check readiness probe events
```

Look at the readiness payload to see which dependency is degraded:

```bash
kubectl -n <ns> port-forward deploy/candidate-api 18080:8080 &
curl -s http://127.0.0.1:18080/health/ready | jq .
```

The response lists each dependency with a healthy flag; the unhealthy one is the
lead.

## Diagnosis

- One dependency unhealthy: the dependency (database, cache, or downstream HTTP)
  is degraded or unreachable. Check that dependency's own health and the
  NetworkPolicy egress rules if connectivity recently changed.
- All dependencies unhealthy at once: suspect shared config or network, for
  example a bad ConfigMap value, DNS, or egress being blocked.
- Started right after a deploy: suspect the new release or its config; correlate
  with the most recent `deploy.yml` run.

## Remediation

If a deploy caused it:

```bash
kubectl -n <ns> rollout undo deploy/candidate-api
kubectl -n <ns> rollout status deploy/candidate-api
```

For a canary, a failed analysis aborts on its own; to force it:

```bash
kubectl argo rollouts abort candidate-api -n <ns>
```

If a dependency caused it: restore or fail over the dependency, or correct the
ConfigMap and let the readiness probe recover the pods automatically. The
PodDisruptionBudget keeps at least one replica during voluntary disruptions, and
readiness gating means degraded pods stay out of rotation rather than serving
errors.

## Verify and close

```bash
kubectl -n <ns> get endpoints candidate-api    # endpoints repopulated
curl -s http://127.0.0.1:18080/health/ready     # Healthy
```

Confirm the burn-rate alert clears, then capture the dependency failure and any
config fix in the incident notes.
