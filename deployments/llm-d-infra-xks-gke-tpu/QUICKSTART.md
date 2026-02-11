# Quick Start Guide

**Goal**: Deploy Pattern 1 (single model with EPP routing) on GKE with TPU in ~2 hours using KServe LLMInferenceService.

## Prerequisites Checklist

```bash
# 1. Verify tools installed
kubectl version --client  # Need 1.28+
helm version             # Need 3.17+
gcloud version           # Need latest

# 2. Verify GCP access
gcloud auth login
gcloud config set project ecoeng-llmd
gcloud projects describe ecoeng-llmd  # Should succeed

# 3. Prepare credentials
# - Red Hat registry: Get from https://access.redhat.com/terms-based-registry/
# - HuggingFace token: Get from https://huggingface.co/settings/tokens
```

## Deployment Steps

### Step 1: Clone Infrastructure Repository (5 min)

```bash
cd /home/jhull/devel

# Clone llm-d-infra-xks (infrastructure operators)
git clone https://github.com/aneeshkp/llm-d-infra-xks.git

# Verify this deployment directory exists
ls -la llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu/
```

**Note:** The llm-d framework repository is NOT needed for KServe deployment. KServe uses declarative manifests instead of Helm charts.

### Step 2: Create GKE Cluster (20 min)

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu

# Run cluster creation script
./cluster-config/create-cluster.sh

# Wait for completion (~15-20 minutes)
# Script will:
# - Create base cluster (2 CPU nodes)
# - Add TPU node pool (1 TPU v6e-4 node)
# - Configure autoscaling
# - Verify node readiness
```

**Verify**:
```bash
kubectl get nodes
# Expected: 2 CPU nodes + 1 TPU node

kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice
# Expected: 1 TPU node with capacity google.com/tpu: 4
```

### Step 3: Deploy Infrastructure Operators (20 min)

```bash
cd /home/jhull/devel/llm-d-infra-xks

# Configure Red Hat authentication
podman login registry.redhat.io
# Enter: 11009103|jhull-svc
# Password: <service account token>

# Create values.yaml
cat > values.yaml <<'EOF'
useSystemPodmanAuth: true
certManager:
  enabled: true
sailOperator:
  enabled: true
lwsOperator:
  enabled: true
EOF

# Deploy all operators
make deploy-all

# Wait for pods to be Ready (~5 minutes)
watch kubectl get pods -A
# Press Ctrl+C when all Running

# Verify status
make status
```

**Verify**:
```bash
kubectl get pods -n cert-manager       # 3 pods Running
kubectl get pods -n istio-system       # 1 pod Running (istiod)
kubectl get pods -n lws-system         # 1 pod Running
```

### Step 4: Deploy KServe (5 min)

```bash
cd /home/jhull/devel/llm-d-infra-xks

# Deploy KServe controller
make deploy-kserve

# Wait for KServe controller to be ready
kubectl get pods -n opendatahub -w
# Press Ctrl+C when kserve-controller-manager is Running

# Verify LLMInferenceServiceConfig templates
kubectl get llminferenceserviceconfig -n opendatahub
```

**Verify**:
```bash
kubectl get pods -n opendatahub
# Expected: kserve-controller-manager Running

kubectl get llminferenceserviceconfig -n opendatahub
# Expected: Multiple config templates (rhaiis-tpu-*, rhaiis-cuda-*)
```

### Step 5: Set Up Inference Gateway (5 min)

```bash
cd /home/jhull/devel/llm-d-infra-xks

# Create Gateway
./scripts/setup-gateway.sh

# Wait for External IP (~2 minutes)
kubectl get gateway -n opendatahub -w
# Press Ctrl+C when STATUS = Programmed and ADDRESS is populated

# Capture Gateway IP
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub \
  -o jsonpath='{.status.addresses[0].value}')

echo "Gateway IP: $GATEWAY_IP"
# Save this IP!
```

**Verify**:
```bash
kubectl get gateway inference-gateway -n opendatahub
# Expected: STATUS = Programmed, ADDRESS = <External IP>
```

### Step 6: Deploy LLMInferenceService (30 min)

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu

# Create namespace
export NAMESPACE=llm-d-inference-scheduling
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Copy Red Hat pull secret from istio-system
kubectl get secret redhat-pull-secret -n istio-system -o yaml | \
  sed "s/namespace: istio-system/namespace: $NAMESPACE/" | \
  kubectl apply -f -

# Create HuggingFace token secret
kubectl create secret generic hf-token \
  -n $NAMESPACE \
  --from-literal=HF_TOKEN=YOUR_HUGGINGFACE_TOKEN \
  --dry-run=client -o yaml | kubectl apply -f -
# ⚠️ Replace YOUR_HUGGINGFACE_TOKEN with your actual token from https://huggingface.co/settings/tokens

# Deploy LLMInferenceService via manifest
kubectl apply -f manifests/llmisvc-tpu.yaml

# Monitor deployment (~12-15 min for model download + TPU compilation)
kubectl get llmisvc -n $NAMESPACE -w
# Wait for READY = True
# Press Ctrl+C when ready
```

