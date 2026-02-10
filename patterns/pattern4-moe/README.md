# Pattern 4 & 5: Advanced MoE Multi-Node Deployments

## Overview

**Pattern 4** and **Pattern 5** represent advanced deployment patterns for **Mixture of Experts (MoE)** models with multi-node parallelism and optional Prefill/Decode disaggregation.

### Pattern Comparison

| Feature | Pattern 1-3 | Pattern 4 | Pattern 5 |
|---------|-------------|-----------|-----------|
| **Model Type** | Standard Dense | MoE | MoE |
| **Parallelism** | Tensor/Pipeline | Data + Expert | Data + Expert |
| **GPU Count** | 1-12 | 16-128+ | 32-256+ |
| **Coordination** | None/Simple | LeaderWorkerSet | LWS + P/D Sidecar |
| **Networking** | Standard GKE | GPUDirect RDMA | GPUDirect + KV-transfer |
| **Use Case** | General inference | High-throughput MoE | Ultra-low latency |
| **Complexity** | Low | High | Very High |
| **Cost/month** | $500-$11k | $170k-$340k | $340k-$680k |

---

## Pattern 4: Multi-Node MoE with DP/EP Parallelism

### Architecture

**What it does:**
- Deploys large MoE models (Mixtral-8x7B, DeepSeek-V2.5) across multiple GPUs/nodes
- Uses **Data Parallelism (DP)** to replicate the model for throughput
- Uses **Expert Parallelism (EP)** to shard experts across GPUs
- Intelligent routing via llm-d to distribute load across DP groups

**Example Configuration:**
```
DP=8, EP=16 → 128 GPUs total

Data Parallel Groups (8 replicas):
  Group 0: [GPU 0-15]   ← 16 GPUs hold all experts
  Group 1: [GPU 16-31]  ← 16 GPUs hold all experts
  ...
  Group 7: [GPU 112-127] ← 16 GPUs hold all experts

Each request routes to ONE DP group
Within group: Sparse A2A routes to relevant experts
```

### Key Technologies

1. **LeaderWorkerSet (LWS)**
   - Kubernetes operator for multi-pod coordination
   - Leader manages Ray cluster
   - Workers join as Ray nodes
   - Each DP group = 1 LWS replica

2. **NCCL + GPUDirect RDMA**
   - High-bandwidth all-to-all for expert routing
   - Zero-copy GPU-to-GPU transfers
   - Critical for MoE performance

3. **vLLM with Ray Backend**
   - Distributed execution via Ray
   - Expert parallelism support
   - Automatic load balancing

### Prerequisites

**Hardware:**
- **Minimum**: 16 GPUs (2× A3-highgpu-8g VMs)
- **Recommended**: 128 GPUs (16× A3-highgpu-8g VMs)
- **GPU Type**: A100 80GB or H100 (MoE needs high memory bandwidth)

**Software:**
- GKE cluster with A3/A3-mega node pools
- LeaderWorkerSet operator installed
- vLLM v0.6+ with MoE support
- llm-d with DP-aware routing plugin (custom)

**Quota Requirements:**
- A100/H100 GPU quota (request via GCP support)
- Regional quotas for A3 VMs
- IP address quota for multi-node networking

### Deployment Steps

#### 1. Install LeaderWorkerSet Operator

```bash
kubectl apply -f https://github.com/kubernetes-sigs/lws/releases/latest/download/manifests.yaml
```

#### 2. Create A3 Node Pool

```bash
gcloud container node-pools create a3-moe-pool \
  --cluster=nvidia-test-cluster \
  --zone=us-central1-a \
  --machine-type=a3-highgpu-8g \
  --num-nodes=2 \
  --accelerator=type=nvidia-h100-80gb,count=8 \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=16
```

#### 3. Deploy Pattern 4 PoC

```bash
kubectl apply -f pattern4-poc-lws.yaml
```

#### 4. Monitor Deployment

```bash
# Check LWS status
kubectl get leaderworkerset -n llm-d-inference-scheduling

# Check pod coordination
kubectl get pods -n llm-d-inference-scheduling -l app=pattern4-moe

# View Ray cluster status
kubectl exec -it -n llm-d-inference-scheduling \
  $(kubectl get pod -n llm-d-inference-scheduling -l role=leader -o name | head -1) \
  -- ray status
```

#### 5. Test Inference

