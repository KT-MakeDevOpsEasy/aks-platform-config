#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_DIR="${REPO_ROOT}/.bootstrap-tmp"

GATEKEEPER_REPO="https://github.com/KT-MakeDevOpsEasy/helm-gatekeeper.git"
GATEKEEPER_REF="v1.0.0"

INGRESS_REPO="https://github.com/KT-MakeDevOpsEasy/helm-ingress-nginx.git"
INGRESS_REF="v1.0.0"

echo "=== AKS Platform Bootstrap (${ENVIRONMENT}) ==="

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR"

# --- 1. Install Gatekeeper ---
echo "[1/5] Cloning helm-gatekeeper (${GATEKEEPER_REF})..."
git clone --depth 1 --branch "$GATEKEEPER_REF" "$GATEKEEPER_REPO" "$WORK_DIR/helm-gatekeeper"

echo "[2/5] Installing Gatekeeper..."
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
echo "[3/5] Applying constraint templates..."
kubectl apply -f "$REPO_ROOT/policies/constraint-templates/"

echo "Waiting for CRDs to register..."
sleep 15

echo "[4/5] Applying constraints..."
kubectl apply -f "$REPO_ROOT/policies/constraints/"

# --- 3. Install NGINX Ingress ---
echo "[5/5] Cloning helm-ingress-nginx (${INGRESS_REF})..."
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
echo "Ingress Controller pods:"
kubectl get pods -n ingress-nginx