**What Happens:**
1. **KServe controller** watches for LLMInferenceService CRD
2. **Auto-creates** HTTPRoute and InferencePool resources
3. **Deploys** vLLM pod with TPU configuration
4. **Configures** EPP scheduler for intelligent routing
5. **Downloads** model from HuggingFace (Qwen/Qwen2.5-3B-Instruct)
6. **Compiles** model for TPU (XLA compilation - first run is slow)

**Verify auto-created resources:**
```bash
# Check LLMInferenceService status
kubectl get llmisvc qwen2-3b-pattern1 -n $NAMESPACE
# Expected: READY = True

# Check HTTPRoute (auto-created by KServe)
kubectl get httproute -n $NAMESPACE
# Expected: 1 route named qwen2-3b-pattern1

# Check InferencePool (auto-created by KServe)
kubectl get inferencepool -n $NAMESPACE
# Expected: 1 pool with STATUS = Programmed

# Check vLLM pod
kubectl get pods -n $NAMESPACE
# Expected: 1 pod Running (qwen2-3b-pattern1-*)
```

<details>
<summary>View LLMInferenceService manifest (click to expand)</summary>

The `manifests/llmisvc-tpu.yaml` file contains:

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: qwen2-3b-pattern1
  namespace: llm-d-inference-scheduling
spec:
  model:
    uri: hf://Qwen/Qwen2.5-3B-Instruct
    name: Qwen/Qwen2.5-3B-Instruct
  replicas: 1

  # Auto-create routing resources
  router:
    route: {}      # Creates HTTPRoute
    gateway: {}    # Binds to Gateway
    scheduler: {}  # Enables EPP scheduler

  # TPU-specific configuration
  template:
    nodeSelector:
      cloud.google.com/gke-tpu-accelerator: tpu-v6e-slice
      cloud.google.com/gke-tpu-topology: 2x2
    tolerations:
    - key: google.com/tpu
      value: present
      effect: NoSchedule
    containers:
    - name: main
      image: registry.redhat.io/rhaiis/vllm-tpu-rhel9:3.2.5
      env:
      - name: TPU_CHIPS_PER_HOST_BOUNDS
        value: "2,2,1"
      resources:
        limits:
          google.com/tpu: "4"
```

</details>

### Step 7: Test Deployment (10 min)

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu

# Run API tests
./scripts/test-cluster.sh

# Expected:
# ✓ Health check passed
# ✓ List models passed
# ✓ Text completion passed
# ✓ Chat completion passed
```

**Manual Test**:
```bash
# Get Gateway IP (if not already set)
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub \
  -o jsonpath='{.status.addresses[0].value}')

# Health check
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/health

# List models
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

### Step 8: Run Benchmarks (15 min)

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu

# Run comprehensive benchmarks
./scripts/benchmark-cluster.sh

# Expected results (Pattern 1 baseline):
# - Throughput: 12-15 req/s at concurrency 20
# - Latency P50: ~800ms
# - Latency P95: ~1400ms
# - Error rate: 0%

# Results saved to: benchmarks/results/
```

## Verification Checklist

After deployment, verify:

- [ ] **Infrastructure**:
  - [ ] cert-manager pods Running
  - [ ] Istio pods Running
  - [ ] LWS operator Running
  - [ ] KServe controller Running
  - [ ] Gateway has External IP

- [ ] **Cluster**:
  - [ ] 2 CPU nodes (n1-standard-4)
  - [ ] 1 TPU node (ct6e-standard-4t)
  - [ ] TPU node has taint and labels

- [ ] **KServe Resources** (auto-created):
  - [ ] LLMInferenceService READY = True
  - [ ] HTTPRoute created and attached to Gateway
  - [ ] InferencePool STATUS = Programmed

- [ ] **Workload**:
  - [ ] vLLM pod Running and Ready
  - [ ] Pod scheduled on TPU node
  - [ ] Pod has 4 TPU chips allocated

- [ ] **Functionality**:
  - [ ] API endpoints responding (200 OK)
  - [ ] Completions generating text
  - [ ] Benchmarks passing
  - [ ] EPP routing verified

## Common Issues

### Issue: Gateway stuck in Pending

**Solution**:
```bash
# Check GCP Load Balancer quota
gcloud compute project-info describe --project=ecoeng-llmd | grep -A 5 "IN_USE_ADDRESSES"

# If quota exhausted, delete unused LBs:
gcloud compute forwarding-rules list --project=ecoeng-llmd
gcloud compute forwarding-rules delete <unused-lb> --region=<region>
```