```bash
export LB_IP=$(kubectl get svc pattern4-moe-service -n llm-d-inference-scheduling -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -X POST http://${LB_IP}:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Mixtral-8x7B-Instruct",
    "prompt": "Explain quantum computing:",
    "max_tokens": 100
  }'
```

### Performance Expectations

**PoC Configuration (DP=2, EP=8, 16 GPUs):**
- Throughput: ~20-30 req/s
- Latency (TTFT): ~1.5-2.5s
- Cost: ~$9,500/month (A100 on-demand)

**Production (DP=8, EP=16, 128 GPUs):**
- Throughput: ~120-200 req/s
- Latency (TTFT): ~1-1.5s
- Cost: ~$170,000/month (A100 CUD)

### Challenges

1. **Networking Complexity**: Multi-node NCCL requires careful tuning
2. **Quota Limits**: A100/H100 quotas can be restrictive
3. **Cost**: 128 GPUs is expensive (~$170k/month)
4. **Coordination**: Ray cluster management adds complexity
5. **llm-d Integration**: DP-aware routing needs custom plugin development

---

## Pattern 5: MoE with Prefill/Decode Disaggregation

### Architecture

**What it adds over Pattern 4:**
- **Separate clusters** for Prefill and Decode phases
- **KV Cache Transfer** over RDMA between phases
- **P/D Scheduler Sidecar** to coordinate request flow
- **2× GPU count** (separate resources for each phase)

**Why disaggregate?**
- **Prefill** is compute-bound (matrix multiplication)
- **Decode** is memory-bound (KV cache access)
- Separating allows independent optimization and scaling

**Request Flow:**
```
1. Request → Gateway → P/D Scheduler
2. Scheduler routes to Prefill Cluster
3. Prefill generates KV cache
4. KV cache transferred to Decode Cluster via RDMA
5. Decode generates tokens
6. Response streamed back to client
```

### Additional Requirements

**Beyond Pattern 4:**
- **2× GPU count** (separate prefill/decode clusters)
- **KV-transfer support** in vLLM (experimental in v0.8+)
- **P/D scheduler sidecar** (requires development)
- **RDMA for KV transfer** (100+ GB/s bandwidth needed)
- **State management** for KV cache location tracking

### Implementation Status

⚠️ **Pattern 5 is NOT production-ready**

**Blockers:**
- vLLM KV-transfer is experimental (unstable API)
- P/D scheduler sidecar needs significant development
- llm-d doesn't support P/D routing yet
- RDMA KV-transfer needs validation on GKE

**Timeline:**
- Pattern 4 PoC: **Ready to deploy now**
- Pattern 5 PoC: **6-12 months** (requires vLLM maturity + sidecar development)

---

## Cost Analysis

### Pattern 4 Options

| Configuration | GPUs | Monthly Cost | Use Case |
|---------------|------|--------------|----------|
| **PoC** | 16 (DP=2, EP=8) | $9,500 | Validation, testing |
| **Small Prod** | 64 (DP=4, EP=16) | $85,000 | Medium traffic |
| **Full Prod** | 128 (DP=8, EP=16) | $170,000 | High traffic |
| **Large Scale** | 256 (DP=16, EP=16) | $340,000 | Very high traffic |

*Pricing assumes A100 80GB with 3-year CUD (~50% discount)*

### Pattern 5 Options

| Configuration | GPUs | Monthly Cost | Use Case |
|---------------|------|--------------|----------|
| **PoC** | 32 (16P + 16D) | $19,000 | Validation |
| **Small Prod** | 128 (64P + 64D) | $170,000 | Medium traffic |
| **Full Prod** | 256 (128P + 128D) | $340,000 | High traffic |
| **Large Scale** | 512 (256P + 256D) | $680,000 | Ultra-high traffic |

---

## Recommended Path Forward

### Option 1: Start Small with Pattern 4 PoC ✅ RECOMMENDED

**Timeline**: 2-4 weeks
**Cost**: ~$10k/month
**Risk**: Low

**Deliverables:**
1. ✅ Deploy Mixtral-8x7B on 16 GPUs (DP=2, EP=8)
2. ✅ Validate LWS + vLLM integration
3. ✅ Benchmark throughput vs single-node
4. ✅ Develop DP-aware routing for llm-d
5. ⚠️ Identify issues before scaling

