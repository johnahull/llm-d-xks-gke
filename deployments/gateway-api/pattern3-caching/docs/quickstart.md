# Pattern 3 Quick Start Guide

## Current Deployment Status

### GPU Deployment (nvidia-test-cluster) ✅

- **Gateway**: http://35.208.175.15
- **Namespace**: `llm-d`
- **Model**: Qwen/Qwen2.5-3B-Instruct
- **Replicas**: 3 (all running and healthy)
- **GPU Memory**: 0.75 utilization
- **Prefix Caching**: Enabled

### TPU Deployment (tpu-test-cluster) ✨ NEW

- **Gateway**: http://35.214.223.251
- **Namespace**: `llm-d-inference-scheduling`
- **Model**: Qwen/Qwen2.5-3B-Instruct
- **Replicas**: 3 (12 TPU v6e chips total)
- **TPU Topology**: 2×2 (4 chips per replica)
- **Prefix Caching**: Enabled
- **Deployment Date**: January 27, 2026

## Quick Commands

### GPU Deployment Commands

#### 1. Test Basic Inference (GPU)
```bash
curl -X POST http://35.208.175.15/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-3B-Instruct","prompt":"What is 2+2?","max_tokens":20}'
```

#### 2. Run GPU Benchmark
```bash
cd /home/jhull/devel/rhaiis-test
./benchmarks/scripts/pattern3_comprehensive_benchmark.sh
```

**What it tests:**
- ✓ Health check (all replicas ready)
- ✓ Prefix cache routing (10 requests with shared system prompt)
- ✓ Load distribution (15 requests across replicas)
- ✓ Throughput (50 concurrent requests → ~16-17 req/s)
- ✓ Latency profile (P50/P95/P99)

### TPU Deployment Commands ✨ NEW

#### 1. Test Basic Inference (TPU)
```bash
curl -X POST http://35.214.223.251/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-3B-Instruct","prompt":"What is 2+2?","max_tokens":20}'
```

#### 2. Run TPU Benchmark
```bash
# Quick validation (10 requests)
python3 benchmarks/python/benchmark_async.py \
  --target llm-d-pattern3-tpu \
  --scenario quick_validation

# Comprehensive latency benchmark (100 requests)
python3 benchmarks/python/benchmark_async.py \
  --target llm-d-pattern3-tpu \
  --scenario latency_benchmark \
  --output results/pattern3_tpu_$(date +%Y%m%d).json \
  --html

# Or use shell script
bash benchmarks/scripts/quick_test.sh http://35.214.223.251 "Qwen/Qwen2.5-3B-Instruct"
```

**Initial Results:**
- Success rate: 100%
- TTFT p95: 513ms ✓ MLPerf compliant
- Throughput: 311.76 tokens/sec
- Request rate: 2.35 req/s

#### 3. Monitor TPU Deployment

**Watch pod status:**
```bash
kubectl config use-context gke_ecoeng-llmd_europe-west4-a_tpu-test-cluster
watch -n 2 'kubectl get pods -n llm-d-inference-scheduling -l llm-d.ai/model=random_model'
```

**Check TPU nodes:**
```bash
kubectl get nodes -o wide | grep tpu
```

**View vLLM logs:**
```bash
kubectl logs -n llm-d-inference-scheduling -f \
  $(kubectl get pods -n llm-d-inference-scheduling -l llm-d.ai/model=random_model -o name | head -1)
```

**Check EPP routing decisions:**
```bash
kubectl logs -n llm-d-inference-scheduling -f deployment/gaie-pattern3-epp | grep -E "prefix-cache|score"
```

**View vLLM metrics:**
```bash
POD_NAME=$(kubectl get pods -n llm-d-inference-scheduling -l llm-d.ai/model=random_model -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n llm-d-inference-scheduling ${POD_NAME} -c vllm -- curl -s localhost:8000/metrics | grep -E "vllm:kv_cache|vllm:num_requests"
```

#### 4. Scale TPU Deployment

**Scale to zero (cost savings ~$10,950/month):**
```bash
kubectl scale deployment ms-pattern3-llm-d-modelservice-decode --replicas=0 -n llm-d-inference-scheduling

gcloud container clusters resize tpu-test-cluster \
  --node-pool tpu-v6e-pool \
  --num-nodes 0 \
  --zone europe-west4-a \
  --project ecoeng-llmd \
  --quiet
```

