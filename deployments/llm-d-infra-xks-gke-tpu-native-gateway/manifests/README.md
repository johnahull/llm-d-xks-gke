# LLMInferenceService Manifests

This directory contains KServe LLMInferenceService manifests for different deployment patterns and hardware accelerators.

## Available Manifests

### Pattern 1: Single Model Baseline

**TPU Variant (Default):**
```bash
kubectl apply -f llmisvc-tpu.yaml
```
- **Replicas:** 1
- **Accelerator:** TPU v6e-4 (4 chips)
- **Throughput:** 5-7 req/s
- **Cost:** ~$133/day (~$3,990/month)
- **Use case:** Development, POC, low-traffic production

### Pattern 3: N/S-Caching Scale-Out

**TPU Variant (High Performance):**
```bash
kubectl apply -f llmisvc-tpu-pattern3.yaml
```
- **Replicas:** 3
- **Accelerator:** 3× TPU v6e-4 (12 chips total)
- **Throughput:** 15-20 req/s
- **Cost:** ~$387/day (~$11,610/month)
- **Cache hit rate:** 60-70% (with shared prompts)
- **Use case:** High-traffic production, latency-sensitive applications

**GPU Variant (Cost-Effective):**
```bash
kubectl apply -f llmisvc-gpu-pattern3.yaml
```
- **Replicas:** 3
- **Accelerator:** 3× NVIDIA T4 GPU (1 GPU per replica)
- **Throughput:** 16-17 req/s (similar to TPU)
- **Cost:** ~$15/day (~$450/month)
- **Cache hit rate:** 60-70% (with shared prompts)
- **Use case:** Production with budget constraints, similar performance to TPU at 25× lower cost

## Comparison Matrix

| Manifest | Pattern | Accelerator | Replicas | Throughput | Monthly Cost | Cost/1M Req |
|----------|---------|-------------|----------|------------|--------------|-------------|
| `llmisvc-tpu.yaml` | 1 | TPU v6e-4 | 1 | 5-7 req/s | $3,990 | $275 |
| `llmisvc-tpu-pattern3.yaml` | 3 | 3× TPU v6e-4 | 3 | 15-20 req/s | $11,610 | $280 |
| `llmisvc-gpu-pattern3.yaml` | 3 | 3× T4 GPU | 3 | 16-17 req/s | $450 | $10 |

## Choosing the Right Manifest

### Use Pattern 1 (TPU)
- ✅ Development and testing
- ✅ Low traffic (<5 req/s)
- ✅ Proof of concept
- ✅ Cost-sensitive POC

### Use Pattern 3 (TPU)
- ✅ High traffic (>10 req/s)
- ✅ Maximum performance needed
- ✅ Budget allows premium hardware
- ✅ Large model deployments (>7B parameters)

### Use Pattern 3 (GPU)
- ✅ High traffic (>10 req/s)
- ✅ Budget constraints
- ✅ Similar performance to TPU Pattern 3
- ✅ **Recommended for most production deployments** (best cost/performance ratio)

## Key Differences

### Pattern 1 vs Pattern 3
- **Replicas:** 1 → 3 (3× scale-out)
- **Throughput:** 5-7 req/s → 15-20 req/s (2.5-3× higher)
- **Prefix caching:** Disabled → Enabled
- **Routing:** Basic EPP → Prefix-cache-aware EPP
- **Redundancy:** None → Survives single replica failure

### TPU vs GPU (Pattern 3)
- **Performance:** Similar throughput (15-20 vs 16-17 req/s)
- **Cost:** TPU is 25× more expensive ($11,610 vs $450/month)
- **Latency:** TPU slightly lower (~450ms vs ~500ms p50)
- **Recommendation:** GPU for Pattern 3 unless maximum performance is critical

## Prerequisites

**All manifests require:**
- KServe controller deployed
- Gateway API enabled
- Red Hat pull secret (`redhat-pull-secret`)
- HuggingFace token secret (`hf-token`)

**Additional requirements by manifest:**

**TPU manifests:**
- TPU v6e node pool created
- TPU quota (4 chips for Pattern 1, 12 chips for Pattern 3)
- Zone with TPU v6e availability (e.g., europe-west4-a)

**GPU manifest:**
- GPU node pool with T4 GPUs
- GPU quota (3 GPUs for Pattern 3)
- Node pool with `cloud.google.com/gke-accelerator: nvidia-tesla-t4` label

## Deployment Examples

### Deploy Pattern 1 (TPU)
```bash
# Create namespace and secrets
export NAMESPACE=llm-d-inference-scheduling
kubectl create namespace $NAMESPACE

# Copy Red Hat pull secret
kubectl get secret redhat-pull-secret -n cert-manager -o yaml | \
  sed "s/namespace: cert-manager/namespace: $NAMESPACE/" | \
  kubectl apply -f -

# Create HuggingFace token secret
kubectl create secret generic hf-token \
  -n $NAMESPACE \
  --from-literal=HF_TOKEN=YOUR_TOKEN

# Deploy Pattern 1
kubectl apply -f llmisvc-tpu.yaml
```

### Switch from Pattern 1 to Pattern 3 (TPU)
```bash
# Delete Pattern 1
kubectl delete llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling

# Increase TPU node pool capacity
gcloud container node-pools update tpu-v6e-pool \
  --cluster=llmd-native-gateway-tpu-pattern1 \
  --zone=europe-west4-a \
  --max-nodes=3

# Deploy Pattern 3
kubectl apply -f llmisvc-tpu-pattern3.yaml
```

### Deploy Pattern 3 (GPU) for Cost Savings
```bash
# Create GPU node pool (if not exists)
gcloud container node-pools create gpu-t4-pool \
  --cluster=llmd-native-gateway-tpu-pattern1 \
  --zone=europe-west4-a \
  --machine-type=n1-standard-4 \
  --accelerator=type=nvidia-tesla-t4,count=1 \
  --num-nodes=3 \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=5

# Deploy Pattern 3 GPU
kubectl apply -f llmisvc-gpu-pattern3.yaml
```

## Monitoring

After deployment, monitor the LLMInferenceService:

```bash
# Watch deployment progress
kubectl get llmisvc -n llm-d-inference-scheduling -w

# Check pods
kubectl get pods -n llm-d-inference-scheduling

# View auto-created resources
kubectl get httproute,inferencepool -n llm-d-inference-scheduling
```

## Documentation

- **Pattern 1:** See main [README.md](../README.md)
- **Pattern 3:** See [PATTERN3.md](../PATTERN3.md)
- **Troubleshooting:** See [ISSUES.md](../ISSUES.md)

---

**Last Updated**: 2026-02-11