### Issue: LLMInferenceService stuck in Not Ready

**Diagnosis**:
```bash
# Check LLMInferenceService status
kubectl describe llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling

# Check pod status
kubectl get pods -n llm-d-inference-scheduling
kubectl describe pod <pod-name> -n llm-d-inference-scheduling

# Check pod logs
kubectl logs <pod-name> -n llm-d-inference-scheduling
```

**Common Causes**:
- Invalid HuggingFace token → Recreate secret with valid token
- Missing TPU node → Check node pool creation
- Image pull error → Verify redhat-pull-secret copied to namespace

### Issue: Pod CrashLoopBackOff

**Diagnosis**:
```bash
kubectl logs -n llm-d-inference-scheduling <pod-name> --previous
kubectl describe pod -n llm-d-inference-scheduling <pod-name>
```

**Common Causes**:
- Invalid HuggingFace token → Fix secret
- Incorrect TPU topology → Check TPU_CHIPS_PER_HOST_BOUNDS = "2,2,1"
- Model download timeout → Increase livenessProbe initialDelaySeconds

### Issue: 503 Service Unavailable

**Diagnosis**:
```bash
# Check InferencePool status
kubectl get inferencepool -n llm-d-inference-scheduling -o yaml

# Check HTTPRoute status
kubectl get httproute -n llm-d-inference-scheduling -o yaml

# Check vLLM pod readiness
kubectl get pods -n llm-d-inference-scheduling
```

**Common Causes**:
- Pod not ready → Wait for readinessProbe to pass
- HTTPRoute not created → Check KServe controller logs
- InferencePool not programmed → Check EPP scheduler

## Cost Management

### Scale Down (Keep Cluster)

```bash
# Delete LLMInferenceService
kubectl delete llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling

# TPU node pool autoscales to 0 after ~10 min
# Cost: $6/day (CPU nodes only)
```

### Delete Cluster (When Done)

```bash
gcloud container clusters delete llmd-istio-tpu-pattern1 \
  --zone=europe-west4-a \
  --project=ecoeng-llmd \
  --quiet

# Cost: $0/day
```

## Next Steps

After successful deployment:

1. **Document results**:
   - Save Gateway IP
   - Export benchmark results
   - Capture KServe auto-created resources

2. **Test advanced features**:
   - Send similar prompts to test prefix caching
   - Monitor EPP scheduler routing decisions
   - Measure cache hit rate

3. **Explore KServe features**:
   - Scale to multiple replicas: `kubectl edit llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling`
   - Change replicas from 1 to 3
   - Observe EPP routing across pods

## Time Estimate

| Phase | Time |
|-------|------|
| Prerequisites check | 10 min |
| Clone repositories | 5 min |
| Create GKE cluster | 20 min |
| Deploy operators | 20 min |
| Deploy KServe | 5 min |
| Setup Gateway | 5 min |
| Deploy LLMInferenceService | 30 min |
| Test deployment | 10 min |
| Run benchmarks | 15 min |
| **Total** | **~120 min (~2 hours)** |

## Architecture Summary

**KServe LLMInferenceService Workflow:**

```
1. User creates LLMInferenceService CRD manifest
   ↓
2. kubectl apply -f manifests/llmisvc-tpu.yaml
   ↓
3. KServe Controller watches CRD
   ↓
4. KServe automatically creates:
   - HTTPRoute (bound to Gateway)
   - InferencePool (with EPP scheduler)
   - Deployment (vLLM pod on TPU)
   ↓
5. Request Flow:
   Client → Gateway → HTTPRoute → InferencePool → EPP → vLLM Pod → TPU
```

**Key Benefits:**
- ✅ Declarative: Single manifest describes entire deployment
- ✅ Automatic: HTTPRoute and InferencePool created automatically
- ✅ Intelligent: EPP scheduler with prefix-cache awareness
- ✅ Integrated: Full lifecycle management by KServe

## Support Resources

- **Deployment Guide**: [docs/deployment-guide.md](docs/deployment-guide.md)
- **Architecture**: [docs/architecture.md](docs/architecture.md)
- **Network Policies**: [manifests/networkpolicies/README.md](manifests/networkpolicies/README.md)
- **Implementation Status**: [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md)
- **Main README**: [README.md](README.md)

## References

- [llm-d-infra-xks](https://github.com/aneeshkp/llm-d-infra-xks) - Infrastructure operators
- [KServe Documentation](https://kserve.github.io/website/) - KServe project
- [OpenDataHub KServe](https://github.com/opendatahub-io/kserve) - ODH KServe fork
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/) - InferencePool spec
- [GKE TPU Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/tpus) - GKE TPU guide
