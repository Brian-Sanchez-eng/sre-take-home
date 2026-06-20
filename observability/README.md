# Observability & SLOs

All signals here are measured at the platform layer — ingress-nginx request
metrics and a blackbox probe against `/health/ready` — so no application code is
instrumented. App teams can later add RED metrics inside the service; the SLO
and alerting model does not depend on it.

## Service Level Objective

- SLI: availability = non-5xx ingress requests / total ingress requests.
- SLO: 99.9% over a rolling 30 days.
- Error budget: 0.1% of requests, roughly 43 minutes of full downtime per 30 days.
- Latency guardrail: p95 under 500ms at the ingress (also gates canary promotion).

## Files

- `prometheus-rules.yaml` — recording rules for the error ratio over 5m–3d
  windows, plus multi-window multi-burn-rate alerts and a blackbox-down alert.
- `blackbox-probe.yaml` — Prometheus Operator `Probe` hitting `/health/ready` in
  dev and test (availability backstop independent of traffic).
- `grafana-dashboard.json` — importable dashboard: availability, burn rate,
  request rate by status, 5xx ratio vs budget, p95/p99 latency, probe status.

## Alerting on burn rate

Alerts fire on how fast the error budget is being consumed, not on a raw
error-rate threshold. Each tier pairs a long and a short window: the long
window confirms the burn is real, the short one confirms it is still happening.

- Fast burn, 14.4x: 1h and 5m windows, ~2% of budget in 1h, pages on-call.
- Medium burn, 6x: 6h and 30m windows, ~5% of budget in 6h, pages on-call.
- Slow burn, 3x: 1d and 2h windows, ~10% of budget in a day, opens a ticket.
- Trickle burn, 1x: 3d and 6h windows, would exhaust the monthly budget, opens a ticket.

Tying pages to user-visible impact and routing low-grade burn to tickets is the
main lever against alert fatigue.

## Dependencies and assumptions

- kube-prometheus-stack (Prometheus Operator); the rules/probe carry the
  `release: kube-prometheus-stack` selector label.
- ingress-nginx exposes `nginx_ingress_controller_*` metrics to Prometheus.
- blackbox-exporter reachable at `blackbox-exporter.monitoring.svc:9115`.

Metric and label names follow ingress-nginx defaults; adjust the `ingress` and
`exported_namespace` selectors to match your scrape relabeling.
