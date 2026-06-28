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
    azure-challenges/challenge-2
    (calls bootstrap.sh after terraform apply)
```

## What this repo manages

| Component | Description |
|---|---|
| **Bootstrap script** | `scripts/bootstrap.sh` — installs Gatekeeper, ESO, Gateway API CRDs, applies OPA policies |
| **OPA constraint templates** | Rego-based policy templates (required labels, allowed registries) |
| **Gatekeeper constraints** | Per-environment constraints (dryrun for dev, deny for prod) |
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
│       ├── dev/                     # enforcementAction: dryrun
│       │   ├── require-app-labels.yaml
│       │   └── allowed-registries.yaml
│       └── prod/                    # enforcementAction: deny
│           ├── require-app-labels.yaml
│           └── allowed-registries.yaml
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
3. Installs External Secrets Operator via Helm
4. Installs Gateway API CRDs (Cilium handles the data plane)
5. Applies constraint templates
6. Applies per-environment constraints (dryrun for dev, deny for prod)

## Branching Strategy

| Branch | Environment | Trigger |
|---|---|---|
| `dev` | dev cluster | Push runs bootstrap for dev |
| `main` | prod cluster | Push runs bootstrap for prod (with approval) |

## Related Repos

- [helm-gatekeeper](https://github.com/KT-MakeDevOpsEasy/helm-gatekeeper) — Gatekeeper Helm configuration
- [azure-challenges](https://github.com/KT-MakeDevOpsEasy/azure-challenges) — Challenge deployments (VNET + AKS)
- [aks-app-deployment](https://github.com/KT-MakeDevOpsEasy/aks-app-deployment) — Application Helm charts
