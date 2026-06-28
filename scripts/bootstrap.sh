#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
ACR_LOGIN_SERVER="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_DIR="${REPO_ROOT}/.bootstrap-tmp"

GATEKEEPER_REPO="https://github.com/KT-MakeDevOpsEasy/helm-gatekeeper.git"
GATEKEEPER_REF="v1.0.0"

GATEWAY_API_VERSION="v1.2.0"
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

# AKS admissionsenforcer reclaims webhook field ownership continuously,
# causing server-side apply conflicts. Delete before upgrade; Helm recreates them.
kubectl delete validatingwebhookconfiguration gatekeeper-validating-webhook-configuration --ignore-not-found
kubectl delete mutatingwebhookconfiguration gatekeeper-mutating-webhook-configuration --ignore-not-found

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

# --- 2. Install External Secrets Operator ---
echo "[3/6] Installing External Secrets Operator (${ESO_VERSION})..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version "$ESO_VERSION" \
  --set installCRDs=true \
  --wait \
  --timeout 5m

# --- 3. Install Gateway API CRDs ---
echo "[4/6] Installing Gateway API CRDs (${GATEWAY_API_VERSION})..."
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

# --- 4. Apply OPA Policies ---
echo "[5/6] Applying constraint templates..."
kubectl apply -f "$REPO_ROOT/policies/constraint-templates/"

echo "Waiting for CRDs to register..."
sleep 15

echo "[6/6] Applying constraints (${ENVIRONMENT})..."
if [[ -n "$ACR_LOGIN_SERVER" ]]; then
  export ACR_LOGIN_SERVER
  envsubst < "$REPO_ROOT/policies/constraints/${ENVIRONMENT}/allowed-registries.yaml" | kubectl apply -f -
  kubectl apply -f "$REPO_ROOT/policies/constraints/${ENVIRONMENT}/require-app-labels.yaml"
else
  echo "WARNING: ACR_LOGIN_SERVER not set, skipping allowed-registries constraint"
  kubectl apply -f "$REPO_ROOT/policies/constraints/${ENVIRONMENT}/require-app-labels.yaml"
fi

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
kubectl get constraints -o custom-columns=NAME:.metadata.name,ACTION:.spec.enforcementAction
echo ""
echo "External Secrets Operator pods:"
kubectl get pods -n external-secrets
echo ""
echo "Gateway API CRDs:"
kubectl get crd | grep gateway || echo "  (none found)"
