# Operational Procedures

## Initial Platform Setup

```bash
# 1. Get AKS credentials
az aks get-credentials --resource-group rg-demo-dev-eus --name aks-demo-dev-eus

# 2. Install Gatekeeper (OPA policy engine)
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm install gatekeeper gatekeeper/gatekeeper --namespace gatekeeper-system --create-namespace

# 3. Apply constraint templates first, then constraints
kubectl apply -f policies/constraint-templates/
sleep 10
kubectl apply -f policies/constraints/

# 4. Install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace
```

## Monitoring & Alerting

### Container Insights
Enabled via the AKS `oms_agent` addon. Collects:
- Container logs (stdout/stderr)
- Node and pod metrics (CPU, memory, disk, network)
- Kubernetes events

### Key Metrics

| Metric | Warning | Critical |
|--------|---------|----------|
| Node CPU utilization | > 70% | > 90% |
| Node memory utilization | > 75% | > 90% |
| Pod restart count | > 3/hour | > 10/hour |
| PVC usage | > 75% | > 90% |
| API server latency | > 500ms | > 2s |

## Security Checklist

- [ ] Gatekeeper constraints active (required labels, allowed registries)
- [ ] Network policies applied (frontend → backend → database only)
- [ ] Pod security: `runAsNonRoot`, `readOnlyRootFilesystem`, drop all capabilities
- [ ] RBAC: Azure AD integration, no local admin accounts
- [ ] ACR: admin disabled, AcrPull via managed identity
- [ ] Private cluster enabled (prod)

## Troubleshooting

```bash
# Check Gatekeeper violations
kubectl get k8srequiredlabels -o yaml
kubectl get k8sallowedregistries -o yaml

# Check cluster autoscaler status
kubectl -n kube-system logs -f deployment/cluster-autoscaler

# Check node status
kubectl get nodes -o wide
kubectl describe node <node-name>
```
