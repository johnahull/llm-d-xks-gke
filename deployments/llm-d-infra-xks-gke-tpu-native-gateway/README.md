# llm-d-infra-xks-gke-tpu-native-gateway

Infrastructure deployment for KServe LLMInferenceService on GKE with TPU v6e acceleration using **GKE native Gateway API** (without Istio service mesh).

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [llm-d-infra-xks](https://github.com/aneeshkp/llm-d-infra-xks) | Infrastructure Helm charts (cert-manager operator) |
| [opendatahub-io/kserve](https://github.com/opendatahub-io/kserve) | KServe controller with LLMInferenceService CRD |

## Overview

| Component | App Version | Description |
|-----------|-------------|-------------|
| cert-manager-operator | 1.15.2 | TLS certificate management |
| GKE Gateway Controller | Built-in | Native GKE Gateway API implementation |
| KServe | v0.15 | LLMInferenceService controller with automatic resource management |

## Deployment Patterns

This deployment supports two patterns:

### Pattern 1: Single Model Baseline ✅ (Default)
- **Replicas:** 1
- **Model:** Qwen/Qwen2.5-3B-Instruct
- **Throughput:** 5-7 req/s (TPU v6e-4)
- **Cost:** ~$133/day (~$3,990/month)
- **Use case:** Development, POC, low-traffic production

**Status:** Deployed and validated (see DEPLOYMENT-COMPLETE.txt)

**Deploy:**
```bash
kubectl apply -f manifests/llmisvc-tpu.yaml
```

### Pattern 3: N/S-Caching Scale-Out 🚀 (Available)
- **Replicas:** 3
- **Model:** Qwen/Qwen2.5-3B-Instruct (same)
- **Throughput:** 15-20 req/s (3× TPU v6e-4 = 12 chips total)
- **Cost:** ~$387/day (~$11,610/month)
- **Cache hit rate:** 60-70% (with shared prompts)
- **Latency:** 10-15% lower than Pattern 1
- **Use case:** High-traffic production, latency-sensitive applications

**Documentation:** See [PATTERN3.md](PATTERN3.md) for comprehensive deployment guide

**Quick Deploy:**
```bash
# Increase TPU node pool capacity
gcloud container node-pools update tpu-v6e-pool \
  --cluster=llmd-native-gateway-tpu-pattern1 \
  --zone=europe-west4-a \
  --max-nodes=3

# Deploy Pattern 3
kubectl apply -f manifests/llmisvc-tpu-pattern3.yaml
```

**Key Benefits:**
- ✅ 2.5-3× higher throughput
- ✅ Intelligent prefix-cache-aware routing via EPP scheduler
- ✅ Built-in redundancy (survive single replica failure)
- ✅ Similar cost per request despite 3× infrastructure

**When to use Pattern 3 instead of Pattern 1:**
- Sustained traffic >10 req/s
- Chatbots/assistants with shared system prompts
- Production SLA requirements
- Cost per request matters more than infrastructure cost

### Version Compatibility

| Component | Version | Notes |
|-----------|---------|-------|
| GKE | 1.34+ | Kubernetes cluster with TPU support and Gateway API |
| Gateway API | v1 | Native GKE implementation (no Istio required) |
| InferencePool API | v1 | `inference.networking.k8s.io/v1` |
| KServe | release-v0.15 | LLMInferenceService controller with automatic HTTPRoute/InferencePool creation |
| TPU | v6e | 4-chip configuration (2×2 topology) |

### Key Differences from Istio Variant

| Feature | Istio Variant | **GKE Native Gateway** (This) |
|---------|---------------|-------------------------------|
| Service Mesh | ✅ Istio (sail-operator) | ❌ None |
| Gateway Controller | Istio Gateway | GKE Gateway (built-in) |
| Infrastructure Pods | cert-manager + Istio + LWS (~6 pods) | cert-manager + KServe (~4 pods) |
| mTLS between services | ✅ Automatic | ❌ Not included |
| Observability | ✅ Istio telemetry | Basic (Kubernetes metrics) |
| Resource Usage | Higher | **Lower** ✅ |
| Deployment Complexity | Moderate | **Simpler** ✅ |
| Cost (infrastructure) | ~$6/day | **~$4/day** ✅ |

**When to use this variant:**
- ✅ Simpler infrastructure preferred
- ✅ Lower cost priority
- ✅ Don't need service mesh features (mTLS, advanced traffic management)
- ✅ Faster deployment (fewer components)

**When to use Istio variant instead:**
- Need mTLS between services
- Require advanced traffic management (retries, circuit breakers, etc.)
- Want comprehensive observability (Istio telemetry)
- Multi-cluster or hybrid cloud deployment

## Prerequisites

- GKE cluster with TPU v6e support (see [GKE Cluster Creation](#step-1-create-gke-cluster-15-20-min) below)
- `kubectl` (1.28+), `helm` (v3.17+), `kustomize` (v5.7+)
- `gcloud` CLI installed and configured
- Red Hat account (for KServe and vLLM images from `registry.redhat.io`)
- HuggingFace token for model access
- Google Cloud project with TPU quota (minimum 4 chips)

### Red Hat Pull Secret Setup

The KServe controller and RHAIIS vLLM images are hosted on `registry.redhat.io` which requires authentication.
Choose **one** of the following methods:

#### Method 1: Registry Service Account (Recommended)

Create a Registry Service Account (works for both KServe and vLLM images):

1. Go to: https://access.redhat.com/terms-based-registry/
2. Click "New Service Account"
3. Create account and note the username (e.g., `12345678|myserviceaccount`)
4. Login with the service account credentials:

```bash
$ podman login registry.redhat.io
Username: {REGISTRY-SERVICE-ACCOUNT-USERNAME}
Password: {REGISTRY-SERVICE-ACCOUNT-PASSWORD}
Login Succeeded!

# Verify it works
$ podman pull registry.redhat.io/rhaiis/vllm-tpu-rhel9:3.2.5
```

Then configure `values.yaml` in llm-d-infra-xks:
```yaml
useSystemPodmanAuth: true
```

**Alternative:** Download the pull secret file (OpenShift secret tab) and copy to persistent location:
```bash
mkdir -p ~/.config/containers
cp ~/pull-secret.txt ~/.config/containers/auth.json
```

> **Note:** Registry Service Accounts are recommended as they don't expire like personal credentials.

#### Method 2: Podman Login with Red Hat Account (For Developers)

If you have direct Red Hat account access (e.g., internal developers):

```bash
$ podman login registry.redhat.io
Username: {YOUR-REDHAT-USERNAME}
Password: {YOUR-REDHAT-PASSWORD}
Login Succeeded!
```

This stores credentials in `${XDG_RUNTIME_DIR}/containers/auth.json` or `~/.config/containers/auth.json`.

Then configure `values.yaml`:
```yaml
useSystemPodmanAuth: true
```

### GKE-Specific Prerequisites

#### Google Cloud Project Setup

```bash
# Authenticate with Google Cloud
gcloud auth login

# Set project
export PROJECT=ecoeng-llmd
gcloud config set project $PROJECT

# Verify access
gcloud projects describe $PROJECT
```

#### TPU Quota Requirements

**Minimum Quota Needed:**
- **TPU v6e chips**: 4 chips (for single ct6e-standard-4t node)

**Check Current Quota:**
```bash
gcloud compute project-info describe --project=$PROJECT | grep -i tpu
```

**Request Quota Increase** (if needed):
1. Go to: https://console.cloud.google.com/iam-admin/quotas?project=$PROJECT
2. Search for "TPU v6e"
3. Request quota for desired region

#### Zone Availability

⚠️ **Important**: TPU availability for GKE node pools differs from TPU VMs. Always validate before cluster creation.

**Confirmed Working Zones for GKE TPU v6e Node Pools:**

| Zone | Region | Status | Notes |
|------|--------|--------|-------|
| `europe-west4-a` | europe-west4 (Netherlands) | ✅ **Verified** | **Recommended** - Confirmed working |
| `us-east1-d` | us-east1 (South Carolina) | ⚠️ Check | May have capacity |
| `us-east5-a` | us-east5 (Columbus) | ⚠️ Check | May have capacity |
| `us-east5-b` | us-east5 (Columbus) | ⚠️ Check | May have capacity |
| `us-central1-a` | us-central1 (Iowa) | ❌ **Not Supported** | TPU VMs only, not GKE |
| `us-central1-b` | us-central1 (Iowa) | ❌ **Stockouts** | GCE_STOCKOUT errors |
| `us-south1-a` | us-south1 (Dallas) | ❌ **No ct6e** | Only ct5lp/ct5p available |

**Validate TPU availability** before cluster creation:
```bash
# Method 1: Use helper script (recommended)
cd /home/jhull/devel/llm-d-xks-gke
./check-gke-tpu-availability.sh

# Method 2: Check specific zone
./check-nodepool-prerequisites.sh \
  --project ecoeng-llmd \
  --zone europe-west4-a \
  --machine-type ct6e-standard-4t

# Method 3: Manual check
gcloud compute tpus accelerator-types list --zone=europe-west4-a | grep v6e
```

**See Also**: [ISSUES.md#1-tpu-zone-availability-issues](ISSUES.md#1-tpu-zone-availability-issues) for detailed troubleshooting

---

## Quick Start

### Step 1: Create GKE Cluster (15-20 min)

```bash
cd cluster-config
./create-cluster.sh
```

This script creates:
- Base GKE cluster (2 × n1-standard-4 CPU nodes)
- TPU v6e node pool (1 × ct6e-standard-4t with autoscaling 0-3)
- **Gateway API enabled** (automatically enabled in GKE 1.34+)
- NetworkPolicy enabled
- Workload Identity enabled

**Verify:**
```bash
kubectl get nodes
# Expected: 2 CPU nodes + 1 TPU node

kubectl api-resources | grep gateway.networking.k8s.io
# Expected: GatewayClass, Gateway, HTTPRoute available
```

<details>
<summary>Manual cluster creation commands (click to expand)</summary>

```bash
# Set configuration
export CLUSTER_NAME=llmd-gke-native-tpu-pattern1
export ZONE=europe-west4-a
export PROJECT=ecoeng-llmd

# Create base cluster
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
```

</details>

### Step 2: Deploy Infrastructure (5 min)

**Note:** This variant uses minimal infrastructure - only cert-manager is needed from llm-d-infra-xks.

```bash
# Clone llm-d-infra-xks repository (if not already cloned)
cd /home/jhull/devel
git clone https://github.com/aneeshkp/llm-d-infra-xks.git
cd llm-d-infra-xks

# Deploy only cert-manager (no Istio, no LWS)
make deploy-cert-manager

# Check status
kubectl get pods -n cert-manager
```

**Verify:**
```bash
kubectl get pods -n cert-manager       # 3 pods Running
kubectl get pods -n cert-manager-operator  # 1 pod Running
```

### Step 3: Deploy KServe (3-5 min)

```bash
cd /home/jhull/devel/llm-d-infra-xks

make deploy-kserve

# Verify
kubectl get pods -n opendatahub
kubectl get llminferenceserviceconfig -n opendatahub
```

<details>
<summary>Manual steps (click to expand)</summary>

```bash
# Create opendatahub namespace
kubectl create namespace opendatahub --dry-run=client -o yaml | kubectl apply -f -

# Copy pull secret
kubectl get secret redhat-pull-secret -n cert-manager -o yaml | \
  sed 's/namespace: cert-manager/namespace: opendatahub/' | \
  kubectl apply -f -

# Apply cert-manager PKI resources first
kubectl apply -k "https://github.com/opendatahub-io/kserve/config/overlays/odh-test/cert-manager?ref=release-v0.15"
kubectl wait --for=condition=Ready clusterissuer/opendatahub-ca-issuer --timeout=120s

# First apply - creates CRDs and deployment
kustomize build "https://github.com/opendatahub-io/kserve/config/overlays/odh-xks?ref=release-v0.15" | kubectl apply --server-side --force-conflicts -f - || true

# Delete webhooks to allow controller startup
kubectl delete validatingwebhookconfiguration llminferenceservice.serving.kserve.io llminferenceserviceconfig.serving.kserve.io --ignore-not-found

# Wait for controller to be ready
kubectl wait --for=condition=Available deployment/kserve-controller-manager -n opendatahub --timeout=300s

# Second apply - now webhooks work
kustomize build "https://github.com/opendatahub-io/kserve/config/overlays/odh-xks?ref=release-v0.15" | kubectl apply --server-side --force-conflicts -f -

# Verify LLMInferenceServiceConfig templates exist
kubectl get llminferenceserviceconfig -n opendatahub
```

</details>

**Post-Installation: Fix KServe Template for GKE Gateway**

⚠️ **Required**: KServe ships with HTTPRoute templates that include timeout fields not supported by GKE Gateway.

```bash
# Fix kserve-config-llm-router-route template (remove unsupported timeouts)
kubectl get llminferenceserviceconfig kserve-config-llm-router-route -n opendatahub -o json | \
  jq 'del(.spec.router.route.http.spec.rules[].timeouts)' | \
  kubectl apply -f -

# Expected warning (safe to ignore):
# Warning: modifying well-known config opendatahub/kserve-config-llm-router-route is not recommended
```

**Install LeaderWorkerSet CRDs** (required by KServe for multi-node workloads):
```bash
kubectl apply --server-side \
  -f https://github.com/kubernetes-sigs/lws/releases/download/v0.4.0/manifests.yaml

# Verify
kubectl api-resources | grep leaderworkerset
```

See [ISSUES.md#8-kserve-template-contains-unsupported-timeouts](ISSUES.md#8-kserve-template-contains-unsupported-timeouts) and [ISSUES.md#6-leaderworkerset-crd-missing](ISSUES.md#6-leaderworkerset-crd-missing)

### Step 4: Create GKE Gateway (3-50 min)

**Important Notes:**
- GKE's native Gateway controller is used (no Istio)
- **Must use regional GatewayClass** for InferencePool support
- GatewayClasses may take **30-45 minutes** to appear after enabling Gateway API (one-time wait)

**Wait for GatewayClasses** (if this is first Gateway after cluster creation):
```bash
# Check if GatewayClasses are available
kubectl get gatewayclass

# If empty, wait for GKE controller to reconcile (up to 45 min after enabling --gateway-api=standard)
while true; do
  echo "$(date): Checking GatewayClasses..."
  COUNT=$(kubectl get gatewayclass --no-headers 2>/dev/null | wc -l)
  if [ "$COUNT" -gt 0 ]; then
    echo "GatewayClasses available!"
    kubectl get gatewayclass
    break
  fi
  echo "Still waiting... (this can take up to 45 minutes on first reconciliation)"
  sleep 120
done
```

See [ISSUES.md#4-gatewayclasses-delayed-appearance](ISSUES.md#4-gatewayclasses-delayed-appearance)

**Create namespace** (if not already exists):
```bash
kubectl create namespace opendatahub --dry-run=client -o yaml | kubectl apply -f -
```

**Create Gateway** using **regional** GatewayClass:
```bash
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: inference-gateway
  namespace: opendatahub
spec:
  gatewayClassName: gke-l7-regional-external-managed  # ⚠️ MUST use regional for InferencePool
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
EOF
```

⚠️ **Critical**: Use `gke-l7-regional-external-managed` (NOT `gke-l7-global-external-managed`)

**Why regional GatewayClass?**
- ✅ **InferencePool support** (required for EPP scheduler)
- ✅ Lower latency within region
- ❌ Global GatewayClass does **NOT** support InferencePool backends

See [ISSUES.md#10-gatewayclass-support-for-inferencepool](ISSUES.md#10-gatewayclass-support-for-inferencepool)

**Wait for External IP** (takes ~2-3 minutes):
```bash
kubectl get gateway inference-gateway -n opendatahub -w
# Wait for PROGRAMMED=True and ADDRESS populated
# Press Ctrl+C when ready
```

**Capture Gateway IP:**
```bash
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub \
  -o jsonpath='{.status.addresses[0].value}')

echo "Gateway IP: $GATEWAY_IP"

# Save for later use
echo "GATEWAY_IP=$GATEWAY_IP" > /tmp/gateway-ip.txt
```

### Step 5: Deploy LLMInferenceService (2-5 min)

#### Create Namespace and Secrets

```bash
# Create namespace
export NAMESPACE=llm-d-inference-scheduling
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Copy Red Hat pull secret
kubectl get secret redhat-pull-secret -n cert-manager -o yaml | \
  sed "s/namespace: cert-manager/namespace: $NAMESPACE/" | \
  kubectl apply -f -

# Create HuggingFace token secret
kubectl create secret generic hf-token \
  -n $NAMESPACE \
  --from-literal=HF_TOKEN=YOUR_HUGGINGFACE_TOKEN \
  --dry-run=client -o yaml | kubectl apply -f -
# Replace YOUR_HUGGINGFACE_TOKEN with your actual token
```

#### Deploy LLMInferenceService

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu-native-gateway

# Apply the LLMInferenceService manifest
kubectl apply -f manifests/llmisvc-tpu.yaml
```

This manifest defines:
- **Model**: Qwen/Qwen2.5-3B-Instruct
- **TPU Configuration**: 4 chips (2×2 topology), tensor parallelism
- **Routing**: Automatic HTTPRoute and InferencePool creation with EPP scheduler
- **Health Probes**: Extended delays (240s) for TPU initialization
- **Gateway**: References GKE Gateway (not Istio Gateway)

**Watch deployment progress** (~12-15 min for model download + TPU compilation):
```bash
kubectl get llmisvc -n $NAMESPACE -w
# Wait for READY = True
```

**Verify auto-created resources:**
```bash
# Check HTTPRoute (auto-created by KServe)
kubectl get httproute -n $NAMESPACE

# Check InferencePool (auto-created by KServe)
kubectl get inferencepool -n $NAMESPACE

# Check pods
kubectl get pods -n $NAMESPACE
```

**Post-Deployment: Fix GCP Health Checks** (after pod is Ready)

⚠️ **Optional but Recommended**: GCP auto-creates health checks with incorrect defaults.

```bash
# Wait for pod to be Ready
kubectl wait --for=condition=Ready pod \
  -l serving.kserve.io/inferenceservice=qwen2-3b-pattern1 \
  -n $NAMESPACE \
  --timeout=20m

# List backend services
gcloud compute backend-services list \
  --filter="name~qwen2" \
  --project=ecoeng-llmd \
  --format="table(name,healthChecks)"

# Fix InferencePool backend health check (replace <backend-name> with actual name)
gcloud compute health-checks update http <inferencepool-health-check-name> \
  --region=europe-west4 \
  --project=ecoeng-llmd \
  --request-path=/health

# Check health status
gcloud compute backend-services get-health <inferencepool-backend-name> \
  --region=europe-west4 \
  --project=ecoeng-llmd
# Should show: healthState: HEALTHY
```

**Note**: The `/v1/models` endpoint may show TLS errors due to Service `appProtocol: https` mismatch. This is a known issue and **does not affect core functionality**. See [ISSUES.md#11-service-appprotocol-hardcoded-to-https](ISSUES.md#11-service-appprotocol-hardcoded-to-https)

**Working endpoints** (via InferencePool):
- ✅ `/v1/completions`
- ✅ `/v1/chat/completions`

### Step 6: Test Inference (5-10 min)

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu-native-gateway

# Get Gateway external IP
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub \
  -o jsonpath='{.status.addresses[0].value}')

echo "Gateway IP: $GATEWAY_IP"

# Test health endpoint
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/health

# List available models
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/models

# Test completion
curl -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-3B-Instruct",
    "prompt": "Hello, how are you?",
    "max_tokens": 50
  }'

# Test chat completion
curl -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-3B-Instruct",
    "messages": [{"role": "user", "content": "What is Kubernetes?"}],
    "max_tokens": 100
  }'
```

**Run automated tests:**
```bash
./scripts/test-cluster.sh
```

See results in `/tmp/test-results-*.txt`

---

### Step 7: Run Performance Benchmarks (15 min)

Comprehensive performance benchmarking to measure throughput, latency, and scalability.

**Run Python benchmark** (recommended - supports HTTP/1.1):
```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu-native-gateway/scripts

# Get Gateway IP
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub \
  -o jsonpath='{.status.addresses[0].value}')

# Run comprehensive benchmark
python3 benchmark-vllm.py \
  --url "http://${GATEWAY_IP}/llm-d-inference-scheduling/qwen2-3b-pattern1"
```

**What it tests:**
- **Baseline performance:** 5 requests, concurrency 1
- **Light load:** 20 requests, concurrency 5
- **Medium load:** 50 requests, concurrency 10
- **Heavy load:** 100 requests, concurrency 20
- **EPP prefix caching:** 5 identical requests to test cache effectiveness

**Expected results** (Qwen2.5-3B on TPU v6e-4):
- Throughput: 30-35 req/sec at concurrency 20
- Mean latency: ~500ms
- P95 latency: ~700ms
- Success rate: 100%

**Results location:**
```bash
# View summary
cat ../benchmarks/results/benchmark_summary_*.txt

# View full JSON metrics
cat ../benchmarks/results/benchmark_*.json | jq .
```

**Detailed analysis:** See [BENCHMARKS.md](BENCHMARKS.md) for comprehensive performance analysis and optimization recommendations.

**Note:** Apache Bench (`benchmark-cluster.sh`) is incompatible with GKE Gateway due to HTTP/1.0 limitations. Use the Python benchmark instead.

---

## Usage

```bash
# Deploy (from llm-d-infra-xks directory)
make deploy-cert-manager  # Only cert-manager needed (no Istio)
make deploy-kserve        # Deploy KServe

# Undeploy
make undeploy-kserve     # Remove KServe
make undeploy            # Remove all infrastructure

# Other
make status              # Show status
```

## Configuration

Edit `values.yaml` in the llm-d-infra-xks repository:

```yaml
# Option 1: Use system podman auth (recommended)
useSystemPodmanAuth: true

# Option 2: Use pull secret file directly
# pullSecretFile: ~/pull-secret.txt

# Operators - only cert-manager needed for this variant
certManager:
  enabled: true

sailOperator:
  enabled: false  # Not needed - using GKE Gateway

lwsOperator:
  enabled: false  # Not needed for Pattern 1
```

---

## Architecture

### Simplified Stack (No Service Mesh)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          GKE Cluster (ecoeng-llmd)                      │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                    Infrastructure Layer                           │ │
│  │  ┌────────────────┐  ┌────────────────────────────────────────┐  │ │
│  │  │ cert-manager   │  │ GKE Gateway Controller (built-in)      │  │ │
│  │  │ (TLS certs)    │  │ - No Istio needed                      │  │ │
│  │  └────────────────┘  │ - Native GKE implementation           │  │ │
│  │                      └────────────────────────────────────────┘  │ │
│  │                                                                   │ │
│  │  ┌────────────────────────────────────────────────────────────┐  │ │
│  │  │ KServe Controller (opendatahub namespace)                  │  │ │
│  │  │ - Watches LLMInferenceService CRDs                         │  │ │
│  │  │ - Auto-creates HTTPRoute + InferencePool                   │  │ │
│  │  │ - Manages vLLM Deployment lifecycle                        │  │ │
│  │  └────────────────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                 ↓                                       │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │            Inference Gateway (GCP Load Balancer)                  │ │
│  │  External IP: 34.x.x.x → GKE Gateway Controller                  │ │
│  │  (No Istio Gateway pods - native GKE implementation)              │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                 ↓                                       │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                      Routing Layer                                │ │
│  │  HTTPRoute → InferencePool → EPP Scheduler                        │ │
│  │  (auto-created by KServe controller)                              │ │
│  │  - Prefix-cache aware routing                                     │ │
│  │  - Queue depth monitoring                                         │ │
│  │  - KV cache utilization tracking                                  │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                 ↓                                       │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │              vLLM Workload (KServe-managed)                       │ │
│  │  Deployment: qwen2-3b-pattern1                                    │ │
│  │  - Image: registry.redhat.io/rhaiis/vllm-tpu-rhel9:3.2.5         │ │
│  │  - Model: Qwen/Qwen2.5-3B-Instruct                               │ │
│  │  - TPU v6e-4 (tensor_parallel_size=4)                            │ │
│  │  - NetworkPolicies: default-deny with Gateway allowlist           │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  Node Pools:                                                            │
│  ┌─────────────────────┐  ┌──────────────────────────────────┐        │
│  │ default-pool        │  │ tpu-v6e-pool                     │        │
│  │ 2 × n1-standard-4   │  │ 1 × ct6e-standard-4t (4 chips)  │        │
│  │ (control plane)     │  │ Taint: google.com/tpu=present   │        │
│  └─────────────────────┘  └──────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────────────┘

Request Flow:
1. Client → GCP Load Balancer (External IP)
2. Load Balancer → GKE Gateway Controller (built-in, no pods)
3. Gateway → HTTPRoute → InferencePool → EPP Scheduler
4. EPP Scheduler → vLLM Pod (selects based on prefix cache, queue depth)
5. vLLM Pod → Process on TPU → Return response
```

### Cost Management

#### Cost Estimates

**Pattern 1 (Single Replica):**

| Component | Configuration | Daily | Monthly |
|-----------|--------------|-------|---------|
| Default pool | 2 × n1-standard-4 | ~$6 | ~$180 |
| TPU pool | 1 × ct6e-standard-4t (4 chips) | ~$127 | ~$3,810 |
| Load Balancer | External IP | ~$0.30 | ~$9 |
| **Total (running)** | | **~$133** | **~$3,999** |
| **Total (scaled to 0)** | | **~$6** | **~$189** |

**Pattern 3 (3 Replicas - Scale-Out):**

| Component | Configuration | Daily | Monthly |
|-----------|--------------|-------|---------|
| Default pool | 2 × n1-standard-4 | ~$6 | ~$180 |
| TPU pool | **3 × ct6e-standard-4t** (12 chips) | ~$381 | ~$11,430 |
| Load Balancer | External IP | ~$0.30 | ~$9 |
| **Total (running)** | | **~$387** | **~$11,619** |
| **Total (scaled to 0)** | | **~$6** | **~$189** |

**Cost Comparison:**
- Pattern 3 costs **3× more** in infrastructure ($387/day vs $133/day)
- Pattern 3 delivers **2.5-3× higher throughput** (15-20 req/s vs 5-7 req/s)
- **Cost per request is similar** (~$275 per 1M requests for both patterns)
- Pattern 3 justifies cost when serving >100K requests/day

**Note:** Infrastructure cost is ~$2/day lower than Istio variant (no Istio pods).

#### Scale-Down Strategies

**Option 1: Delete LLMInferenceService** (recommended for short breaks):
```bash
# For Pattern 1
kubectl delete llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling

# For Pattern 3
kubectl delete llmisvc qwen2-3b-pattern3 -n llm-d-inference-scheduling

# TPU node pool autoscales to 0 after ~10 minutes
# Cost: ~$6/day (default pool only)
```

**Option 2: Scale Pattern 3 down to Pattern 1** (moderate cost savings):
```bash
# Reduce from 3 replicas to 1 replica
kubectl patch llmisvc qwen2-3b-pattern3 -n llm-d-inference-scheduling \
  --type='json' -p='[{"op": "replace", "path": "/spec/replicas", "value": 1}]'

# Or delete Pattern 3 and deploy Pattern 1
kubectl delete llmisvc qwen2-3b-pattern3 -n llm-d-inference-scheduling
kubectl apply -f manifests/llmisvc-tpu.yaml

# Cost: $387/day → $133/day (saves $254/day)
```

**Option 3: Manually resize TPU node pool to 0** (immediate cost savings):
```bash
gcloud container clusters resize llmd-native-gateway-tpu-pattern1 \
  --node-pool tpu-v6e-pool \
  --num-nodes 0 \
  --zone europe-west4-a \
  --project ecoeng-llmd

# Cost: ~$6/day immediately
```

**Option 4: Delete entire cluster** (when done with testing):
```bash
gcloud container clusters delete llmd-native-gateway-tpu-pattern1 \
  --zone europe-west4-a \
  --project ecoeng-llmd \
  --quiet

# Cost: $0/day
```

---

## Troubleshooting

### GKE Gateway Issues

If Gateway external IP is pending:
```bash
# Check LoadBalancer quota
gcloud compute project-info describe --project=ecoeng-llmd | grep -i "IN_USE_ADDRESSES"

# List existing forwarding rules (LoadBalancers)
gcloud compute forwarding-rules list --project=ecoeng-llmd

# Delete unused LoadBalancers if quota is exhausted
gcloud compute forwarding-rules delete <unused-lb-name> --region=<region>
```

If Gateway is not Programmed:
```bash
# Check GatewayClass
kubectl get gatewayclass

# Check Gateway events
kubectl describe gateway inference-gateway -n opendatahub

# Verify GKE Gateway controller is enabled
gcloud container clusters describe $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT \
  --format="value(addonsConfig.gatewayApiConfig.channel)"
# Should show: CHANNEL_STANDARD or similar
```

### KServe Controller Issues

See the [Istio variant troubleshooting guide](../llm-d-infra-xks-gke-tpu/README.md#troubleshooting) for KServe-specific issues.

---

## Additional Resources

### Documentation

- [Architecture Details](docs/architecture.md) - Component interaction, request flow
- [Deployment Guide](docs/deployment-guide.md) - Detailed step-by-step instructions
- [Comparison with Istio Variant](../llm-d-infra-xks-gke-tpu/README.md) - When to use which variant

### Related Deployments

| Deployment | Gateway | Service Mesh | Complexity | Cost |
|-----------|---------|--------------|------------|------|
| [llm-d-infra-xks-gke-tpu](../llm-d-infra-xks-gke-tpu/) | Istio Gateway | ✅ Istio | Moderate | Higher |
| **This Deployment** | GKE Gateway | ❌ None | **Simple** | **Lower** |
| [gateway-api/pattern1-baseline](../../deployments/gateway-api/pattern1-baseline/) | GKE Gateway | ❌ None | Manual setup | Lower |

### Upstream Projects

- [GKE Gateway Controller](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api) - Native GKE Gateway API
- [KServe Documentation](https://kserve.github.io/website/) - KServe project docs
- [OpenDataHub](https://opendatahub.io/) - Open source AI platform
- [Gateway API](https://gateway-api.sigs.k8s.io/) - Kubernetes Gateway API specification

### Support and Issues

- **Infrastructure Issues**: [llm-d-infra-xks](https://github.com/aneeshkp/llm-d-infra-xks/issues)
- **KServe Issues**: [opendatahub-io/kserve](https://github.com/opendatahub-io/kserve/issues)
- **GKE Issues**: [Google Cloud Support](https://cloud.google.com/support)
- **This Deployment**: Create issue in this repository

---

**Last Updated**: 2026-02-11
**Status**: ✅ **Production-Ready** - GKE native Gateway API (no Istio) with documented solutions for all known issues
**Pattern**: Pattern 1 - Single model baseline with EPP routing on GKE TPU v6e

---

## Known Issues and Solutions

All deployment issues have been documented with solutions. See **[ISSUES.md](ISSUES.md)** for comprehensive troubleshooting:

**Critical Issues** (deployment blockers - all solved):
- ✅ [#1 TPU Zone Availability](ISSUES.md#1-tpu-zone-availability-issues) - Use europe-west4-a
- ✅ [#3 Gateway API Not Enabled](ISSUES.md#3-gateway-api-not-enabled) - Use `--gateway-api=standard`
- ✅ [#7 HTTPRoute Timeouts Not Supported](ISSUES.md#7-httproute-timeout-fields-not-supported) - Patch KServe template
- ✅ [#10 GatewayClass for InferencePool](ISSUES.md#10-gatewayclass-support-for-inferencepool) - Use regional GatewayClass

**Configuration Issues** (fixed in this README):
- ✅ [#2 check-nodepool-prerequisites.sh Bug](ISSUES.md#2-check-nodepool-prerequisitessh-script-bug) - Fixed accelerator names
- ✅ [#5 Invalid Gateway Field Structure](ISSUES.md#5-llminferenceservice-manifest---invalid-gateway-field-structure) - Use `gateway.refs[]`
- ✅ [#6 LeaderWorkerSet CRD Missing](ISSUES.md#6-leaderworkerset-crd-missing) - Install kubernetes-sigs/lws

**Operational Issues** (workarounds documented):
- ⚠️ [#9 GCP Health Check Misconfiguration](ISSUES.md#9-gcp-health-check-misconfiguration) - Manual gcloud fix
- ⚠️ [#11 Service appProtocol HTTPS](ISSUES.md#11-service-appprotocol-hardcoded-to-https) - Non-critical, core works

**Expected Behavior** (not bugs):
- ⏳ [#4 GatewayClasses Delayed](ISSUES.md#4-gatewayclasses-delayed-appearance) - Wait 30-45 min after cluster creation