**Go/No-Go Decision:**
- If throughput meets requirements → Scale to Pattern 4 Production
- If cost too high → Stick with Pattern 3 scale-out
- If complexity too high → Re-evaluate architecture

### Option 2: Build Pattern 4-lite on T4s

**Timeline**: 1-2 weeks
**Cost**: ~$4k/month
**Risk**: Very Low

**Benefits:**
- Use existing T4 infrastructure
- Validate LWS operator integration
- Test llm-d routing without A100 quota
- Develop skills on smaller scale

**Limitations:**
- No GPUDirect RDMA (use TCP/IP)
- Lower throughput (T4 bandwidth limited)
- Smaller model (Mixtral-8x7B quantized to 4-bit)

### Option 3: Skip Pattern 4, Focus on Pattern 3 GPU Optimization

**Rationale:**
- Pattern 3 GPU already provides 17× throughput vs Pattern 1
- Cost is **40× cheaper** than Pattern 4 (~$1k vs ~$170k/month)
- Much simpler to operate and scale
- Prefix caching + intelligent routing already very effective

**When Pattern 4 makes sense:**
- Need to serve models >50B parameters
- Throughput requirements >100 req/s
- MoE architecture critical for quality
- Budget allows $100k+/month inference spend

---

## Key Takeaways

### Pattern 4
✅ **Pros:**
- Enables large MoE models (Mixtral, DeepSeek)
- High throughput via DP scaling
- Expert parallelism for model sharding
- Production-ready technology stack

❌ **Cons:**
- Very expensive (~$170k/month for 128 GPUs)
- Complex networking (RDMA required)
- Requires significant GPU quota
- Needs custom llm-d plugin for DP routing

### Pattern 5
✅ **Pros:**
- Ultra-low latency via P/D disaggregation
- Independent scaling of prefill/decode
- Theoretical 2× throughput vs Pattern 4

❌ **Cons:**
- **2× cost** of Pattern 4 (~$340k/month)
- vLLM KV-transfer still experimental
- Requires significant sidecar development
- Higher operational complexity
- Not production-ready yet

### Recommendation

**For most use cases: Stick with Pattern 3**
- 17× throughput improvement already achieved
- 40× cheaper than Pattern 4
- Production-proven on GPU and TPU
- Much simpler to operate

**Consider Pattern 4 only if:**
- You NEED MoE models specifically
- You have budget for $100k+/month
- You have dedicated team for operating complex infra
- Throughput requirements exceed Pattern 3 capabilities

**Avoid Pattern 5 until:**
- vLLM KV-transfer is stable (v1.0+)
- llm-d P/D routing is implemented
- You've successfully run Pattern 4 in production
- Latency requirements justify 2× cost

---

## Next Steps

### To Deploy Pattern 4 PoC:

1. **Request GPU Quota** (Week 1)
   ```bash
   # Request A100 quota increase via GCP Console
   # Target: 16+ GPUs in us-central1
   ```

2. **Setup Infrastructure** (Week 2)
   ```bash
   # Install LWS operator
   kubectl apply -f https://github.com/kubernetes-sigs/lws/releases/latest/download/manifests.yaml
   
   # Create A3 node pool
   gcloud container node-pools create a3-moe-pool ...
   ```

3. **Deploy Pattern 4** (Week 3)
   ```bash
   kubectl apply -f pattern4-poc-lws.yaml
   ```

4. **Benchmark & Evaluate** (Week 4)
   ```bash
   # Run comprehensive benchmarks
   # Compare cost vs Pattern 3
   # Make go/no-go decision for production scale
   ```

---

## Resources

- [vLLM MoE Documentation](https://docs.vllm.ai/en/latest/models/supported_models.html#mixture-of-experts-models)
- [LeaderWorkerSet GitHub](https://github.com/kubernetes-sigs/lws)
- [GKE A3 VMs Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/gpus)
- [llm-d Documentation](https://llm-d.ai/)
- [NCCL Tuning Guide](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html)

---

## Files in This Directory

- `README.md` - This file (Pattern 4 & 5 overview)
- `pattern4-poc-lws.yaml` - LeaderWorkerSet manifest for 16 GPU PoC
- `PATTERN4_5_ANALYSIS.md` - Detailed implementation analysis
- `manifests/` - Additional Kubernetes manifests (TBD)

---

**Status**: Pattern 4 PoC ready for deployment | Pattern 5 in research phase
**Last Updated**: January 27, 2026
