# Istio/KServe Technology Stack

Declarative LLM inference deployment using **KServe** and **Istio service mesh** for production-grade, controller-driven infrastructure.

## Overview

This technology stack uses KServe's `LLMInferenceService` custom resource to declaratively manage vLLM deployments, with Istio providing service mesh capabilities for traffic management, security, and observability.

**Key Principle**: Define the desired state once; let KServe controllers handle the complexity.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Istio Ingress Gateway (External IP)                        │
│  - TLS termination                                          │
│  - Gateway API integration                                  │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  HTTPRoute (Auto-created by KServe)                         │
│  - Routes /v1/* to InferencePool                            │
│  - Created when LLMInferenceService is deployed             │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  InferencePool (Auto-created by KServe)                     │
│  - EPP (Efficient Parameter Partitioning) scheduler         │
│  - Load balancing across replicas                           │
│  - Health checking and failover                             │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  vLLM Pod (Managed by KServe)                               │
│  - RHAIIS vllm-tpu-rhel9:3.2.5 or vllm-cuda-rhel9:3.0.0     │
│  - NetworkPolicy isolation (default-deny + allow-gateway)   │
│  - Istio sidecar injection                                  │
│  - Prometheus metrics (/metrics)                            │
└─────────────────────────────────────────────────────────────┘
```

## Components

### KServe v0.15
- **LLMInferenceService CRD**: Declarative vLLM deployment specification
- **Controller**: Automates HTTPRoute, InferencePool, and Deployment creation
- **Integration**: Works with Istio for traffic management

### Red Hat OpenShift Service Mesh (OSSM 3.1.x)
- **Deployment**: Via sail-operator
- **Capabilities**: mTLS, traffic shaping, observability, security policies
- **Gateway**: Istio Ingress Gateway for external access

### Gateway API
- **HTTPRoute**: Routes HTTP traffic from gateway to InferencePool
- **InferencePool**: Intelligent load balancing with EPP scheduler
- **Auto-Creation**: KServe controller creates these resources automatically

### NetworkPolicy Security
- **default-deny.yaml**: Blocks all ingress/egress by default
- **allow-gateway.yaml**: Permits traffic from Istio gateway to vLLM
- **allow-vllm-egress.yaml**: Allows vLLM to download models and access DNS

## Available Patterns

### Pattern 1: Baseline Single Replica
**Directory**: `pattern1-baseline/`

Single replica deployment for testing and cost-effective inference.

**Key Files**:
- [manifests/llmisvc-tpu.yaml](./pattern1-baseline/manifests/llmisvc-tpu.yaml) - KServe LLMInferenceService definition
- [manifests/networkpolicies/](./pattern1-baseline/manifests/networkpolicies/) - Security hardening
- [scripts/test-cluster.sh](./pattern1-baseline/scripts/test-cluster.sh) - Cluster validation
- [scripts/benchmark-cluster.sh](./pattern1-baseline/scripts/benchmark-cluster.sh) - Performance testing

**Documentation**:
- [Architecture Guide](./pattern1-baseline/docs/istio-kserve-architecture.md) - Complete integration details
- [Cluster Deployment Guide](./pattern1-baseline/docs/cluster-deployment-guide.md) - Step-by-step setup
- [Security Model](./pattern1-baseline/docs/security-model.md) - NetworkPolicy design
- [Cluster Architecture](./pattern1-baseline/docs/cluster-architecture.md) - Network topology

📖 **[Full Pattern 1 Documentation](./pattern1-baseline/README.md)**

## Deployment Workflow

### 1. Prerequisites
```bash
# Install operators on GKE cluster
kubectl apply -f https://github.com/openshift-service-mesh/sail-operator/releases/latest/download/sail-operator.yaml
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.15.0/kserve.yaml

# Apply pull secret for RHAIIS images
kubectl apply -f /path/to/11009103-jhull-svc-pull-secret.yaml
```

### 2. Deploy LLMInferenceService
```bash
cd deployments/istio-kserve/pattern1-baseline

# Deploy the declarative spec
kubectl apply -f manifests/llmisvc-tpu.yaml

# KServe controller automatically creates:
# - Deployment (vLLM pod)
# - Service
# - HTTPRoute (gateway routing)
# - InferencePool (load balancing)
```

### 3. Apply Security Hardening
```bash
# Apply NetworkPolicies for zero-trust security
kubectl apply -f manifests/networkpolicies/
```

### 4. Validate Deployment
```bash
# Run automated tests
./scripts/test-cluster.sh

# Check KServe resources
kubectl get llmis
kubectl get httproute
kubectl get inferencepools
kubectl get pods
```

### 5. Benchmark Performance
```bash
# Run performance benchmarks
./scripts/benchmark-cluster.sh
```

## Key Advantages

### Declarative Infrastructure
- Define once in `llmisvc-tpu.yaml`
- KServe controller handles complexity
- GitOps-friendly (ArgoCD, Flux compatible)

### Automatic Resource Management
- HTTPRoute auto-created and updated
- InferencePool auto-configured
- No manual manifest coordination required

### Production-Grade Service Mesh
- Istio provides mTLS, observability, resilience
- NetworkPolicy integration for defense-in-depth
- Traffic management capabilities (retries, timeouts, circuit breaking)

### Enterprise Support
- Red Hat OpenShift Service Mesh (OSSM)
- RHAIIS vLLM containers with enterprise support
- Production-ready operator lifecycle management

## Example LLMInferenceService

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: vllm-gemma
  namespace: default
spec:
  image: registry.redhat.io/rhaiis/vllm-tpu-rhel9:3.2.5
  model: google/gemma-2b-it
  replicas: 1
  runtime:
    containerPort: 8000
  resources:
    limits:
      google.com/tpu: 1
  env:
    - name: PJRT_DEVICE
      value: "TPU"
    - name: HF_TOKEN
      valueFrom:
        secretKeyRef:
          name: huggingface-token
          key: token
  args:
    - --dtype=half
    - --max-model-len=2048
```

**What KServe Creates Automatically**:
1. **Deployment**: vLLM pod with above spec
2. **Service**: ClusterIP service on port 8000
3. **HTTPRoute**: Routes `/v1/*` from gateway to InferencePool
4. **InferencePool**: EPP scheduler with health checking

## Configuration

### Hardware Support
- **TPU**: Google Cloud TPU v6e (v2-alpha-tpuv6e image)
- **GPU**: NVIDIA T4 (GKE auto-installs drivers)

### Model Configuration
Specify in LLMInferenceService spec:
```yaml
spec:
  model: google/gemma-2b-it  # HuggingFace model ID
  args:
    - --dtype=half           # FP16 precision
    - --max-model-len=2048   # Context length
```

### Scaling
```yaml
spec:
  replicas: 3  # KServe creates 3 vLLM pods
  # InferencePool automatically load balances
```

### Environment Variables
```yaml
spec:
  env:
    - name: HF_TOKEN
      valueFrom:
        secretKeyRef:
          name: huggingface-token
          key: token
```

## Monitoring and Observability

### Istio Observability
```bash
# Access Kiali dashboard (if installed)
kubectl port-forward -n istio-system svc/kiali 20001:20001

# View Jaeger traces (if installed)
kubectl port-forward -n istio-system svc/jaeger-query 16686:16686
```

### Prometheus Metrics
```bash
# vLLM metrics available at pod /metrics endpoint
kubectl port-forward <vllm-pod> 8000:8000
curl http://localhost:8000/metrics
```

### KServe Status
```bash
# Check LLMInferenceService status
kubectl get llmis -o yaml

# Check controller logs
kubectl logs -n kserve deployment/kserve-controller-manager
```

## Troubleshooting

### Common Issues

**Pod CrashLoopBackOff:**
```bash
# Check pod logs
kubectl logs <pod-name>

# Common causes:
# - Missing HuggingFace token
# - Model access denied (gated models)
# - Insufficient TPU/GPU resources
# - Image pull errors (check pull secret)
```

**HTTPRoute Not Created:**
```bash
# Check KServe controller logs
kubectl logs -n kserve deployment/kserve-controller-manager

# Verify LLMInferenceService status
kubectl describe llmis <name>
```

**Gateway 404 Errors:**
```bash
# Verify HTTPRoute exists
kubectl get httproute

# Check InferencePool backend health
kubectl describe inferencepools

# Verify pod is ready
kubectl get pods
```

**NetworkPolicy Blocking Traffic:**
```bash
# Temporarily remove NetworkPolicies for debugging
kubectl delete networkpolicy --all

# Check connectivity
kubectl exec -it <test-pod> -- curl http://<vllm-service>:8000/health

# Reapply NetworkPolicies after debugging
kubectl apply -f manifests/networkpolicies/
```

### Debug Commands

```bash
# Full cluster state
kubectl get llmis,httproute,inferencepools,deployments,pods,svc

# Check Istio injection
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].name}'
# Should show: vllm, istio-proxy

# Test internal connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://<vllm-service>:8000/v1/models

# Check NetworkPolicy status
kubectl describe networkpolicy
```

## Migration to Gateway API/llm-d

To switch from Istio/KServe to Gateway API/llm-d:

```bash
# 1. Delete LLMInferenceService (auto-deletes HTTPRoute, InferencePool)
kubectl delete llmis <name>

# 2. Deploy via Helm
cd /home/jhull/devel/llm-d
helmfile -f helmfile.yaml.gotmpl apply

# 3. Manually create HTTPRoute
kubectl apply -f /home/jhull/devel/llmd-gke/deployments/gateway-api/pattern1-baseline/manifests/httproute.yaml
```

See [Gateway API/llm-d documentation](../gateway-api/pattern1-baseline/README.md) for details.

## References

### KServe Documentation
- [KServe LLMInferenceService Guide](https://kserve.github.io/website/latest/modelserving/llm/)
- [KServe v0.15 Release Notes](https://github.com/kserve/kserve/releases/tag/v0.15.0)

### Istio Documentation
- [Istio Gateway API Integration](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/)
- [Red Hat OpenShift Service Mesh](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/service_mesh/index)

### Gateway API Documentation
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/)
- [InferencePool Specification](https://gateway-api-inference-extension.sigs.k8s.io/api-types/inferencepools/)

### Pattern-Specific Documentation
- [Istio/KServe Architecture](./pattern1-baseline/docs/istio-kserve-architecture.md)
- [Cluster Deployment Guide](./pattern1-baseline/docs/cluster-deployment-guide.md)
- [Security Model](./pattern1-baseline/docs/security-model.md)
- [Troubleshooting Issues](./pattern1-baseline/docs/issues-istio.md)
- [Kustomize Fix Notes](./pattern1-baseline/docs/kustomize-fix.md)
