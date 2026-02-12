# Helm-Based KServe Deployment Guide

This guide documents deploying KServe on GKE using the **rhaii-xks-kserve Helm chart** instead of kustomize.

## Why Helm Chart?

**Advantages over kustomize approach:**
- ✅ Versioned releases - pin specific chart versions
- ✅ Simpler upgrades - `helm upgrade` with rollback support
- ✅ Declarative configuration - values.yaml for customization
- ✅ Dependency management - CRDs applied separately
- ✅ Official Red Hat AI Inference images
- ✅ Cleaner uninstall - `helm uninstall` removes all resources

**Version Deployed:**
- **KServe**: 3.4.0-ea.1 (likely v0.16 development build)
- **Chart**: rhaii-xks-kserve (pierdipi/rhaii-xks-kserve)
- **Images**: All from `registry.redhat.io` (Red Hat AI Inference)

---

## Prerequisites

### Required Tools

```bash
# Verify versions
kubectl version --client  # Need 1.28+
helm version              # Need v3.17+
gcloud version            # Need latest
```

### Required Repositories

```bash
# Clone the Helm chart
cd /home/jhull/devel
git clone https://github.com/pierdipi/rhaii-xks-kserve.git
cd rhaii-xks-kserve

# Verify chart structure
ls -la
# Expected: Chart.yaml, crds/, templates/, values.yaml
```

### Required Credentials

1. **Red Hat Registry Service Account** (for KServe and vLLM images)
   - Get from: https://access.redhat.com/terms-based-registry/
   - Login: `podman login registry.redhat.io`

2. **HuggingFace Token** (for model access)
   - Get from: https://huggingface.co/settings/tokens

3. **Google Cloud Access**
   - Project: `ecoeng-llmd`
   - Permissions: `container.admin`, `compute.admin`

---

## Full Deployment: Fresh Cluster

### Step 1: Create GKE Cluster (20 min)

```bash
export CLUSTER_NAME=llmd-helm-kserve-tpu
export ZONE=europe-west4-a
export PROJECT=ecoeng-llmd

# Create cluster with Gateway API enabled
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

# Get credentials
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT

# Create TPU node pool
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

# Verify
kubectl get nodes
kubectl api-resources | grep gateway.networking.k8s.io
```

### Step 2: Deploy cert-manager (10 min)

```bash
cd /home/jhull/devel/llm-d-infra-xks

# Configure Red Hat authentication
podman login registry.redhat.io
# Enter service account credentials

# Deploy cert-manager only (no Istio)
make deploy-cert-manager

# Verify
kubectl get pods -n cert-manager
kubectl get pods -n cert-manager-operator
```

### Step 3: Deploy KServe via Helm Chart (5 min)

#### 3.1 Create Namespace and Secrets

```bash
# Create opendatahub namespace
kubectl create namespace opendatahub

# Copy Red Hat pull secret to opendatahub
kubectl get secret redhat-pull-secret -n cert-manager -o yaml | \
  sed 's/namespace: cert-manager/namespace: opendatahub/' | \
  kubectl apply -f -
```

#### 3.2 Apply CRDs First

**Important**: CRDs must be applied separately to avoid hitting Helm's 1MB secret size limit.

```bash
cd /home/jhull/devel/rhaii-xks-kserve

# Apply CRDs server-side (handles ownership conflicts gracefully)
kubectl apply -f crds/ --server-side --force-conflicts

# Verify CRDs installed
kubectl get crd | grep -E "serving.kserve.io|inference.networking"
```

**Expected CRDs:**
- `llminferenceservices.serving.kserve.io`
- `llminferenceserviceconfigs.serving.kserve.io`
- `inferencepools.inference.networking.k8s.io`
- `inferencepools.inference.networking.x-k8s.io`
- `inferencemodels.inference.networking.x-k8s.io`
- `inferenceobjectives.inference.networking.x-k8s.io`

#### 3.3 Install Helm Chart

```bash
# Install KServe controller
helm install rhaii-xks-kserve . \
  --namespace opendatahub \
  --wait \
  --timeout 10m

# Verify installation
helm list -n opendatahub
kubectl get pods -n opendatahub
```

**Expected Output:**
```
NAME                NAMESPACE   REVISION STATUS   CHART                APP VERSION
rhaii-xks-kserve    opendatahub 1        deployed rhaii-xks-kserve-1.0.0 3.4.0-ea.1

NAME                                     READY   STATUS    RESTARTS   AGE
kserve-controller-manager-xxxxx-xxxxx    1/1     Running   0          2m
```

#### 3.4 Post-Installation Fixes

