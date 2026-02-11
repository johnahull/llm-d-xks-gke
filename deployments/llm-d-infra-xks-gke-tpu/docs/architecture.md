# Architecture: Istio + KServe on GKE with TPU

## Executive Summary

This deployment architecture combines **operator-based infrastructure automation** (llm-d-infra-xks) with **declarative LLM serving** (KServe LLMInferenceService) to create a production-ready LLM serving platform on Google Kubernetes Engine with TPU acceleration.

**Key Design Decision**: Use Istio operators for infrastructure + KServe LLMInferenceService for workloads, creating a fully declarative stack with enterprise support and automatic routing intelligence.

## Architecture Layers

### Layer 1: Infrastructure (llm-d-infra-xks)

```
┌─────────────────────────────────────────────────────────┐
│              Infrastructure Operators                   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  cert-manager-operator                           │  │
│  │  - TLS certificate management                    │  │
│  │  - ClusterIssuer for self-signed certs           │  │
│  │  - Automatic CA bundle injection                 │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  sail-operator (Red Hat Istio)                   │  │
│  │  - Istio control plane (istiod)                  │  │
│  │  - Envoy sidecars (optional for workloads)       │  │
│  │  - mTLS between components                       │  │
│  │  - Gateway API integration                       │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  LeaderWorkerSet operator                        │  │
│  │  - Multi-replica workload orchestration          │  │
│  │  - Leader/worker topology (for Pattern 4)        │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**Deployment Method**: Helm + Makefile automation
**Configuration**: Single `values.yaml` file
**Managed By**: llm-d-infra-xks repository

### Layer 2: Gateway and Routing

```
┌─────────────────────────────────────────────────────────┐
│              Inference Gateway (Istio)                  │
│                                                         │
│  External Load Balancer (GCP)                          │
│           ↓                                             │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Gateway (gateway.networking.k8s.io/v1)          │  │
│  │  - namespace: opendatahub                        │  │
│  │  - name: inference-gateway                       │  │
│  │  - class: istio                                   │  │
│  │  - listener: HTTP (port 80)                      │  │
│  └──────────────────────────────────────────────────┘  │
│           ↓                                             │
│  ┌──────────────────────────────────────────────────┐  │
│  │  HTTPRoute (gateway.networking.k8s.io/v1)        │  │
│  │  - path: /llm-d-inference-scheduling/*/v1/*     │  │
│  │  - parentRef: inference-gateway                  │  │
│  │  - backendRefs: InferencePool                    │  │
│  └──────────────────────────────────────────────────┘  │
│           ↓                                             │
│  ┌──────────────────────────────────────────────────┐  │
│  │  InferencePool (inference.networking.k8s.io/v1)  │  │
│  │  - scheduler: EPP (prefix-cache aware)           │  │
│  │  - targetRef: vLLM Service                       │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**Gateway Creation**: `setup-gateway.sh` script (from llm-d-infra-xks)
**HTTPRoute/InferencePool**: Automatically created by KServe controller
**External IP**: Assigned by GCP Load Balancer

### Layer 3: Workload (KServe LLMInferenceService)

```
┌─────────────────────────────────────────────────────────┐
│              vLLM Inference Workload                    │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  LLMInferenceService: qwen2-3b-pattern1          │  │
│  │  - API: serving.kserve.io/v1alpha1               │  │
│  │  - Namespace: llm-d-inference-scheduling         │  │
│  │  - Controller: KServe (opendatahub namespace)    │  │
│  └──────────────────────────────────────────────────┘  │
│           ↓                                             │
│  ┌──────────────────────────────────────────────────┐  │
│  │  KServe Controller Auto-Creates:                 │  │
│  │  - Deployment (vLLM Pod)                         │  │
│  │  - HTTPRoute (routing config)                    │  │
│  │  - InferencePool (EPP scheduler)                 │  │
│  └──────────────────────────────────────────────────┘  │
│           ↓                                             │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Deployment: vLLM Pod(s)                         │  │
│  │  - Image: registry.redhat.io/rhaiis/vllm-tpu    │  │
│  │  - Model: Qwen/Qwen2.5-3B-Instruct               │  │
│  │  - Hardware: TPU v6e-4 (4 chips)                 │  │
│  │  - Tensor parallelism: 4                         │  │
│  └──────────────────────────────────────────────────┘  │
│           ↓                                             │
│  ┌──────────────────────────────────────────────────┐  │
│  │  EPP Scheduler (InferencePool)                   │  │
│  │  - Prefix-cache awareness                        │  │
│  │  - Queue depth monitoring                        │  │
│  │  - KV cache utilization tracking                 │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**Deployment Method**: Declarative manifest (`kubectl apply -f llmisvc-tpu.yaml`)
**Configuration**: `manifests/llmisvc-tpu.yaml` (LLMInferenceService CRD)
**Managed By**: KServe controller (OpenDataHub)

## Request Flow

```
User HTTP Request
     ↓
GCP Load Balancer (External IP)
     ↓
Istio Gateway (gateway.networking.k8s.io)
     ↓
HTTPRoute (path-based routing)
     ↓
InferencePool (intelligent backend selection)
     ↓
EPP Scheduler (prefix-cache aware placement)
     ↓
vLLM Pod (TPU v6e inference)
     ↓
HTTP Response
```

### EPP Scheduler Intelligence

The **EPP (Enhanced Prefix Processing) scheduler** provides intelligent request routing based on:

1. **Prefix Cache Awareness**
   - Tracks which pods have which prompt prefixes cached
   - Routes similar requests to the same pod for cache hits
   - Reduces redundant KV cache computation

2. **Queue Depth Monitoring**
   - Monitors request queue length at each backend
   - Avoids overloading specific pods
   - Balances load across replicas

3. **KV Cache Utilization**
   - Tracks KV cache memory usage per pod
   - Avoids pods with high cache pressure
   - Optimizes memory allocation

**Benefit**: Up to 30% latency reduction for repeated/similar prompts (Pattern 3)

## Node Architecture

### Node Pool Configuration

```
┌─────────────────────────────────────────────────────────┐
│                    GKE Cluster                          │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  default-pool (control plane)                    │  │
│  │  - Machine: n1-standard-4                        │  │
│  │  - vCPUs: 4                                       │  │
│  │  - Memory: 15 GB                                  │  │
│  │  - Nodes: 2 (autoscale 2-4)                      │  │
│  │  - Workloads: istiod, cert-manager, LWS          │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  tpu-v6e-pool (inference workload)               │  │
│  │  - Machine: ct6e-standard-4t                     │  │
│  │  - TPU: v6e-4 (4 chips, 2×2 topology)            │  │
│  │  - vCPUs: 4                                       │  │
│  │  - Memory: 16 GB                                  │  │
│  │  - Nodes: 1 (autoscale 0-3)                      │  │
│  │  - Taint: google.com/tpu=present:NoSchedule      │  │
│  │  - Labels: tpu-accelerator, tpu-topology         │  │
│  │  - Workloads: vLLM pods only                     │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**Autoscaling Strategy**:
- Default pool: Always 2+ nodes (infrastructure stability)
- TPU pool: 0-3 nodes (cost optimization)
- When LLMInferenceService is deleted, TPU pool scales to 0 after ~10 min

## TPU v6e Configuration

### Hardware Topology

```
TPU v6e-4 (2×2 topology)
┌─────────────┬─────────────┐
│  TPU Chip 0 │  TPU Chip 1 │
├─────────────┼─────────────┤
│  TPU Chip 2 │  TPU Chip 3 │
└─────────────┴─────────────┘

TPU_CHIPS_PER_HOST_BOUNDS = 2,2,1
```

**Tensor Parallelism**: Model sharded across 4 chips
**Communication**: High-bandwidth inter-chip links
**Memory**: ~16 GB HBM per chip (64 GB total)

### VFIO Device Mounting

```yaml
# Pod spec (generated by KServe controller)
# Note: KServe automatically configures VFIO device access on GKE TPU nodes
# No manual volume mounting required - GKE Warden handles device allocation
```

**Critical**: TPU v6e uses `/dev/vfio/0` (not `/dev/accel*` like older TPUs)
**Note**: GKE automatically handles VFIO device mounting for TPU workloads

### Environment Variables

```yaml
env:
  - name: TPU_CHIPS_PER_HOST_BOUNDS
    value: "2,2,1"              # 2×2 topology
  - name: TPU_HOST_BOUNDS
    value: "1,1,1"              # Single host
  - name: PJRT_DEVICE
    value: "TPU"                # Enable TPU backend
  - name: TPU_WORKER_HOSTNAMES
    value: "localhost"          # Single-node
  - name: TPU_WORKER_ID
    value: "0"                  # Primary worker
  - name: TPU_NUM_DEVICES
    value: "4"                  # 4 chips
```

## Security Architecture

### Network Policies

```
┌─────────────────────────────────────────────────────────┐
│              Network Policy Stack                       │
│                                                         │
│  1. default-deny-all                                    │
│     - Deny all ingress/egress by default               │
│     - Applied to namespace: llm-d-inference-scheduling │
│                                                         │
│  2. allow-gateway-to-vllm                               │
│     - Allow Istio Gateway → vLLM pods (port 8000)      │
│     - Source: opendatahub namespace (Gateway)          │
│     - Destination: vLLM pods                           │
│                                                         │
│  3. allow-vllm-egress                                   │
│     - Allow vLLM → HuggingFace Hub (model downloads)   │
│     - Allow vLLM → kube-apiserver (liveness probes)    │
│     - Allow vLLM → DNS (name resolution)               │
└─────────────────────────────────────────────────────────┘
```

### Secret Management

```
Secrets in llm-d-inference-scheduling namespace:
  1. redhat-pull-secret (Docker registry auth)
     - Source: Copied from istio-system namespace
     - Used by: vLLM pod imagePullSecrets

  2. huggingface-token (HF Hub auth)
     - Source: kubectl create secret generic
     - Used by: vLLM env HF_TOKEN
```

## Comparison with Alternative Architectures

### Option A: Manual KServe (istio-kserve-pattern1)

```
Istio → Gateway → HTTPRoute → InferencePool → EPP → vLLM
        ↑
    (Manual kubectl deployment - 30+ steps)
```

**Characteristics**:
- ✅ EPP scheduler intelligence
- ✅ KServe LLMInferenceService (same as this deployment)
- ❌ Manual infrastructure deployment (no automation)
- ✅ Enterprise support (Red Hat KServe)

### Option B: llm-d Helm + GKE Gateway (gateway-api-pattern1)

```
GKE Gateway → HTTPRoute → InferencePool → EPP → vLLM
                            ↑
                    (Manual resource creation)
```

**Characteristics**:
- ❌ No service mesh (no mTLS, observability)
- ✅ EPP scheduler intelligence
- ❌ Manual HTTPRoute/InferencePool creation
- ⚠️ Community llm-d (no enterprise support)

### Option C: Istio + KServe (This Architecture)

```
Istio Gateway → HTTPRoute → InferencePool → EPP → vLLM
        ↑                      ↑
    (Automated)          (Auto-created by KServe)
```

**Advantages**:
- ✅ EPP scheduler intelligence (automatic)
- ✅ Prefix-cache awareness
- ✅ Service mesh (Istio for mTLS, observability)
- ✅ Operator-based infrastructure (Makefile automation)
- ✅ Declarative workload (single CRD manifest)
- ✅ Enterprise support (Red Hat KServe + Istio)
- ✅ Automatic resource creation (HTTPRoute + InferencePool)

**Decision**: Option C provides best balance of automation, enterprise support, and operational simplicity.

## Deployment Workflow

```
┌─────────────────────────────────────────────────────────┐
│              Deployment Sequence                        │
│                                                         │
│  Phase 1: GKE Cluster Creation                         │
│    - gcloud container clusters create                  │
│    - Add default node pool (n1-standard-4)             │
│    - Add TPU node pool (ct6e-standard-4t)              │
│                                                         │
│  Phase 2: Infrastructure Operators                     │
│    - Clone llm-d-infra-xks repo                        │
│    - Configure values.yaml                             │
│    - make deploy-all (cert-manager + Istio + LWS)     │
│    - make deploy-kserve (KServe controller)           │
│                                                         │
│  Phase 3: Gateway Setup                                │
│    - ./scripts/setup-gateway.sh                        │
│    - Creates: Istio Gateway (opendatahub namespace)    │
│    - Assigns: External IP via GCP LB                   │
│                                                         │
│  Phase 4: KServe LLMInferenceService                   │
│    - Create namespace: llm-d-inference-scheduling     │
│    - Copy secrets (redhat-pull-secret, hf-token)      │
│    - kubectl apply -f manifests/llmisvc-tpu.yaml      │
│    - KServe controller auto-creates:                   │
│      - vLLM Deployment                                 │
│      - HTTPRoute (routing config)                      │
│      - InferencePool (EPP scheduler)                   │
│                                                         │
│  Phase 5: Network Policies (Optional)                  │
│    - kubectl apply -f networkpolicies/                 │
│    - Applies: default-deny, allow-gateway, allow-egress│
│                                                         │
│  Phase 6: Verification                                 │
│    - Test API endpoints (/v1/models, /v1/completions)  │
│    - Run benchmarks (throughput, latency)              │
│    - Verify auto-created HTTPRoute and InferencePool   │
└─────────────────────────────────────────────────────────┘
```

## Resource Requirements

### CPU Node Pool (default-pool)

| Component | Pods | CPU Request | Memory Request |
|-----------|------|-------------|----------------|
| istiod | 1 | 500m | 2048 Mi |
| cert-manager-operator | 1 | 100m | 256 Mi |
| cert-manager | 1 | 100m | 256 Mi |
| cert-manager-webhook | 1 | 100m | 256 Mi |
| cert-manager-cainjector | 1 | 100m | 256 Mi |
| lws-controller-manager | 1 | 100m | 256 Mi |
| EPP scheduler | 1 | 500m | 512 Mi |
| **Total** | | **~1.5 CPU** | **~4 GB** |

**Recommendation**: 2 × n1-standard-4 nodes (4 vCPU, 15 GB each)

### TPU Node Pool (tpu-v6e-pool)

| Component | Pods | TPU Request | CPU Request | Memory Request |
|-----------|------|-------------|-------------|----------------|
| vLLM (Qwen2.5-3B) | 1 | 4 chips | 2 CPU | 8 GB |

**Recommendation**: 1 × ct6e-standard-4t node (4 TPU chips, 4 vCPU, 16 GB)

## Scaling Patterns

### Pattern 1: Single Model (Current)

```
1 vLLM pod → 4 TPU chips → 1 model
```

**Use Case**: Baseline inference
**Cost**: 1 TPU node (~$127/day)

### Pattern 2: Multi-Model (Future)

```
3 vLLM pods → 12 TPU chips → 3 models
EPP scheduler routes by model name
```

**Use Case**: Multiple models with shared EPP scheduler
**Cost**: 3 TPU nodes (~$381/day)

### Pattern 3: N/S-Caching Scale-Out (Future)

```
3 vLLM pods → 12 TPU chips → 1 model (3 replicas)
EPP scheduler routes by prefix-cache affinity
```

**Use Case**: High throughput with prefix caching
**Cost**: 3 TPU nodes (~$381/day)
**Benefit**: 30% latency reduction for repeated prompts

## Monitoring and Observability

### Metrics Endpoints

```
vLLM Prometheus metrics:
  http://<vllm-pod>:8000/metrics

EPP Scheduler metrics:
  http://<epp-pod>:8080/metrics

Istio control plane metrics:
  http://istiod.istio-system:15014/metrics
```

### Key Metrics to Monitor

**vLLM Performance**:
- `vllm_request_duration_seconds` - Inference latency
- `vllm_queue_length` - Request queue depth
- `vllm_kv_cache_usage_ratio` - Cache utilization
- `vllm_num_requests_running` - Concurrent requests

**EPP Scheduler**:
- `epp_routing_decisions_total` - Routing decisions
- `epp_cache_hit_rate` - Prefix cache hit rate
- `epp_backend_queue_depth` - Per-pod queue depth

**Istio Gateway**:
- `istio_requests_total` - Total requests
- `istio_request_duration_milliseconds` - Gateway latency

## Health Probes Configuration

### Liveness Probe (Pod Restart)

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8000
    scheme: HTTP
  initialDelaySeconds: 240    # TPU initialization (4 min)
  periodSeconds: 30
  timeoutSeconds: 30
  failureThreshold: 5         # 2.5 min grace period
```

**Rationale**: TPU takes ~4-7 min to initialize (model download + XLA compilation)

### Readiness Probe (Traffic Routing)

```yaml
readinessProbe:
  httpGet:
    path: /v1/models
    port: 8000
    scheme: HTTP
  initialDelaySeconds: 240    # Wait for model to load
  periodSeconds: 10
  timeoutSeconds: 10
```

**Rationale**: Don't route traffic until model is fully loaded and compiled

## Failure Modes and Recovery

### TPU Initialization Failure

**Symptom**: Pod CrashLoopBackOff, logs show "TPU not found"
**Cause**: Wrong VM image (missing VFIO drivers)
**Recovery**: Verify node has label `cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice`

### Model Download Timeout

**Symptom**: Liveness probe failure, logs show "404 Not Found"
**Cause**: Invalid HuggingFace token or gated model access
**Recovery**: Verify `huggingface-token` secret, check HF Hub access

### EPP Scheduler Not Routing

**Symptom**: 503 Service Unavailable at Gateway
**Cause**: InferencePool not Programmed
**Recovery**: Check EPP scheduler logs, verify vLLM Service exists

### Gateway External IP Pending

**Symptom**: Gateway stuck in Pending state
**Cause**: GCP Load Balancer quota exhausted
**Recovery**: Check GCP quotas, delete unused LBs

## References

- [llm-d-infra-xks Repository](https://github.com/aneeshkp/llm-d-infra-xks) - Infrastructure operators
- [KServe Documentation](https://kserve.github.io/website/) - KServe project docs
- [OpenDataHub KServe](https://github.com/opendatahub-io/kserve) - ODH KServe fork with LLMInferenceService
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/) - InferencePool specification
- [GKE TPU Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/tpus) - GKE TPU guide
- [Red Hat Istio Documentation](https://docs.redhat.com/en/documentation/openshift_service_mesh) - RHOSSM docs
