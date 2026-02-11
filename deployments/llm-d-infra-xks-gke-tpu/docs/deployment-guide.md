# Deployment Guide: Istio + KServe on GKE with TPU

## Overview

This guide provides step-by-step instructions for deploying a production-ready LLM inference platform using:
- **Infrastructure**: llm-d-infra-xks operators (cert-manager + Istio + LWS + KServe)
- **Workload**: KServe LLMInferenceService (declarative vLLM deployment)
- **Hardware**: Google Cloud TPU v6e (4 chips per node)
- **Pattern**: Pattern 1 - Single model baseline

**Estimated Time**: 90-120 minutes
**Difficulty**: Intermediate

## Prerequisites

### Required Tools

```bash
# Verify tool versions
kubectl version --client    # Need 1.28+
helm version               # Need 3.17+
gcloud version             # Need latest
```

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
- External IP addresses: At least 2

---

## Phase 1: Create GKE Cluster (15 min)

### 1.1 Set Environment Variables

```bash
export CLUSTER_NAME=llmd-istio-tpu-pattern1
export ZONE=europe-west4-a
export PROJECT=ecoeng-llmd
export REGION=europe-west4
```

**Zone Selection**:
- `europe-west4-a` (Netherlands) - Lower latency for EU
- `us-central1-a` (Iowa) - Lower cost, higher TPU availability

### 1.2 Create Base Cluster

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
  --addons=GcePersistentDiskCsiDriver,GkeNetworkPolicy \
  --enable-network-policy \
  --workload-pool=$PROJECT.svc.id.goog \
  --enable-shielded-nodes \
  --shielded-secure-boot \
  --shielded-integrity-monitoring \
  --release-channel=regular
```

**Flags Explained**:
- `--cluster-version=1.34` - Use recent Kubernetes version (Gateway API v1 support)
- `--enable-network-policy` - Required for NetworkPolicy enforcement
- `--workload-pool` - Enable Workload Identity (GKE <-> GCP IAM)
- `--shielded-nodes` - Security hardening (secure boot + integrity monitoring)

**Wait Time**: ~5 minutes

### 1.3 Get Cluster Credentials

```bash
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT

# Verify connection
kubectl get nodes
```

**Expected Output**:
```
NAME                                             STATUS   ROLES    AGE     VERSION
gke-llmd-istio-tpu-pattern1-default-pool-...   Ready    <none>   2m30s   v1.34.x
gke-llmd-istio-tpu-pattern1-default-pool-...   Ready    <none>   2m30s   v1.34.x
```

### 1.4 Create TPU Node Pool

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

**Flags Explained**:
- `--machine-type=ct6e-standard-4t` - TPU v6e with 4 chips (2×2 topology)
- `--node-taints` - Prevent non-TPU workloads from scheduling here
- `--enable-autoscaling --min-nodes=0` - Scale to 0 when no workloads (cost savings)

**Wait Time**: ~3 minutes

### 1.5 Verify Node Pools

```bash
kubectl get nodes -o wide
```

**Expected Output**:
```
NAME                                             STATUS   ROLES    AGE   VERSION   LABELS
gke-...-default-pool-...                         Ready    <none>   5m    v1.34.x   ...
gke-...-default-pool-...                         Ready    <none>   5m    v1.34.x   ...
gke-...-tpu-v6e-pool-...                         Ready    <none>   2m    v1.34.x   cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice
```

**Verify TPU node**:
```bash
kubectl describe node $(kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice -o name)
```

Look for:
- `Taints: google.com/tpu=present:NoSchedule`
- `Capacity: google.com/tpu: 4`

---

## Phase 2: Deploy Infrastructure Operators (20 min)

### 2.1 Clone llm-d-infra-xks Repository

```bash
cd /home/jhull/devel
git clone https://github.com/aneeshkp/llm-d-infra-xks.git
cd llm-d-infra-xks
```

### 2.2 Configure Podman Authentication

```bash
# Login to Red Hat registry (uses system podman auth)
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

### 2.3 Create values.yaml

