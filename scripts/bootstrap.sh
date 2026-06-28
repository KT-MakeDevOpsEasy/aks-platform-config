#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
ACR_LOGIN_SERVER="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_DIR="${REPO_ROOT}/.bootstrap-tmp"

GATEKEEPER_REPO="https://github.com/KT-MakeDevOpsEasy/helm-gatekeeper.git"
GATEKEEPER_REF="v1.0.0"

INGRESS_REPO="https://github.com/KT-MakeDevOpsEasy/helm-ingress-nginx.git"
INGRESS_REF="v1.0.0"

ESO_VERSION="0.10.7"

echo "=== AKS Platform Bootstrap (${ENVIRONMENT}) ==="
echo "ACR Login Server: ${ACR_LOGIN_SERVER:-not set}"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR"

# --- 1. Install Gatekeeper ---
echo "[1/6] Cloning helm-gatekeeper (${GATEKEEPER_REF})..."
git clone --depth 1 --branch "$GATEKEEPER_REF" "$GATEKEEPER_REPO" "$WORK_DIR/helm-gatekeeper"

echo "[2/6] Installing Gatekeeper..."
cd "$WORK_DIR/helm-gatekeeper"
helm dependency update .
helm upgrade --install gatekeeper . \
  --namespace gatekeeper-system \
  --create-namespace \
  -f "values-${ENVIRONMENT}.yaml" \
  --wait \
  --timeout 5m

echo "Waiting for Gatekeeper webhook to be ready..."
kubectl wait --for=condition=ready pod \
  -l control-plane=controller-manager \
  -n gatekeeper-system \
  --timeout=120s

# --- 2. Apply OPA Policies ---
echo "[3/6] Applying constraint templates..."
kubectl apply -f "$REPO_ROOT/policies/constraint-templates/"

echo "Waiting for CRDs to register..."
sleep 15

echo "[4/6] Applying constraints..."
if [[ -n "$ACR_LOGIN_SERVER" ]]; then
  envsubst < "$REPO_ROOT/policies/constraints/allowed-registries.yaml" | kubectl apply -f -
  kubectl apply -f "$REPO_ROOT/policies/constraints/require-app-labels.yaml"
else
  echo "WARNING: ACR_LOGIN_SERVER not set, skipping allowed-registries constraint"
  kubectl apply -f "$REPO_ROOT/policies/constraints/require-app-labels.yaml"
fi

# --- 3. Install External Secrets Operator ---
echo "[5/6] Installing External Secrets Operator (${ESO_VERSION})..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version "$ESO_VERSION" \
  --set installCRDs=true \
  --wait \
  --timeout 5m

# --- 4. Install NGINX Ingress ---
echo "[6/6] Cloning helm-ingress-nginx (${INGRESS_REF})..."
git clone --depth 1 --branch "$INGRESS_REF" "$INGRESS_REPO" "$WORK_DIR/helm-ingress-nginx"

cd "$WORK_DIR/helm-ingress-nginx"
helm dependency update .
helm upgrade --install ingress-nginx . \
  --namespace ingress-nginx \
  --create-namespace \
  -f "values-${ENVIRONMENT}.yaml" \
  --wait \
  --timeout 5m

# --- Verify ---
echo ""
echo "=== Platform Bootstrap Complete ==="
echo "Gatekeeper pods:"
kubectl get pods -n gatekeeper-system
echo ""
echo "Constraint Templates:"
kubectl get constrainttemplates
echo ""
echo "Constraints:"
kubectl get constraints
echo ""
echo "External Secrets Operator pods:"
kubectl get pods -n external-secrets
echo ""
echo "Ingress Controller pods:"
kubectl get pods -n ingress-nginx
