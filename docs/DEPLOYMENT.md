# Deployment guide

## Pipelines

`pr-validation.yml` runs on pull requests and never pushes or deploys. It
builds, tests, packs the NuGet, builds and scans the image, and runs the kind
e2e deploy.

`deploy.yml` runs on push to main (and via manual dispatch) and does the
promotion flow:
1. build-test — restore, build, test.
2. build-push-image — push `ghcr.io/brian-sanchez-eng/sre-take-home/candidate-api`
   tagged with the commit short SHA and `latest`.
3. publish-nuget — push the Contracts package to GitHub Packages.
4. deploy-dev — deploy to the development environment.
5. deploy-test — after dev succeeds, promote the same image tag to test.

The same immutable image tag flows from dev to test; nothing is rebuilt between
environments.

## Environments

Two GitHub Environments back the promotion, `development` and `test`. Add
required reviewers on `test` in repo settings to turn promotion into a manual
approval gate. The Kubernetes namespaces are `candidate-api-dev` and
`candidate-api-test`.

## Cluster credentials

Each deploy job reads a base64-encoded kubeconfig from a secret:
- `KUBE_CONFIG_DEV` for development.
- `KUBE_CONFIG_TEST` for test.

Create them with:

```bash
base64 -i dev-kubeconfig.yaml | gh secret set KUBE_CONFIG_DEV \
  --env development --repo Brian-Sanchez-eng/sre-take-home
base64 -i test-kubeconfig.yaml | gh secret set KUBE_CONFIG_TEST \
  --env test --repo Brian-Sanchez-eng/sre-take-home
```

When a secret is absent the job renders the overlay with `kustomize build` and
skips apply (dry-run), so the pipeline stays green before a cluster exists. When
present it runs `kubectl apply -k`, waits on `rollout status`, then smoke-tests
`/health/ready` through a port-forward.

## Image tag pinning

Deploy does not edit manifests by hand. It runs `kustomize edit set image` in
the overlay directory to pin the exact tag built in this run, so the deployed
image always matches the artifact that was tested.

## Manual deploy

```bash
kubectl apply -k k8s/overlays/development
kubectl -n candidate-api-dev rollout status deploy/candidate-api
```

Swap `development` / `candidate-api-dev` for the test equivalents. For the
canary strategy see `k8s/rollouts/README.md`.

## Rollback

Rolling Deployment: `kubectl -n <ns> rollout undo deploy/candidate-api`, or
re-run `deploy.yml` pinned to a previous SHA.

Canary (Argo Rollouts): a failed analysis aborts automatically. To intervene,
`kubectl argo rollouts abort candidate-api -n <ns>` and then `undo`. See
`docs/RUNBOOK.md`.