```bash
cat > values.yaml <<'EOF'
# Use system podman auth (credentials from ~/.config/containers/auth.json)
useSystemPodmanAuth: true

# Enable all operators
certManager:
  enabled: true

sailOperator:
  enabled: true

lwsOperator:
  enabled: true
EOF
```

### 2.4 Deploy Infrastructure

```bash
# Deploy all operators
make deploy-all

# Wait for all pods to be Ready (~5 minutes)
watch kubectl get pods -A
```

**Press Ctrl+C when all pods are Running/Ready**

### 2.5 Verify Deployment

```bash
# Check status
make status
```

**Expected Output**:
```
=== Deployment Status ===
cert-manager-operator: 1/1 Running
cert-manager: 1/1 Running
cert-manager-cainjector: 1/1 Running
cert-manager-webhook: 1/1 Running
istiod: 1/1 Running
lws-controller-manager: 1/1 Running

=== API Versions ===
InferencePool API: v1 (inference.networking.k8s.io)
Istio version: v1.27.x
```

### 2.6 Verify Individual Components

```bash
# cert-manager
kubectl get pods -n cert-manager-operator
kubectl get pods -n cert-manager

# Istio
kubectl get pods -n istio-system
kubectl get istio -n istio-system

# LeaderWorkerSet
kubectl get pods -n lws-system

# Gateway API CRDs
kubectl api-resources | grep gateway.networking.k8s.io
```

**Expected Gateway API Resources**:
- `gateways.gateway.networking.k8s.io`
- `httproutes.gateway.networking.k8s.io`
- `inferencepools.inference.networking.k8s.io`

---

## Phase 3: Set Up Inference Gateway (5 min)

### 3.1 Create Gateway

```bash
cd /home/jhull/devel/llm-d-infra-xks

# Run gateway setup script
./scripts/setup-gateway.sh
```

**What this does**:
- Creates `opendatahub` namespace
- Deploys Istio Gateway resource
- Configures HTTP listener on port 80
- Provisions GCP Load Balancer

**Wait Time**: ~2 minutes for External IP assignment

### 3.2 Verify Gateway

```bash
kubectl get gateway -n opendatahub
```

**Expected Output**:
```
NAME                CLASS   ADDRESS         PROGRAMMED   AGE
inference-gateway   istio   <EXTERNAL_IP>   True         1m
```

### 3.3 Capture Gateway IP

```bash
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub \
  -o jsonpath='{.status.addresses[0].value}')

echo "Gateway IP: $GATEWAY_IP"
```

**Save this IP** - you'll use it for testing later.

---

## Phase 4: Deploy KServe Controller (5 min)

### 4.1 Deploy KServe

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

### 4.2 Verify KServe Deployment

```bash
# Check KServe controller pod
kubectl get pods -n opendatahub

# Check LLMInferenceServiceConfig templates
kubectl get llminferenceserviceconfig -n opendatahub
```

**Expected Output**:
```
NAME                            READY   STATUS    RESTARTS   AGE
kserve-controller-manager-...   1/1     Running   0          2m
```

**LLMInferenceServiceConfig Templates**:
```
NAME                          AGE
rhaiis-tpu-default           2m
rhaiis-cuda-default          2m
```

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
# Copy pull secret from istio-system namespace
kubectl get secret redhat-pull-secret -n istio-system -o yaml | \
  sed "s/namespace: istio-system/namespace: $NAMESPACE/" | \
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

**File**: `manifests/llmisvc-tpu.yaml` (already exists in the repository)

The manifest is located at:
```
/home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu/manifests/llmisvc-tpu.yaml
```

**Key Configuration**:
- **Model**: Qwen/Qwen2.5-3B-Instruct
- **Hardware**: TPU v6e-4 (4 chips, 2×2 topology)
- **Routing**: Automatic HTTPRoute and InferencePool creation
- **Scheduler**: EPP (prefix-cache aware)

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu

# View the manifest (optional)
cat manifests/llmisvc-tpu.yaml

