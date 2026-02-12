#!/bin/bash
# GKE Cluster Creation Script for GKE Native Gateway + KServe on TPU
# Pattern 1: Single model baseline with EPP routing
# Deployment: llm-d-infra-xks-gke-tpu-native-gateway

set -e

# Configuration
export CLUSTER_NAME=${CLUSTER_NAME:-llmd-native-gateway-tpu-pattern1}
export ZONE=${ZONE:-europe-west4-a}
export PROJECT=${PROJECT:-ecoeng-llmd}
export REGION=${REGION:-europe-west4}

echo "========================================="
echo "GKE Cluster Creation"
echo "========================================="
echo "Cluster Name: $CLUSTER_NAME"
echo "Zone: $ZONE"
echo "Project: $PROJECT"
echo "========================================="

# Verify gcloud is configured
if ! gcloud config get-value project &> /dev/null; then
  echo "ERROR: gcloud CLI not configured. Run 'gcloud auth login' first."
  exit 1
fi

# Set project
gcloud config set project $PROJECT

# Check quotas (optional - skip if gcloud command fails)
echo ""
echo "Checking TPU quotas..."
TPU_QUOTA=$(gcloud compute project-info describe --project=$PROJECT 2>/dev/null | grep -i "tpu" || echo "")

if [ -z "$TPU_QUOTA" ]; then
  echo "Note: Could not verify TPU quota automatically."
  echo "If cluster creation fails, request TPU v6e quota at:"
  echo "https://console.cloud.google.com/iam-admin/quotas?project=$PROJECT"
  echo ""
  echo "Proceeding with cluster creation..."
fi

# Create base cluster
echo ""
echo "Creating GKE cluster with default node pool..."
echo "⚠️  Gateway API will be enabled (--gateway-api=standard)"
echo "⚠️  GatewayClasses may take 30-45 minutes to appear after cluster creation"
gcloud container clusters create $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT \
  --cluster-version=1.34 \
  --machine-type=n1-standard-4 \
  --num-nodes=2 \
  --enable-ip-alias \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=4 \
  --gateway-api=standard \
  --addons=HttpLoadBalancing,GcePersistentDiskCsiDriver,NetworkPolicy \
  --enable-network-policy \
  --workload-pool=$PROJECT.svc.id.goog \
  --enable-shielded-nodes \
  --shielded-secure-boot \
  --shielded-integrity-monitoring \
  --release-channel=regular

echo ""
echo "Cluster created successfully!"

# Get credentials
echo ""
echo "Getting cluster credentials..."
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT

# Verify nodes
echo ""
echo "Verifying cluster nodes..."
kubectl get nodes -o wide

# Create TPU node pool
echo ""
echo "Creating TPU v6e node pool..."
gcloud container node-pools create tpu-v6e-pool \
  --cluster=$CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT \
  --machine-type=ct6e-standard-4t \
  --num-nodes=1 \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=3 \
  --node-locations=$ZONE \
  --node-taints=google.com/tpu=present:NoSchedule \
  --node-labels=cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice,cloud.google.com/gke-tpu-topology=2x2

echo ""
echo "TPU node pool created successfully!"

# Verify TPU node
echo ""
echo "Verifying TPU nodes..."
sleep 30  # Wait for node to register
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice

# Show TPU node details
echo ""
echo "TPU node details:"
TPU_NODE=$(kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice -o name | head -1)
if [ -n "$TPU_NODE" ]; then
  kubectl describe $TPU_NODE | grep -A 5 "Capacity:"
else
  echo "WARNING: TPU node not found yet. It may still be provisioning."
fi

# Verify Gateway API enabled
echo ""
echo "Verifying Gateway API configuration..."
GATEWAY_API_STATUS=$(gcloud container clusters describe $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT \
  --format="value(addonsConfig.gatewayApiConfig.channel)" 2>/dev/null || echo "unknown")

echo "Gateway API Status: $GATEWAY_API_STATUS"

if [ "$GATEWAY_API_STATUS" = "CHANNEL_STANDARD" ]; then
  echo "✅ Gateway API is enabled"
  echo "⚠️  Note: GatewayClasses may take 30-45 minutes to appear"
  echo "   Check with: kubectl get gatewayclass"
else
  echo "⚠️  Warning: Gateway API status unexpected. Expected: CHANNEL_STANDARD"
fi

# Summary
echo ""
echo "========================================="
echo "Cluster Creation Complete!"
echo "========================================="
echo "Cluster Name: $CLUSTER_NAME"
echo "Zone: $ZONE"
echo "Project: $PROJECT"
echo "Variant: GKE Native Gateway (no Istio)"
echo ""
echo "Node Pools:"
kubectl get nodes -o custom-columns=NAME:.metadata.name,POOL:.metadata.labels.cloud\\.google\\.com/gke-nodepool,MACHINE:.metadata.labels.node\\.kubernetes\\.io/instance-type
echo ""
echo "Gateway API:"
echo "  - Status: $GATEWAY_API_STATUS"
echo "  - GatewayClasses will appear in 30-45 min (first time)"
echo ""
echo "Next Steps:"
echo "1. Deploy cert-manager (cd /home/jhull/devel/llm-d-infra-xks && make deploy-cert-manager)"
echo "2. Deploy KServe (make deploy-kserve)"
echo "3. Fix KServe template for GKE Gateway (see QUICKSTART.md)"
echo "4. Create GKE Gateway (wait for GatewayClasses first)"
echo "5. Deploy LLMInferenceService"
echo ""
echo "Cost Estimate:"
echo "  - Default pool (2 × n1-standard-4): ~\$6/day"
echo "  - TPU v6e pool (1 × ct6e-standard-4t): ~\$127/day"
echo "  - Total (running): ~\$133/day (~\$3,990/month)"
echo "  - Total (scaled to 0): ~\$4/day (~\$120/month)"
echo ""
echo "Documentation:"
echo "  - Quick Start: QUICKSTART.md"
echo "  - Full Guide: README.md"
echo "  - Known Issues: ISSUES.md"
echo ""
echo "To delete cluster: gcloud container clusters delete $CLUSTER_NAME --zone=$ZONE --project=$PROJECT --quiet"
echo "========================================="
