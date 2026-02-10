# Complete Pattern Comparison Matrix

## All Five Deployment Patterns

| Aspect | Pattern 1 | Pattern 2 | Pattern 3 | Pattern 4 | Pattern 5 |
|--------|-----------|-----------|-----------|-----------|-----------|
| **Name** | Baseline | Multi-Model BBR | N/S-Caching | MoE Multi-Node | MoE P/D Disagg |
| **Model Type** | Dense | Dense (multi) | Dense | MoE | MoE |
| **Replicas** | 1 | 2+ (1 per model) | 3+ (same model) | DP groups | 2× DP groups |
| **Parallelism** | Tensor/Pipeline | None/Tensor | Tensor | Data + Expert | Data + Expert |
| **GPU Count (min)** | 1 | 2 | 3 | 16 | 32 |
| **GPU Count (prod)** | 1 | 2-8 | 3-5 | 128 | 256 |
| **Coordination** | None | Gateway | Gateway + EPP | LWS + Ray | LWS + P/D Sidecar |
| **Routing Strategy** | Simple | Model-based | Prefix-cache aware | DP-aware | P/D + DP-aware |
| **Networking** | Standard | Standard | Standard | GPUDirect RDMA | RDMA + KV-transfer |
| **Complexity** | ★☆☆☆☆ | ★★☆☆☆ | ★★★☆☆ | ★★★★☆ | ★★★★★ |
| **Cost/month (GPU)** | $365 | $730 | $1,095 | $170,000 | $340,000 |
| **Cost/month (TPU)** | $3,650 | $7,300 | $10,950 | N/A | N/A |
| **Throughput** | 1× | 2× | 17× | 120× | 240× |
| **Use Case** | Dev/Test | Multi-task | Production | Large MoE | Ultra-low latency |
| **Status** | ✅ Production | ✅ Production | ✅ Production | ⚠️ PoC Ready | ❌ Research |

---

## Cost Efficiency Comparison

### Cost per Request/Second (GPU, monthly)

| Pattern | Monthly Cost | Throughput (req/s) | Cost per req/s |
|---------|--------------|-------------------|----------------|
| **Pattern 1** | $365 | ~1 | $365 |
| **Pattern 2** | $730 | ~2 | $365 |
| **Pattern 3** ✅ | $1,095 | ~17 | **$64** |
| **Pattern 4** | $170,000 | ~120 | $1,417 |
| **Pattern 5** | $340,000 | ~240 | $1,417 |

**Winner**: Pattern 3 (5.7× more cost-efficient than Pattern 1, 22× cheaper than Pattern 4)

---

## Technical Complexity Comparison

### Infrastructure Requirements

| Component | P1 | P2 | P3 | P4 | P5 |
|-----------|----|----|----|----|-----|
| **Custom Gateway** | ❌ | ✅ | ✅ | ✅ | ✅ |
| **llm-d EPP** | ❌ | ✅ | ✅ | ✅ | ✅ |
| **LeaderWorkerSet** | ❌ | ❌ | ❌ | ✅ | ✅ |
| **Ray Cluster** | ❌ | ❌ | ❌ | ✅ | ✅ |
| **GPUDirect RDMA** | ❌ | ❌ | ❌ | ✅ | ✅ |
| **P/D Sidecar** | ❌ | ❌ | ❌ | ❌ | ✅ |
| **KV-Transfer** | ❌ | ❌ | ❌ | ❌ | ✅ |

### Operational Overhead

| Aspect | P1 | P2 | P3 | P4 | P5 |
|--------|----|----|----|----|-----|
| **Deployment Time** | 5 min | 10 min | 15 min | 60+ min | 120+ min |
| **Startup Time** | 3 min | 5 min | 7 min | 20+ min | 40+ min |
| **Monitoring Complexity** | Low | Medium | Medium | High | Very High |
| **Debug Difficulty** | Easy | Medium | Medium | Hard | Very Hard |
| **Operator Skill Required** | Junior | Mid-level | Mid-level | Senior | Expert |

---

