# Pattern 4 & 5: MoE Multi-Node GPU Implementation Analysis

## Pattern 4: Multi-node MoE with DP/EP Parallelism

### Architecture Overview
```
Internet → Gateway → llm-d EPP (DP-aware routing)
                     ↓
         LeaderWorkerSet Coordinator
                     ↓
    ┌────────────────┼────────────────┐
    ↓                ↓                ↓
Leader Group 0   Leader Group 1   ... Leader Group 7  (DP=8)
    ↓                ↓                ↓
Workers (EP=16)  Workers (EP=16)  Workers (EP=16)
    ↓                ↓                ↓
Sparse A2A over IB/RoCE for expert routing
```

### Technical Requirements

**1. Hardware Requirements**
- **GPU Count**: DP × EP = 8 × 16 = 128 GPUs minimum
- **GPU Type**: A100 or H100 (need high bandwidth for MoE)
- **Memory**: 80GB per GPU for larger MoE models
- **Networking**: 
  - GPUDirect RDMA capable NICs (Mellanox ConnectX-6 or newer)
  - InfiniBand or RoCE fabric
  - Multi-rail configuration for A2A bandwidth

**2. GKE Constraints**
❌ **Blockers:**
- GKE doesn't natively support InfiniBand
- GPUDirect RDMA requires custom networking stack
- 128 GPUs = significant quota requirements
- A100/H100 availability varies by region

✅ **Possible Workarounds:**
- Use A3/A3-mega VMs (pre-configured with GPUDirect)
- Deploy on Bare Metal Solution with IB
- Use GKE with RoCE over VPC (degraded performance)

**3. Software Stack**
- **vLLM**: Supports MoE with Megatron-LM backend
- **LeaderWorkerSet**: Kubernetes operator for multi-pod coordination
- **NCCL**: For collective communication
- **UCX/OpenUCX**: For RDMA transport

### Implementation Plan

#### Phase 1: Proof of Concept (2-4 GPUs)
```yaml
# Small-scale MoE test with Mixtral-8x7B
apiVersion: leaderworkerset.x-k8s.io/v1
kind: LeaderWorkerSet
metadata:
  name: pattern4-moe-poc
spec:
  replicas: 2  # DP=2
  leaderWorkerTemplate:
    size: 4    # EP=4, 1 leader + 3 workers
    leaderTemplate:
      spec:
        containers:
        - name: vllm-leader
          image: vllm/vllm-openai:latest
          command: ["vllm", "serve"]
          args:
            - "mistralai/Mixtral-8x7B-Instruct-v0.1"
            - "--tensor-parallel-size=4"
            - "--pipeline-parallel-size=1"
            - "--max-model-len=4096"
          resources:
            limits:
              nvidia.com/gpu: 1
    workerTemplate:
      spec:
        containers:
        - name: vllm-worker
          # Same config, workers join leader's process group
```

#### Phase 2: Multi-Node Networking
```bash
# Enable GPUDirect RDMA on A3 VMs
gcloud compute instances create moe-node-{1..8} \
  --machine-type=a3-highgpu-8g \
  --accelerator=type=nvidia-h100-80gb,count=8 \
  --zone=us-central1-a \
  --network-interface=network-tier=PREMIUM,nic-type=GVNIC
  
# Configure NCCL for multi-node
export NCCL_IB_DISABLE=0
export NCCL_NET_GDR_LEVEL=5
export NCCL_IB_HCA=mlx5_0:1,mlx5_1:1
```

#### Phase 3: DP-Aware Routing in llm-d EPP
```yaml
# EPP configuration for DP-aware routing
apiVersion: inference.networking.x-k8s.io/v1alpha1
kind: EndpointPickerConfig
plugins:
  - type: dp-aware-scorer
    config:
      dpReplicas: 8
      routingStrategy: "round-robin-per-dp-group"
  - type: queue-scorer
    weight: 2
schedulingProfiles:
  - name: moe-routing
    plugins:
      - pluginRef: dp-aware-scorer
        weight: 5
      - pluginRef: queue-scorer
        weight: 2
```