**Fix 1: Remove HTTPRoute Timeout Fields** (GKE doesn't support them)

```bash
kubectl get llminferenceserviceconfig kserve-config-llm-router-route \
  -n opendatahub -o json | \
  jq 'del(.spec.router.route.http.spec.rules[].timeouts)' | \
  kubectl apply -f -
```

**Fix 2: Install LeaderWorkerSet CRDs** (required for multi-node workloads)

```bash
kubectl apply --server-side \
  -f https://github.com/kubernetes-sigs/lws/releases/download/v0.4.0/manifests.yaml

# Verify
kubectl api-resources | grep leaderworkerset
```

### Step 4: Create GKE Gateway (3-50 min)

⚠️ **Note**: GatewayClasses may take 30-45 minutes to appear after first cluster creation.

```bash
# Wait for GatewayClasses (if needed)
kubectl get gatewayclass
# If empty, wait up to 45 min for GKE controller

# Create Gateway using REGIONAL GatewayClass
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: inference-gateway
  namespace: opendatahub
spec:
  gatewayClassName: gke-l7-regional-external-managed
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
EOF

# Wait for External IP
kubectl get gateway inference-gateway -n opendatahub -w
# Press Ctrl+C when PROGRAMMED=True

# Capture Gateway IP
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub \
  -o jsonpath='{.status.addresses[0].value}')
echo "Gateway IP: $GATEWAY_IP"
```

### Step 5: Deploy LLMInferenceService (30 min)

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu-native-gateway

# Create namespace
export NAMESPACE=llm-d-inference-scheduling
kubectl create namespace $NAMESPACE

# Copy Red Hat pull secret
kubectl get secret redhat-pull-secret -n cert-manager -o yaml | \
  sed "s/namespace: cert-manager/namespace: $NAMESPACE/" | \
  kubectl apply -f -

# Create HuggingFace token secret
kubectl create secret generic hf-token \
  -n $NAMESPACE \
  --from-literal=HF_TOKEN=YOUR_HUGGINGFACE_TOKEN

# Deploy LLMInferenceService
kubectl apply -f manifests/llmisvc-tpu.yaml

# Monitor deployment
kubectl get llmisvc -n $NAMESPACE -w
# Wait for READY = True (~12-15 minutes)
```

### Step 6: Verify and Test (10 min)

```bash
# Check all resources
kubectl get llmisvc -n $NAMESPACE
kubectl get httproute -n $NAMESPACE
kubectl get inferencepool -n $NAMESPACE
kubectl get pods -n $NAMESPACE

# Run tests
./scripts/test-cluster.sh

# Manual test
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/health

curl -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-3B-Instruct",
    "prompt": "Hello, how are you?",
    "max_tokens": 50
  }'
```

---

## Helm Chart Management

### Upgrade KServe

```bash
cd /home/jhull/devel/rhaii-xks-kserve

# Pull latest chart changes
git pull

# Upgrade installation
helm upgrade rhaii-xks-kserve . \
  --namespace opendatahub \
  --wait \
  --timeout 10m

# Check upgrade status
helm list -n opendatahub
helm history rhaii-xks-kserve -n opendatahub
```

### Rollback KServe

```bash
# List revisions
helm history rhaii-xks-kserve -n opendatahub

# Rollback to previous revision
helm rollback rhaii-xks-kserve -n opendatahub

# Rollback to specific revision
helm rollback rhaii-xks-kserve 1 -n opendatahub
```

### Uninstall KServe

```bash
# Uninstall Helm release
helm uninstall rhaii-xks-kserve -n opendatahub

# Clean up CRDs (optional - if you want complete removal)
kubectl delete crd llminferenceservices.serving.kserve.io
kubectl delete crd llminferenceserviceconfigs.serving.kserve.io
kubectl delete crd -l app.kubernetes.io/part-of=kserve
```

### Customize Helm Values

```bash
# Create custom values file
cat > custom-values.yaml <<EOF
# Custom configuration for rhaii-xks-kserve
controller:
  replicas: 2  # HA setup
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi

# Add custom annotations
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
EOF

# Install with custom values
helm install rhaii-xks-kserve /home/jhull/devel/rhaii-xks-kserve \
  --namespace opendatahub \
  --values custom-values.yaml \
  --wait
```

---

## Troubleshooting

### Helm Install Fails: Resource Already Exists

**Symptom:**
```
Error: INSTALLATION FAILED: Unable to continue with install: ServiceAccount "kserve-controller-manager"
in namespace "opendatahub" exists and cannot be imported into the current release
```

**Cause**: Leftover resources from previous kustomize deployment

**Solution:**
```bash
# Delete all kserve-related resources
kubectl delete all -n opendatahub -l app.kubernetes.io/part-of=kserve
kubectl delete serviceaccount,role,rolebinding -n opendatahub -l app.kubernetes.io/part-of=kserve
kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/part-of=kserve
kubectl delete configmap,secret -n opendatahub -l app.kubernetes.io/part-of=kserve

