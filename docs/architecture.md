# Cluster Architecture

## Network Architecture

```
┌─────────────────────────────────────────────────────────┐
│  VNET: 10.10.0.0/16                                    │
│                                                         │
│  ┌──────────────────────┐  ┌──────────────────────────┐ │
│  │ snet-aks-nodes       │  │ snet-appgw               │ │
│  │ 10.10.1.0/24         │  │ 10.10.2.0/24             │ │
│  │                      │  │                          │ │
│  │  ┌────────────────┐  │  │  ┌────────────────────┐  │ │
│  │  │ System Pool    │  │  │  │ App Gateway /       │  │ │
│  │  │ (1-3 nodes)    │  │  │  │ Ingress Controller  │  │ │
│  │  │ D2s_v3         │  │  │  └────────────────────┘  │ │
│  │  └────────────────┘  │  │                          │ │
│  │                      │  └──────────────────────────┘ │
│  │  ┌────────────────┐  │                               │
│  │  │ Workload Pool  │  │  Services: 172.16.0.0/16      │
│  │  │ (1-5 nodes)    │  │  DNS: 172.16.0.10             │
│  │  │ D4s_v3         │  │                               │
│  │  └────────────────┘  │                               │
│  └──────────────────────┘                               │
└─────────────────────────────────────────────────────────┘
```

## Networking: Azure CNI vs Kubenet

**Chosen: Azure CNI**

| Factor | Azure CNI | Kubenet |
|--------|-----------|---------|
| Pod IPs | Real VNET IPs | NAT'd behind node IP |
| Network Policies | Full support | Limited |
| Performance | Native, no overlay | Extra hop via bridge |
| IP consumption | High (plan subnet size) | Low |
| VNET integration | Direct pod-to-VNET routing | Requires UDR |

Azure CNI is chosen because:
- Pods get first-class VNET citizens (routable IPs), enabling direct connectivity with other Azure services.
- Required for Kubernetes network policies to work properly.
- Better performance for east-west traffic (no NAT overhead).
- Trade-off: requires larger subnets to accommodate pod IPs. A /24 gives ~250 IPs, sufficient for a small-medium cluster.

## Node Pool Strategy

### System Pool
- **Purpose**: Runs Kubernetes system components (CoreDNS, metrics-server, kube-proxy).
- **Taint**: `CriticalAddonsOnly=true:NoSchedule` — prevents application workloads from landing here.
- **Sizing**: D2s_v3 (2 vCPU, 8 GiB) — sufficient for control-plane workloads.
- **Scaling**: 1-3 nodes with cluster autoscaler.

### Workload Pool
- **Purpose**: Runs application pods (frontend, backend, database).
- **Sizing**: D4s_v3 (4 vCPU, 16 GiB) — room for multiple pods with proper resource limits.
- **Scaling**: 1-5 nodes with cluster autoscaler.
- **Zones**: Spread across 3 availability zones for HA.

## Identity & RBAC

- **User-Assigned Managed Identity**: No credential rotation needed.
- **OIDC Issuer** enabled for workload identity federation.
- **Azure AD RBAC**: Cluster access governed by Azure AD group membership.

## API Server Security

- **Dev**: Public API server with optional `authorized_ip_ranges`.
- **Prod**: Recommend `private_cluster_enabled = true` — API server accessible only within VNET.
