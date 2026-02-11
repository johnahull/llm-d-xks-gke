# Quick Start Guide - GKE Native Gateway

**Goal**: Deploy Pattern 1 (single model with EPP routing) on GKE with TPU in ~90 minutes using **GKE native Gateway API** (no Istio).

## Why This Variant?

✅ **Simpler**: No Istio service mesh - fewer components
✅ **Lower Cost**: ~$2/day less infrastructure cost
✅ **Faster Deployment**: Fewer steps, quicker setup
✅ **Native GKE**: Uses built-in Gateway controller

**When to use Istio variant instead:**
- Need mTLS between services
- Require advanced traffic management
- Want comprehensive observability with Istio telemetry

## Prerequisites Checklist

```bash
# 1. Verify tools installed
kubectl version --client  # Need 1.28+
gcloud version           # Need latest

# 2. Verify GCP access
gcloud auth login
gcloud config set project ecoeng-llmd
gcloud projects describe ecoeng-llmd  # Should succeed

# 3. Prepare credentials
# - Red Hat registry: Get from https://access.redhat.com/terms-based-registry/
# - HuggingFace token: Get from https://huggingface.co/settings/tokens
```

## Deployment Steps (~90 min)

### Step 1: Create GKE Cluster (20 min)

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu-native-gateway

# Run cluster creation script
./cluster-config/create-cluster.sh

# Verify Gateway API is available (built into GKE 1.34+)
kubectl api-resources | grep gateway.networking.k8s.io
# Should show: GatewayClass, Gateway, HTTPRoute
```

### Step 2: Deploy Minimal Infrastructure (10 min)

```bash
cd /home/jhull/devel/llm-d-infra-xks

# Configure Red Hat authentication
podman login registry.redhat.io
# Enter: Service account credentials

# Deploy ONLY cert-manager (no Istio, no LWS)
make deploy-cert-manager

# Verify
kubectl get pods -n cert-manager
# Expected: 3 pods Running
```

### Step 3: Deploy KServe (5 min)

```bash
cd /home/jhull/devel/llm-d-infra-xks

# Deploy KServe controller
make deploy-kserve

# Verify
kubectl get pods -n opendatahub
# Expected: kserve-controller-manager Running
```

### Step 4: Create GKE Gateway (3 min)

```bash
# Create Gateway using GKE's native controller
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: inference-gateway
  namespace: opendatahub
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
EOF

# Wait for External IP (~2-3 minutes)
kubectl get gateway inference-gateway -n opendatahub -w
# Press Ctrl+C when ADDRESS is populated

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

# Copy Red Hat pull secret from cert-manager namespace
kubectl get secret redhat-pull-secret -n cert-manager -o yaml | \
  sed "s/namespace: cert-manager/namespace: $NAMESPACE/" | \
  kubectl apply -f -

# Create HuggingFace token secret
kubectl create secret generic hf-token \
  -n $NAMESPACE \
  --from-literal=HF_TOKEN=YOUR_HUGGINGFACE_TOKEN \
  --dry-run=client -o yaml | kubectl apply -f -
# ⚠️ Replace YOUR_HUGGINGFACE_TOKEN with your actual token

# Deploy LLMInferenceService
kubectl apply -f manifests/llmisvc-tpu.yaml

# Monitor deployment (~12-15 min)
kubectl get llmisvc -n $NAMESPACE -w
# Wait for READY = True
```

**What happens:**
1. KServe controller auto-creates HTTPRoute (bound to GKE Gateway)
2. KServe controller auto-creates InferencePool (with EPP scheduler)
3. vLLM pod deploys on TPU node
4. Model downloads from HuggingFace
5. TPU initializes and compiles model

**Verify auto-created resources:**
```bash
# Check LLMInferenceService status
kubectl get llmisvc -n $NAMESPACE

# Check HTTPRoute (auto-created)
kubectl get httproute -n $NAMESPACE