### Challenges & Solutions

| Challenge | Solution |
|-----------|----------|
| **IB not supported in GKE** | Use A3-mega VMs with pre-configured GPUDirect |
| **128 GPU quota** | Start with 16-32 GPUs, scale incrementally |
| **A2A bandwidth bottleneck** | Multi-rail networking, NCCL tuning |
| **LWS coordination complexity** | Start with StatefulSet, migrate to LWS |
| **vLLM MoE support** | Use latest vLLM with Megatron backend |

---

## Pattern 5: MoE with P/D Disaggregation

### Architecture Overview
```
Internet → Gateway → llm-d EPP (DP + P/D aware)
                     ↓
         LeaderWorkerSet Coordinator
                     ↓
    ┌─────────────────┼──────────────────┐
    ↓                 ↓                  ↓
Prefill Cluster   Prefill Cluster   ... (DP=8)
(EP=16 experts)   (EP=16 experts)
    ↓                 ↓
KV Cache Transfer over IB/RoCE
    ↓                 ↓
Decode Cluster    Decode Cluster    ... (DP=8)
(EP=16 experts)   (EP=16 experts)
```

### Additional Requirements Beyond Pattern 4

**1. KV Cache Transfer**
- **Bandwidth**: 100+ GB/s per transfer
- **Latency**: <1ms for sub-second TTFT
- **Protocol**: RDMA for zero-copy transfer

**2. Sidecar for P/D Scheduling**
```yaml
# P/D Sidecar injection
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: vllm-prefill
    # ... vLLM prefill config
  - name: pd-scheduler-sidecar
    image: llm-d/pd-scheduler:v1
    env:
    - name: PREFILL_MODE
      value: "true"
    - name: KV_TRANSFER_TARGET
      value: "decode-service.default.svc.cluster.local:9000"
    - name: KV_TRANSFER_PROTOCOL
      value: "rdma"
```

**3. Separate Prefill/Decode Deployments**
```yaml
---
# Prefill Deployment
apiVersion: leaderworkerset.x-k8s.io/v1
kind: LeaderWorkerSet
metadata:
  name: pattern5-prefill
spec:
  replicas: 8  # DP=8
  leaderWorkerTemplate:
    size: 16   # EP=16
    leaderTemplate:
      spec:
        containers:
        - name: vllm-prefill
          args:
            - "--num-scheduler-steps=1"  # Prefill only
            - "--use-v2-block-manager"
            - "--kv-transfer-mode=rdma"
---
# Decode Deployment  
apiVersion: leaderworkerset.x-k8s.io/v1
kind: LeaderWorkerSet
metadata:
  name: pattern5-decode
spec:
  replicas: 8  # DP=8
  leaderWorkerTemplate:
    size: 16   # EP=16
    leaderTemplate:
      spec:
        containers:
        - name: vllm-decode
          args:
            - "--num-scheduler-steps=100"  # Decode only
            - "--kv-transfer-mode=rdma"
```

### Implementation Complexity

| Aspect | Pattern 4 | Pattern 5 | Delta |
|--------|-----------|-----------|-------|
| **GPU Count** | 128 | 256 | 2× |
| **Network Complexity** | High | Very High | KV transfer adds latency sensitivity |
| **Coordination** | LWS only | LWS + P/D sidecar | Sidecar state management |
| **Cost/month** | ~$120k (128× A100) | ~$240k (256× A100) | 2× |

---

## Recommended Implementation Path

### Phase 1: Pattern 4 PoC (2-4 weeks)
**Goal**: Prove MoE + DP/EP on small scale

**Hardware**:
- 16 GPUs (DP=2, EP=8)
- A3-highgpu-8g VMs (2 nodes × 8 GPUs)
- Model: Mixtral-8x7B-Instruct

**Deliverables**:
1. LWS deployment manifest
2. NCCL multi-node communication validated
3. llm-d DP-aware routing working
4. Benchmark: Throughput vs single-node