## When to Use Each Pattern

### Pattern 1: Baseline ✅

**Use when:**
- Development/testing environments
- Low traffic (<1 req/s)
- Simple proof-of-concept
- Budget <$500/month

**Don't use when:**
- Need high throughput
- Production workload
- Cost per request matters

### Pattern 2: Multi-Model BBR ✅

**Use when:**
- Need multiple models (e.g., 7B + 3B)
- Different models for different tasks
- Model selection based on request
- Budget <$2k/month

**Don't use when:**
- Only need one model (use Pattern 1 or 3)
- Need very high throughput (use Pattern 3)
- Models have different latency requirements

### Pattern 3: N/S-Caching ✅ RECOMMENDED

**Use when:**
- Production workloads
- Throughput >5 req/s needed
- Repeated system prompts (RAG, chatbots)
- Want best cost/performance ratio
- Budget $1k-$15k/month

**Don't use when:**
- Traffic <5 req/s (use Pattern 1)
- Need MoE models (use Pattern 4)
- Every request has unique prompt

**✨ Best choice for 90% of production deployments**

### Pattern 4: MoE Multi-Node ⚠️

**Use when:**
- MUST use MoE models (Mixtral, DeepSeek)
- Throughput >100 req/s required
- Model quality requires 100B+ parameters
- Budget >$100k/month available
- Team can manage complex infra

**Don't use when:**
- Dense models meet quality requirements
- Budget <$50k/month
- Team lacks distributed systems expertise
- Pattern 3 can meet throughput needs

### Pattern 5: MoE with P/D Disaggregation ❌

**Use when:**
- Pattern 4 deployed and stable
- Need <500ms TTFT at scale
- Budget >$200k/month
- Dedicated platform team
- Research/experimental projects

**Don't use when:**
- Pattern 4 not yet proven
- vLLM KV-transfer not stable
- Production workload (too risky)
- Can achieve latency targets with Pattern 3

---

## Migration Path

```
Pattern 1 (Dev/Test)
    ↓
Pattern 3 (Production - start here for most cases)
    ↓
Pattern 2 (if need multi-model) OR Pattern 4 (if need MoE)
    ↓
Pattern 5 (only if Pattern 4 insufficient and budget allows)
```

**Recommended**: Start with Pattern 3 for production, only escalate to Pattern 4/5 if requirements truly demand it.

---

## ROI Analysis

### Pattern 3 vs Pattern 4

**Scenario**: Need 100 req/s throughput

**Option A: Pattern 3 Scale-Out**
- GPUs needed: ~18 (6 replicas × 3 GPUs)
- Monthly cost: ~$6,500
- Complexity: Medium
- Deployment time: 1 week

**Option B: Pattern 4 PoC → Production**
- GPUs needed: 128
- Monthly cost: ~$170,000
- Complexity: Very High
- Deployment time: 3-6 months

**Savings with Pattern 3**: $163,500/month (96% cheaper)

**When Pattern 4 justified:**
- Dense models cannot achieve quality targets
- MoE architecture scientifically required
- Cost per request not primary concern
- Platform engineering team available

---

## Summary Recommendation

### For 90% of Use Cases: Pattern 3 ✅

**Why:**
- 17× throughput improvement vs Pattern 1
- $64 per req/s (5.7× cheaper than Pattern 1)
- 40× cheaper than Pattern 4
- Production-proven (GPU and TPU)
- Simple to operate
- Scales to 100+ req/s with 5-6 replicas

### For MoE Requirements: Pattern 4 ⚠️

**Why:**
- Only way to run large MoE models
- Proven technology stack
- Can achieve 100+ req/s throughput
- But: Very expensive, complex, needs dedicated team

### Avoid Pattern 5 Until: ❌

**Blockers:**
- vLLM KV-transfer experimental
- No production deployments yet
- 2× cost of Pattern 4
- High risk for production

---

**Last Updated**: January 27, 2026
**Status**: Patterns 1-3 production-ready | Pattern 4 PoC-ready | Pattern 5 research phase
