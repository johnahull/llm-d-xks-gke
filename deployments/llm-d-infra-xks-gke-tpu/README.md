# llm-d-infra-xks-gke-tpu

Infrastructure deployment for KServe LLMInferenceService on GKE with TPU v6e acceleration.

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [llm-d-infra-xks](https://github.com/aneeshkp/llm-d-infra-xks) | Infrastructure Helm charts (cert-manager + Istio + LWS operators) |
| [opendatahub-io/kserve](https://github.com/opendatahub-io/kserve) | KServe controller with LLMInferenceService CRD |

## Overview

| Component | App Version | Description |
|-----------|-------------|-------------|
| cert-manager-operator | 1.15.2 | TLS certificate management |
| sail-operator (Istio) | 3.2.x | Service mesh and Gateway API for inference routing |
| lws-operator | 1.0 | LeaderWorkerSet controller for multi-node workloads |
| KServe | v0.15 | LLMInferenceService controller with automatic resource management |

### Version Compatibility

| Component | Version | Notes |
|-----------|---------|-------|
| GKE | 1.34+ | Kubernetes cluster with TPU support |
| OSSM (Sail Operator) | 3.2.x | Gateway API for inference routing |
| Istio | v1.27.x | Service mesh |
| InferencePool API | v1 | `inference.networking.k8s.io/v1` |
| KServe | release-v0.15 | LLMInferenceService controller with automatic HTTPRoute/InferencePool creation |
| TPU | v6e | 4-chip configuration (2×2 topology) |

## Prerequisites

- GKE cluster with TPU v6e support (see [GKE Cluster Creation](#step-1-create-gke-cluster-15-20-min) below)
- `kubectl` (1.28+), `helm` (v3.17+), `helmfile`, `kustomize` (v5.7+)
- `gcloud` CLI installed and configured
- Red Hat account (for Sail Operator and vLLM images from `registry.redhat.io`)
- HuggingFace token for model access
- Google Cloud project with TPU quota (minimum 4 chips)

### Red Hat Pull Secret Setup

The Sail Operator and RHAIIS vLLM images are hosted on `registry.redhat.io` which requires authentication.
Choose **one** of the following methods:

#### Method 1: Registry Service Account (Recommended)

Create a Registry Service Account (works for both Sail Operator and vLLM images):

1. Go to: https://access.redhat.com/terms-based-registry/
2. Click "New Service Account"
3. Create account and note the username (e.g., `12345678|myserviceaccount`)
4. Login with the service account credentials:

```bash
$ podman login registry.redhat.io
Username: {REGISTRY-SERVICE-ACCOUNT-USERNAME}
Password: {REGISTRY-SERVICE-ACCOUNT-PASSWORD}
Login Succeeded!

# Verify it works
$ podman pull registry.redhat.io/openshift-service-mesh/istio-sail-operator-bundle:3.2
```

Then configure `values.yaml` in llm-d-infra-xks:
```yaml
useSystemPodmanAuth: true
```

**Alternative:** Download the pull secret file (OpenShift secret tab) and copy to persistent location:
```bash
mkdir -p ~/.config/containers
cp ~/pull-secret.txt ~/.config/containers/auth.json
```

> **Note:** Registry Service Accounts are recommended as they don't expire like personal credentials.

#### Method 2: Podman Login with Red Hat Account (For Developers)

If you have direct Red Hat account access (e.g., internal developers):

```bash
$ podman login registry.redhat.io
Username: {YOUR-REDHAT-USERNAME}
Password: {YOUR-REDHAT-PASSWORD}
Login Succeeded!
```

This stores credentials in `${XDG_RUNTIME_DIR}/containers/auth.json` or `~/.config/containers/auth.json`.

Then configure `values.yaml`:
```yaml
useSystemPodmanAuth: true
```

### GKE-Specific Prerequisites

#### Google Cloud Project Setup

```bash
# Authenticate with Google Cloud
gcloud auth login

# Set project
export PROJECT=ecoeng-llmd
gcloud config set project $PROJECT

# Verify access
gcloud projects describe $PROJECT
```

#### TPU Quota Requirements

**Minimum Quota Needed:**
- **TPU v6e chips**: 4 chips (for single ct6e-standard-4t node)

**Check Current Quota:**
```bash
gcloud compute project-info describe --project=$PROJECT | grep -i tpu
```

**Request Quota Increase** (if needed):
1. Go to: https://console.cloud.google.com/iam-admin/quotas?project=$PROJECT
2. Search for "TPU v6e"
3. Request quota for desired region

#### Zone Availability

TPU v6e is available in the following zones:

| Zone | Region | Notes |
|------|--------|-------|
| `europe-west4-a` | europe-west4 (Netherlands) | Recommended for EU |
| `us-central1-a` | us-central1 (Iowa) | Recommended for US Central |
| `us-east5-a` | us-east5 (Columbus) | Alternative US zone |

**Verify TPU availability** in your zone:
```bash
gcloud compute tpus accelerator-types list --zone=europe-west4-a
```

---

## Quick Start

### Step 1: Create GKE Cluster (15-20 min)

```bash
cd cluster-config
./create-cluster.sh
```

This script creates:
- Base GKE cluster (2 × n1-standard-4 CPU nodes)
- TPU v6e node pool (1 × ct6e-standard-4t with autoscaling 0-3)
- NetworkPolicy enabled
- Workload Identity enabled

**Verify:**
```bash
kubectl get nodes
# Expected: 2 CPU nodes + 1 TPU node

kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice
# Expected: 1 TPU node with 2x2 topology
```

<details>
<summary>Manual cluster creation commands (click to expand)</summary>

```bash
# Set configuration
export CLUSTER_NAME=llmd-istio-tpu-pattern1
export ZONE=europe-west4-a
export PROJECT=ecoeng-llmd

# Create base cluster
gcloud container clusters create $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT \
  --cluster-version=1.34 \
  --machine-type=n1-standard-4 \
  --num-nodes=2 \
  --enable-ip-alias \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=4 \
  --addons=GcePersistentDiskCsiDriver,NetworkPolicy \
  --enable-network-policy \
  --workload-pool=$PROJECT.svc.id.goog \
  --enable-shielded-nodes \
  --shielded-secure-boot \
  --shielded-integrity-monitoring \
  --release-channel=regular

# Get credentials
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT

# Create TPU node pool
gcloud container node-pools create tpu-v6e-pool \
  --cluster=$CLUSTER_NAME \
  --zone=$ZONE \
  --project=$PROJECT \
  --machine-type=ct6e-standard-4t \
  --num-nodes=1 \
  --enable-autoscaling \
  --min-nodes=0 \
  --max-nodes=3 \
  --node-locations=$ZONE \
  --node-taints=google.com/tpu=present:NoSchedule \
  --node-labels=cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice,cloud.google.com/gke-tpu-topology=2x2
```

</details>

### Step 2: Deploy Infrastructure (5-10 min)

```bash
# Clone llm-d-infra-xks repository (if not already cloned)
cd /home/jhull/devel
git clone https://github.com/aneeshkp/llm-d-infra-xks.git
cd llm-d-infra-xks

# Deploy cert-manager + istio + lws
make deploy-all

# Check status
make status
```

**Verify:**
```bash
kubectl get pods -n cert-manager       # 3 pods Running
kubectl get pods -n istio-system       # 1 pod Running (istiod)
kubectl get pods -n lws-system         # 1 pod Running
```

### Step 3: Deploy KServe (3-5 min)

```bash
cd /home/jhull/devel/llm-d-infra-xks

make deploy-kserve

# Verify
kubectl get pods -n opendatahub
kubectl get llminferenceserviceconfig -n opendatahub
```

<details>
<summary>Manual steps (click to expand)</summary>

```bash
# Create opendatahub namespace
kubectl create namespace opendatahub --dry-run=client -o yaml | kubectl apply -f -

# Copy pull secret from istio-system (created by infrastructure deployment)
kubectl get secret redhat-pull-secret -n istio-system -o yaml | \
  sed 's/namespace: istio-system/namespace: opendatahub/' | \
  kubectl apply -f -

# Apply cert-manager PKI resources first (required for webhook certificates)
kubectl apply -k "https://github.com/opendatahub-io/kserve/config/overlays/odh-test/cert-manager?ref=release-v0.15"
kubectl wait --for=condition=Ready clusterissuer/opendatahub-ca-issuer --timeout=120s

# First apply - creates CRDs and deployment (CR errors expected due to webhook)
kustomize build "https://github.com/opendatahub-io/kserve/config/overlays/odh-xks?ref=release-v0.15" | kubectl apply --server-side --force-conflicts -f - || true

# Delete webhooks to allow controller startup
kubectl delete validatingwebhookconfiguration llminferenceservice.serving.kserve.io llminferenceserviceconfig.serving.kserve.io --ignore-not-found

# Wait for controller to be ready
kubectl wait --for=condition=Available deployment/kserve-controller-manager -n opendatahub --timeout=300s

# Second apply - now webhooks work, applies CRs
kustomize build "https://github.com/opendatahub-io/kserve/config/overlays/odh-xks?ref=release-v0.15" | kubectl apply --server-side --force-conflicts -f -

# Verify LLMInferenceServiceConfig templates exist
kubectl get llminferenceserviceconfig -n opendatahub
```

</details>

### Step 4: Set up Gateway (2-3 min)

```bash
cd /home/jhull/devel/llm-d-infra-xks

./scripts/setup-gateway.sh

# Verify
kubectl get gateway -n opendatahub
```

**Wait for External IP** (takes ~2 minutes):
```bash
kubectl get gateway inference-gateway -n opendatahub -w
# Wait for PROGRAMMED status and ADDRESS populated
```

<details>
<summary>What the script does (click to expand)</summary>

The script:
1. Copies the CA bundle from cert-manager to opendatahub namespace
2. Creates a Gateway with the CA bundle mounted for mTLS to backend services
3. Patches the Gateway pod to use the pull secret

</details>

### Step 5: Deploy LLMInferenceService (2-5 min)

#### Create Namespace and Secrets

```bash
# Create namespace
export NAMESPACE=llm-d-inference-scheduling
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Copy Red Hat pull secret from istio-system
kubectl get secret redhat-pull-secret -n istio-system -o yaml | \
  sed "s/namespace: istio-system/namespace: $NAMESPACE/" | \
  kubectl apply -f -

# Create HuggingFace token secret
kubectl create secret generic hf-token \
  -n $NAMESPACE \
  --from-literal=HF_TOKEN=YOUR_HUGGINGFACE_TOKEN \
  --dry-run=client -o yaml | kubectl apply -f -
# Replace YOUR_HUGGINGFACE_TOKEN with your actual token
```

#### Deploy LLMInferenceService

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu

# Apply the LLMInferenceService manifest
kubectl apply -f manifests/llmisvc-tpu.yaml
```

This manifest defines:
- **Model**: Qwen/Qwen2.5-3B-Instruct
- **TPU Configuration**: 4 chips (2×2 topology), tensor parallelism
- **Routing**: Automatic HTTPRoute and InferencePool creation with EPP scheduler
- **Health Probes**: Extended delays (240s) for TPU initialization

**Watch deployment progress** (~12-15 min for model download + TPU compilation):
```bash
kubectl get llmisvc -n $NAMESPACE -w
# Wait for READY = True
```

**Verify auto-created resources:**
```bash
# Check HTTPRoute (auto-created by KServe)
kubectl get httproute -n $NAMESPACE

# Check InferencePool (auto-created by KServe)
kubectl get inferencepool -n $NAMESPACE

# Check pods
kubectl get pods -n $NAMESPACE
```

<details>
<summary>LLMInferenceService manifest details (click to expand)</summary>

The `manifests/llmisvc-tpu.yaml` includes:

**TPU Node Selection** (required by GKE Warden):
```yaml
nodeSelector:
  cloud.google.com/gke-tpu-accelerator: tpu-v6e-slice
  cloud.google.com/gke-tpu-topology: 2x2  # 4 chips, single-host

tolerations:
- key: google.com/tpu
  operator: Equal
  value: present
  effect: NoSchedule
```

**TPU Environment Variables**:
```yaml
env:
- name: TPU_CHIPS_PER_HOST_BOUNDS
  value: "2,2,1"  # 2x2 topology for 4 chips
- name: TPU_HOST_BOUNDS
  value: "1,1,1"  # Single host
- name: PJRT_DEVICE
  value: "TPU"
```

**Resource Allocation**:
```yaml
resources:
  limits:
    google.com/tpu: "4"  # MUST request all 4 chips
  requests:
    google.com/tpu: "4"
```

**Extended Health Probes** (TPU init + model download + compilation):
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8000
    scheme: HTTP
  initialDelaySeconds: 240  # 2-3 min TPU init + model download
  periodSeconds: 30
  timeoutSeconds: 30
  failureThreshold: 5
```

</details>

### Step 6: Test Inference (5-10 min)

```bash
cd /home/jhull/devel/llm-d-xks-gke/deployments/llm-d-infra-xks-gke-tpu

# Get Gateway external IP
export GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub \
  -o jsonpath='{.status.addresses[0].value}')

echo "Gateway IP: $GATEWAY_IP"

# Test health endpoint
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/health

# List available models
curl http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/models

# Test completion
curl -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-3B-Instruct",
    "prompt": "Hello, how are you?",
    "max_tokens": 50
  }'

# Test chat completion
curl -X POST http://$GATEWAY_IP/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-3B-Instruct",
    "messages": [{"role": "user", "content": "What is Kubernetes?"}],
    "max_tokens": 100
  }'
```

**Run automated tests:**
```bash
./scripts/test-cluster.sh
```

**Run benchmarks:**
```bash
./scripts/benchmark-cluster.sh
```

---

## Usage

```bash
# Deploy (from llm-d-infra-xks directory)
make deploy              # cert-manager + istio
make deploy-all          # cert-manager + istio + lws
make deploy-kserve       # Deploy KServe

# Undeploy
make undeploy            # Remove all infrastructure
make undeploy-kserve     # Remove KServe

# Other
make status              # Show status
make sync                # Update helm repos
```

## Configuration

Edit `values.yaml` in the llm-d-infra-xks repository:

```yaml
# Option 1: Use system podman auth (recommended)
useSystemPodmanAuth: true

# Option 2: Use pull secret file directly
# pullSecretFile: ~/pull-secret.txt

# Operators
certManager:
  enabled: true

sailOperator:
  enabled: true

lwsOperator:
  enabled: true   # Required for multi-node LLM workloads
```

---

## KServe Controller Settings

The odh-xks overlay disables several OpenShift-specific features for vanilla Kubernetes (GKE) compatibility:

```yaml
# Disabled by default in odh-xks overlay
- name: LLMISVC_MONITORING_DISABLED
  value: "true"              # No Prometheus Operator dependency
- name: LLMISVC_AUTH_DISABLED
  value: "true"              # No Kuadrant/RHCL dependency
- name: LLMISVC_SCC_DISABLED
  value: "true"              # No OpenShift SecurityContextConstraints
```

| Setting | Why Disabled on GKE |
|---------|---------------------|
| `LLMISVC_MONITORING_DISABLED` | Prometheus Operator not required for basic inference |
| `LLMISVC_AUTH_DISABLED` | Authorino/Kuadrant (Red Hat Connectivity Link) is OpenShift-only |
| `LLMISVC_SCC_DISABLED` | SecurityContextConstraints are OpenShift-specific |

---

## Troubleshooting

### KServe Controller Issues

If the controller pod is stuck in `ContainerCreating` (waiting for certificate):
```bash
# Apply cert-manager resources separately first
kubectl apply -k "https://github.com/opendatahub-io/kserve/config/overlays/odh-test/cert-manager?ref=release-v0.15"
kubectl wait --for=condition=Ready certificate/kserve-webhook-server -n opendatahub --timeout=120s

# Then re-apply the overlay
kustomize build "https://github.com/opendatahub-io/kserve/config/overlays/odh-xks?ref=release-v0.15" | kubectl apply --server-side --force-conflicts -f -
```

If webhook validation blocks apply (manual deployment only - `make deploy-kserve` handles this automatically):
```bash
kubectl delete validatingwebhookconfiguration llminferenceservice.serving.kserve.io llminferenceserviceconfig.serving.kserve.io
kustomize build "https://github.com/opendatahub-io/kserve/config/overlays/odh-xks?ref=release-v0.15" | kubectl apply --server-side --force-conflicts -f -
```

If you get "no matches for kind LLMInferenceServiceConfig" errors:
```bash
# This is a CRD timing issue - run the apply command again after CRDs are registered
sleep 5
kustomize build "https://github.com/opendatahub-io/kserve/config/overlays/odh-xks?ref=release-v0.15" | kubectl apply --server-side --force-conflicts -f -
```

### Gateway Issues

If Gateway pod has `ErrImagePull`:
```bash
# Copy pull secret to opendatahub namespace
kubectl get secret redhat-pull-secret -n istio-system -o yaml | \
  sed 's/namespace: istio-system/namespace: opendatahub/' | kubectl apply -f -

# Patch the gateway ServiceAccount
kubectl patch sa inference-gateway-istio -n opendatahub \
  -p '{"imagePullSecrets": [{"name": "redhat-pull-secret"}]}'

# Delete the failing pod to trigger restart
kubectl delete pod -n opendatahub -l gateway.networking.k8s.io/gateway-name=inference-gateway
```

If Gateway external IP is pending:
```bash
# Check LoadBalancer quota
gcloud compute project-info describe --project=ecoeng-llmd | grep -i "IN_USE_ADDRESSES"

# List existing forwarding rules (LoadBalancers)
gcloud compute forwarding-rules list --project=ecoeng-llmd

# Delete unused LoadBalancers if quota is exhausted
gcloud compute forwarding-rules delete <unused-lb-name> --region=<region>
```

### GKE-Specific Issues

#### TPU Quota Exceeded

**Symptom:** Node pool creation fails with quota error

**Solution:**
1. Check current quota: `gcloud compute project-info describe --project=ecoeng-llmd | grep -i tpu`
2. Request quota increase: https://console.cloud.google.com/iam-admin/quotas?project=ecoeng-llmd
3. Search for "TPU v6e" and increase quota for your zone
4. Wait ~15 minutes for approval (automatic for most increases)

#### TPU Node Not Scheduling

**Symptom:** Pod stuck in Pending with "No nodes match pod topology spread constraints"

**Diagnosis:**
```bash
kubectl describe pod -n llm-d-inference-scheduling <pod-name>

# Check node labels
kubectl get nodes -l cloud.google.com/gke-tpu-accelerator=tpu-v6e-slice --show-labels
```

**Common Causes:**
- **Node selector mismatch**: Verify `cloud.google.com/gke-tpu-topology: 2x2` label exists
- **Warden allocation issue**: GKE Warden may need a few minutes to register TPU
- **Taint mismatch**: Ensure pod has toleration for `google.com/tpu=present:NoSchedule`

**Solution:**
```bash
# Wait 5 minutes for Warden registration
sleep 300

# Verify TPU node capacity
kubectl describe node <tpu-node-name> | grep -A 5 "Capacity:"
# Should show: google.com/tpu: 4

# Delete and recreate pod if still pending
kubectl delete pod -n llm-d-inference-scheduling <pod-name>
```

#### NetworkPolicy Blocking Traffic

**Symptom:** Requests fail with 503 or connection timeout

**Diagnosis:**
```bash
# Check if NetworkPolicies are applied
kubectl get networkpolicies -n llm-d-inference-scheduling

# Check pod labels (must match NetworkPolicy selectors)
kubectl get pods -n llm-d-inference-scheduling --show-labels

# Test from Gateway pod directly
GATEWAY_POD=$(kubectl get pod -n opendatahub -l gateway.networking.k8s.io/gateway-name=inference-gateway -o name)
kubectl exec -n opendatahub $GATEWAY_POD -- curl -v http://qwen2-3b-pattern1.llm-d-inference-scheduling.svc.cluster.local:8000/health
```

**Solution:**
See [manifests/networkpolicies/README.md](manifests/networkpolicies/README.md) for label requirements.

#### vLLM Pod CrashLoopBackOff on TPU

**Symptom:** Pod restarts repeatedly with JAX/TPU errors

**Common Causes:**

1. **Incorrect TPU topology**:
```bash
# Check environment variable
kubectl get pod <pod-name> -n llm-d-inference-scheduling -o yaml | grep TPU_CHIPS_PER_HOST_BOUNDS
# Should be: "2,2,1" for 4-chip topology
```

2. **Missing VFIO devices** (shouldn't happen on GKE):
```bash
kubectl logs <pod-name> -n llm-d-inference-scheduling | grep "vfio"
# Should NOT show errors about /dev/vfio/0
```

3. **HuggingFace token issues**:
```bash
# Check secret exists
kubectl get secret hf-token -n llm-d-inference-scheduling

# Verify token is valid
kubectl get secret hf-token -n llm-d-inference-scheduling -o jsonpath='{.data.HF_TOKEN}' | base64 -d
# Should show valid token starting with hf_...
```

4. **Model download timeout**:
```bash
# Check logs for download progress
kubectl logs <pod-name> -n llm-d-inference-scheduling | grep "download"

# Increase initialDelaySeconds in livenessProbe if needed
kubectl edit llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling
# Change initialDelaySeconds from 240 to 360 for slow downloads
```

---

## GKE-Specific Configuration

### TPU Topology and Resources

**ct6e-standard-4t Architecture:**
- **4 TPU v6e chips** arranged in 2×2 topology
- **Single-host** configuration (all chips on one node)
- **Tensor parallelism**: Distributes model layers across 4 chips

**TPU_CHIPS_PER_HOST_BOUNDS Explanation:**
```bash
TPU_CHIPS_PER_HOST_BOUNDS="2,2,1"
#                           │ │ └─ Z dimension (1 = single layer)
#                           │ └─── Y dimension (2 chips)
#                           └───── X dimension (2 chips)
# Result: 2 × 2 × 1 = 4 chips total
```

**GKE Warden Scheduling Requirements:**
- Pods MUST use `nodeSelector` for `cloud.google.com/gke-tpu-topology`
- Resource request MUST match exact chip count: `google.com/tpu: "4"`
- Mismatched requests will never schedule (Warden validates topology)

### NetworkPolicy Enforcement

GKE enforces NetworkPolicies strictly. This deployment uses a **default-deny** model:

**Applied Policies:**
1. **default-deny.yaml** - Blocks all ingress traffic by default
2. **allow-gateway-to-vllm.yaml** - Allows Gateway → vLLM pod (port 8000)
3. **allow-vllm-egress.yaml** - Allows vLLM → external (HuggingFace, internet)

**Critical Label Requirements:**
- vLLM pods MUST have label: `serving.kserve.io/inferenceservice: qwen2-3b-pattern1`
- Gateway pods MUST have label: `gateway.networking.k8s.io/gateway-name: inference-gateway`

See [manifests/networkpolicies/README.md](manifests/networkpolicies/README.md) for complete details.

### Workload Identity (Optional)

For using GCS buckets to store models instead of HuggingFace Hub:

```bash
# Create GCS bucket
gsutil mb -p ecoeng-llmd gs://llm-models-bucket

# Create Kubernetes service account
kubectl create sa model-sa -n llm-d-inference-scheduling

# Bind to Google service account
gcloud iam service-accounts create model-accessor
gcloud storage buckets add-iam-policy-binding gs://llm-models-bucket \
  --member="serviceAccount:model-accessor@ecoeng-llmd.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

gcloud iam service-accounts add-iam-policy-binding \
  model-accessor@ecoeng-llmd.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:ecoeng-llmd.svc.id.goog[llm-d-inference-scheduling/model-sa]"

# Annotate Kubernetes SA
kubectl annotate sa model-sa -n llm-d-inference-scheduling \
  iam.gke.io/gcp-service-account=model-accessor@ecoeng-llmd.iam.gserviceaccount.com

# Update LLMInferenceService to use GCS URI and service account
kubectl edit llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling
# Change: spec.model.uri: "gs://llm-models-bucket/Qwen2.5-3B-Instruct"
# Add: spec.template.serviceAccountName: model-sa
```

### Cost Management

#### Cost Estimates

| Component | Configuration | Daily | Monthly |
|-----------|--------------|-------|---------|
| Default pool | 2 × n1-standard-4 | ~$6 | ~$180 |
| TPU pool | 1 × ct6e-standard-4t | ~$127 | ~$3,810 |
| Load Balancer | External IP | ~$0.30 | ~$9 |
| **Total (running)** | | **~$133** | **~$3,999** |
| **Total (scaled to 0)** | | **~$6** | **~$189** |

#### Scale-Down Strategies

**Option 1: Delete LLMInferenceService** (recommended for short breaks):
```bash
kubectl delete llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling

# TPU node pool autoscales to 0 after ~10 minutes
# Cost: ~$6/day (default pool only)
```

**Option 2: Manually resize TPU node pool to 0** (immediate cost savings):
```bash
gcloud container clusters resize llmd-istio-tpu-pattern1 \
  --node-pool tpu-v6e-pool \
  --num-nodes 0 \
  --zone europe-west4-a \
  --project ecoeng-llmd

# Cost: ~$6/day immediately
```

**Option 3: Delete entire cluster** (when done with testing):
```bash
gcloud container clusters delete llmd-istio-tpu-pattern1 \
  --zone europe-west4-a \
  --project ecoeng-llmd \
  --quiet

# Cost: $0/day
```

#### Monitoring Costs

View real-time costs in GCP Console:
```bash
# Open billing dashboard
open "https://console.cloud.google.com/billing/$(gcloud beta billing projects describe ecoeng-llmd --format='value(billingAccountName)' | cut -d/ -f2)/reports?project=ecoeng-llmd"

# Or use gcloud to estimate
gcloud compute instances list --project=ecoeng-llmd --format="table(name,zone,machineType,status)"
```

---

## Reinstalling Istio

If you need to do a clean reinstall of Istio:

```bash
# 1. Delete the Istio CR (triggers istiod cleanup)
kubectl delete istio default -n istio-system

# 2. Wait for istiod to be removed
kubectl wait --for=delete pod -l app=istiod -n istio-system --timeout=120s

# 3. Redeploy
cd /home/jhull/devel/llm-d-infra-xks
make deploy-istio
```

---

## Architecture

### TLS Certificate Architecture

The odh-xks overlay creates an OpenDataHub-scoped CA:
1. Self-signed bootstrap issuer creates root CA in cert-manager namespace
2. ClusterIssuer (`opendatahub-ca-issuer`) uses this CA to sign certificates
3. KServe controller generates certificates for LLM workload mTLS automatically
4. Gateway needs CA bundle mounted at `/var/run/secrets/opendatahub/ca.crt`

### Key Differences from OpenShift (ODH) Overlay

| Component | OpenShift (ODH) | Vanilla K8s (odh-xks on GKE) |
|-----------|-----------------|------------------------------|
| Certificates | OpenShift service-ca | cert-manager |
| Security constraints | SCC included | Removed (use PodSecurityStandards) |
| Traffic routing | Istio VirtualService | Gateway API HTTPRoute |
| Webhook CA injection | Service annotations | cert-manager annotations |
| Auth | Authorino/Kuadrant | Disabled |
| Monitoring | Prometheus included | Disabled (optional) |
| Container runtime | CRI-O | Containerd |
| Load Balancer | OpenShift Router | GCP Network Load Balancer |

### GKE Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          GKE Cluster (ecoeng-llmd)                      │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                    Infrastructure Layer                           │ │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐     │ │
│  │  │ cert-manager   │  │ Istio          │  │ LWS            │     │ │
│  │  │ (TLS certs)    │  │ (service mesh) │  │ (multi-node)   │     │ │
│  │  └────────────────┘  └────────────────┘  └────────────────┘     │ │
│  │                                                                   │ │
│  │  ┌────────────────────────────────────────────────────────────┐  │ │
│  │  │ KServe Controller (opendatahub namespace)                  │  │ │
│  │  │ - Watches LLMInferenceService CRDs                         │  │ │
│  │  │ - Auto-creates HTTPRoute + InferencePool                   │  │ │
│  │  │ - Manages vLLM Deployment lifecycle                        │  │ │
│  │  └────────────────────────────────────────────────────────────┘  │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                 ↓                                       │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │            Inference Gateway (GCP Network Load Balancer)          │ │
│  │  External IP: 34.x.x.x → Istio Gateway Pod                       │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                 ↓                                       │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                      Routing Layer                                │ │
│  │  HTTPRoute → InferencePool → EPP Scheduler                        │ │
│  │  (auto-created by KServe controller)                              │ │
│  │  - Prefix-cache aware routing                                     │ │
│  │  - Queue depth monitoring                                         │ │
│  │  - KV cache utilization tracking                                  │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                 ↓                                       │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │              vLLM Workload (KServe-managed)                       │ │
│  │  Deployment: qwen2-3b-pattern1                                    │ │
│  │  - Image: registry.redhat.io/rhaiis/vllm-tpu-rhel9:3.2.5         │ │
│  │  - Model: Qwen/Qwen2.5-3B-Instruct                               │ │
│  │  - TPU v6e-4 (tensor_parallel_size=4)                            │ │
│  │  - NetworkPolicies: default-deny with Gateway allowlist           │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  Node Pools:                                                            │
│  ┌─────────────────────┐  ┌──────────────────────────────────┐        │
│  │ default-pool        │  │ tpu-v6e-pool                     │        │
│  │ 2 × n1-standard-4   │  │ 1 × ct6e-standard-4t (4 chips)  │        │
│  │ (control plane)     │  │ Taint: google.com/tpu=present   │        │
│  └─────────────────────┘  └──────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────────────┘

Request Flow:
1. Client → GCP Load Balancer (External IP)
2. Load Balancer → Istio Gateway Pod (opendatahub namespace)
3. Gateway → HTTPRoute → InferencePool → EPP Scheduler
4. EPP Scheduler → vLLM Pod (selects based on prefix cache, queue depth)
5. vLLM Pod → Process on TPU → Return response
```

---

## Repository Structure

```
deployments/llm-d-infra-xks-gke-tpu/
├── README.md                          # This file
├── QUICKSTART.md                      # Fast-track deployment guide
├── IMPLEMENTATION_STATUS.md           # Implementation progress tracking
│
├── cluster-config/
│   └── create-cluster.sh              # GKE cluster creation (base + TPU pool)
│
├── manifests/
│   ├── llmisvc-tpu.yaml              # KServe LLMInferenceService definition
│   └── networkpolicies/               # Network security policies
│       ├── README.md
│       ├── default-deny.yaml
│       ├── allow-gateway-to-vllm.yaml
│       └── allow-vllm-egress.yaml
│
├── scripts/
│   ├── test-cluster.sh                # API functional tests
│   └── benchmark-cluster.sh           # Performance benchmarks
│
├── benchmarks/
│   └── results/                       # Benchmark results (created during testing)
│
└── docs/
    ├── architecture.md                # Architecture deep-dive
    └── deployment-guide.md            # Step-by-step deployment guide
```

### External Dependencies

This deployment requires sibling repositories:

```
/home/jhull/devel/
├── llm-d-xks-gke/                    # This repository
├── llm-d-infra-xks/                  # Infrastructure operators (clone separately)
└── llm-d/                            # llm-d framework (optional, for reference)
```

**Setup commands:**
```bash
cd /home/jhull/devel
git clone https://github.com/aneeshkp/llm-d-infra-xks.git
# llm-d framework clone is optional - not needed for KServe deployment
```

---

## Source Repositories

Infrastructure operators are imported from:

- https://github.com/aneeshkp/cert-manager-operator-chart
- https://github.com/aneeshkp/sail-operator-chart
- https://github.com/aneeshkp/lws-operator-chart

KServe deployment uses:

- https://github.com/opendatahub-io/kserve (release-v0.15, odh-xks overlay)

---

## Additional Resources

### Documentation

- [Architecture Details](docs/architecture.md) - Component interaction, request flow, node architecture
- [Deployment Guide](docs/deployment-guide.md) - Detailed step-by-step instructions
- [NetworkPolicy Guide](manifests/networkpolicies/README.md) - Network security configuration
- [Benchmarking Guide](../../docs/benchmarking-quickstart.md) - Performance testing procedures

### Related Deployments

| Deployment | Infrastructure | Workload | Notes |
|-----------|---------------|----------|-------|
| [istio-kserve/pattern1-baseline](../istio-kserve/pattern1-baseline/) | Manual kubectl | KServe (kustomize) | TPU best practices source |
| [gateway-api/pattern1-baseline](../../deployments/gateway-api/pattern1-baseline/) | Manual kubectl | llm-d Helm | Alternative routing approach |
| **This Deployment** | llm-d-infra-xks (operators) | KServe (declarative) | Best of both worlds |

### Upstream Projects

- [llm-d Website](https://llm-d.ai/) - llm-d framework documentation
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/) - InferencePool specification
- [KServe Documentation](https://kserve.github.io/website/) - KServe project docs
- [OpenDataHub](https://opendatahub.io/) - Open source AI platform

### GKE Resources

- [GKE TPU Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/tpus)
- [AI on GKE](https://github.com/ai-on-gke) - Google's AI deployment patterns
- [GKE NetworkPolicy](https://cloud.google.com/kubernetes-engine/docs/how-to/network-policy)
- [GKE Gateway API](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api)

### Support and Issues

- **Infrastructure Issues**: [llm-d-infra-xks](https://github.com/aneeshkp/llm-d-infra-xks/issues)
- **KServe Issues**: [opendatahub-io/kserve](https://github.com/opendatahub-io/kserve/issues)
- **GKE Issues**: [Google Cloud Support](https://cloud.google.com/support)
- **This Deployment**: Create issue in this repository

---

**Last Updated**: 2026-02-11
**Status**: Documentation updated to reflect KServe LLMInferenceService architecture
**Pattern**: Pattern 1 - Single model baseline with EPP routing on GKE TPU v6e
