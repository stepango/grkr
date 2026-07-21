# Deploy grkr (Docker + Helm)

Run the long-lived grkr supervisor against a GitHub repo/project with minimal setup.

## What you get

| Path | Purpose |
|------|---------|
| `Dockerfile` | Runtime image (Node + Gleam + `gh` + git/jq/flock + grkr) |
| `docker-compose.yml` | One-command local/single-node run |
| `deploy/docker/entrypoint.sh` | Clones target repo, writes config from env, starts supervisor |
| `deploy/helm/grkr/` | Kubernetes chart (Deployment + PVC + Secret) |

The container keeps durable state on `/workspace` (git checkout + `.grkr/`).  
**Replica count must stay 1** — the supervisor owns locks and worktrees on that volume.

## Prerequisites

- Docker (Compose v2+) for local
- Kubernetes + Helm 3 for cluster deploy
- A GitHub token with repo + project scopes (`GH_TOKEN`)
- A GitHub Project number whose Status field has Todo / In Progress / Done / Backlog
- A coding agent CLI on the host (or mounted): **codex** and/or **grok**

Coding agents are **not** baked into the image (licenses + auth). Mount them at `/opt/coding-agents/codex` and/or `/opt/coding-agents/grok`.

## Docker Compose (easiest)

```bash
# from repo root
export GH_TOKEN=ghp_...
export REPO=owner/name          # target repo the bot works in
export PROJECT_NUMBER=1
export PROJECT_OWNER=owner      # optional; defaults to REPO owner
export BOT_LOGIN=my-bot         # optional; picker assignee filter
# optional:
# export GRKR_CODING_AGENT=grok
# export XAI_API_KEY=...
# mkdir -p coding-agents && ln -s $(which codex) coding-agents/codex

docker compose up --build
```

Useful one-shots:

```bash
docker compose run --rm grkr doctor
docker compose run --rm grkr issue 42
docker compose run --rm grkr shell
```

Logs: `docker compose logs -f grkr`

### Environment reference (compose / container)

| Variable | Required | Notes |
|----------|----------|--------|
| `REPO` / `GRKR_REPO` | yes | `owner/name` |
| `PROJECT_NUMBER` | yes* | GitHub Project number (*or mount config) |
| `GH_TOKEN` | yes | also accepted as `GITHUB_TOKEN` |
| `PROJECT_OWNER` | no | defaults to owner of `REPO` |
| `MAIN_BRANCH` | no | default `main` |
| `LOOP_INTERVAL_SECS` | no | default `20` |
| `BOT_LOGIN` | no | Todo assignee filter |
| `GRKR_CODING_AGENT` | no | `codex` (default in compose) or `grok` |
| `XAI_API_KEY` | for grok | |
| `GRKR_LINEAR_ACCESS_TOKEN` | Linear | |
| `TARGET_REPO_URL` | no | override clone URL |
| `GRKR_FORCE_CONFIG=1` | no | rewrite generated `.grkr/config.sh` |

Entrypoint commands: `supervisor` (default), `doctor`, `init`, `issue <n>`, `linear-issue <id>`, `shell`.

## Plain Docker

```bash
docker build -t grkr:local .

docker run --rm -it \
  -e GH_TOKEN \
  -e REPO=owner/name \
  -e PROJECT_NUMBER=1 \
  -v grkr-data:/workspace \
  -v "$PWD/coding-agents:/opt/coding-agents:ro" \
  grkr:local supervisor
```

## Helm

```bash
# build/push image to your registry first
docker build -t ghcr.io/YOU/grkr:0.1.0 .
docker push ghcr.io/YOU/grkr:0.1.0

# recommended: pre-create secret
kubectl create secret generic grkr-secrets \
  --from-literal=GH_TOKEN="$GH_TOKEN" \
  --from-literal=XAI_API_KEY="$${XAI_API_KEY:-}"

helm upgrade --install grkr ./deploy/helm/grkr \
  --set image.repository=ghcr.io/YOU/grkr \
  --set image.tag=0.1.0 \
  --set repo.name=owner/name \
  --set github.projectNumber=1 \
  --set github.projectOwner=owner \
  --set github.existingSecret=grkr-secrets \
  --set codingAgent.default=codex \
  --set codingAgent.agentsVolume.enabled=true \
  --set codingAgent.agentsVolume.hostPath=/opt/coding-agents
```

Example values file: `deploy/helm/grkr/examples/values-example.yaml`.

```bash
kubectl logs -f deploy/grkr
kubectl exec -it deploy/grkr -- doctor
kubectl exec -it deploy/grkr -- issue 12
```

### Chart knobs (high signal)

| values key | Meaning |
|------------|---------|
| `repo.name` | Target `owner/name` (required) |
| `github.projectNumber` | Project v2 number (required unless configFile) |
| `github.existingSecret` | Secret with `GH_TOKEN` |
| `persistence.size` | Workspace PVC (git + `.grkr`) |
| `codingAgent.default` | `codex` \| `grok` |
| `codingAgent.agentsVolume.*` | Mount agent CLIs |
| `config.extraEnv` | Pass-through env map |
| `configFile.*` | Mount a full `.grkr/config.sh` instead of env generation |
| `replicaCount` | Keep `1` |

Strategy is `Recreate` so two pods never share one workspace PVC.

## How the image wires grkr

1. Tool install lives at `/opt/grkr` (`GRKR_GLEAM_PROJECT_ROOT`).
2. Target checkout + state live at `/workspace` (`GRKR_ROOT`).
3. Entrypoint clones `REPO` into `/workspace` when the volume is empty.
4. Workers are resolved under `$GRKR_ROOT/bin/*` — entrypoint symlinks `/opt/grkr/bin` into the workspace when missing.
5. Config is generated at `/workspace/.grkr/config.sh` from env (or your mounted file).

## Security notes

- Prefer `github.existingSecret` over `--set github.token=...` in shared clusters.
- Tokenized clone URLs are set in-process for `git`/`gh`; do not bake tokens into images.
- Dropped Linux capabilities + non-root uid `10001`.
- Supervisor can push branches and open PRs — scope the token accordingly.

## Limitations

- No HTTP health endpoint yet (optional exec probes only).
- Coding agent auth (ChatGPT/Codex login, grok login) must be provided via mounted config/home or API keys.
- Multi-replica HA is not supported (shared worktree/lock model).
