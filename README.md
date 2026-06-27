# aks-platform-config

Platform-level configuration for AKS clusters — Gatekeeper policies, NGINX Ingress, and operational documentation. References external Helm repos for component installation.

## Architecture

```
helm-gatekeeper (Gatekeeper Helm values, pinned v3.15.0)
helm-ingress-nginx (NGINX Ingress Helm values, pinned v4.10.0)
    │                    │
    └────────┬───────────┘
             ▼
    aks-platform-config (this repo)
    ├── scripts/bootstrap.sh  ← clones both, installs, applies policies
    └── policies/             ← OPA constraint templates + constraints
             │
             ▼
    terraform-aks-deployment
    (calls bootstrap.sh after terraform apply)
```

## What this repo manages

| Component | Description |
|---|---|
| **Bootstrap script** | `scripts/bootstrap.sh` — installs Gatekeeper, applies OPA policies, installs NGINX Ingress |
| **OPA constraint templates** | Rego-based policy templates (required labels, allowed registries) |
| **Gatekeeper constraints** | Constraint instances applied to workloads |
| **Docs** | Architecture decisions, operations runbook, security checklist |

## Structure

```
aks-platform-config/
├── scripts/
│   └── bootstrap.sh                 # Idempotent platform bootstrap
├── policies/
│   ├── constraint-templates/
│   │   ├── require-labels.yaml
│   │   └── restrict-registries.yaml
│   └── constraints/
│       ├── require-app-labels.yaml
│       └── allowed-registries.yaml
├── docs/
│   ├── architecture.md
│   └── operations.md
└── .github/workflows/
    └── deploy-platform.yml
```

## Usage

```bash
# Bootstrap platform onto a cluster (dev or prod)
./scripts/bootstrap.sh dev

# Or for production
./scripts/bootstrap.sh prod
```

The bootstrap script:
1. Clones `helm-gatekeeper` (pinned version) → installs via Helm
2. Waits for Gatekeeper webhook readiness
3. Applies constraint templates, then constraints
4. Clones `helm-ingress-nginx` (pinned version) → installs via Helm

## Branching Strategy

| Branch | Environment | Trigger |
|---|---|---|
| `dev` | dev cluster | Push runs bootstrap for dev |
| `main` | prod cluster | Push runs bootstrap for prod (with approval) |

## Related Repos

- [helm-gatekeeper](https://github.com/KT-MakeDevOpsEasy/helm-gatekeeper) — Gatekeeper Helm configuration
- [helm-ingress-nginx](https://github.com/KT-MakeDevOpsEasy/helm-ingress-nginx) — NGINX Ingress Helm configuration
- [terraform-aks-deployment](https://github.com/KT-MakeDevOpsEasy/terraform-aks-deployment) — AKS infrastructure
- [aks-app-deployment](https://github.com/KT-MakeDevOpsEasy/aks-app-deployment) — Application Helm charts
