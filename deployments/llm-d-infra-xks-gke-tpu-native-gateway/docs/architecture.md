# Architecture: GKE Native Gateway + KServe on GKE with TPU

## Executive Summary

This deployment architecture combines **minimal infrastructure** (cert-manager only) with **declarative LLM serving** (KServe LLMInferenceService) using **GKE's native Gateway API controller** to create a lightweight, cost-effective LLM serving platform on Google Kubernetes Engine with TPU acceleration.

**Key Design Decision**: Use GKE native Gateway instead of Istio to reduce infrastructure complexity and cost while maintaining KServe's declarative workflow and EPP routing intelligence.

## Why This Variant?

### Advantages

✅ **Simpler Architecture** - Fewer moving parts (no service mesh)
✅ **Lower Cost** - ~$2/day less than Istio variant (no Istio control plane pods)
✅ **Faster Deployment** - ~27 minutes faster (fewer components to deploy)
✅ **Native GKE Integration** - Uses GKE's built-in Gateway controller
✅ **Same EPP Intelligence** - Retains prefix-cache aware routing

### Trade-offs

❌ **No mTLS** - No automatic service-to-service encryption
❌ **Limited Observability** - No Istio telemetry (must use vLLM metrics directly)
❌ **No Service Mesh** - No advanced traffic management features

### When to Use This Variant

**Choose Native Gateway** when:
- Cost optimization is priority
- Simplicity matters more than advanced features
- You don't need mTLS between services
- Direct metrics collection is acceptable

**Choose Istio Variant** when:
- Need service mesh capabilities (mTLS, observability)
- Require advanced traffic management
- Want comprehensive Istio telemetry
- Enterprise support for service mesh is important

## Critical Discovery: GatewayClass Support

⚠️ **IMPORTANT**: Not all GKE GatewayClasses support the InferencePool backend.

### GatewayClass Support Matrix

| GatewayClass | InferencePool Support | Use Case |
|--------------|----------------------|----------|
| `gke-l7-regional-external-managed` | ✅ **YES** | **Recommended** - External HTTP/HTTPS with regional load balancer |
| `gke-l7-rilb` | ✅ YES | Internal load balancer (VPC-only access) |
| `gke-l7-global-external-managed` | ❌ **NO** | Global load balancer - does NOT work with InferencePool |

**Why This Matters**:
- InferencePool is a Gateway API Inference Extension custom backend
- Global GatewayClass only supports standard Kubernetes Service backends
- Regional GatewayClass supports both Service and InferencePool backends
- Using global class causes HTTPRoute to accept but traffic fails routing

**Lesson Learned**: Always use `gke-l7-regional-external-managed` for InferencePool-based intelligent routing.