# Deploy LLMInferenceService
kubectl apply -f manifests/llmisvc-tpu.yaml
```

**What Happens**:
1. **KServe controller** watches for the LLMInferenceService CRD
2. **Auto-creates** HTTPRoute bound to inference-gateway
3. **Auto-creates** InferencePool with EPP scheduler
4. **Deploys** vLLM Deployment with TPU configuration
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
- **vLLM pod**: Running and Ready
- **HTTPRoute**: qwen2-3b-pattern1 (auto-created)
- **InferencePool**: qwen2-3b-pattern1 (STATUS = Programmed)

**Example Output**:
```
NAME                 READY   URL                                                        AGE
qwen2-3b-pattern1   True    http://34.x.x.x/llm-d-inference-scheduling/qwen2-3b-pattern1   15m
```

---

## Phase 6: Apply Network Policies (5 min)

### 6.1 Create NetworkPolicy Directory

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu
mkdir -p manifests/networkpolicies
```

### 6.2 Default Deny Policy

**File**: `manifests/networkpolicies/default-deny.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: llm-d-inference-scheduling
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### 6.3 Allow Gateway to vLLM

**File**: `manifests/networkpolicies/allow-gateway-to-vllm.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-gateway-to-vllm
  namespace: llm-d-inference-scheduling
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: qwen2-3b-pattern1

  policyTypes:
  - Ingress

  ingress:
  # Allow traffic from Istio Gateway
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: opendatahub
      podSelector:
        matchLabels:
          gateway.networking.k8s.io/gateway-name: inference-gateway
    ports:
    - protocol: TCP
      port: 8000

  # Allow health probes from kubelet
  - from:
    - namespaceSelector: {}
      podSelector: {}
    ports:
    - protocol: TCP
      port: 8000
```

### 6.4 Allow vLLM Egress

**File**: `manifests/networkpolicies/allow-vllm-egress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-vllm-egress
  namespace: llm-d-inference-scheduling
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: qwen2-3b-pattern1

  policyTypes:
  - Egress

  egress:
  # Allow all egress (PoC - restrict in production)
  - {}
```

**Production Recommendation**: Restrict egress to:
- HuggingFace Hub (huggingface.co)
- Kubernetes API server
- DNS (kube-dns)

### 6.5 Apply Policies

```bash
kubectl apply -f manifests/networkpolicies/
```

**Verify**:
```bash
kubectl get networkpolicies -n $NAMESPACE
```

---

## Phase 7: Verification and Testing (15 min)

### 7.1 Verify All Components

```bash
# Infrastructure
kubectl get pods -n cert-manager
kubectl get pods -n istio-system
kubectl get pods -n lws-system

# Gateway
kubectl get gateway -n opendatahub

# Workload
kubectl get pods -n $NAMESPACE
kubectl get httproute -n $NAMESPACE
kubectl get inferencepool -n $NAMESPACE
```

**All pods should be Running and Ready.**

### 7.2 Test API Endpoints

#### List Models

```bash
curl http://${GATEWAY_IP}/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/models
```

**Expected Response**:
```json
{
  "object": "list",
  "data": [
    {
      "id": "Qwen/Qwen2.5-3B-Instruct",
      "object": "model",
      "created": 1234567890,
      "owned_by": "huggingface"
    }
  ]
}
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

**Expected Response**:
```json
{
  "id": "cmpl-...",
  "object": "text_completion",
  "created": 1234567890,
  "model": "Qwen/Qwen2.5-3B-Instruct",
  "choices": [
    {
      "index": 0,
      "text": " I'm doing well, thank you for asking! How can I help you today?",
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 6,
    "completion_tokens": 15,
    "total_tokens": 21
  }
}
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

### 7.3 Run Performance Benchmark

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu

# Copy benchmark script from previous deployment
cp ../istio-kserve/pattern1-baseline/scripts/benchmark-cluster.sh scripts/

# Run benchmark
./scripts/benchmark-cluster.sh http $GATEWAY_IP
```

**Expected Results** (Pattern 1 baseline):
- Throughput: ~12-15 req/s at concurrency 20
- Latency P50: ~800ms
- Latency P95: ~1400ms
- Latency P99: ~2000ms
- Error rate: 0%

### 7.4 Verify EPP Routing