# Delete CRDs
kubectl delete crd llminferenceservices.serving.kserve.io
kubectl delete crd llminferenceserviceconfigs.serving.kserve.io

# Retry Helm install
helm install rhaii-xks-kserve /home/jhull/devel/rhaii-xks-kserve \
  --namespace opendatahub \
  --wait
```

### CRD Application Conflicts

**Symptom:**
```
error: Apply failed with conflicts: conflicts with "kube-addon-manager"
```

**Solution:**
```bash
# Use --force-conflicts flag
kubectl apply -f /home/jhull/devel/rhaii-xks-kserve/crds/ \
  --server-side \
  --force-conflicts
```

### Helm Uninstall Leaves Resources Behind

**Symptom**: Resources remain after `helm uninstall`

**Explanation**: CRDs are intentionally not deleted by Helm (safety feature)

**Solution:**
```bash
# Manual CRD cleanup
kubectl get crd | grep serving.kserve.io
kubectl delete crd llminferenceservices.serving.kserve.io
kubectl delete crd llminferenceserviceconfigs.serving.kserve.io

# Clean up InferencePool CRDs (if needed)
kubectl get crd | grep inference.networking
kubectl delete crd inferencepools.inference.networking.k8s.io
kubectl delete crd inferencepools.inference.networking.x-k8s.io
```

---

## Comparison: Helm vs Kustomize

| Aspect | Kustomize (Old) | **Helm Chart (New)** |
|--------|----------------|----------------------|
| **Deployment** | `kustomize build ... \| kubectl apply` | `helm install` ✅ |
| **Upgrades** | Manual re-apply, no versioning | `helm upgrade` with rollback ✅ |
| **Configuration** | Patch overlays | values.yaml ✅ |
| **Uninstall** | Manual resource tracking | `helm uninstall` ✅ |
| **Versioning** | Git ref only | Chart versions ✅ |
| **Dependencies** | Manual CRD apply | CRD management ✅ |
| **Ownership** | Server-side apply conflicts | Helm manages ownership ✅ |
| **KServe Version** | v0.15 | **3.4.0-ea.1** ✅ |

**Recommendation**: Use Helm chart for all new deployments. Kustomize approach is deprecated.

---

## Migration from Kustomize to Helm

**If you have existing kustomize-based deployment:**

### Option 1: Clean Slate (Recommended)

```bash
# Delete cluster completely
gcloud container clusters delete <cluster-name> \
  --zone=<zone> \
  --project=ecoeng-llmd \
  --quiet

# Redeploy with Helm chart (follow Step 1-6 above)
```

### Option 2: In-Place Migration (Advanced)

**Warning**: Complex migration with potential downtime. Not recommended for production.

```bash
# 1. Backup existing configuration
kubectl get llmisvc -n llm-d-inference-scheduling -o yaml > backup-llmisvc.yaml
kubectl get llminferenceserviceconfig -n opendatahub -o yaml > backup-configs.yaml

# 2. Scale down workloads
kubectl delete llmisvc --all -n llm-d-inference-scheduling

# 3. Remove kustomize-based KServe
kubectl delete deployment kserve-controller-manager -n opendatahub
kubectl delete validatingwebhookconfiguration -l app.kubernetes.io/part-of=kserve
kubectl delete crd llminferenceservices.serving.kserve.io
kubectl delete crd llminferenceserviceconfigs.serving.kserve.io

# 4. Clean up RBAC and resources
kubectl delete serviceaccount,role,rolebinding -n opendatahub -l app.kubernetes.io/part-of=kserve
kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/part-of=kserve
kubectl delete configmap,secret -n opendatahub -l app.kubernetes.io/part-of=kserve

# 5. Wait for cleanup
sleep 30

# 6. Deploy Helm chart (follow Step 3 above)

# 7. Restore workloads
kubectl apply -f backup-llmisvc.yaml
```

---

## Chart Customization Examples

### Example 1: Custom Controller Resources

```yaml
# custom-values.yaml
controller:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 2Gi
```

### Example 2: Custom Image Repository

```yaml
# custom-values.yaml
controller:
  image:
    repository: custom.registry.io/kserve/controller
    tag: 3.4.0-custom
    pullPolicy: IfNotPresent
```

### Example 3: Additional Annotations

```yaml
# custom-values.yaml
controller:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

---

## References

- **Helm Chart Repository**: https://github.com/pierdipi/rhaii-xks-kserve
- **KServe Documentation**: https://kserve.github.io/website/
- **Helm Documentation**: https://helm.sh/docs/
- **GKE Gateway API**: https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api
- **Red Hat AI Inference**: https://www.redhat.com/en/technologies/cloud-computing/openshift/ai

---

**Last Updated**: 2026-02-12
**Chart Version**: 1.0.0
**KServe Version**: 3.4.0-ea.1
**Status**: ✅ Production-Ready - Helm-based deployment tested and validated