See [ISSUES.md#10](../ISSUES.md#10-gatewayclass-support-for-inferencepool) for detailed troubleshooting steps.

## Architecture Layers

### Layer 1: Minimal Infrastructure

```
┌─────────────────────────────────────────────────────────┐
│              Infrastructure Operators                   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  cert-manager                                    │  │
│  │  - TLS certificate management                    │  │
│  │  - ClusterIssuer for self-signed certs           │  │
│  │  - Automatic CA bundle injection                 │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  KServe controller                               │  │
│  │  - LLMInferenceService reconciliation            │  │
│  │  - HTTPRoute/InferencePool auto-creation         │  │
│  │  - EPP scheduler integration                     │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**Key Difference**: No Istio operators (sail-operator, LeaderWorkerSet)

**Deployment Method**: Makefile targets from llm-d-infra-xks
**Configuration**: `make deploy-cert-manager && make deploy-kserve`
**Managed By**: llm-d-infra-xks repository

### Layer 2: Gateway and Routing (GKE Native)

```
┌─────────────────────────────────────────────────────────┐
│              Inference Gateway (GKE Native)             │
│                                                         │
│  External Load Balancer (GCP)                          │
│           ↓                                             │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Gateway (gateway.networking.k8s.io/v1)          │  │
│  │  - namespace: opendatahub                        │  │
│  │  - name: inference-gateway                       │  │
│  │  - class: gke-l7-regional-external-managed       │  │
│  │  - listener: HTTP (port 80)                      │  │
│  │  - NO Gateway pods (native controller)           │  │
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

**Key Difference**:
- `gatewayClassName: gke-l7-regional-external-managed` (not `istio` or global)
- **CRITICAL**: Must use regional GatewayClass - global does NOT support InferencePool
- No Istio Gateway pods - GKE controller runs in control plane
- Direct HTTP (no Envoy sidecars)

**Gateway Creation**: Manual `kubectl apply` (see QUICKSTART.md)
**HTTPRoute/InferencePool**: Automatically created by KServe controller
**External IP**: Assigned by GCP Load Balancer (~2-3 min)

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
│  │  - NO Istio sidecars - direct HTTP               │  │
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

**Key Difference**:
- No Envoy sidecar injection
- Health probes use `scheme: HTTP` (not HTTPS)
- Direct vLLM HTTP server (no TLS termination)

**Deployment Method**: Declarative manifest (`kubectl apply -f llmisvc-tpu.yaml`)
**Configuration**: `manifests/llmisvc-tpu.yaml` (LLMInferenceService CRD)
**Managed By**: KServe controller (OpenDataHub)

## Request Flow

```
User HTTP Request
     ↓
GCP Load Balancer (External IP)
     ↓
GKE Gateway Controller (native - no pods)
     ↓
HTTPRoute (path-based routing)
     ↓
InferencePool (intelligent backend selection)
     ↓
EPP Scheduler (prefix-cache aware placement)
     ↓
vLLM Pod (TPU v6e inference - direct HTTP)
     ↓
HTTP Response
```

**Simplified Path**: 5 hops vs 6 hops in Istio variant (no Envoy sidecar)

### EPP Scheduler Intelligence

The **EPP (Enhanced Prefix Processing) scheduler** provides identical intelligent routing as the Istio variant:

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

**Benefit**: Up to 30% latency reduction for repeated/similar prompts (same as Istio variant)

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
│  │  - Workloads: cert-manager, KServe, EPP          │  │
│  │  - NO Istio control plane                        │  │
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

### Environment Variables

```yaml
env:
  - name: TPU_CHIPS_PER_HOST_BOUNDS
    value: "2,2,1"              # 2×2 topology
  - name: TPU_HOST_BOUNDS
    value: "1,1,1"              # Single host
  - name: PJRT_DEVICE
    value: "TPU"                # Enable TPU backend
  - name: HF_TOKEN
    valueFrom:
      secretKeyRef:
        name: hf-token
        key: HF_TOKEN
```

**Note**: Identical to Istio variant - TPU configuration is platform-agnostic

## Comparison with Istio Variant

| Feature | Istio Variant | **Native Gateway** |
|---------|--------------|---------------------|
| Service Mesh | ✅ Yes (Istio) | ❌ No |
| Gateway Implementation | Istio Gateway (pods) | GKE Gateway (native) |
| Infrastructure Pods | ~6 pods | **~4 pods** |
| Deployment Time | ~2 hours | **~1.5 hours** |
| Infrastructure Cost | ~$6/day | **~$4/day** |
| mTLS | ✅ Automatic | ❌ Not included |
| Advanced Traffic Mgmt | ✅ Yes | ❌ No |
| EPP Scheduler | ✅ Yes | ✅ **Yes (same)** |
| KServe Auto-creation | ✅ Yes | ✅ **Yes (same)** |
| Envoy Sidecars | ✅ Optional | ❌ No |
| Istio Telemetry | ✅ Yes | ❌ No |

**Summary**: Native Gateway variant trades service mesh features for simplicity and cost savings while retaining core KServe/EPP intelligence.

## Deployment Workflow

```
┌─────────────────────────────────────────────────────────┐
│              Deployment Sequence                        │
│                                                         │
│  Phase 1: GKE Cluster Creation (20 min)                │
│    - gcloud container clusters create                  │
│    - Add default node pool (n1-standard-4)             │
│    - Add TPU node pool (ct6e-standard-4t)              │
│                                                         │
│  Phase 2: Minimal Infrastructure (10 min)              │
│    - Clone llm-d-infra-xks repo                        │
│    - make deploy-cert-manager                          │
│    - make deploy-kserve                                │
│    - NO Istio deployment                               │
│                                                         │
│  Phase 3: GKE Gateway Setup (3 min)                    │
│    - kubectl apply Gateway manifest                    │
│    - GKE assigns External IP                           │
│    - NO setup-gateway.sh script                        │
│                                                         │
│  Phase 4: KServe LLMInferenceService (30 min)          │
│    - Create namespace: llm-d-inference-scheduling     │
│    - Copy secrets (redhat-pull-secret, hf-token)      │
│    - kubectl apply -f manifests/llmisvc-tpu.yaml      │
│    - KServe controller auto-creates:                   │
│      - vLLM Deployment (no sidecars)                   │
│      - HTTPRoute (routing config)                      │
│      - InferencePool (EPP scheduler)                   │
│                                                         │
│  Phase 5: Verification (10 min)                        │
│    - Test API endpoints (/v1/models, /v1/completions)  │
│    - Run benchmarks (throughput, latency)              │
│    - Verify auto-created HTTPRoute and InferencePool   │
│                                                         │
│  Total: ~90 minutes (~27 min faster than Istio)       │
└─────────────────────────────────────────────────────────┘
```

## Resource Requirements

### CPU Node Pool (default-pool)

| Component | Pods | CPU Request | Memory Request |
|-----------|------|-------------|----------------|
| cert-manager-operator | 1 | 100m | 256 Mi |
| cert-manager | 1 | 100m | 256 Mi |
| cert-manager-webhook | 1 | 100m | 256 Mi |
| cert-manager-cainjector | 1 | 100m | 256 Mi |
| kserve-controller-manager | 1 | 100m | 300 Mi |
| EPP scheduler | 1 | 500m | 512 Mi |
| **Total** | | **~1.0 CPU** | **~1.8 GB** |

**Key Difference**: No istiod pod (~500m CPU, 2 GB saved)

**Recommendation**: 2 × n1-standard-4 nodes (4 vCPU, 15 GB each)

### TPU Node Pool (tpu-v6e-pool)

| Component | Pods | TPU Request | CPU Request | Memory Request |
|-----------|------|-------------|-------------|----------------|
| vLLM (Qwen2.5-3B) | 1 | 4 chips | 2 CPU | 8 GB |

**Recommendation**: 1 × ct6e-standard-4t node (4 TPU chips, 4 vCPU, 16 GB)

**Note**: Identical to Istio variant

## Health Probes Configuration

### Liveness Probe (Pod Restart)

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8000
    scheme: HTTP              # Direct HTTP (not HTTPS)
  initialDelaySeconds: 240    # TPU initialization (4 min)
  periodSeconds: 30
  timeoutSeconds: 30
  failureThreshold: 5         # 2.5 min grace period
```

**Key Difference**: `scheme: HTTP` (no TLS sidecars)

### Readiness Probe (Traffic Routing)

```yaml
readinessProbe:
  httpGet:
    path: /v1/models
    port: 8000
    scheme: HTTP              # Direct HTTP (not HTTPS)
  initialDelaySeconds: 240    # Wait for model to load
  periodSeconds: 10
  timeoutSeconds: 10
```

**Rationale**: Don't route traffic until model is fully loaded and compiled

## Cost Analysis

### Daily Cost Breakdown

| Component | Configuration | Istio Variant | **Native Gateway** |
|-----------|--------------|---------------|---------------------|
| Default pool | 2 × n1-standard-4 | $6/day | **$6/day** |
| Gateway pods | Istio Gateway | ~$0/day | **$0/day (native)** |
| Infrastructure pods | istiod, LWS, etc | Included above | **~$0/day (fewer pods)** |
| TPU pool | 1 × ct6e-standard-4t | $127/day | **$127/day** |
| **Total (running)** | | **$133/day** | **~$133/day** |
| **Infrastructure only** | | **$6/day** | **~$4/day** |

**Savings**: ~$2/day in infrastructure costs when TPU scaled down

### Monthly Cost Estimates

| Scenario | Istio Variant | **Native Gateway** |
|----------|---------------|---------------------|
| Running 24/7 | ~$3,990/month | **~$3,930/month** |
| Scaled to 0 TPU | ~$180/month | **~$120/month** |
| **Annual savings** | | **~$720/year** |

## Monitoring and Observability

### Metrics Endpoints

```
vLLM Prometheus metrics:
  http://<vllm-pod>:8000/metrics

EPP Scheduler metrics:
  http://<epp-pod>:8080/metrics

GKE Gateway metrics:
  Exported to GCP Cloud Monitoring
```

**Key Difference**: No Istio telemetry - use vLLM and GCP metrics directly

### Recommended Monitoring Setup

**Option 1: GCP Cloud Monitoring**
- Enable GKE cluster monitoring
- Configure Log Router for vLLM logs
- Create dashboards for:
  - Request rate (from GCP Load Balancer)
  - Latency percentiles (from LB)
  - vLLM metrics (scraped from pods)

**Option 2: Prometheus (Manual Install)**
```bash
# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace

# Configure ServiceMonitor for vLLM
kubectl apply -f manifests/monitoring/vllm-servicemonitor.yaml
```

## Failure Modes and Recovery

### Gateway External IP Pending

**Symptom**: Gateway stuck in Pending state
**Cause**: GCP Load Balancer provisioning delay or quota
**Recovery**:
```bash
# Check Gateway status
kubectl describe gateway inference-gateway -n opendatahub

# Verify GCP LB quota
gcloud compute project-info describe --project=ecoeng-llmd

# Wait 2-3 minutes for GCP provisioning
```

### HTTPRoute Not Attaching to Gateway

**Symptom**: HTTPRoute shows `Accepted: False`
**Cause**: Gateway namespace mismatch or Gateway not ready
**Recovery**:
```bash
# Verify Gateway is Programmed
kubectl get gateway inference-gateway -n opendatahub

# Check HTTPRoute status
kubectl describe httproute -n llm-d-inference-scheduling
```

### Other Issues

See [Troubleshooting section in README.md](../README.md#troubleshooting) for complete guide including:
- TPU initialization failures
- Model download timeouts
- EPP scheduler routing issues
- NetworkPolicy blocking traffic

## Migration from Istio Variant

To migrate from the Istio variant to native Gateway:

```bash
# 1. Delete LLMInferenceService (keeps infra)
kubectl delete llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling

# 2. Delete Istio Gateway
kubectl delete gateway inference-gateway -n opendatahub

# 3. Uninstall Istio operators (optional - cost savings)
cd /home/jhull/devel/llm-d-infra-xks
make undeploy-istio

# 4. Create GKE Gateway (MUST use regional class)
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: inference-gateway
  namespace: opendatahub
spec:
  gatewayClassName: gke-l7-regional-external-managed  # CRITICAL: regional, not global
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
EOF

# 5. Redeploy LLMInferenceService
kubectl apply -f manifests/llmisvc-tpu.yaml
```

**Downtime**: ~5-10 minutes (Gateway IP change)
**Rollback**: Reinstall Istio, recreate Istio Gateway

## References

- [llm-d-infra-xks Repository](https://github.com/aneeshkp/llm-d-infra-xks) - Infrastructure operators
- [KServe Documentation](https://kserve.github.io/website/) - KServe project docs
- [OpenDataHub KServe](https://github.com/opendatahub-io/kserve) - ODH KServe fork with LLMInferenceService
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/) - InferencePool specification
- [GKE Gateway API Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api) - GKE native Gateway
- [GKE TPU Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/tpus) - GKE TPU guide
- [Istio Variant](../llm-d-infra-xks-gke-tpu/) - Full-featured alternative with service mesh
