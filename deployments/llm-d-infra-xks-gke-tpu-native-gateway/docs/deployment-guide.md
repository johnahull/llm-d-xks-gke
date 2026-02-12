# Deployment Guide: GKE Native Gateway + KServe on GKE with TPU

## Overview

This guide provides step-by-step instructions for deploying a lightweight LLM inference platform using:
- **Infrastructure**: Minimal operators (cert-manager + KServe only)
- **Gateway**: GKE native Gateway API controller (no Istio)
- **Workload**: KServe LLMInferenceService (declarative vLLM deployment)
- **Hardware**: Google Cloud TPU v6e (4 chips per node)
- **Pattern**: Pattern 1 - Single model baseline

**Estimated Time**: 90 minutes (~27 minutes faster than Istio variant)
**Difficulty**: Intermediate

## Why This Guide?

**Advantages over Istio variant**:
- ✅ Simpler deployment (fewer components)
- ✅ Lower cost (~$2/day less infrastructure)
- ✅ Faster setup (~90 min vs 2 hours)
- ✅ Native GKE integration

**Trade-offs**:
- ❌ No service mesh features
- ❌ No mTLS between services
- ❌ Limited observability (no Istio telemetry)

**When to use this guide**: Cost optimization and simplicity are priorities

**When to use Istio variant**: Need service mesh, mTLS, or advanced traffic management

## Prerequisites

### Required Tools

```bash
# Verify tool versions
kubectl version --client    # Need 1.28+
gcloud version             # Need latest
```

**Note**: No Helm required for this variant (KServe uses kubectl only)

### Required Credentials

1. **Red Hat Registry Service Account**
   - Obtain from: https://access.redhat.com/terms-based-registry/
   - File: `11009103-jhull-svc-pull-secret.yaml` (or create new account)

2. **HuggingFace Token**
   - Obtain from: https://huggingface.co/settings/tokens
   - Permissions: Read access to models

3. **Google Cloud Access**
   - Project: `ecoeng-llmd`
   - Permissions: `container.admin`, `compute.admin`

### Configure gcloud CLI

```bash
# Login
gcloud auth login

# Set project
gcloud config set project ecoeng-llmd

# Verify quotas
gcloud compute project-info describe --project=ecoeng-llmd \
  | grep -A 5 "TPU"
```

**Required Quotas**:
- TPU v6e chips: At least 4
- External IP addresses: At least 1

---

## Phase 1: Create GKE Cluster (20 min)

### 1.1 Set Environment Variables

```bash
export CLUSTER_NAME=llmd-gke-native-tpu-pattern1
export ZONE=europe-west4-a
export PROJECT=ecoeng-llmd
export REGION=europe-west4
```

**Zone Selection**:
- `europe-west4-a` (Netherlands) - ✅ **Recommended** - Confirmed working with TPU v6e
- ~~`us-central1-a` (Iowa)~~ - ❌ **Not supported** - TPU VMs only, not GKE node pools

