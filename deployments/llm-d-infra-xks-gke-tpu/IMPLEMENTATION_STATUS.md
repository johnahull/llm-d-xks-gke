# Implementation Status: llm-d-infra-xks GKE TPU Deployment

**Status**: Documentation Complete, Ready for Implementation
**Date**: 2026-02-10
**Pattern**: Pattern 1 - Single model baseline with EPP routing

## Overview

This deployment combines **llm-d-infra-xks operators** (infrastructure automation) with **KServe LLMInferenceService** (declarative workload management) to create a production-ready LLM inference platform on GKE with TPU acceleration.

### Key Advantages Over Previous Deployments

| Feature | istio-kserve-pattern1 | gateway-api-pattern1 | **This Deployment** |
|---------|----------------------|---------------------|---------------------|
| Infrastructure | Manual kubectl (30+ steps) | Manual kubectl | Automated (Makefile) ✅ |
| Reproducibility | Low | Medium | High ✅ |
| Service Mesh | Istio (manual) | None | Istio (operator) ✅ |
| Routing | EPP (KServe) | EPP (llm-d) | EPP (KServe) ✅ |
| Configuration | Scattered YAML | Helm values | KServe CRD manifest ✅ |
| Enterprise Support | Red Hat KServe | Community llm-d | Red Hat KServe ✅ |

## Completed Items

### ✅ Documentation

- [x] **README.md** - Quick start guide with architecture overview
- [x] **docs/architecture.md** - Comprehensive architecture documentation
  - Request flow diagrams
  - Component interaction patterns
  - Comparison with alternative architectures
  - Node pool configuration
  - TPU topology details
- [x] **docs/deployment-guide.md** - Step-by-step deployment instructions
  - Prerequisites and tool requirements
  - 7 deployment phases with verification steps
  - Troubleshooting guide
  - Cost optimization strategies

### ✅ Configuration Files

#### Cluster Configuration
- [x] **cluster-config/create-cluster.sh** - GKE cluster creation script
  - Base cluster with 2 CPU nodes (n1-standard-4)
  - TPU node pool with 1 node (ct6e-standard-4t, TPU v6e-4)
  - Auto-scaling configuration (0-3 nodes)
  - Network policy enabled
  - Workload identity enabled

#### KServe Manifests
- [x] **manifests/llmisvc-tpu.yaml** - KServe LLMInferenceService configuration
  - Model: Qwen/Qwen2.5-3B-Instruct
  - Runtime: Red Hat vLLM TPU RHEL9 3.2.5
  - TPU v6e-4 configuration (4 chips, 2×2 topology)
  - Extended health probes (240s initialDelay)
  - Automatic HTTPRoute and InferencePool creation
  - EPP scheduler with prefix-cache awareness
  - Resource requests: 4 TPU chips

#### Network Policies
- [x] **manifests/networkpolicies/default-deny.yaml** - Default deny all traffic
- [x] **manifests/networkpolicies/allow-gateway-to-vllm.yaml** - Allow Gateway → vLLM
- [x] **manifests/networkpolicies/allow-vllm-egress.yaml** - Allow vLLM egress
- [x] **manifests/networkpolicies/README.md** - Network policy documentation

### ✅ Scripts

- [x] **scripts/test-cluster.sh** - API functional tests
  - Health check
  - List models
  - Text completion
  - Chat completion
  - Prometheus metrics
  - Prefix cache test (EPP routing)

- [x] **scripts/benchmark-cluster.sh** - Performance benchmarks
  - 5 load scenarios (1-100 requests, 1-20 concurrency)
  - Apache Bench integration
  - Latency percentiles (P50, P95, P99)
  - Throughput measurements
  - EPP prefix cache validation
  - Auto-detect Gateway IP

## Pending Implementation

### Phase 1: Infrastructure Setup

**Status**: Not Started
**Estimated Time**: 40 minutes

Tasks:
1. Clone llm-d-infra-xks repository
2. Configure Red Hat registry authentication (podman login)
3. Create values.yaml for operators
4. Deploy operators: `make deploy-all`
5. Verify infrastructure: `make status`
6. Set up Inference Gateway: `./scripts/setup-gateway.sh`

**Prerequisites**:
- Red Hat registry service account credentials
- GCP project `ecoeng-llmd` access
- kubectl, helm, gcloud CLI installed

**Verification**:
- [ ] cert-manager pods Running in cert-manager namespace
- [ ] Istio pods Running in istio-system namespace
- [ ] LWS operator Running in lws-system namespace
- [ ] Inference Gateway has External IP assigned

### Phase 2: GKE Cluster Creation

**Status**: Not Started
**Estimated Time**: 20 minutes

Tasks:
1. Run cluster creation script: `./cluster-config/create-cluster.sh`
2. Verify node pools created (default + TPU)
3. Verify TPU node has correct labels and taints

**Automated by**: `create-cluster.sh` script

**Verification**:
- [ ] 2 CPU nodes (n1-standard-4) in default-pool
- [ ] 1 TPU node (ct6e-standard-4t) in tpu-v6e-pool
- [ ] TPU node has taint: `google.com/tpu=present:NoSchedule`
- [ ] TPU node has capacity: `google.com/tpu: 4`