```bash
# Check EPP scheduler logs
kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=scheduler --tail=100

# Send multiple similar requests to test prefix caching
for i in {1..5}; do
  curl -X POST http://${GATEWAY_IP}/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"Qwen/Qwen2.5-3B-Instruct","prompt":"Explain Kubernetes in one sentence:","max_tokens":30}'
  echo ""
done
```

**Look for** in EPP logs:
- `Routing decision: cache hit` (requests 2-5 should hit cache)
- `Backend selected: <pod-name>` (should be same pod for similar prompts)

---

## Troubleshooting

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
   - Solution: Verify `huggingface-token` secret
3. **Image pull error**: Can't pull `rhaiis/vllm-tpu`
   - Solution: Verify `redhat-pull-secret`

### Gateway Stuck in Pending

**Symptom**: Gateway has no External IP after 5 minutes

**Diagnosis**:
```bash
kubectl describe gateway inference-gateway -n opendatahub
```

**Common Causes**:
1. **GCP Load Balancer quota**: Exhausted external IP quota
   - Solution: Check GCP quotas, delete unused LBs
2. **Istio not ready**: istiod pod not Running
   - Solution: Check `kubectl get pods -n istio-system`

### 503 Service Unavailable

**Symptom**: API requests return 503

**Diagnosis**:
```bash
# Check InferencePool status
kubectl get inferencepool -n $NAMESPACE -o yaml

# Check EPP scheduler logs
kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=scheduler
```

**Common Causes**:
1. **vLLM pod not Ready**: Still initializing
   - Solution: Wait for readiness probe (240s initialDelaySeconds)
2. **InferencePool not Programmed**: EPP scheduler issue
   - Solution: Check EPP scheduler logs for errors
3. **NetworkPolicy blocking**: Gateway can't reach vLLM
   - Solution: Verify NetworkPolicy allows opendatahub → $NAMESPACE

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
# Option 1: Uninstall Helm release (cleanest)
helm uninstall qwen2-3b-pattern1 -n $NAMESPACE

# Option 2: Scale deployment to 0 (keeps Helm release)
kubectl scale deployment qwen2-3b-pattern1 \
  -n $NAMESPACE \
  --replicas=0
```

**Result**: TPU node pool autoscales to 0 after ~10 minutes
**Cost**: $0/day for TPU, $6/day for CPU nodes

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

1. **Document actual Gateway IP** in your notes
2. **Run comprehensive benchmarks** and save results
3. **Test EPP routing intelligence**:
   - Send requests with similar prefixes
   - Verify cache hits in scheduler logs
   - Measure latency reduction (should be ~20-30% for cache hits)
4. **Prepare for Pattern 3** (N/S-caching scale-out):
   - Scale to 3 replicas: `helm upgrade qwen2-3b-pattern1 ... --set replicas=3`
   - Test prefix-cache routing across pods
5. **Evaluate enterprise readiness** when Red Hat announces llm-d support

---

## Appendix: Directory Structure

```
/home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu/
├── README.md                          # Quick start guide
├── cluster-config/
│   └── create-cluster.sh              # GKE cluster creation script
├── manifests/
│   └── networkpolicies/               # NetworkPolicy manifests
│       ├── default-deny.yaml
│       ├── allow-gateway-to-vllm.yaml
│       └── allow-vllm-egress.yaml
├── helm-values/
│   └── pattern1-tpu-values.yaml       # llm-d modelservice configuration
├── scripts/
│   ├── test-cluster.sh                # API tests
│   └── benchmark-cluster.sh           # Performance tests
├── benchmarks/
│   └── results/                       # Benchmark results
└── docs/
    ├── architecture.md                # Architecture overview (this file)
    └── deployment-guide.md            # Step-by-step guide
```

---

## References

- [llm-d-infra-xks Repository](https://github.com/aneeshkp/llm-d-infra-xks)
- [llm-d Website](https://llm-d.ai/)
- [llm-d GKE Infrastructure Guide](https://llm-d.ai/docs/guide/InfraProviders/gke)
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/)
- [GKE TPU Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/tpus)
- [Red Hat Istio Documentation](https://docs.redhat.com/en/documentation/openshift_service_mesh)
- [vLLM Documentation](https://docs.vllm.ai/)