### Phase 2: Pattern 4 Scale-Out (1-2 months)
**Goal**: Full-scale DP/EP deployment

**Hardware**:
- 128 GPUs (DP=8, EP=16)
- A3-mega VMs with GPUDirect
- Model: DeepSeek-V2.5 (16× expert MoE)

**Deliverables**:
1. Multi-rail RDMA configuration
2. Sparse A2A benchmarks
3. Production-ready routing
4. Cost optimization strategies

### Phase 3: Pattern 5 P/D Disaggregation (2-3 months)
**Goal**: Add prefill/decode separation

**Prerequisites**:
- Pattern 4 stable in production
- vLLM KV-transfer support mature
- P/D sidecar developed and tested

**Deliverables**:
1. KV transfer over RDMA validated
2. P/D scheduler sidecar
3. End-to-end latency optimization
4. Production deployment guide

---

## Critical Dependencies

### 1. vLLM Features Needed
- ✅ MoE support (available in v0.6+)
- ✅ Tensor parallelism (available)
- ⚠️ KV-transfer for P/D disaggregation (experimental in v0.8+)
- ❌ Native LeaderWorkerSet integration (not yet)

### 2. GKE/GCP Features
- ✅ A3/A3-mega VMs with GPUDirect
- ✅ GPU quota (request via support)
- ⚠️ InfiniBand (Bare Metal Solution only)
- ✅ RoCE over VPC (available but slower)

### 3. llm-d Features
- ✅ Gateway API integration
- ✅ InferencePool CRD
- ⚠️ DP-aware routing (needs custom plugin)
- ❌ P/D scheduling (major feature addition)

---

## Cost Estimate

### Pattern 4 (128 GPUs)
```
Hardware:
- 16× A3-highgpu-8g (8 GPUs each) = 128 GPUs
- A100 80GB pricing: ~$3.67/hour per GPU
- Total: 128 × $3.67 = $469.76/hour
- Monthly (24/7): ~$339,000

With committed use discount (3-year):
- ~$169,500/month

Networking:
- GPUDirect RDMA: Included in A3 pricing
- Egress: ~$5k/month
```

### Pattern 5 (256 GPUs)
```
Hardware:
- 32× A3-highgpu-8g = 256 GPUs
- Total: 256 × $3.67 = $939.52/hour
- Monthly (24/7): ~$678,000

With committed use discount:
- ~$339,000/month
```

---

## Alternative: Incremental Approach with Existing GPUs (T4)

If budget/quota constrained, start smaller:

### Pattern 4-lite: MoE on T4s
```
Hardware:
- 16× T4 GPUs (DP=4, EP=4)
- Model: Mixtral-8x7B-Instruct (quantized to 4-bit)
- Cost: ~$3,800/month

Limitations:
- No InfiniBand (use TCP/IP)
- Slower A2A (bandwidth limited)
- Smaller batch sizes
- Good for proving architecture, not production throughput
```

**Benefits**:
- Validate LWS + llm-d integration
- Test DP-aware routing
- Develop sidecar for P/D
- Low cost proof-of-concept

---

## Next Steps Recommendation

1. **Immediate (Week 1-2)**:
   - Request A3 GPU quota from Google
   - Review vLLM MoE documentation
   - Set up LeaderWorkerSet operator on test cluster

2. **Short-term (Week 3-6)**:
   - Deploy Pattern 4 PoC with 16 GPUs
   - Benchmark Mixtral-8x7B with DP=2, EP=8
   - Develop DP-aware routing plugin for llm-d

3. **Medium-term (Month 2-3)**:
   - Scale to 128 GPUs if PoC successful
   - Optimize NCCL for multi-node A2A
   - Production-harden deployment

4. **Long-term (Month 4-6)**:
   - Evaluate P/D disaggregation ROI
   - Develop KV-transfer sidecar
   - Deploy Pattern 5 if justified by latency requirements