### Phase 3: Workload Deployment

**Status**: Not Started
**Estimated Time**: 30 minutes (5 min setup + 15 min deployment + 10 min wait)

Tasks:
1. Create application namespace (llm-d-inference-scheduling)
2. Copy Red Hat pull secret from istio-system namespace
3. Create HuggingFace token secret
4. Deploy KServe LLMInferenceService manifest (`kubectl apply -f manifests/llmisvc-tpu.yaml`)
5. Wait for KServe controller to auto-create resources
6. Verify HTTPRoute and InferencePool auto-creation
7. Wait for pod to be Ready (~12-15 min)

**Prerequisites**:
- Infrastructure deployed (Phase 1)
- GKE cluster created (Phase 2)
- KServe controller deployed (Phase 1)
- HuggingFace token

**Verification**:
- [ ] LLMInferenceService READY = True
- [ ] vLLM pod Running and Ready
- [ ] HTTPRoute auto-created by KServe
- [ ] InferencePool auto-created by KServe with STATUS = Programmed
- [ ] NetworkPolicies applied

### Phase 4: Verification and Testing

**Status**: Not Started
**Estimated Time**: 20 minutes

Tasks:
1. Run API tests: `./scripts/test-cluster.sh`
2. Run benchmarks: `./scripts/benchmark-cluster.sh`
3. Verify EPP routing (check scheduler logs)
4. Document actual Gateway IP
5. Save benchmark results

**Verification**:
- [ ] All API endpoints responding (200 OK)
- [ ] Throughput: 12-15 req/s at concurrency 20
- [ ] Latency P95: <1500ms
- [ ] 0 failed requests
- [ ] EPP scheduler logs show routing decisions
- [ ] Prefix cache hits observed in repeated requests

## Directory Structure

```
llm-d-infra-xks-gke-tpu/
├── README.md                          ✅ Complete
├── QUICKSTART.md                      ✅ Complete
├── IMPLEMENTATION_STATUS.md           ✅ This file
├── cluster-config/
│   └── create-cluster.sh              ✅ Complete
├── manifests/
│   ├── llmisvc-tpu.yaml              ✅ Complete (KServe LLMInferenceService)
│   └── networkpolicies/               ✅ Complete
│       ├── README.md
│       ├── default-deny.yaml
│       ├── allow-gateway-to-vllm.yaml
│       └── allow-vllm-egress.yaml
├── archived-examples/
│   └── llm-d-helm-alternative.yaml   📁 (Archived - not used for KServe deployment)
├── scripts/
│   ├── test-cluster.sh                ✅ Complete
│   └── benchmark-cluster.sh           ✅ Complete
├── benchmarks/
│   └── results/                       📁 (created during benchmarking)
└── docs/
    ├── architecture.md                ⏳ Needs review for KServe
    └── deployment-guide.md            ⏳ Needs review for KServe
```

## Implementation Timeline

| Phase | Task | Time | Status |
|-------|------|------|--------|
| **Phase 1** | Infrastructure Setup | 40 min | ⏳ Pending |
| | Clone llm-d-infra-xks | 5 min | ⏳ Pending |
| | Configure auth | 5 min | ⏳ Pending |
| | Deploy operators | 20 min | ⏳ Pending |
| | Setup Gateway | 10 min | ⏳ Pending |
| **Phase 2** | GKE Cluster Creation | 20 min | ⏳ Pending |
| | Create cluster + node pools | 20 min | ⏳ Pending |
| **Phase 3** | Workload Deployment | 30 min | ⏳ Pending |
| | Create namespace & secrets | 5 min | ⏳ Pending |
| | Deploy LLMInferenceService | 5 min | ⏳ Pending |
| | Wait for auto-creation | 5 min | ⏳ Pending |
| | Wait for Ready | 15 min | ⏳ Pending |
| **Phase 4** | Verification | 20 min | ⏳ Pending |
| | API tests | 5 min | ⏳ Pending |
| | Benchmarks | 15 min | ⏳ Pending |
| **Total** | | **~110 min** | ⏳ Pending |

## Cost Analysis

### Running Costs

| Resource | Configuration | Daily Cost | Monthly Cost |
|----------|--------------|------------|--------------|
| Default pool | 2 × n1-standard-4 | ~$6 | ~$180 |
| TPU pool | 1 × ct6e-standard-4t (TPU v6e-4) | ~$127 | ~$3,810 |
| Load Balancer | 1 external IP | ~$0.30 | ~$9 |
| **Total (running)** | | **~$133/day** | **~$3,999/month** |

### Scaled Down Costs

| Resource | Configuration | Daily Cost | Monthly Cost |
|----------|--------------|------------|--------------|
| Default pool | 2 × n1-standard-4 | ~$6 | ~$180 |
| TPU pool | Scaled to 0 | $0 | $0 |
| Load Balancer | 1 external IP | ~$0.30 | ~$9 |
| **Total (scaled down)** | | **~$6/day** | **~$189/month** |

### Cost Optimization Commands

