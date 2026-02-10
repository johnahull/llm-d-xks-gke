# Gateway API/llm-d Technology Stack

Helm-based LLM inference deployment using **llm-d framework** and **Gateway API** for flexible, explicit configuration and multi-pattern support.

## Overview

This technology stack uses llm-d's Helm charts with helmfile for deployment orchestration, providing direct control over vLLM configuration and explicit HTTPRoute/InferencePool creation. Supports four deployment patterns from baseline to advanced architectures.

**Key Principle**: Explicit configuration over automation; flexibility over convention.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  GKE Gateway (External IP)                                  │
│  - Cloud Load Balancer integration                          │
│  - Gateway API native (no Istio)                            │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  HTTPRoute (Manual creation)                                │
│  - Routes /v1/* to InferencePool                            │
│  - Explicitly defined in manifests/httproute.yaml           │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  InferencePool (Manual creation)                            │
│  - EPP (Efficient Parameter Partitioning) scheduler         │
│  - Load balancing across replicas                           │
│  - Explicitly defined in Helm values or manifests           │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│  vLLM Pods (Deployed via Helm)                              │
│  - RHAIIS vllm-tpu-rhel9:3.2.5 or vllm-cuda-rhel9:3.0.0     │
│  - Direct Helm chart deployment (llm-d modelservice)        │
│  - No sidecar injection (lightweight)                       │
│  - Prometheus metrics (/metrics)                            │
└─────────────────────────────────────────────────────────────┘
```

## Components

### llm-d Framework
- **Helm Charts**: Declarative vLLM deployment via Helm
- **helmfile**: Multi-environment orchestration and templating
- **InferencePool Integration**: Intelligent routing with EPP scheduler
- **Multi-Pattern Support**: Baseline, multi-model, caching, MoE architectures

### GKE Gateway API
- **Native Integration**: GKE-managed Gateway resource
- **HTTPRoute**: Traffic routing from gateway to InferencePool
- **No Service Mesh**: Lightweight infrastructure without Istio overhead
- **Cloud Load Balancer**: Automatic provisioning and health checks

### Helm Deployment
- **helmfile.yaml.gotmpl**: Template-driven configuration
- **Pattern Overrides**: Pattern-specific values files
- **Explicit Configuration**: All settings visible in Helm values
- **Version Control**: GitOps-friendly with clear change tracking

## Available Patterns

### Pattern 1: Baseline Single Replica
**Directory**: `pattern1-baseline/`

Single replica deployment for testing and cost-effective inference.

**Key Files**:
- [llm-d-pattern1-values.yaml](./pattern1-baseline/llm-d-pattern1-values.yaml) - Helm values for modelservice
- [manifests/httproute.yaml](./pattern1-baseline/manifests/httproute.yaml) - Manual HTTPRoute definition
- [docs/llm-d-tpu-setup.md](./pattern1-baseline/docs/llm-d-tpu-setup.md) - TPU deployment guide
- [docs/llm-d-gpu-setup.md](./pattern1-baseline/docs/llm-d-gpu-setup.md) - GPU deployment guide

📖 **[Full Pattern 1 Documentation](./pattern1-baseline/README.md)**

### Pattern 2: Multi-Model Serving
**Directory**: `pattern2-multimodel/`

Concurrent serving of multiple models with intelligent routing based on model selection.

**Key Features**:
- Deploy multiple vLLM instances (different models)
- HTTPRoute with path-based or header-based routing
- InferencePool per model with EPP scheduling
- Backend-based routing (BBR) for model selection

**Key Files**:
- [manifests/routing/httproutes-bbr.yaml](./pattern2-multimodel/manifests/routing/httproutes-bbr.yaml) - Multi-model routing
- [manifests/routing/inferencepools-bbr.yaml](./pattern2-multimodel/manifests/routing/inferencepools-bbr.yaml) - Per-model pools
- [docs/bbr-helm-deployment.md](./pattern2-multimodel/docs/bbr-helm-deployment.md) - Backend-based routing guide

📖 **[Full Pattern 2 Documentation](./pattern2-multimodel/README.md)**

### Pattern 3: N/S-Caching Scale-Out
**Directory**: `pattern3-caching/`

Three-replica deployment with prefix caching for improved throughput and cost efficiency.

**Key Features**:
- 3 replica deployment (scale-out architecture)
- Prefix caching enabled (shared KV cache)
- EPP scheduler with cache-aware routing
- Improved throughput for repeated prompts

**Key Files**:
- [manifests/httproute.yaml](./pattern3-caching/manifests/httproute.yaml) - Routing to 3-replica pool
- [docs/quickstart.md](./pattern3-caching/docs/quickstart.md) - Fast deployment guide

📖 **[Full Pattern 3 Documentation](./pattern3-caching/README.md)**

### Pattern 4: Mixture of Experts (MoE)
**Directory**: `pattern4-moe/`

Multi-node deployment for large MoE models requiring distributed inference.

**Key Features**:
- Multi-node tensor parallelism
- LeaderWorkerSet for coordinated deployment
- Support for large MoE models (Mixtral, Qwen-MoE)
- Inter-node communication with NCCL/GLOO

**Key Files**:
- [manifests/pattern4-poc-lws.yaml](./pattern4-moe/manifests/pattern4-poc-lws.yaml) - LeaderWorkerSet deployment
- [docs/analysis.md](./pattern4-moe/docs/analysis.md) - Architecture analysis
- [docs/comparison.md](./pattern4-moe/docs/comparison.md) - MoE vs dense model comparison

📖 **[Full Pattern 4 Documentation](./pattern4-moe/README.md)**

## Deployment Workflow

### 1. Prerequisites

**Clone Required Repositories**:
```bash
cd /home/jhull/devel

# Clone llm-d framework
git clone https://github.com/llm-d/llm-d.git

# Clone llm-d infrastructure
git clone https://github.com/llm-d-incubation/llm-d-infra.git llm-d-infra-xks
```

**Apply Secrets**:
```bash
# Pull secret for RHAIIS images
kubectl apply -f /path/to/11009103-jhull-svc-pull-secret.yaml

# HuggingFace token for model access
kubectl apply -f /path/to/huggingface-token-secret.yaml
```

**Install Gateway API CRDs** (if not already installed):
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
```

### 2. Configure Helm Values

**Pattern-Specific Values**:
```bash
cd /home/jhull/devel/llmd-gke

# Edit pattern-specific values
vim deployments/gateway-api/pattern1-baseline/llm-d-pattern1-values.yaml

# Key configurations:
# - model: HuggingFace model ID
# - replicas: Number of vLLM pods
# - resources: TPU/GPU requirements
# - args: vLLM runtime arguments
```

**Link Values to Helm Configs**:
```bash
# Copy or symlink pattern values to helm-configs
cp deployments/gateway-api/pattern1-baseline/llm-d-pattern1-values.yaml \
   helm-configs/pattern-overrides/
```

### 3. Deploy via Helmfile

```bash
cd /home/jhull/devel/llm-d

# Deploy using helmfile
helmfile -f helmfile.yaml.gotmpl apply

# Watch deployment progress
kubectl get pods -w
```

**What Helm Creates**:
1. **Deployment**: vLLM pods with specified configuration
2. **Service**: ClusterIP service on port 8000
3. **ServiceAccount**: For pod identity
4. **ConfigMap**: (if using custom configurations)

**What Helm Does NOT Create** (manual steps required):
- HTTPRoute (must apply manually)
- InferencePool (must apply manually or via Helm values)
- Gateway resource (GKE auto-creates)

### 4. Create HTTPRoute and InferencePool

**Manual HTTPRoute**:
```bash
cd /home/jhull/devel/llmd-gke/deployments/gateway-api/pattern1-baseline

# Apply HTTPRoute manifest
kubectl apply -f manifests/httproute.yaml

# Verify creation
kubectl get httproute
```

**InferencePool** (if not created by Helm):
```yaml
apiVersion: inference.gateway.llm-d.ai/v1alpha2
kind: InferencePool
metadata:
  name: vllm-gemma-pool
spec:
  selector:
    matchLabels:
      app: vllm-gemma
  targetPort: 8000
  scheduler:
    type: EPP  # Efficient Parameter Partitioning
```

### 5. Validate Deployment

```bash
# Check all resources
kubectl get deployments,pods,svc,httproute,inferencepools

# Get gateway external IP
kubectl get gateway -n gateway-system

# Test health endpoint
curl http://<GATEWAY_IP>/health

# Test inference
curl -X POST http://<GATEWAY_IP>/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemma-2b-it",
    "prompt": "Hello, how are you?",
    "max_tokens": 50
  }'
```

## Key Advantages

### Explicit Configuration
- All settings visible in Helm values files
- No hidden controller automation
- Clear understanding of what gets deployed
- Version-controlled configuration

### Multi-Pattern Support
- Pattern 1: Single replica baseline
- Pattern 2: Multi-model serving
- Pattern 3: N/S-caching scale-out
- Pattern 4: MoE multi-node
- Easy to switch and experiment

### Lightweight Infrastructure
- No service mesh required (no Istio overhead)
- Fewer components to manage and debug
- Direct pod-to-gateway routing
- Lower resource consumption

### Flexible Experimentation
- Rapid iteration on configurations
- Easy to modify Helm values and redeploy
- Pattern-specific overrides
- helmfile templating for complex scenarios

### GitOps-Friendly
- Declarative Helm values in git
- Clear change tracking
- Easy rollback with `helmfile destroy`
- Compatible with ArgoCD, Flux

## Example Helm Values

### Pattern 1: Baseline
```yaml
# llm-d-pattern1-values.yaml
modelservice:
  name: vllm-gemma
  image:
    repository: registry.redhat.io/rhaiis/vllm-tpu-rhel9
    tag: "3.2.5"

  model: google/gemma-2b-it
  replicas: 1

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
    - --port=8000
```

### Pattern 3: Caching (3 Replicas)
```yaml
# Additional configuration for Pattern 3
modelservice:
  replicas: 3  # Scale to 3 replicas

  args:
    - --dtype=half
    - --max-model-len=2048
    - --enable-prefix-caching  # Enable caching
    - --port=8000
```

## Configuration

### Hardware Support

**TPU Deployment**:
```yaml
modelservice:
  image:
    repository: registry.redhat.io/rhaiis/vllm-tpu-rhel9
    tag: "3.2.5"

  resources:
    limits:
      google.com/tpu: 1

  env:
    - name: PJRT_DEVICE
      value: "TPU"
```

**GPU Deployment**:
```yaml
modelservice:
  image:
    repository: registry.redhat.io/rhaiis/vllm-cuda-rhel9
    tag: "3.0.0"

  resources:
    limits:
      nvidia.com/gpu: 1

  env:
    - name: CUDA_VISIBLE_DEVICES
      value: "0"
```

### Model Configuration

**Specify Model**:
```yaml
modelservice:
  model: google/gemma-2b-it  # HuggingFace model ID
```

**vLLM Arguments**:
```yaml
modelservice:
  args:
    - --dtype=half              # FP16 precision
    - --max-model-len=2048      # Context length
    - --enable-prefix-caching   # Enable caching (Pattern 3)
    - --tensor-parallel-size=2  # Multi-GPU (Pattern 4)
    - --port=8000
```

### Scaling

**Horizontal Scaling**:
```yaml
modelservice:
  replicas: 3  # Deploy 3 vLLM pods
  # InferencePool automatically load balances
```

**Vertical Scaling**:
```yaml
modelservice:
  resources:
    limits:
      google.com/tpu: 2  # Use 2 TPU chips
    requests:
      memory: 32Gi       # Increase memory
```

### Environment Variables

```yaml
modelservice:
  env:
    - name: HF_TOKEN
      valueFrom:
        secretKeyRef:
          name: huggingface-token
          key: token

    - name: VLLM_LOGGING_LEVEL
      value: "INFO"

    - name: VLLM_ATTENTION_BACKEND
      value: "FLASHINFER"  # Override attention backend
```

## Monitoring and Observability

### Prometheus Metrics

**vLLM Metrics**:
```bash
# Port-forward to vLLM pod
kubectl port-forward <vllm-pod> 8000:8000

# Scrape metrics
curl http://localhost:8000/metrics

# Key metrics:
# - vllm_request_success_total
# - vllm_request_duration_seconds
# - vllm_num_requests_running
# - vllm_gpu_cache_usage_perc (GPU)
# - vllm_tpu_cache_usage_perc (TPU)
```

### Helm Release Status

```bash
# List Helm releases
helm list -A

# Get release status
helm status <release-name> -n <namespace>

# View release history
helm history <release-name> -n <namespace>
```

### Gateway API Status

```bash
# Check Gateway status
kubectl get gateway -n gateway-system -o yaml

# Check HTTPRoute status
kubectl get httproute -o yaml

# Check InferencePool backend health
kubectl describe inferencepools
```

### Logging

```bash
# vLLM pod logs
kubectl logs <vllm-pod> -f

# helmfile deployment logs
helmfile -f helmfile.yaml.gotmpl apply --debug

# Filter for errors
kubectl logs <vllm-pod> | grep -i error
```

## Troubleshooting

### Common Issues

#### Helm Deployment Fails

**Symptom**: `helmfile apply` returns errors

**Diagnosis**:
```bash
# Check helmfile with dry-run
helmfile -f helmfile.yaml.gotmpl apply --debug --dry-run

# Verify values file syntax
helm template <chart> -f <values.yaml>
```

**Common Causes**:
- Invalid YAML syntax in values file
- Missing required Helm chart dependencies
- Incorrect image pull secret reference
- Invalid resource requests (TPU/GPU)

**Solution**:
```bash
# Validate values file
yamllint llm-d-pattern1-values.yaml

# Re-apply with verbose output
helmfile -f helmfile.yaml.gotmpl apply --debug
```

#### HTTPRoute Not Routing Traffic

**Symptom**: Gateway returns 404 or 503 errors

**Diagnosis**:
```bash
# Check HTTPRoute status
kubectl get httproute -o yaml | grep -A 10 status

# Verify InferencePool backends
kubectl describe inferencepools

# Check pod readiness
kubectl get pods -o wide
```

**Common Causes**:
- InferencePool selector doesn't match pod labels
- vLLM pods not ready (health checks failing)
- HTTPRoute parentRefs incorrect (wrong gateway)
- Service port mismatch (HTTPRoute → Service → Pod)

**Solution**:
```bash
# Verify label matching
kubectl get pods --show-labels
kubectl get inferencepools -o yaml | grep -A 5 selector

# Fix HTTPRoute parentRefs
kubectl edit httproute <name>

# Manually test service connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://<service-name>:8000/health
```

#### InferencePool No Healthy Backends

**Symptom**: InferencePool shows 0 ready backends

**Diagnosis**:
```bash
# Check InferencePool status
kubectl describe inferencepools

# Check pod health
kubectl get pods
kubectl describe pod <vllm-pod>

# Test health endpoint directly
kubectl port-forward <vllm-pod> 8000:8000
curl http://localhost:8000/health
```

**Common Causes**:
- vLLM container crash (check logs)
- Model download failure (HuggingFace token issue)
- Insufficient memory/TPU resources
- Health check endpoint not responding

**Solution**:
```bash
# Check pod logs for errors
kubectl logs <vllm-pod>

# Verify HuggingFace token
kubectl get secret huggingface-token -o yaml

# Increase resource limits
# Edit Helm values and redeploy
vim llm-d-pattern1-values.yaml
helmfile apply
```

#### Model Download Fails

**Symptom**: Pod logs show "Access denied" or "401 Unauthorized"

**Diagnosis**:
```bash
# Check pod logs
kubectl logs <vllm-pod> | grep -i "download\|huggingface\|403\|401"

# Verify secret exists
kubectl get secret huggingface-token
```

**Common Causes**:
- Missing or incorrect HuggingFace token
- Token doesn't have access to gated models
- Network egress blocked (firewall)

**Solution**:
```bash
# Recreate secret with valid token
kubectl delete secret huggingface-token
kubectl create secret generic huggingface-token \
  --from-literal=token='hf_...'

# Restart deployment
kubectl rollout restart deployment <vllm-deployment>

# For gated models, accept license on HuggingFace website
# then wait for token permissions to propagate
```

#### Helm Release in Failed State

**Symptom**: `helm list` shows release as "failed"

**Diagnosis**:
```bash
# Get release history
helm history <release-name> -n <namespace>

# Get failure details
helm status <release-name> -n <namespace>
```

**Solution**:
```bash
# Rollback to previous version
helm rollback <release-name> -n <namespace>

# Or uninstall and redeploy
helmfile -f helmfile.yaml.gotmpl destroy
helmfile -f helmfile.yaml.gotmpl apply
```

### Debug Commands

```bash
# Full cluster state for Gateway API/llm-d
kubectl get deployments,pods,svc,httproute,inferencepools,gateway

# Check Helm releases
helm list -A

# Verify all llm-d components
kubectl get all -l app.kubernetes.io/part-of=llm-d

# Test internal service connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://<vllm-service>:8000/v1/models

# Check Gateway API resources
kubectl get gateway,httproute,inferencepools -A

# Trace request path
# Gateway → HTTPRoute → InferencePool → Service → Pod
kubectl get gateway -o yaml | grep -A 5 listeners
kubectl get httproute -o yaml | grep -A 10 parentRefs
kubectl describe inferencepools
kubectl get endpoints <service-name>
```

## Migration to Istio/KServe

To switch from Gateway API/llm-d to Istio/KServe:

```bash
# 1. Delete Helm deployment
cd /home/jhull/devel/llm-d
helmfile -f helmfile.yaml.gotmpl destroy

# 2. Delete manual HTTPRoute
kubectl delete httproute <name>

# 3. Delete InferencePool (if manually created)
kubectl delete inferencepools <name>

# 4. Install Istio and KServe operators (if not installed)
kubectl apply -f https://github.com/openshift-service-mesh/sail-operator/releases/latest/download/sail-operator.yaml
kubectl apply -f https://github.com/kserve/kserve/releases/download/v0.15.0/kserve.yaml

# 5. Deploy KServe LLMInferenceService
kubectl apply -f /home/jhull/devel/llmd-gke/deployments/istio-kserve/pattern1-baseline/manifests/llmisvc-tpu.yaml

# 6. KServe controller automatically creates HTTPRoute and InferencePool
```

See [Istio/KServe documentation](../istio-kserve/pattern1-baseline/README.md) for details.

## Pattern Selection Guide

### When to Use Each Pattern

**Pattern 1: Baseline**
- ✅ Testing and development
- ✅ Low-traffic applications
- ✅ Cost-sensitive deployments
- ✅ Single model serving
- ❌ High throughput requirements
- ❌ Multiple models needed

**Pattern 2: Multi-Model**
- ✅ Serving multiple models concurrently
- ✅ Model selection based on use case
- ✅ Different models for different users/tenants
- ✅ A/B testing different models
- ❌ Single model is sufficient
- ❌ Limited GPU/TPU quota

**Pattern 3: N/S-Caching**
- ✅ High throughput requirements
- ✅ Repeated prompts with common prefixes
- ✅ Cost optimization through caching
- ✅ Scale-out architecture
- ❌ Highly variable prompts
- ❌ Single replica is sufficient

**Pattern 4: MoE**
- ✅ Large MoE models (Mixtral, Qwen-MoE)
- ✅ Multi-node inference required
- ✅ Maximum model capacity
- ✅ Research and experimentation
- ❌ Standard dense models
- ❌ Limited GPU/TPU resources

## References

### llm-d Documentation
- [llm-d Website](https://llm-d.ai/)
- [llm-d GKE Infrastructure Guide](https://llm-d.ai/docs/guide/InfraProviders/gke)
- [llm-d Architecture](https://llm-d.ai/docs/architecture/Components/modelservice)
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/)

### Helm and Helmfile
- [Helm Documentation](https://helm.sh/docs/)
- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [llm-d modelservice Chart](https://github.com/llm-d-incubation/llm-d-modelservice)

### Gateway API
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [GKE Gateway Controller](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api)
- [InferencePool Specification](https://gateway-api-inference-extension.sigs.k8s.io/api-types/inferencepools/)

### Pattern-Specific Documentation

**Pattern 1: Baseline**
- [TPU Setup Guide](./pattern1-baseline/docs/llm-d-tpu-setup.md)
- [GPU Setup Guide](./pattern1-baseline/docs/llm-d-gpu-setup.md)

**Pattern 2: Multi-Model**
- [Backend-Based Routing](./pattern2-multimodel/docs/bbr-helm-deployment.md)
- [Benchmark Results](./pattern2-multimodel/docs/benchmark-results.md)
- [Investigation Summary](./pattern2-multimodel/docs/investigation-summary.md)

**Pattern 3: N/S-Caching**
- [Quickstart Guide](./pattern3-caching/docs/quickstart.md)
- [TPU Setup](./pattern3-caching/docs/llm-d-tpu-setup.md)
- [GPU Setup](./pattern3-caching/docs/llm-d-gpu-setup.md)

**Pattern 4: MoE**
- [MoE Analysis](./pattern4-moe/docs/analysis.md)
- [Model Comparison](./pattern4-moe/docs/comparison.md)

### External Resources
- [vLLM Documentation](https://docs.vllm.ai/)
- [RHAIIS Documentation](https://docs.redhat.com/en/documentation/red_hat_ai_inference_services/)
- [Google Cloud TPU Documentation](https://cloud.google.com/tpu/docs)
- [GKE GPU Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/gpus)