# Check InferencePool (auto-created)
kubectl get inferencepool -n $NAMESPACE
```

### Step 6: Test Deployment (10 min)

```bash
# Run automated tests
./scripts/test-cluster.sh

# Or test manually
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/health

curl -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-3B-Instruct",
    "prompt": "Hello, how are you?",
    "max_tokens": 50
  }'
```

### Step 7: Run Benchmarks (15 min)

```bash
./scripts/benchmark-cluster.sh
```

## Verification Checklist

- [ ] **Infrastructure** (minimal - no Istio):
  - [ ] cert-manager pods Running (3 pods)
  - [ ] KServe controller Running (1 pod)
  - [ ] GKE Gateway has External IP (no Gateway pods - native controller)

- [ ] **Cluster**:
  - [ ] 2 CPU nodes (n1-standard-4)
  - [ ] 1 TPU node (ct6e-standard-4t)
  - [ ] Gateway API CRDs available

- [ ] **KServe Resources** (auto-created):
  - [ ] LLMInferenceService READY = True
  - [ ] HTTPRoute created and attached to GKE Gateway
  - [ ] InferencePool STATUS = Programmed

- [ ] **Workload**:
  - [ ] vLLM pod Running and Ready
  - [ ] Pod scheduled on TPU node

- [ ] **Functionality**:
  - [ ] API endpoints responding (200 OK)
  - [ ] Completions generating text
  - [ ] Benchmarks passing

## Cost Management

### Scale Down

```bash
# Delete LLMInferenceService
kubectl delete llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling

# TPU node pool autoscales to 0 after ~10 min
# Cost: ~$6/day (CPU nodes only)
```

### Delete Cluster

```bash
gcloud container clusters delete llmd-gke-native-tpu-pattern1 \
  --zone=europe-west4-a \
  --project=ecoeng-llmd \
  --quiet

# Cost: $0/day
```

## Time Estimate

| Phase | Time |
|-------|------|
| Create GKE cluster | 20 min |
| Deploy cert-manager | 10 min |
| Deploy KServe | 5 min |
| Create GKE Gateway | 3 min |
| Deploy LLMInferenceService | 30 min |
| Test deployment | 10 min |
| Run benchmarks | 15 min |
| **Total** | **~93 min (~1.5 hours)** |

**Note:** 27 minutes faster than Istio variant due to simpler infrastructure.

## Key Differences from Istio Variant

| Feature | Istio Variant | **This Variant** |
|---------|--------------|------------------|
| Service Mesh | ✅ Yes | ❌ No |
| Infrastructure Pods | ~6 pods | ~4 pods |
| Gateway Implementation | Istio Gateway (pods) | GKE Gateway (native) |
| Deployment Time | ~2 hours | **~1.5 hours** |
| Infrastructure Cost | ~$6/day | **~$4/day** |
| mTLS | ✅ Automatic | ❌ Not included |

## Troubleshooting

### Gateway stuck in Pending

```bash
# Check GatewayClass
kubectl get gatewayclass

# Verify GKE Gateway controller is enabled
gcloud container clusters describe llmd-gke-native-tpu-pattern1 \
  --zone=europe-west4-a \
  --project=ecoeng-llmd \
  --format="value(addonsConfig.gatewayApiConfig.channel)"
```

### Other Issues

See the main [README.md](README.md#troubleshooting) for complete troubleshooting guide.

## Next Steps

After successful deployment:

1. **Compare with Istio variant**: Deploy the [Istio variant](../llm-d-infra-xks-gke-tpu/) to compare features
2. **Test advanced scenarios**: Scale to multiple replicas, test EPP routing
3. **Explore NetworkPolicies**: Add security policies for production use

## References

- **Main README**: [README.md](README.md) - Complete deployment guide
- **Istio Variant**: [../llm-d-infra-xks-gke-tpu/](../llm-d-infra-xks-gke-tpu/) - Compare approaches
- **GKE Gateway Docs**: https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api
- **KServe Docs**: https://kserve.github.io/website/