```bash
# Scale down (keep cluster)
kubectl delete llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling
# TPU node pool autoscales to 0 after ~10 min
# Cost: $6/day

# Delete cluster (when done)
gcloud container clusters delete llmd-istio-tpu-pattern1 \
  --zone=europe-west4-a --project=ecoeng-llmd --quiet
# Cost: $0/day
```

## Next Steps

### Immediate (Before Implementation)

1. **Verify prerequisites**:
   - [ ] Red Hat registry credentials available
   - [ ] HuggingFace token created
   - [ ] GCP project access confirmed
   - [ ] Local tools installed (kubectl, helm, gcloud)

2. **Clone external dependencies**:
   ```bash
   cd /home/jhull/devel
   git clone https://github.com/aneeshkp/llm-d-infra-xks.git
   # Note: llm-d framework clone is NOT needed for KServe deployment
   ```

3. **Review documentation**:
   - [ ] Read deployment-guide.md
   - [ ] Understand architecture.md
   - [ ] Review troubleshooting section

### During Implementation

4. **Follow deployment guide** (docs/deployment-guide.md):
   - Execute phases 1-4 in sequence
   - Verify each step before proceeding
   - Document any deviations or issues

5. **Capture results**:
   - [ ] Document actual Gateway IP
   - [ ] Save benchmark results to benchmarks/results/
   - [ ] Take screenshots of key metrics
   - [ ] Export EPP scheduler logs

### After Implementation

6. **Document learnings**:
   - [ ] Update CLAUDE.md with deployment insights
   - [ ] Document any troubleshooting steps needed
   - [ ] Compare performance with previous deployments

7. **Test advanced features**:
   - [ ] Verify EPP prefix-cache routing
   - [ ] Test prefix cache hit rate
   - [ ] Measure latency improvement with caching

8. **Prepare for Pattern 3** (N/S-caching scale-out):
   - [ ] Test scaling to 3 replicas
   - [ ] Verify EPP routes to same pod for similar prompts
   - [ ] Measure cache hit rate across replicas

## Enterprise Support Roadmap

### Current State (February 2026)

**Fully Supported**:
- ✅ Red Hat Istio (sail-operator) - RHOSSM
- ✅ Red Hat KServe (LLMInferenceService) - Enterprise support via OpenDataHub
- ✅ Red Hat vLLM (RHAIIS) - Enterprise support
- ✅ cert-manager (Red Hat) - Enterprise support

**Benefit**: Full stack enterprise support with SLA-backed components.

### Advantages of KServe Approach

**Enterprise Support**:
- ✅ KServe is supported by Red Hat via OpenDataHub
- ✅ LLMInferenceService CRD is stable and production-ready
- ✅ EPP scheduler is part of Gateway API Inference Extension (CNCF project)

**Technical Benefits**:
- ✅ Declarative: Single manifest describes entire deployment
- ✅ Automatic: HTTPRoute and InferencePool created automatically
- ✅ Lifecycle Management: KServe controller handles full workload lifecycle

### Why This Architecture vs Alternatives

**vs Manual KServe (istio-kserve-pattern1)**:
- ✅ Automated infrastructure: Makefile-based operator deployment (vs manual kubectl)
- ✅ Reproducible: Single command deploys all infrastructure
- ✅ Same KServe: Identical LLMInferenceService CRD approach
- ✅ Same routing: EPP scheduler with prefix-cache awareness

**vs llm-d Helm (gateway-api-pattern1)**:
- ✅ Enterprise support: Red Hat KServe vs community llm-d
- ✅ Automatic resource creation: KServe auto-creates HTTPRoute/InferencePool
- ✅ Declarative: Single manifest vs Helm values + manual resources
- ✅ Service mesh: Istio for mTLS, observability, advanced traffic management

**Decision**: This architecture combines automated infrastructure deployment (llm-d-infra-xks operators) with proven KServe LLMInferenceService for best enterprise readiness and operational simplicity.

## References

### Infrastructure
- [llm-d-infra-xks Repository](https://github.com/aneeshkp/llm-d-infra-xks)
- [Red Hat Istio Documentation](https://docs.redhat.com/en/documentation/openshift_service_mesh)

### llm-d Framework
- [llm-d Website](https://llm-d.ai/)
- [llm-d GKE Infrastructure Guide](https://llm-d.ai/docs/guide/InfraProviders/gke)
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/)

### Previous Work
- [istio-kserve Pattern 1](../istio-kserve/pattern1-baseline/) - TPU best practices
- [gateway-api Pattern 1](../../patterns/pattern1-baseline/) - llm-d Helm patterns

### Google Cloud
- [GKE TPU Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/tpus)
- [GKE Network Policies](https://cloud.google.com/kubernetes-engine/docs/how-to/network-policy)

---

**Last Updated**: 2026-02-11
**Status**: Documentation updated to reflect KServe LLMInferenceService architecture
**Next Action**: Begin Phase 1 (Infrastructure Setup) when ready to deploy

**Key Architecture Change**: Updated from llm-d Helm deployment to KServe LLMInferenceService (declarative CRD). KServe controller automatically creates HTTPRoute and InferencePool resources, providing better enterprise support and operational simplicity.