⚠️ **Important**: TPU v6e availability on GKE is limited. See [Zone Availability](../README.md#zone-availability) for confirmed working zones.

### 1.2 Run Cluster Creation Script

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu-native-gateway

# Run automated cluster creation
./cluster-config/create-cluster.sh
```

**What this does**:
1. Creates GKE cluster (version 1.34+, 2 CPU nodes)
2. Enables Gateway API and NetworkPolicy
3. Creates TPU v6e node pool (autoscale 0-3 nodes)
4. Verifies node pool configuration

**Wait Time**: ~15-20 minutes

<details>
<summary><strong>Manual Cluster Creation (Alternative)</strong></summary>

If you prefer manual control, expand this section for individual commands.

#### Create Base Cluster

```bash
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
  --addons=GcePersistentDiskCsiDriver,NetworkPolicy \
  --enable-network-policy \
  --workload-pool=$PROJECT.svc.id.goog \
  --enable-shielded-nodes \
  --shielded-secure-boot \
  --shielded-integrity-monitoring \
  --release-channel=regular
```

#### Get Credentials

```bash
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT
```

#### Create TPU Node Pool

```bash
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

### 1.3 Verify Cluster

```bash
# Check nodes
kubectl get nodes -o wide

# Verify Gateway API CRDs (built into GKE 1.34+)
kubectl api-resources | grep gateway.networking.k8s.io

# Verify TPU node
kubectl describe node $(kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice -o name)
```

**Expected Output**:
- 2 CPU nodes (n1-standard-4)
- 1 TPU node (ct6e-standard-4t with taint)
- Gateway API resources: `Gateway`, `HTTPRoute`, `GatewayClass`

---

## Phase 2: Deploy Minimal Infrastructure (10 min)

**Key Difference**: No Istio deployment - only cert-manager and KServe

### 2.1 Clone llm-d-infra-xks Repository

```bash
cd /home/jhull/devel
git clone https://github.com/aneeshkp/llm-d-infra-xks.git
cd llm-d-infra-xks
```

### 2.2 Configure Podman Authentication

```bash
# Login to Red Hat registry
podman login registry.redhat.io

# Enter credentials:
# Username: 11009103|jhull-svc
# Password: <service account token>

# Verify auth stored
cat ~/.config/containers/auth.json | jq .
```

**Alternative**: If you have `11009103-jhull-svc-pull-secret.yaml`:
```bash
# Extract auth from secret YAML
grep 'dockerconfigjson:' /path/to/11009103-jhull-svc-pull-secret.yaml | \
  awk '{print $2}' | \
  base64 -d > ~/.config/containers/auth.json
```

### 2.3 Deploy cert-manager Only

```bash
# Deploy ONLY cert-manager (no Istio, no LWS)
make deploy-cert-manager
```

**What this does**:
- Creates `cert-manager-operator` namespace
- Deploys cert-manager operator
- Creates cert-manager components
- Configures ClusterIssuer for self-signed certs
- Copies Red Hat pull secret to cert-manager namespace

**Wait Time**: ~5 minutes

### 2.4 Verify cert-manager

```bash
# Check pods
kubectl get pods -n cert-manager

# Expected output:
# cert-manager-x-x           1/1     Running
# cert-manager-cainjector-x  1/1     Running
# cert-manager-webhook-x     1/1     Running
```

**All 3 pods should be Running**.

---

## Phase 3: Deploy KServe Controller (5 min)

### 3.1 Deploy KServe

```bash
cd /home/jhull/devel/llm-d-infra-xks

# Deploy KServe controller
make deploy-kserve
```

**What this does**:
- Creates `opendatahub` namespace
- Deploys KServe controller manager
- Installs LLMInferenceService CRD
- Configures LLMInferenceServiceConfig templates

**Wait Time**: ~3 minutes

### 3.2 Verify KServe Deployment

```bash
# Check KServe controller pod
kubectl get pods -n opendatahub

# Expected output:
# kserve-controller-manager-...   1/1     Running   0          2m

# Check LLMInferenceServiceConfig templates
kubectl get llminferenceserviceconfig -n opendatahub
```

**Expected Templates**:
```
NAME                          AGE
rhaiis-tpu-default           2m
rhaiis-cuda-default          2m
```

---

## Phase 4: Create GKE Gateway (3 min)

**Key Difference**: Manual Gateway creation (no setup-gateway.sh script)

### 4.1 Verify GatewayClass

```bash
# Check available GatewayClasses (provided by GKE)
kubectl get gatewayclass

# Expected output:
# NAME                                  CONTROLLER                  AGE
# gke-l7-global-external-managed        networking.gke.io/gateway   ...
# gke-l7-regional-external-managed      networking.gke.io/gateway   ...
```

**Note**: These are built into GKE 1.34+ (no installation needed)

⚠️ **CRITICAL**: You **MUST** use `gke-l7-regional-external-managed` for InferencePool support. The global class does NOT support InferencePool backends. See [architecture.md](architecture.md#critical-discovery-gatewayclass-support) for details.

### 4.2 Create Gateway

```bash
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
```

**Configuration**:
- `gatewayClassName: gke-l7-regional-external-managed` - **MUST be regional** (not global) for InferencePool support
- `namespace: opendatahub` - Same namespace KServe uses
- `allowedRoutes.namespaces.from: All` - Allow HTTPRoutes from any namespace

**Why Regional?**: Global GatewayClass only supports standard Service backends. Regional supports both Service and InferencePool (required for EPP routing).

### 4.3 Wait for External IP

```bash
# Watch Gateway status (~2-3 minutes for GCP Load Balancer provisioning)
kubectl get gateway inference-gateway -n opendatahub -w
```

**Press Ctrl+C** when ADDRESS column is populated.

**Expected Output**:
```
NAME                CLASS                            ADDRESS         PROGRAMMED   AGE
inference-gateway   gke-l7-regional-external-managed   34.x.x.x        True         2m
```

### 4.4 Capture Gateway IP

```bash
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub \
  -o jsonpath='{.status.addresses[0].value}')

echo "Gateway IP: $GATEWAY_IP"
```

**Save this IP** - you'll use it for testing later.

---

## Phase 5: Deploy LLMInferenceService (30 min)

### 5.1 Create Application Namespace

```bash
export NAMESPACE=llm-d-inference-scheduling

kubectl create namespace $NAMESPACE
```

### 5.2 Configure Secrets

#### Red Hat Pull Secret

```bash
# Copy pull secret from cert-manager namespace
kubectl get secret redhat-pull-secret -n cert-manager -o yaml | \
  sed "s/namespace: cert-manager/namespace: $NAMESPACE/" | \
  kubectl apply -f -

# Verify
kubectl get secret redhat-pull-secret -n $NAMESPACE
```

#### HuggingFace Token Secret

```bash
# Replace YOUR_HUGGINGFACE_TOKEN with actual token
kubectl create secret generic hf-token \
  -n $NAMESPACE \
  --from-literal=HF_TOKEN=YOUR_HUGGINGFACE_TOKEN \
  --dry-run=client -o yaml | kubectl apply -f -

# Verify
kubectl get secret hf-token -n $NAMESPACE
```

### 5.3 Deploy LLMInferenceService Manifest

**File**: `manifests/llmisvc-tpu.yaml`

**Key Configuration**:
- **Model**: Qwen/Qwen2.5-3B-Instruct
- **Hardware**: TPU v6e-4 (4 chips, 2×2 topology)
- **Gateway Reference**: inference-gateway (namespace: opendatahub)
- **Health Probes**: `scheme: HTTP` (no Istio sidecars)

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu-native-gateway

# View the manifest (optional)
cat manifests/llmisvc-tpu.yaml

# Deploy LLMInferenceService
kubectl apply -f manifests/llmisvc-tpu.yaml
```

**What Happens**:
1. **KServe controller** watches for the LLMInferenceService CRD
2. **Auto-creates** HTTPRoute bound to GKE Gateway (opendatahub/inference-gateway)
3. **Auto-creates** InferencePool with EPP scheduler
4. **Deploys** vLLM Deployment with TPU configuration (no Istio sidecars)
5. **Downloads** model from HuggingFace (using hf-token secret)
6. **Compiles** model for TPU (XLA compilation on first run)

### 5.4 Monitor Deployment Progress

**Deployment Timeline**:
1. CRD creation: ~5 seconds
2. KServe creates resources: ~30 seconds
3. Pod creation: ~30 seconds
4. Model download (Qwen2.5-3B): ~2-3 minutes
5. TPU initialization: ~2 minutes
6. XLA compilation: ~3-5 minutes
7. First readiness check: ~12-15 minutes total

**Monitor Progress**:
```bash
# Watch LLMInferenceService status
kubectl get llmisvc -n $NAMESPACE -w

# Watch pod status (in another terminal)
kubectl get pods -n $NAMESPACE -w

# View pod logs (in another terminal)
kubectl logs -n $NAMESPACE -l serving.kserve.io/inferenceservice=qwen2-3b-pattern1 -f
```

**Expected Log Messages**:
```
INFO: Downloading model from HuggingFace...
INFO: Initializing TPU runtime...
INFO: TPU device initialized: /dev/vfio/0
INFO: Compiling model with XLA...
INFO: vLLM server started on port 8000
INFO: Model Qwen/Qwen2.5-3B-Instruct loaded successfully
```

### 5.5 Verify Auto-Created Resources

```bash
# Check LLMInferenceService status
kubectl get llmisvc qwen2-3b-pattern1 -n $NAMESPACE

# Check vLLM pod (created by KServe)
kubectl get pods -n $NAMESPACE

# Check HTTPRoute (auto-created by KServe)
kubectl get httproute -n $NAMESPACE

# Check InferencePool (auto-created by KServe)
kubectl get inferencepool -n $NAMESPACE

# Describe LLMInferenceService for detailed status
kubectl describe llmisvc qwen2-3b-pattern1 -n $NAMESPACE
```

**Expected Resources**:
- **LLMInferenceService**: READY = True
- **vLLM pod**: Running and Ready (no Istio sidecar containers)
- **HTTPRoute**: qwen2-3b-pattern1 (auto-created, attached to GKE Gateway)
- **InferencePool**: qwen2-3b-pattern1 (STATUS = Programmed)

**Example Output**:
```
NAME                 READY   URL                                                        AGE
qwen2-3b-pattern1   True    http://34.x.x.x/llm-d-inference-scheduling/qwen2-3b-pattern1   15m
```

**Key Difference**: Pod has 1 container (main), not 2 containers (main + istio-proxy)

---

## Phase 6: Verification and Testing (10 min)

### 6.1 Verify All Components

```bash
# Infrastructure
kubectl get pods -n cert-manager
kubectl get pods -n opendatahub

# Gateway
kubectl get gateway -n opendatahub

# Workload
kubectl get pods -n $NAMESPACE
kubectl get httproute -n $NAMESPACE
kubectl get inferencepool -n $NAMESPACE
```

**All pods should be Running and Ready.**

### 6.2 Run Automated Tests

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu-native-gateway

# Run test suite
./scripts/test-cluster.sh
```

**What this tests**:
- Health endpoint (/health)
- List models endpoint (/v1/models)
- Text completion endpoint (/v1/completions)
- Chat completion endpoint (/v1/chat/completions)
- Prefix cache test (3 similar requests)

**Expected Output**:
```
Test 1: Health Check
✓ Health check passed (HTTP 200)

Test 2: List Models
✓ List models passed

Test 3: Text Completion
✓ Text completion passed
Generated text: I'm doing well, thank you for asking!
Total tokens: 21

Test 4: Chat Completion
✓ Chat completion passed

Test 6: Prefix Cache Test (EPP Routing)
Request 1: ✓ 1234ms
Request 2: ✓ 856ms
Request 3: ✓ 821ms
Note: Requests 2-3 should be faster if prefix caching is working
```

### 6.3 Manual API Testing (Optional)

#### List Models

```bash
curl http://${GATEWAY_IP}/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/models
```

#### Text Completion

```bash
curl -X POST http://${GATEWAY_IP}/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-3B-Instruct",
    "prompt": "Hello, how are you?",
    "max_tokens": 50,
    "temperature": 0.7
  }'
```

#### Chat Completion

```bash
curl -X POST http://${GATEWAY_IP}/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-3B-Instruct",
    "messages": [
      {"role": "user", "content": "What is Kubernetes?"}
    ],
    "max_tokens": 100
  }'
```

---

## Phase 7: Run Benchmarks (15 min)

### 7.1 Run Performance Benchmark

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu-native-gateway

# Run benchmark suite
./scripts/benchmark-cluster.sh http $GATEWAY_IP
```

**What this tests**:
- Baseline (1 request, concurrency 1)
- Serial load (10 requests, concurrency 1)
- Light load (20 requests, concurrency 5)
- Medium load (50 requests, concurrency 10)
- Heavy load (100 requests, concurrency 20)
- EPP prefix cache test (5 similar requests)

**Expected Results** (Pattern 1 baseline on TPU v6e-4):
- Throughput: ~12-15 req/s at concurrency 20
- Latency P50: ~800ms
- Latency P95: ~1400ms
- Latency P99: ~2000ms
- Error rate: 0%
- Cache hit latency reduction: ~20-30%

### 7.2 Review Benchmark Results

```bash
# View summary
cat benchmarks/results/benchmark_summary_*.txt

# View detailed results
ls -la benchmarks/results/
```

**Results saved to**:
- `benchmark_summary_*.txt` - Overall summary
- `cache_test_*.txt` - Prefix cache test results
- `ab_*req_*c_*.tsv` - Apache Bench TSV data (for visualization)
- `ab_*req_*c_*.txt` - Raw Apache Bench output

### 7.3 Verify EPP Routing

```bash
# Check EPP scheduler logs
kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=scheduler --tail=100
```

**Look for** in EPP logs:
- `Routing decision: cache hit` (requests 2-5 should hit cache)
- `Backend selected: <pod-name>` (should be same pod for similar prompts)

---

## Troubleshooting

### Gateway Stuck in Pending

**Symptom**: Gateway has no External IP after 5 minutes

**Diagnosis**:
```bash
kubectl describe gateway inference-gateway -n opendatahub

# Check GKE Gateway controller status
kubectl get gatewayclass
```

**Common Causes**:
1. **GKE Gateway controller not enabled**
   - Solution: Verify GKE version 1.34+ (`kubectl version`)
2. **GCP Load Balancer quota exhausted**
   - Solution: Check GCP quotas, delete unused LBs
3. **Wrong GatewayClass** (using global instead of regional)
   - Solution: **CRITICAL** - Must use `gke-l7-regional-external-managed`, NOT global
   - Global class does NOT support InferencePool backends
   - See [ISSUES.md#10](../ISSUES.md#10-gatewayclass-support-for-inferencepool)

**Verification**:
```bash
# Verify Gateway API is available
kubectl api-resources | grep gateway.networking.k8s.io

# Should show: Gateway, HTTPRoute, GatewayClass
```

### HTTPRoute Not Attaching to Gateway

**Symptom**: HTTPRoute shows `Accepted: False`

**Diagnosis**:
```bash
kubectl describe httproute -n $NAMESPACE
```

**Common Causes**:
1. **Gateway namespace mismatch**
   - Solution: Verify HTTPRoute references `inference-gateway` in `opendatahub` namespace
2. **Gateway not ready**
   - Solution: Wait for Gateway PROGRAMMED = True
3. **allowedRoutes misconfigured**
   - Solution: Ensure Gateway has `allowedRoutes.namespaces.from: All`

### Pod in CrashLoopBackOff

**Symptom**: vLLM pod restarts repeatedly

**Diagnosis**:
```bash
kubectl logs -n $NAMESPACE <pod-name> --previous
kubectl describe pod -n $NAMESPACE <pod-name>
```

**Common Causes**:
1. **Missing TPU**: Node doesn't have `google.com/tpu` resource
   - Solution: Verify TPU node pool labels
2. **Invalid HF token**: Model download fails with 403
   - Solution: Verify `hf-token` secret
3. **Image pull error**: Can't pull `rhaiis/vllm-tpu`
   - Solution: Verify `redhat-pull-secret`
4. **Wrong health probe scheme**: Using HTTPS instead of HTTP
   - Solution: Verify `livenessProbe.httpGet.scheme: HTTP` (not HTTPS)

**Key Difference**: No Istio sidecars, so health probes use HTTP directly

### 503 Service Unavailable

**Symptom**: API requests return 503

**Diagnosis**:
```bash
# Check InferencePool status
kubectl get inferencepool -n $NAMESPACE -o yaml

# Check GKE Gateway backend health
gcloud compute backend-services describe <backend-name> --global
```

**Common Causes**:
1. **vLLM pod not Ready**: Still initializing
   - Solution: Wait for readiness probe (240s initialDelaySeconds)
2. **InferencePool not Programmed**: EPP scheduler issue
   - Solution: Check EPP scheduler logs for errors
3. **HTTPRoute not attached**: Gateway not accepting route
   - Solution: Verify HTTPRoute status

### Slow First Inference

**Symptom**: First request takes 30+ seconds

**Explanation**: This is **expected** on TPU:
1. XLA compilation triggered on first inference
2. Subsequent requests are fast (~1-2s latency)
3. Compilation results are cached per pod

**Not a bug** - TPU compilation is one-time overhead.

---

## Cost Optimization

### Scale Down (Keep Cluster)

```bash
# Delete LLMInferenceService (cleanest)
kubectl delete llmisvc qwen2-3b-pattern1 -n $NAMESPACE

# TPU node pool autoscales to 0 after ~10 minutes
```

**Result**: $0/day for TPU, ~$4/day for CPU nodes (cert-manager + KServe only)

### Delete Cluster (When Done)

```bash
gcloud container clusters delete $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT \
  --quiet
```

**Cost**: $0/day (all resources deleted)

---

## Next Steps

1. **Compare with Istio variant**:
   - Deploy [Istio variant](../../llm-d-infra-xks-gke-tpu/) to compare features
   - Evaluate trade-offs (simplicity vs service mesh capabilities)

2. **Test advanced scenarios**:
   - Scale to multiple replicas: Edit `manifests/llmisvc-tpu.yaml` (replicas: 3)
   - Test EPP routing with higher concurrency
   - Measure prefix cache hit rates

3. **Explore NetworkPolicies** (optional for production):
   - Apply default-deny policy
   - Allow only Gateway → vLLM traffic
   - Restrict vLLM egress to HuggingFace Hub only

4. **Plan for production**:
   - Evaluate when to use Istio variant (service mesh requirements)
   - Consider cost vs features trade-offs
   - Plan monitoring strategy (GCP Cloud Monitoring or Prometheus)

---

## Appendix: Comparison with Istio Variant

| Aspect | Istio Variant | **Native Gateway** |
|--------|--------------|---------------------|
| **Deployment Time** | ~2 hours | **~1.5 hours** ✅ |
| **Infrastructure** | cert-manager + Istio + LWS + KServe | **cert-manager + KServe** ✅ |
| **Gateway** | Istio Gateway (pods) | **GKE Gateway (native)** ✅ |
| **Infrastructure Cost** | ~$6/day | **~$4/day** ✅ |
| **Service Mesh** | ✅ Yes | ❌ No |
| **mTLS** | ✅ Automatic | ❌ Not included |
| **Istio Telemetry** | ✅ Yes | ❌ No |
| **EPP Scheduler** | ✅ Yes | ✅ **Yes (same)** |
| **KServe Auto-creation** | ✅ Yes | ✅ **Yes (same)** |
| **Complexity** | Higher | **Lower** ✅ |

**Recommendation**: Start with Native Gateway for simplicity. Migrate to Istio variant later if you need service mesh features.

---

## References

- [Main README](../README.md) - Complete deployment overview
- [QUICKSTART](../QUICKSTART.md) - 90-minute fast-track guide
- [Architecture](architecture.md) - Detailed architecture documentation
- [Istio Variant](../../llm-d-infra-xks-gke-tpu/) - Full-featured alternative
- [llm-d-infra-xks Repository](https://github.com/aneeshkp/llm-d-infra-xks)
- [GKE Gateway API Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api)
- [KServe Documentation](https://kserve.github.io/website/)
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/)