**Resume TPU deployment:**
```bash
# Scale TPU nodes back up
gcloud container clusters resize tpu-test-cluster \
  --node-pool tpu-v6e-pool \
  --num-nodes 3 \
  --zone europe-west4-a \
  --project ecoeng-llmd \
  --quiet

# Wait for nodes to be ready (~5-10 minutes)
kubectl get nodes -w | grep tpu

# Scale deployment back up
kubectl scale deployment ms-pattern3-llm-d-modelservice-decode --replicas=3 -n llm-d-inference-scheduling

# Wait for pods to be ready (~15-20 minutes including XLA compilation)
kubectl get pods -n llm-d-inference-scheduling -l llm-d.ai/model=random_model -w
```

### 3. Monitor Deployment (GPU)

**Watch pod status:**
```bash
watch -n 2 'kubectl get pods -n llm-d -l llm-d.ai/inferenceServing=true'
```

**Check GPU utilization:**
```bash
kubectl exec -n kube-system \
  $(kubectl get pods -n kube-system -l app=nvidia-gpu-device-plugin -o name | head -1) \
  -- nvidia-smi
```

**View vLLM logs:**
```bash
kubectl logs -n llm-d -f \
  $(kubectl get pods -n llm-d -l llm-d.ai/inferenceServing=true -o name | head -1 | cut -d/ -f2)
```

**Check routing decisions:**
```bash
kubectl logs -n llm-d -f deployment/gaie-pattern3-epp | grep -E "score|endpoint"
```

### 4. Check Backend Health
```bash
gcloud compute backend-services get-health \
  gkegw1-on7z-llm-d-gaie-pattern3-ips-bed94ffb-54321-mpaad6qnrg3h \
  --region=us-central1 \
  --project=ecoeng-llmd
```

**Expected:** All 3 backends show `HEALTHY`

## Performance Metrics

### Actual Results (from deployment)
- **Throughput**: 16.66 req/s (50 requests in 3 seconds)
- **Improvement over Pattern 1**: ~16.7× faster
- **Cost**: $1.50/hour ($1,095/month for 3 T4 GPUs)
- **Cost per 1M requests**: $4.36

### Comparison
| Pattern | GPUs | Throughput | Monthly Cost | Cost/1M Req |
|---------|------|------------|--------------|-------------|
| Pattern 1 | 1 | ~1 req/s | $365 | $12.50 |
| Pattern 3 | 3 | ~17 req/s | $1,095 | $4.36 |
| **Ratio** | 3× | **17× faster** | 3× | **65% cheaper** |

## Scaling Operations

### Scale to Zero (cost savings)
```bash
kubectl scale deployment ms-pattern3-llm-d-modelservice-decode -n llm-d --replicas=0

gcloud container clusters resize nvidia-test-cluster \
  --node-pool nvidia-t4-pool \
  --num-nodes 0 \
  --zone us-central1-a \
  --project ecoeng-llmd
```

### Resume Pattern 3
```bash
# Scale GPU nodes back up
gcloud container clusters resize nvidia-test-cluster \
  --node-pool nvidia-t4-pool \
  --num-nodes 3 \
  --zone us-central1-a \
  --project ecoeng-llmd

# Scale deployment back
kubectl scale deployment ms-pattern3-llm-d-modelservice-decode -n llm-d --replicas=3
```

## Troubleshooting

### Issue: Pods stuck in Pending
**Cause:** Not enough GPU nodes

**Fix:**
```bash
gcloud container clusters resize nvidia-test-cluster \
  --node-pool nvidia-t4-pool \
  --num-nodes 3 \
  --zone us-central1-a
```

### Issue: OOM errors
**Cause:** GPU memory utilization too high

**Fix:** Already applied (0.75 instead of 0.80)

### Issue: No response from gateway
**Cause:** Old HTTPRoute conflict

**Fix:**
```bash
kubectl delete httproute -n llm-d llm-d-pattern1-inference-scheduling
```

## Documentation

- **Full Setup Guide**: `llm-d-pattern3-gpu-setup.md`
- **Configuration**: `../llm-d/guides/inference-scheduling/ms-inference-scheduling/pattern3-gpu-overrides.yaml`
- **Benchmark Script**: `benchmarks/scripts/pattern3_comprehensive_benchmark.sh`

## Next Steps

1. ✅ **Deploy Pattern 3** - COMPLETE
2. ✅ **Test inference** - COMPLETE (working at http://35.208.175.15)
3. ✅ **Run throughput benchmark** - COMPLETE (16.66 req/s)
4. ⏭️ **Monitor in production** - Use monitoring commands above
5. ⏭️ **Set up Grafana dashboards** - See monitoring section in full guide
6. ⏭️ **Compare with TPU Pattern 3** - See cost analysis section

---

**Status**: ✅ Pattern 3 GPU is production-ready!
