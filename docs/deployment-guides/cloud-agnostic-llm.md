# Cloud-Agnostic LLM Inference Deployment
## Run on GKE Today, Migrate to Any Cloud Tomorrow

**Production-grade LLM inference using portable Kubernetes interfaces**

---

## Table of Contents

1. [Introduction](#introduction)
2. [Part 1: GKE Cluster Setup (Cloud-Specific)](#part-1-gke-cluster-setup-cloud-specific)
3. [Step 0: Acquire Red Hat Pull Secret (Optional)](#step-0-acquire-red-hat-pull-secret-optional)
4. [Part 2: Deploy Cloud-Agnostic Stack](#part-2-deploy-cloud-agnostic-stack)
   - [Step 1: Install cert-manager](#step-1-install-cert-manager)
   - [Step 2: Install Istio Service Mesh](#step-2-install-istio-service-mesh)
   - [Step 3: Install Gateway API Inference Extensions](#step-3-install-gateway-api-inference-extensions)
   - [Step 4: Install NVIDIA GPU Operator (Optional)](#step-4-install-nvidia-gpu-operator-optional)
   - [Step 5: Deploy llm-d with Istio Environment](#step-5-deploy-llm-d-with-istio-environment)
   - [Step 6: Configure Gateway and HTTPRoute](#step-6-configure-gateway-and-httproute)
   - [Step 7: Verify Cloud-Agnostic Deployment](#step-7-verify-cloud-agnostic-deployment)
5. [Part 3: Testing & Validation](#part-3-testing--validation)
6. [Part 4: Migration Readiness](#part-4-migration-readiness)
7. [Troubleshooting](#troubleshooting)
8. [Cost Comparison](#cost-comparison)
9. [Appendix](#appendix)

---

## Introduction

### What Makes This Deployment Cloud-Agnostic?

This guide shows you how to deploy a production-grade LLM inference stack on **GKE** today using **only standard Kubernetes interfaces**. Because we avoid cloud-specific features, the same deployment can be migrated to **AWS EKS**, **Azure AKS**, **Red Hat OpenShift**, or vanilla Kubernetes with minimal changes.

**The key principle:** Use standard Kubernetes APIs instead of cloud-specific managed services.

### Architecture

**Cloud-Agnostic Stack (works on any Kubernetes):**
```
Internet → Istio Ingress Gateway (standard K8s LoadBalancer)
              ↓
         Gateway API (istio GatewayClass)
              ↓
         InferencePool (EPP ext-proc via Istio)
              ↓
         vLLM Pod (GPU accelerated)
```

**Why this is portable:**
- ✅ **Istio Gateway** - Works on any Kubernetes cluster (not GKE-specific ALB)
- ✅ **Standard Gateway API** - `gateway.networking.k8s.io/v1` (Kubernetes standard)
- ✅ **InferencePool CRDs** - Custom but portable (install with kubectl)
- ✅ **Helm charts** - Standard Kubernetes package manager
- ✅ **NVIDIA GPU Operator** - Consistent GPU support across all clouds
- ✅ **llm-d helmfile** - Uses `istio` environment (cloud-agnostic)

**Comparison with GKE-Specific Approach:**

| Component | GKE-Specific | Cloud-Agnostic (Upstream) | Cloud-Agnostic (Red Hat) |
|-----------|--------------|---------------------------|--------------------------|
| **Gateway** | GKE Gateway API (`gke-l7-regional-external-managed`) | Istio Gateway (`istio` GatewayClass) | Istio Gateway (`istio` GatewayClass) |
| **Load Balancer** | GKE Regional External ALB (proxy-only subnet) | Istio Ingress Gateway (standard K8s LoadBalancer) | Istio Ingress Gateway (standard K8s LoadBalancer) |
| **Operator Source** | N/A | Official Helm charts | Red Hat registry |
| **Network Config** | proxy-only subnet, Network Services API | None (Istio handles internally) | None (Istio handles internally) |
| **GPU Drivers** | GKE auto-installed | NVIDIA GPU Operator (portable) | NVIDIA GPU Operator (portable) |
| **Support** | Google | Community | Red Hat Enterprise |
| **Cost** | GKE fees | Free (open-source) | Red Hat subscription |
| **Pull Secret** | No | No | Yes (Red Hat account) |
| **Certification** | N/A | Community | Red Hat certified |
| **Helmfile Env** | `helmfile -e gke` | `helmfile -e istio` | `helmfile -e istio` |
| **Migration Effort** | High (locked to GKE) | Low (2-3 hours to any cloud) | Low (2-3 hours to any cloud) |
| **Supported Platforms** | GKE only | **GKE, EKS, AKS, OpenShift, vanilla K8s** | **GKE, EKS, AKS, OpenShift, vanilla K8s** |

### Supported Platforms

This deployment has been tested on:
- ✅ **Google Kubernetes Engine (GKE)** - Primary deployment target
- ✅ **AWS Elastic Kubernetes Service (EKS)** - Validated (see Part 4)
- ✅ **Azure Kubernetes Service (AKS)** - Validated (see Part 4)
- ✅ **Red Hat OpenShift** - Validated with minor adjustments (see Part 4)
- ✅ **Vanilla Kubernetes** - Any conformant Kubernetes 1.28+

### Prerequisites

**Local Tools:**
- `kubectl` v1.28.0+ - Kubernetes CLI
- `helm` v3.12.0+ - Kubernetes package manager
- `helmfile` v1.1.0+ - Helm orchestration tool
- `git` v2.30.0+ - Version control
- `podman` or `docker` (optional - for Red Hat pull secret verification)

**Cloud-Specific CLI (only for Part 1):**
- GKE: `gcloud` CLI (Google Cloud SDK)
- EKS: `aws` CLI + `eksctl`
- AKS: `az` CLI (Azure CLI)
- OpenShift: `oc` CLI

**Credentials:**
- **HuggingFace Token** - From https://huggingface.co/settings/tokens
  - Needed for downloading models (any valid token works for public models)
- **Red Hat Pull Secret** (Optional - for Red Hat operator approach)
  - From https://console.redhat.com/openshift/install/pull-secret
  - Required if using Red Hat-certified operators
  - Free with Red Hat developer account

**Kubernetes Cluster:**
- Kubernetes 1.28.0+
- At least 1 GPU node (NVIDIA T4, L4, A100, or equivalent)
- 2+ CPU nodes for control plane components

### What You'll Deploy

By the end of this guide, you will have:

1. ✅ Kubernetes cluster with GPU support
2. ✅ Istio service mesh with ingress gateway
3. ✅ Gateway API with Inference Extensions (InferencePool CRDs)
4. ✅ NVIDIA GPU Operator (for portable GPU support)
5. ✅ llm-d Pattern 1 serving google/gemma-2b-it
6. ✅ Working inference API at `http://<GATEWAY-IP>/v1/completions`
7. ✅ Intelligent routing via EPP (Endpoint Picker)
8. ✅ **Zero cloud lock-in** - migrate to any platform with minimal changes

**Total Time:** ~45 minutes

---

## Part 1: GKE Cluster Setup (Cloud-Specific)

> **Note:** This is the **only cloud-specific section** in this guide. When migrating to EKS, AKS, or OpenShift, you'll replace this section with your cloud's cluster creation steps (see Part 4).

### Why This Section is Cloud-Specific

- Uses `gcloud` CLI (GKE-specific tool)
- Creates GKE cluster with GPU node pool
- GKE-specific node provisioning commands

**Everything after this section (Part 2, 3, 4) is cloud-agnostic and works identically on all platforms.**

### 1.1 Set Environment Variables

```bash
# GCP Configuration
export PROJECT_ID="your-gcp-project-id"
export CLUSTER_NAME="llm-d-cluster"
export REGION="us-central1"
export ZONE="us-central1-a"

# llm-d Configuration
export NAMESPACE="llm-d"
export RELEASE_NAME_POSTFIX="pattern1"

# HuggingFace Token (replace with your token)
export HF_TOKEN="hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Set gcloud project
gcloud config set project $PROJECT_ID
```

### 1.2 Create GKE Cluster with CPU Nodes

```bash
# Create base cluster with CPU nodes
gcloud container clusters create $CLUSTER_NAME \
  --zone $ZONE \
  --machine-type n1-standard-4 \
  --num-nodes 2 \
  --enable-ip-alias \
  --project $PROJECT_ID
```

**Expected output:**
```
Creating cluster llm-d-cluster in us-central1-a...
...
Created [https://container.googleapis.com/v1/projects/.../clusters/llm-d-cluster].
kubeconfig entry generated for llm-d-cluster.
```

**Wait:** ~5-7 minutes for cluster creation

### 1.3 Add GPU Node Pool (NVIDIA T4)

```bash
# Add GPU node pool with T4 GPUs
gcloud container node-pools create nvidia-t4-pool \
  --cluster $CLUSTER_NAME \
  --zone $ZONE \
  --machine-type n1-standard-4 \
  --accelerator type=nvidia-tesla-t4,count=1 \
  --num-nodes 1 \
  --enable-autoscaling \
  --min-nodes 0 \
  --max-nodes 3 \
  --project $PROJECT_ID
```

**Expected output:**
```
Creating node pool nvidia-t4-pool...
...
Created [https://container.googleapis.com/v1/projects/.../nodePools/nvidia-t4-pool].
```

> **GKE Note:** GKE automatically installs NVIDIA GPU drivers when you create a GPU node pool. However, we'll install the GPU Operator in Part 2 Step 4 for portability across all clouds.

### 1.4 Get Cluster Credentials

```bash
# Get cluster credentials for kubectl
gcloud container clusters get-credentials $CLUSTER_NAME \
  --zone $ZONE \
  --project $PROJECT_ID
```

**Expected output:**
```
Fetching cluster endpoint and auth data.
kubeconfig entry generated for llm-d-cluster.
```

### 1.5 Verify Cluster

```bash
# Check nodes are ready
kubectl get nodes
```

**Expected output:**
```
NAME                                          STATUS   ROLES    AGE     VERSION
gke-llm-d-cluster-default-pool-xxxxx          Ready    <none>   3m      v1.33.5-gke.2019000
gke-llm-d-cluster-default-pool-xxxxx          Ready    <none>   3m      v1.33.5-gke.2019000
gke-llm-d-cluster-nvidia-t4-pool-xxxxx        Ready    <none>   2m      v1.33.5-gke.2019000
```

**Verify GPU:**
```bash
# Check GPU allocation on T4 node
kubectl describe nodes | grep nvidia.com/gpu
```

**Expected output:**
```
  nvidia.com/gpu:     1
  nvidia.com/gpu:     1
```

✅ **Checkpoint:** You now have a GKE cluster with 2 CPU nodes + 1 GPU node (T4)

---

## Step 0: Acquire Red Hat Pull Secret (Optional)

> **Note:** This step is **only required** if you choose the Red Hat operator deployment approach (Option B in Part 2). If using upstream operators (Option A), skip to Part 2.

### Why Red Hat Pull Secret?

The Red Hat operator deployment uses container images from Red Hat's private registry (`registry.redhat.io`). This registry requires authentication.

**What it provides access to:**
- cert-manager-operator: `registry.redhat.io/cert-manager/cert-manager-operator-rhel9`
- sail-operator (Istio): `registry.redhat.io/openshift-service-mesh/istio-*-rhel9`
- lws-operator: `registry.redhat.io/openshift-lws-operator/lws-operator-rhel9`

**Without the pull secret:**
- Pods will fail with `ImagePullBackOff` or `ErrImagePull`
- Kubernetes cannot authenticate to download the images

### 0.1 Download Pull Secret

1. Go to: https://console.redhat.com/openshift/install/pull-secret
2. Login with your Red Hat account (free developer account works)
3. Click "Download pull secret"
4. Save as `~/pull-secret.txt`

### 0.2 Configure Pull Secret for Podman

```bash
# Create persistent location
mkdir -p ~/.config/containers
cp ~/pull-secret.txt ~/.config/containers/auth.json
```

### 0.3 Verify Pull Secret

```bash
# Test pulling a Red Hat image
podman pull registry.redhat.io/ubi8/ubi-minimal --quiet && echo "Pull secret OK"
```

**Expected output:** `Pull secret OK`

✅ **Checkpoint:** Red Hat pull secret configured (if using Red Hat operators)

---

## Part 2: Deploy Cloud-Agnostic Stack

> **🌍 Cloud-Agnostic Zone:** Everything in this section uses standard Kubernetes APIs and works identically on **GKE, EKS, AKS, OpenShift, and vanilla Kubernetes**.

### Deployment Approach Choice

You can deploy the required operators using two approaches:

#### Approach 1: Upstream Operators (Recommended for Maximum Portability)
- Deploy each operator individually using official Helm charts
- Steps 1-4 below use this approach
- ✅ Maximum portability
- ✅ Free, open-source
- ✅ Community support

#### Approach 2: Red Hat Operators via llm-d-infra-xks (Enterprise Support)
- Deploy all operators at once using meta helmfile
- Faster deployment (single command)
- ✅ Enterprise support from Red Hat
- ✅ Red Hat-certified images
- ✅ Requires Red Hat subscription/pull secret

---

### Quick Start: Deploy All Operators at Once (llm-d-infra-xks)

If you prefer the Red Hat operator approach, you can deploy **all operators at once** using the meta helmfile:

```bash
# Clone meta helmfile repo
git clone https://github.com/aneeshkp/llm-d-infra-xks.git
cd llm-d-infra-xks

# Deploy cert-manager + Istio (default)
make deploy

# Or deploy all 3 operators including LWS
make deploy-all
```

**What this deploys:**
- cert-manager operator (in cert-manager-operator namespace)
- sail-operator / Istio (in istio-system namespace)
- lws-operator (in openshift-lws-operator namespace) - if using `make deploy-all`

**Verify:**
```bash
make status
```

**Expected output:**
```
=== cert-manager ===
cert-manager-operator namespace: 1/1 pods running
cert-manager namespace: 3/3 pods running

=== sail-operator (Istio) ===
istio-system namespace: 2/2 pods running

=== lws-operator ===
openshift-lws-operator namespace: 2/2 pods running
```

**After deploying with meta helmfile, skip to Step 3 (Gateway API Inference Extensions).**

---

**If using individual operator deployment (Approach 1), continue with Step 1 below:**

### Step 1: Install cert-manager

**Purpose:** Certificate management for TLS (required by Istio)

**Choose your deployment approach:**
- **Option A: Upstream cert-manager** (Recommended for maximum portability)
  - Uses Jetstack Helm chart from https://charts.jetstack.io
  - Open-source, community-supported
  - No Red Hat subscription required

- **Option B: Red Hat cert-manager Operator** (Enterprise support)
  - Uses Red Hat-certified operator from llm-d-infra-xks
  - Enterprise support from Red Hat
  - Requires Red Hat pull secret (see Step 0)

---

#### Option A: Upstream cert-manager (Helm)

**Why it's cloud-agnostic:** cert-manager uses standard Kubernetes APIs and Helm. Works on any Kubernetes cluster.

##### 1.1 Add Helm Repository

```bash
# Add jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

##### 1.2 Create cert-manager Namespace

```bash
kubectl create namespace cert-manager
```

##### 1.3 Install cert-manager CRDs

```bash
# Install CRDs separately (recommended for production)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.crds.yaml
```

**Expected output:**
```
customresourcedefinition.apiextensions.k8s.io/certificaterequests.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/certificates.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/challenges.acme.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/clusterissuers.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/issuers.cert-manager.io created
customresourcedefinition.apiextensions.k8s.io/orders.acme.cert-manager.io created
```

##### 1.4 Deploy cert-manager with Helm

```bash
# Install cert-manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.16.2 \
  --wait
```

**Expected output:**
```
Release "cert-manager" does not exist. Installing it now.
NAME: cert-manager
...
STATUS: deployed
```

##### 1.5 Verify Deployment

```bash
# Check all cert-manager pods are running
kubectl get pods -n cert-manager
```

**Expected output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-5d7f97b46d-xxxxx             1/1     Running   0          2m
cert-manager-cainjector-69d885bf55-xxxxx  1/1     Running   0          2m
cert-manager-webhook-54754dcdfd-xxxxx     1/1     Running   0          2m
```

**Wait until all pods are 1/1 Running** (approximately 1-2 minutes)

---

#### Option B: Red Hat cert-manager Operator (llm-d-infra-xks)

##### 1.1 Clone llm-d-infra-xks Repository

```bash
# Clone meta helmfile repository
git clone https://github.com/aneeshkp/llm-d-infra-xks.git
cd llm-d-infra-xks
```

##### 1.2 Deploy cert-manager Operator

```bash
# Deploy using Makefile
make deploy-cert-manager
```

**What this does:**
- Deploys cert-manager-operator in `cert-manager-operator` namespace
- Deploys cert-manager components in `cert-manager` namespace
- Installs all CRDs automatically via presync hooks
- Waits for all pods to be ready

**Expected output:**
```
Deploying cert-manager operator...
helmfile -f helmfile.yaml -e cert-manager apply
...
Release "cert-manager-operator" deployed successfully
```

##### 1.3 Verify Deployment

```bash
# Check operator pod
kubectl get pods -n cert-manager-operator

# Check cert-manager pods
kubectl get pods -n cert-manager
```

**Expected output:**
```
# cert-manager-operator namespace
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-operator-xxxxx               1/1     Running   0          2m

# cert-manager namespace
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-5d7f97b46d-xxxxx             1/1     Running   0          2m
cert-manager-cainjector-xxxxx             1/1     Running   0          2m
cert-manager-webhook-xxxxx                1/1     Running   0          2m
```

##### 1.4 Run Integration Tests

```bash
# Run cert-manager tests
make test-cert-manager
```

**Expected:** Self-signed and CA certificate tests pass

**Alternative: Deploy individual operator chart:**
```bash
# If you prefer individual chart over meta helmfile
git clone https://github.com/aneeshkp/cert-manager-operator-chart.git
cd cert-manager-operator-chart
make deploy
make test
```

---

✅ **Checkpoint:** cert-manager deployed (upstream or Red Hat operator)

---

### Step 2: Install Istio Service Mesh

**Purpose:** Service mesh with intelligent routing capabilities

**Choose your deployment approach:**
- **Option A: Upstream Istio via Helm** (Recommended for non-OpenShift)
  - Uses official Istio Helm charts from istio.io
  - Maximum portability, works everywhere

- **Option B: Upstream Sail Operator** (Red Hat, OpenShift-friendly)
  - Uses community sail-operator
  - Good middle ground

- **Option C: Red Hat sail-operator via llm-d-infra-xks** (Enterprise support)
  - Uses Red Hat-certified operator
  - Enterprise support from Red Hat
  - Requires Red Hat pull secret (see Step 0)

---

#### Option A: Install Istio via Helm (Recommended)

##### 2.1 Add Istio Helm Repository

```bash
# Add Istio Helm repository
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
```

##### 2.2 Create istio-system Namespace

```bash
kubectl create namespace istio-system
```

##### 2.3 Install Istio Base Chart

```bash
# Install Istio base (CRDs and cluster-wide resources)
helm upgrade --install istio-base istio/base \
  --namespace istio-system \
  --version 1.24.1 \
  --wait
```

##### 2.4 Install Istiod (Control Plane)

```bash
# Install Istio control plane
helm upgrade --install istiod istio/istiod \
  --namespace istio-system \
  --version 1.24.1 \
  --wait
```

##### 2.5 Install Istio Ingress Gateway

```bash
# Install Istio ingress gateway
helm upgrade --install istio-ingressgateway istio/gateway \
  --namespace istio-system \
  --version 1.24.1 \
  --wait
```

#### Option B: Install Istio via Sail Operator (Red Hat/OpenShift)

##### 2.1 Add Sail Operator Helm Repository

```bash
# Add Red Hat sail-operator repository
helm repo add sail-operator https://istio-ecosystem.github.io/sail-operator
helm repo update
```

##### 2.2 Create sail-operator Namespace

```bash
kubectl create namespace sail-operator
```

##### 2.3 Install Sail Operator

```bash
# Deploy sail-operator
helm upgrade --install sail-operator sail-operator/sail-operator \
  --namespace sail-operator \
  --version 0.2.0 \
  --wait
```

##### 2.4 Deploy Istio Control Plane

Create Istio control plane configuration:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: operator.istio.io/v1alpha1
kind: Istio
metadata:
  name: default
spec:
  version: v1.24.1
  namespace: istio-system
  values:
    global:
      istioNamespace: istio-system
    pilot:
      autoscaleEnabled: true
EOF
```

---

#### Option C: Red Hat sail-operator (llm-d-infra-xks)

##### 2.1 Deploy Using Meta Helmfile

```bash
# From llm-d-infra-xks directory
cd ~/llm-d-infra-xks
make deploy-istio
```

**What this does:**
- Deploys servicemesh-operator3 in `istio-system` namespace
- Deploys Istio control plane (istiod)
- Installs all Istio CRDs automatically
- Uses Red Hat registry images
- Waits for all pods to be ready

**Expected output:**
```
Deploying sail-operator (Istio)...
helmfile -f helmfile.yaml -e istio apply
...
Release "sail-operator" deployed successfully
```

##### 2.2 Verify Deployment

```bash
# Check sail-operator pods
kubectl get pods -n istio-system
```

**Expected output:**
```
NAME                                    READY   STATUS    RESTARTS   AGE
servicemesh-operator3-xxxxx             1/1     Running   0          2m
istiod-7d6f9d4c8-xxxxx                  1/1     Running   0          2m
```

##### 2.3 Run Integration Tests

```bash
# From llm-d-infra-xks directory
make test-istio
```

**Expected:** Istio control plane tests pass

**Alternative: Deploy individual operator chart:**
```bash
# If you prefer individual chart
git clone https://github.com/aneeshkp/sail-operator-chart.git
cd sail-operator-chart
make deploy
make test
```

---

#### 2.6 Verify Istio Installation

```bash
# Check istiod deployment
kubectl get pods -n istio-system
```

**Expected output (Option A - Helm):**
```
NAME                                    READY   STATUS    RESTARTS   AGE
istiod-7d6f9d4c8-xxxxx                  1/1     Running   0          2m
istio-ingressgateway-6b8f9d4c8-xxxxx    1/1     Running   0          1m
```

**Expected output (Option B - Upstream Sail Operator):**
```
NAME                      READY   STATUS    RESTARTS   AGE
istiod-7d6f9d4c8-xxxxx    1/1     Running   0          2m
```

**Expected output (Option C - Red Hat sail-operator):**
```
NAME                                    READY   STATUS    RESTARTS   AGE
servicemesh-operator3-xxxxx             1/1     Running   0          2m
istiod-7d6f9d4c8-xxxxx                  1/1     Running   0          2m
```

```bash
# Verify Istio CRDs are available
kubectl api-resources | grep istio.io
```

**Expected CRDs:**
```
NAME                 SHORTNAMES   APIVERSION                 NAMESPACED   KIND
gateways             gw           gateway.networking.k8s.io/v1  true      Gateway
virtualservices      vs           networking.istio.io/v1beta1    true      VirtualService
destinationrules     dr           networking.istio.io/v1beta1    true      DestinationRule
```

✅ **Checkpoint:** Istio service mesh deployed (upstream or Red Hat operator)

---

### Step 3: Install Gateway API Inference Extensions

**Purpose:** Install InferencePool CRDs for intelligent routing

**Why it's cloud-agnostic:** These are standard Kubernetes CRDs installed via kubectl. No cloud dependencies.

#### 3.1 Clone llm-d Repository

```bash
# Clone llm-d repository
cd ~
git clone https://github.com/llm-d/llm-d.git
cd llm-d/guides/prereq/gateway-provider
```

#### 3.2 Install Gateway API Inference Extension CRDs

```bash
# Install Inference Extension CRDs
./install-gateway-provider-dependencies.sh
```

**Expected output:**
```
Installing Gateway API Inference Extension CRDs...
customresourcedefinition.apiextensions.k8s.io/inferencepools.inference.networking.k8s.io created
customresourcedefinition.apiextensions.k8s.io/inferenceobjectives.inference.networking.k8s.io created
```

#### 3.3 Verify Inference Extension CRDs

```bash
# Check InferencePool and InferenceObjective CRDs
kubectl api-resources --api-group=inference.networking.k8s.io
```

**Expected output:**
```
NAME                 SHORTNAMES   APIVERSION                              NAMESPACED   KIND
inferenceobjectives  io           inference.networking.k8s.io/v1alpha2    true         InferenceObjective
inferencepools       ip           inference.networking.k8s.io/v1          true         InferencePool
```

**What these CRDs enable:**
- **InferencePool** - Manages pools of inference endpoints with intelligent selection
- **InferenceObjective** - Defines routing objectives (load-aware, prefix-cache-aware)

✅ **Checkpoint:** Gateway API Inference Extensions are installed

---

### Step 4: Install NVIDIA GPU Operator (Optional)

**Purpose:** Provide consistent GPU support across all Kubernetes platforms

**Why this matters for portability:**
- **GKE** auto-installs NVIDIA drivers (GPU Operator is optional)
- **EKS, AKS, OpenShift, vanilla K8s** do NOT auto-install drivers (GPU Operator is required)
- Installing GPU Operator on GKE ensures your deployment is portable

**Benefits:**
- ✅ Works on all Kubernetes platforms
- ✅ Automated driver installation and updates
- ✅ Container runtime configuration
- ✅ Device plugin deployment
- ✅ Monitoring and telemetry

#### 4.1 Add NVIDIA Helm Repository

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

#### 4.2 Create gpu-operator Namespace

```bash
kubectl create namespace gpu-operator
```

#### 4.3 Install GPU Operator

**For GKE (drivers already installed):**
```bash
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --set driver.enabled=false \
  --wait
```

**For EKS, AKS, OpenShift, vanilla K8s (install drivers):**
```bash
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --set driver.enabled=true \
  --wait
```

#### 4.4 Verify GPU Operator

```bash
# Check operator pods
kubectl get pods -n gpu-operator
```

**Expected output (GKE with driver.enabled=false):**
```
NAME                                       READY   STATUS    RESTARTS   AGE
gpu-feature-discovery-xxxxx                1/1     Running   0          2m
gpu-operator-xxxxx                         1/1     Running   0          2m
nvidia-container-toolkit-daemonset-xxxxx   1/1     Running   0          2m
nvidia-dcgm-exporter-xxxxx                 1/1     Running   0          2m
nvidia-device-plugin-daemonset-xxxxx       1/1     Running   0          2m
```

**Expected output (EKS/AKS/OpenShift with driver.enabled=true):**
```
NAME                                       READY   STATUS    RESTARTS   AGE
gpu-feature-discovery-xxxxx                1/1     Running   0          2m
gpu-operator-xxxxx                         1/1     Running   0          2m
nvidia-container-toolkit-daemonset-xxxxx   1/1     Running   0          2m
nvidia-dcgm-exporter-xxxxx                 1/1     Running   0          2m
nvidia-device-plugin-daemonset-xxxxx       1/1     Running   0          2m
nvidia-driver-daemonset-xxxxx              1/1     Running   0          3m
```

**Verify GPU visible to Kubernetes:**
```bash
kubectl get nodes -o json | jq '.items[].status.capacity."nvidia.com/gpu"'
# Expected: "1" for each GPU node
```

**Cloud-specific configuration summary:**

| Platform | driver.enabled | Notes |
|----------|---------------|-------|
| **GKE** | `false` | Drivers pre-installed by GKE |
| **EKS** | `true` | Drivers not pre-installed |
| **AKS** | `true` | Drivers not pre-installed |
| **OpenShift** | `false` | Use NVIDIA GPU Operator for OpenShift instead |
| **Vanilla K8s** | `true` | Drivers not pre-installed |

✅ **Checkpoint:** GPU Operator deployed (portable GPU support enabled)

---

### Step 4.5: Install LWS Operator (Optional)

**Purpose:** LeaderWorkerSet operator for multi-pod coordination (required for advanced patterns like MoE)

> **Note:** This step is **optional** for Pattern 1 (single replica). Required for Pattern 4 (MoE) and Pattern 5 (P/D disaggregation).

**Choose your deployment approach:**
- **Option A: Upstream LWS** (from kubernetes-sigs)
- **Option B: Red Hat LWS Operator** (from llm-d-infra-xks)

---

#### Option A: Upstream LWS Operator

##### 4.5.1 Install LWS CRDs

```bash
# Install LeaderWorkerSet CRDs
kubectl apply --server-side -f https://github.com/kubernetes-sigs/lws/releases/download/v0.4.0/manifests.yaml
```

**Expected output:**
```
customresourcedefinition.apiextensions.k8s.io/leaderworkersets.leaderworkerset.x-k8s.io serverside-applied
namespace/lws-system serverside-applied
serviceaccount/lws-controller-manager serverside-applied
...
deployment.apps/lws-controller-manager serverside-applied
```

##### 4.5.2 Verify LWS Operator

```bash
# Check LWS controller pod
kubectl get pods -n lws-system
```

**Expected output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
lws-controller-manager-xxxxx              2/2     Running   0          1m
```

---

#### Option B: Red Hat LWS Operator (llm-d-infra-xks)

##### 4.5.1 Deploy Using Meta Helmfile

```bash
# From llm-d-infra-xks directory
cd ~/llm-d-infra-xks
make deploy-lws
```

**What this does:**
- Deploys openshift-lws-operator in `openshift-lws-operator` namespace
- Deploys lws-controller-manager pods
- Installs LeaderWorkerSet CRD
- Uses Red Hat registry images
- Waits for pods to be ready

**Expected output:**
```
Deploying lws-operator...
helmfile -f helmfile.yaml -e lws apply
...
Release "lws-operator" deployed successfully
```

##### 4.5.2 Verify Deployment

```bash
# Check operator pods
kubectl get pods -n openshift-lws-operator
```

**Expected output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
openshift-lws-operator-xxxxx              1/1     Running   0          2m
lws-controller-manager-xxxxx              2/2     Running   0          2m
```

##### 4.5.3 Run Integration Tests

```bash
# From llm-d-infra-xks directory
make test-lws
```

**Alternative: Deploy individual operator chart:**
```bash
git clone https://github.com/aneeshkp/lws-operator-chart.git
cd lws-operator-chart
make deploy
make test
```

✅ **Checkpoint:** LWS Operator deployed (optional, for advanced patterns)

---

### Step 5: Deploy llm-d with Istio Environment

**Purpose:** Deploy llm-d Pattern 1 with intelligent routing

**Why it's cloud-agnostic:** Uses Helm charts and standard Kubernetes resources. The `istio` environment ensures compatibility across all clouds.

#### 5.1 Create Namespace and Secrets

```bash
# Create llm-d namespace
kubectl create namespace $NAMESPACE

# Create HuggingFace token secret
kubectl create secret generic huggingface-token \
  --from-literal=token=$HF_TOKEN \
  --namespace $NAMESPACE

# Verify secret created
kubectl get secret huggingface-token -n $NAMESPACE
```

**Expected output:**
```
namespace/llm-d created
secret/huggingface-token created
NAME                TYPE     DATA   AGE
huggingface-token   Opaque   1      5s
```

#### 5.2 Review llm-d Configuration

Navigate to llm-d inference scheduling guide:

```bash
cd ~/../llm-d/guides/inference-scheduling
ls -la
```

**Key files:**
- `helmfile.yaml.gotmpl` - Orchestrates 3 Helm releases (infra, gaie, modelservice)
- `pattern1-overrides.yaml` - GPU-specific configuration overrides
- `gaie-inference-scheduling/values.yaml` - EPP scheduler configuration
- `ms-inference-scheduling/values.yaml` - Model service defaults

**View Istio-specific configuration:**
```bash
cat ~/llm-d/guides/prereq/gateway-provider/common-configurations/istio.yaml
```

**Key configuration:**
```yaml
# Infra values
gateway:
  gatewayClassName: istio  # ← Uses Istio instead of GKE Gateway

# GAIE values
provider:
  name: istio  # ← Configures EPP to use Istio ext-proc
```

#### 5.3 Deploy with Helmfile

```bash
# Set environment variables
export NAMESPACE="llm-d"
export RELEASE_NAME_POSTFIX="pattern1"

# Deploy all components (infra, gaie, modelservice) with Istio environment
helmfile -e istio -n $NAMESPACE apply
```

**Critical difference from GKE-specific guide:**
```bash
# GKE-specific (uses GKE Gateway API)
helmfile -e gke -n $NAMESPACE apply

# Cloud-agnostic (uses Istio Gateway)
helmfile -e istio -n $NAMESPACE apply
```

**What this deploys:**
1. **infra-pattern1** - Gateway infrastructure (Gateway with `istio` GatewayClass)
2. **gaie-pattern1** - EPP scheduler/router (InferencePool controller, ext-proc via Istio)
3. **ms-pattern1** - vLLM model service (1 replica, google/gemma-2b-it)

**Expected output:**
```
Building dependency release=infra-pattern1, chart=oci://registry.k8s.io/gateway-api-inference-extension/charts/infra
...
Upgrading release=infra-pattern1, chart=oci://...
Release "infra-pattern1" does not exist. Installing it now.
...
Upgrading release=gaie-pattern1, chart=oci://...
Upgrading release=ms-pattern1, chart=oci://...
```

**Deployment timeline:**
- Infrastructure: ~30 seconds
- EPP scheduler: ~1 minute
- vLLM model service: ~5-8 minutes (model download ~2-3 min + GPU loading ~2-3 min)

#### 5.4 Monitor Deployment

```bash
# Watch all pods in llm-d namespace
kubectl get pods -n $NAMESPACE -w
```

**Expected pods (during deployment):**
```
NAME                                                  READY   STATUS              RESTARTS   AGE
gaie-pattern1-epp-6cdc8cfc4b-xxxxx                    0/1     ContainerCreating   0          10s
ms-pattern1-llm-d-modelservice-decode-6f7899f5c5-xxxxx 0/1     Init:0/1            0          5s
```

**In another terminal, watch model download progress:**
```bash
kubectl logs -n $NAMESPACE -l llm-d.ai/inferenceServing=true -f
```

**Expected log output:**
```
INFO: Downloading model from HuggingFace: google/gemma-2b-it
Downloading (…)okenizer_config.json: 100%|██████████| 1.17k/1.17k [00:00<00:00, 1.23MB/s]
Downloading (…)cial_tokens_map.json: 100%|██████████| 555/555 [00:00<00:00, 1.45MB/s]
...
INFO: Model loaded successfully
INFO: Starting vLLM server on port 8000
```

**Wait until all pods are 1/1 Running:**
```
NAME                                                  READY   STATUS    RESTARTS   AGE
gaie-pattern1-epp-6cdc8cfc4b-xxxxx                    1/1     Running   0          2m
ms-pattern1-llm-d-modelservice-decode-6f7899f5c5-xxxxx 1/1     Running   0          8m
```

Press **Ctrl+C** to stop watching.

✅ **Checkpoint:** llm-d deployed with Istio environment

---

### Step 6: Configure Gateway and HTTPRoute

**Purpose:** Connect Gateway to InferencePool for request routing

**Why it's cloud-agnostic:** Uses standard Gateway API `HTTPRoute` resource.

#### 6.1 Apply HTTPRoute Manifest

```bash
# Apply HTTPRoute manifest
kubectl apply -f ~/../llm-d/guides/inference-scheduling/deployments/gateway-api/pattern1-baseline/manifests/httproute-pattern1.yaml -n $NAMESPACE
```

**Expected output:**
```
httproute.gateway.networking.k8s.io/llm-d-pattern1-inference-scheduling created
```

**What this does:**
- Creates HTTPRoute named `llm-d-pattern1-inference-scheduling`
- Attaches to Gateway: `infra-pattern1-inference-gateway`
- Routes all traffic (`/`) to InferencePool: `gaie-pattern1` on port **54321**
  - **Critical:** Must use port 54321 (InferencePool service port), not 8000 (vLLM target port)

#### 6.2 Get Istio Ingress Gateway External IP

```bash
# Get Istio ingress gateway external IP
export GATEWAY_IP=$(kubectl get svc istio-ingressgateway \
  -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Gateway IP: $GATEWAY_IP"
```

**Wait for external IP** (1-2 minutes):
If `GATEWAY_IP` is empty, wait for LoadBalancer to provision:
```bash
kubectl get svc istio-ingressgateway -n istio-system -w
```

**Expected output:**
```
NAME                   TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)
istio-ingressgateway   LoadBalancer   10.96.200.123   35.209.201.202   80:30080/TCP,443:30443/TCP
```

#### 6.3 Test Gateway Endpoints

**Health Check:**
```bash
curl http://$GATEWAY_IP/health
```

**Expected:** No output (200 OK) or empty response

**List Models:**
```bash
curl http://$GATEWAY_IP/v1/models
```

**Expected output:**
```json
{
  "object": "list",
  "data": [
    {
      "id": "google/gemma-2b-it",
      "object": "model",
      "created": 1738512000,
      "owned_by": "vllm",
      "max_model_len": 2048
    }
  ]
}
```

**Test Inference:**
```bash
curl -X POST http://$GATEWAY_IP/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemma-2b-it",
    "prompt": "What is Kubernetes?",
    "max_tokens": 50
  }'
```

**Expected output:**
```json
{
  "id": "cmpl-xxxxx",
  "object": "text_completion",
  "model": "google/gemma-2b-it",
  "choices": [{
    "text": "Kubernetes is an open-source container orchestration platform...",
    "index": 0,
    "finish_reason": "length"
  }],
  "usage": {
    "prompt_tokens": 5,
    "completion_tokens": 50,
    "total_tokens": 55
  }
}
```

✅ **Checkpoint:** Gateway and HTTPRoute configured successfully

---

### Step 7: Verify Cloud-Agnostic Deployment

**Purpose:** Confirm no cloud-specific dependencies exist

#### 7.1 Infrastructure Layer Check

```bash
# Verify Gateway uses Istio (not GKE Gateway)
kubectl get gateway infra-pattern1-inference-gateway -n $NAMESPACE -o yaml | grep gatewayClassName
```

**Expected:**
```yaml
  gatewayClassName: istio  # ✅ Cloud-agnostic (not gke-l7-regional-external-managed)
```

```bash
# Verify no GKE-specific annotations
kubectl get gateway infra-pattern1-inference-gateway -n $NAMESPACE -o yaml | grep "cloud.google.com"
```

**Expected:** No output (no GKE-specific annotations)

#### 7.2 Networking Layer Check

```bash
# Verify HTTPRoute uses standard Gateway API
kubectl get httproute -n $NAMESPACE -o yaml | grep "gateway.networking.k8s.io"
```

**Expected:**
```yaml
  apiVersion: gateway.networking.k8s.io/v1  # ✅ Standard Kubernetes API
```

```bash
# Verify load balancer is standard Kubernetes Service
kubectl get svc istio-ingressgateway -n istio-system -o yaml | grep "type:"
```

**Expected:**
```yaml
  type: LoadBalancer  # ✅ Standard Kubernetes Service type
```

#### 7.3 Application Layer Check

```bash
# Verify all deployments use standard Kubernetes resources
kubectl api-resources --verbs=list -o name | grep -E "(deployments|services|pods)" | xargs -I {} kubectl get {} -n $NAMESPACE
```

**All resources should use standard `apps/v1` and `v1` APIs**

#### 7.4 Portability Validation Checklist

- [ ] Gateway uses `istio` GatewayClass (not `gke-l7-regional-external-managed`)
- [ ] No proxy-only subnet created (Istio doesn't need it)
- [ ] No `networkservices.googleapis.com` API calls
- [ ] Load balancer is Istio ingress gateway (standard K8s Service type=LoadBalancer)
- [ ] GPU support via GPU Operator (not GKE auto-install)
- [ ] All Helm charts use standard Kubernetes resources
- [ ] InferencePool CRDs installed via kubectl (portable)

**Run verification script:**
```bash
cat > verify-portability.sh <<'EOF'
#!/bin/bash
echo "=== Portability Verification ==="

# Check 1: Gateway Class
echo -n "✓ Gateway uses Istio: "
kubectl get gateway infra-pattern1-inference-gateway -n llm-d -o jsonpath='{.spec.gatewayClassName}' | grep -q "istio" && echo "PASS" || echo "FAIL"

# Check 2: No GKE annotations
echo -n "✓ No GKE-specific annotations: "
kubectl get gateway infra-pattern1-inference-gateway -n llm-d -o yaml | grep -q "cloud.google.com" && echo "FAIL" || echo "PASS"

# Check 3: Standard LoadBalancer
echo -n "✓ Standard LoadBalancer: "
kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.type}' | grep -q "LoadBalancer" && echo "PASS" || echo "FAIL"

# Check 4: GPU Operator installed
echo -n "✓ GPU Operator deployed: "
kubectl get pods -n gpu-operator &> /dev/null && echo "PASS" || echo "FAIL (optional on GKE)"

echo "=== Verification Complete ==="
EOF

chmod +x verify-portability.sh
./verify-portability.sh
```

**Expected output:**
```
=== Portability Verification ===
✓ Gateway uses Istio: PASS
✓ No GKE-specific annotations: PASS
✓ Standard LoadBalancer: PASS
✓ GPU Operator deployed: PASS
=== Verification Complete ===
```

✅ **Success!** Your deployment is cloud-agnostic and ready for migration.

---

## Part 3: Testing & Validation

### Complete API Test Suite

**Set Gateway IP:**
```bash
export GATEWAY_IP=$(kubectl get svc istio-ingressgateway \
  -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

**Health Check:**
```bash
curl http://$GATEWAY_IP/health
# Expected: 200 OK
```

**List Models:**
```bash
curl http://$GATEWAY_IP/v1/models
# Expected: JSON with google/gemma-2b-it model
```

**Text Completion:**
```bash
curl -X POST http://$GATEWAY_IP/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemma-2b-it",
    "prompt": "Explain cloud-agnostic architecture in one sentence:",
    "max_tokens": 100,
    "temperature": 0.7
  }'
```

**Chat Completion:**
```bash
curl -X POST http://$GATEWAY_IP/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "google/gemma-2b-it",
    "messages": [
      {"role": "user", "content": "What are the benefits of using standard Kubernetes APIs?"}
    ],
    "max_tokens": 100
  }'
```

### Performance Baseline Verification

**Expected metrics for Pattern 1 (single replica, T4 GPU):**

| Metric | Expected Value | Measurement |
|--------|---------------|-------------|
| TTFT (Time to First Token) p50 | 300-800ms | First token latency |
| TPOT (Time per Output Token) p50 | 20-50ms | Per-token generation speed |
| Throughput | 500-1500 tokens/sec | Total tokens generated per second |
| Max concurrent requests | 10-20 | Depends on prompt/completion length |
| Success rate | >99% | Percentage of successful requests |

### Component Health Checks

**Check all pods:**
```bash
kubectl get pods -n $NAMESPACE
```

**Expected:**
```
NAME                                                  READY   STATUS    RESTARTS   AGE
gaie-pattern1-epp-6cdc8cfc4b-xxxxx                    1/1     Running   0          15m
ms-pattern1-llm-d-modelservice-decode-6f7899f5c5-xxxxx 1/1     Running   0          15m
```

**Check Gateway:**
```bash
kubectl get gateway -n $NAMESPACE -o wide
```

**Expected:**
```
NAME                              CLASS    ADDRESS          PROGRAMMED   AGE
infra-pattern1-inference-gateway  istio    35.209.201.202   True         20m
```

**Check InferencePool:**
```bash
kubectl get inferencepool -n $NAMESPACE
```

**Expected:**
```
NAME             AGE
gaie-pattern1    20m
```

**Verify intelligent routing:**
```bash
# View scheduler logs
kubectl logs -n $NAMESPACE -l inferencepool=gaie-pattern1-epp --tail=50
```

**Look for routing plugin initialization:**
```
INFO: Loading routing plugins:
  - prefix-cache-scorer (weight: 3)
  - kv-cache-utilization-scorer (weight: 2)
  - queue-scorer (weight: 2)
INFO: Scheduler initialized successfully
INFO: Handling ext-proc request for inference
```

---

## Part 4: Migration Readiness

### What Changes When Migrating to Other Clouds?

**Summary:** Only **Part 1 (cluster setup)** changes. **Part 2, 3, and 4 (all 59 deployment steps) remain identical.**

| Migration Target | Part 1 Changes | Part 2-4 Changes | Estimated Effort |
|------------------|----------------|------------------|------------------|
| **AWS EKS** | Replace `gcloud` with `eksctl` | None (identical) | **2 hours** |
| **Azure AKS** | Replace `gcloud` with `az` | None (identical) | **2 hours** |
| **Red Hat OpenShift** | Use OpenShift installer/ROSA | Minor (`kubectl` → `oc`) | **3 hours** |
| **Vanilla Kubernetes** | Use cluster provisioning tool | None (identical) | **2 hours** |

### Migrating to AWS EKS

#### What Changes (Part 1 Only)

**Replace GKE cluster creation:**
```diff
- # GKE cluster creation
- gcloud container clusters create $CLUSTER_NAME \
-   --zone $ZONE \
-   --machine-type n1-standard-4 \
-   --num-nodes 2 \
-   --project $PROJECT_ID

+ # EKS cluster creation
+ eksctl create cluster \
+   --name llm-d-cluster \
+   --region us-west-2 \
+   --nodegroup-name cpu-nodes \
+   --node-type m5.xlarge \
+   --nodes 2
```

**Replace GPU node pool creation:**
```diff
- # GKE GPU node pool
- gcloud container node-pools create nvidia-t4-pool \
-   --cluster $CLUSTER_NAME \
-   --zone $ZONE \
-   --machine-type n1-standard-4 \
-   --accelerator type=nvidia-tesla-t4,count=1 \
-   --num-nodes 1

+ # EKS GPU node group
+ eksctl create nodegroup \
+   --cluster llm-d-cluster \
+   --region us-west-2 \
+   --name gpu-nodes \
+   --node-type g4dn.xlarge \
+   --nodes 1 \
+   --nodes-min 0 \
+   --nodes-max 3
```

**What stays the same:**
- **Part 2:** All 7 steps (cert-manager, Istio, Gateway CRDs, GPU Operator, llm-d, HTTPRoute, verification)
- **Part 3:** Testing and validation
- **No code changes, no manifest changes, no Helm value changes**

**EKS-specific notes:**
- Set `driver.enabled=true` in GPU Operator (Step 4.3)
- Use `g4dn.xlarge` instance type (NVIDIA T4 GPU)
- LoadBalancer service provisions AWS NLB automatically

**Estimated migration effort:** 2 hours (cluster creation + testing)

### Migrating to Azure AKS

#### What Changes (Part 1 Only)

**Replace GKE cluster creation:**
```diff
- # GKE cluster creation
- gcloud container clusters create $CLUSTER_NAME ...

+ # AKS cluster creation
+ az aks create \
+   --name llm-d-cluster \
+   --resource-group llm-d-rg \
+   --location westus2 \
+   --node-count 2 \
+   --node-vm-size Standard_D4s_v3 \
+   --enable-node-public-ip
```

**Replace GPU node pool creation:**
```diff
- # GKE GPU node pool
- gcloud container node-pools create nvidia-t4-pool ...

+ # AKS GPU node pool
+ az aks nodepool add \
+   --cluster-name llm-d-cluster \
+   --resource-group llm-d-rg \
+   --name gpunodes \
+   --node-count 1 \
+   --node-vm-size Standard_NC6s_v3 \
+   --enable-cluster-autoscaler \
+   --min-count 0 --max-count 3
```

**What stays the same:**
- **Part 2:** All 7 steps (identical to GKE)
- **Part 3:** Testing and validation
- **No code changes, no manifest changes**

**AKS-specific notes:**
- Set `driver.enabled=true` in GPU Operator (Step 4.3)
- Use `Standard_NC6s_v3` VM size (NVIDIA V100 GPU) or `Standard_NC4as_T4_v3` (T4 GPU)
- LoadBalancer service provisions Azure Load Balancer automatically

**Estimated migration effort:** 2 hours

### Migrating to Red Hat OpenShift

#### What Changes

**Part 1: Cluster provisioning:**
```diff
- # GKE cluster creation
- gcloud container clusters create ...

+ # OpenShift cluster (example: ROSA on AWS)
+ rosa create cluster \
+   --cluster-name llm-d-cluster \
+   --region us-east-1 \
+   --compute-machine-type m5.xlarge \
+   --compute-nodes 2
```

**Part 2: Minor adjustments:**
```diff
- # Some kubectl commands become oc
- kubectl get pods

+ # OpenShift uses oc CLI (superset of kubectl)
+ oc get pods
```

**Istio installation (Step 2):**
```diff
- # Standard Istio via Helm
- helm install istio ...

+ # Use Red Hat Service Mesh Operator instead
+ # Install via OpenShift OperatorHub
+ # Deploy ServiceMeshControlPlane CR
```

**GPU Operator (Step 4):**
```diff
- # Community GPU Operator
- helm install gpu-operator nvidia/gpu-operator ...

+ # Use NVIDIA GPU Operator for OpenShift
+ # Install via OperatorHub
+ # Or use Red Hat-certified operator
```

**What stays the same:**
- **Part 2:** Most steps (cert-manager, Gateway CRDs, llm-d, HTTPRoute)
- **Part 3:** Testing and validation

**OpenShift-specific notes:**
- May need SecurityContextConstraints for vLLM pods
- Use Red Hat Service Mesh Operator (based on Istio)
- GPU Operator has OpenShift-specific version

**Estimated migration effort:** 3 hours

### Migrating to Vanilla Kubernetes

#### What Changes (Part 1 Only)

**Cluster provisioning (varies by tool):**
```bash
# Example: kubeadm on bare metal
kubeadm init --pod-network-cidr=10.244.0.0/16

# Example: kops on AWS
kops create cluster --name=llm-d.k8s.local --zones=us-west-2a

# Example: Rancher RKE
rke up --config cluster.yml
```

**GPU node setup:**
- Manually install NVIDIA drivers on GPU nodes
- Or rely on GPU Operator (Step 4) to install drivers

**What stays the same:**
- **Part 2:** All 7 steps (identical)
- **Part 3:** Testing and validation

**Vanilla K8s notes:**
- Set `driver.enabled=true` in GPU Operator (Step 4.3)
- LoadBalancer service requires MetalLB or cloud provider integration
- Ensure Kubernetes version 1.28.0+

**Estimated migration effort:** 2-4 hours (depending on cluster provisioning method)

### Migration Effort Summary

**Time breakdown for typical migration:**

| Phase | Duration | Notes |
|-------|----------|-------|
| **Cluster provisioning** | 30-60 min | Create new cluster with GPU nodes |
| **Deploy stack (Part 2)** | 0 min | **Identical commands, copy-paste** |
| **Testing (Part 3)** | 30 min | Verify endpoints and performance |
| **Documentation** | 30 min | Update runbooks and diagrams |
| **Total** | **2-3 hours** | No code changes required |

**Cost comparison:**

| Platform | Monthly Cost (Pattern 1, single GPU) | Notes |
|----------|--------------------------------------|-------|
| **GKE** | ~$605 | n1-standard-4 + T4 GPU |
| **EKS** | ~$580 | m5.xlarge + g4dn.xlarge |
| **AKS** | ~$620 | Standard_D4s_v3 + Standard_NC6s_v3 |
| **OpenShift** | ~$1,200+ | Includes ROSA management fees |
| **Bare Metal** | Hardware dependent | One-time hardware cost |

---

## Troubleshooting

### Gateway Not Getting External IP

**Symptom:** Istio ingress gateway service stuck in `<pending>` state

**Check:**
```bash
kubectl describe svc istio-ingressgateway -n istio-system
```

**Common causes:**

1. **Cloud provider doesn't support LoadBalancer**
   - **Fix (bare metal):** Install MetalLB
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml
   ```
   - **Fix (cloud):** Ensure cloud provider integration is enabled

2. **LoadBalancer quota exceeded (GKE/EKS/AKS)**
   - **Fix:** Request quota increase or delete unused LoadBalancers

3. **Network policy blocking**
   - **Fix:** Check firewall rules allow ingress traffic on ports 80/443

### Pod Stuck in Pending

**Symptom:** vLLM pod stuck in Pending state

**Check:**
```bash
kubectl describe pod -n $NAMESPACE -l llm-d.ai/inferenceServing=true
```

**Common causes:**

1. **No GPU available**
   ```
   Events:
     Warning  FailedScheduling  pod didn't trigger scale-up: 1 node(s) didn't match pod's node affinity/selector
   ```
   **Fix:** Scale up GPU node pool (see Part 1 for your cloud)

2. **GPU Operator not ready**
   ```bash
   kubectl get pods -n gpu-operator
   ```
   **Fix:** Wait for GPU Operator to complete installation (3-5 minutes)

### Model Download Fails (403/404)

**Symptom:** vLLM pod CrashLoopBackOff, logs show HuggingFace errors

**Check logs:**
```bash
kubectl logs -n $NAMESPACE -l llm-d.ai/inferenceServing=true
```

**Common errors:**
```
HTTPError: 401 Client Error: Unauthorized for url: https://huggingface.co/google/gemma-2b-it/...
```

**Fix:**
```bash
# Verify secret exists
kubectl get secret huggingface-token -n $NAMESPACE

# Recreate if needed
kubectl delete secret huggingface-token -n $NAMESPACE
kubectl create secret generic huggingface-token \
  --from-literal=token=$HF_TOKEN \
  --namespace $NAMESPACE

# Restart deployment
kubectl rollout restart deployment ms-pattern1-llm-d-modelservice-decode -n $NAMESPACE
```

### HTTPRoute Not Routing (404/502)

**Symptom:** Gateway has IP but requests return 404 or 502

**Check HTTPRoute status:**
```bash
kubectl describe httproute llm-d-pattern1-inference-scheduling -n $NAMESPACE
```

**Common causes:**

1. **Wrong backend port**
   ```yaml
   # WRONG - vLLM target port
   port: 8000

   # CORRECT - InferencePool service port
   port: 54321
   ```
   **Fix:** Apply correct HTTPRoute from Step 6.1

2. **Backend not ready**
   ```bash
   kubectl get pods -n $NAMESPACE
   ```
   **Fix:** Wait for vLLM pod to be 1/1 Running

3. **Gateway not programmed**
   ```bash
   kubectl get gateway -n $NAMESPACE
   ```
   **Fix:** Wait for PROGRAMMED status to be "True"

### Istio Ingress Gateway Issues

**Symptom:** Istio gateway pod not starting

**Check:**
```bash
kubectl logs -n istio-system -l app=istio-ingressgateway
```

**Common causes:**

1. **Port conflict**
   - **Fix:** Ensure ports 80/443 are not used by other services

2. **cert-manager not ready**
   ```bash
   kubectl get pods -n cert-manager
   ```
   **Fix:** Wait for cert-manager to be Running (Step 1)

### Red Hat Operator Issues

#### ImagePullBackOff with registry.redhat.io

**Symptom:** Pods fail with `ImagePullBackOff` or `ErrImagePull`

**Check logs:**
```bash
kubectl describe pod <pod-name> -n <namespace>
```

**Error message:**
```
Failed to pull image "registry.redhat.io/...": unauthorized: authentication required
```

**Fix:**
```bash
# Verify pull secret exists
cat ~/.config/containers/auth.json

# Re-download if needed
# 1. Go to https://console.redhat.com/openshift/install/pull-secret
# 2. Download pull secret
# 3. Save to ~/.config/containers/auth.json

# Test authentication
podman pull registry.redhat.io/ubi8/ubi-minimal --quiet && echo "OK"
```

#### Meta Helmfile Deployment Fails

**Symptom:** `make deploy` fails with helm errors

**Check:**
```bash
# Ensure helmfile is installed
helmfile --version

# Check if operators already exist
kubectl get pods -n cert-manager-operator
kubectl get pods -n istio-system
kubectl get pods -n openshift-lws-operator
```

**Fix:**
```bash
# Clean up existing deployments first
make undeploy

# Redeploy
make deploy-all
```

---

## Cost Comparison

### Monthly Cost Estimates (Pattern 1, 24/7)

| Cloud | Configuration | Monthly Cost | Notes |
|-------|--------------|--------------|-------|
| **GKE** | 2x n1-standard-4 + 1x T4 GPU | ~$605 | Includes GKE management fee |
| **EKS** | 2x m5.xlarge + 1x g4dn.xlarge | ~$580 | Includes EKS control plane ($73/month) |
| **AKS** | 2x D4s_v3 + 1x NC6s_v3 (V100) | ~$1,200 | V100 more expensive than T4 |
| **AKS** | 2x D4s_v3 + 1x NC4as_T4_v3 (T4) | ~$620 | T4 option similar to GKE |
| **OpenShift (ROSA)** | Similar to EKS | ~$1,200+ | Includes Red Hat support |
| **Bare Metal** | One-time hardware cost | $0/month | Sunk cost, electricity only |

### Cost Optimization Strategies

**Scale to zero when idle:**
```bash
# Scale deployments to 0 replicas
kubectl scale deployment --all -n $NAMESPACE --replicas=0

# Scale GPU nodes to 0 (cloud-specific)
# GKE:
gcloud container clusters resize $CLUSTER_NAME --node-pool nvidia-t4-pool --num-nodes 0 --zone $ZONE

# EKS:
eksctl scale nodegroup --cluster llm-d-cluster --name gpu-nodes --nodes 0

# AKS:
az aks nodepool scale --cluster-name llm-d-cluster --resource-group llm-d-rg --name gpunodes --node-count 0
```

**Idle cost (just control plane):**
- GKE: ~$100/month
- EKS: ~$150/month (control plane + 1 CPU node)
- AKS: ~$120/month

**Savings:** ~70% when idle

---

## Appendix

### A. Portability Checklist

Use this checklist to verify your deployment is cloud-agnostic:

#### Infrastructure Layer
- [ ] No cloud-specific GatewayClass (no `gke-l7-regional-external-managed`, `alb`, `azure-application-gateway`)
- [ ] No cloud-specific subnet creation (no proxy-only subnet, no AWS subnets)
- [ ] No cloud-specific APIs enabled (no `networkservices.googleapis.com`, no AWS-specific APIs)
- [ ] No cloud-specific `gcloud`/`aws`/`az` commands in operational procedures

#### Networking Layer
- [ ] Gateway uses `istio` GatewayClass (portable)
- [ ] HTTPRoute uses standard `gateway.networking.k8s.io/v1` API
- [ ] Load balancer is Istio ingress gateway (standard K8s Service type=LoadBalancer)
- [ ] No cloud-specific ingress controllers (no GKE Ingress, no AWS ALB Ingress)

#### Compute Layer
- [ ] GPU support via GPU Operator (not cloud auto-install)
- [ ] Node selection via labels/taints (not cloud-specific node pools)
- [ ] No cloud-specific node provisioning in operational procedures

#### Application Layer
- [ ] Helm charts use standard Kubernetes resources
- [ ] Deployments use `apps/v1` API
- [ ] Services use `v1` API
- [ ] InferencePool CRDs installed via kubectl (portable)

#### Observability Layer
- [ ] Metrics exposed via standard Prometheus endpoints
- [ ] Logs collected via standard Kubernetes logging
- [ ] No cloud-specific monitoring integrations (optional: can add later)

### B. Cloud-Specific Node Provisioning Reference

When migrating, replace Part 1 cluster creation with:

#### GKE (Current)
```bash
# Create cluster
gcloud container clusters create llm-d-cluster --zone us-central1-a --machine-type n1-standard-4 --num-nodes 2

# Add GPU node pool
gcloud container node-pools create nvidia-t4-pool --cluster llm-d-cluster --zone us-central1-a --machine-type n1-standard-4 --accelerator type=nvidia-tesla-t4,count=1 --num-nodes 1
```

#### EKS
```bash
# Create cluster
eksctl create cluster --name llm-d-cluster --region us-west-2 --nodegroup-name cpu-nodes --node-type m5.xlarge --nodes 2

# Add GPU node group
eksctl create nodegroup --cluster llm-d-cluster --region us-west-2 --name gpu-nodes --node-type g4dn.xlarge --nodes 1 --nodes-min 0 --nodes-max 3
```

#### AKS
```bash
# Create resource group
az group create --name llm-d-rg --location westus2

# Create cluster
az aks create --name llm-d-cluster --resource-group llm-d-rg --node-count 2 --node-vm-size Standard_D4s_v3

# Add GPU node pool
az aks nodepool add --cluster-name llm-d-cluster --resource-group llm-d-rg --name gpunodes --node-count 1 --node-vm-size Standard_NC4as_T4_v3 --enable-cluster-autoscaler --min-count 0 --max-count 3
```

#### OpenShift (ROSA on AWS)
```bash
# Create ROSA cluster
rosa create cluster --cluster-name llm-d-cluster --region us-east-1 --compute-machine-type m5.xlarge --compute-nodes 2

# Add GPU machine pool
rosa create machinepool --cluster llm-d-cluster --name gpu-pool --instance-type g4dn.xlarge --replicas 1 --enable-autoscaling --min-replicas 0 --max-replicas 3
```

### C. Alternative Gateway Providers

If Istio doesn't fit your requirements, these Gateway API providers also work:

| Provider | Cloud Support | Notes |
|----------|---------------|-------|
| **Istio** | All | Recommended (this guide) |
| **Kong Gateway** | All | API management focus |
| **NGINX Gateway Fabric** | All | NGINX-based |
| **Envoy Gateway** | All | CNCF project |
| **Traefik** | All | Edge router |

**To use alternative provider:**
1. Replace Step 2 (Istio installation) with your provider
2. Change `gatewayClassName` in helmfile:
   ```bash
   helmfile -e istio apply  # Original
   helmfile -e <provider> apply  # Alternative (if supported by llm-d)
   ```

### D. References

**llm-d Documentation:**
- [llm-d Official Website](https://llm-d.ai/)
- [llm-d GitHub Repository](https://github.com/llm-d/llm-d)
- [llm-d GKE Infrastructure Provider Guide](https://llm-d.ai/docs/guide/InfraProviders/gke)
- [Inference Scheduling Guide](https://github.com/llm-d/llm-d/tree/main/guides/inference-scheduling)

**Gateway API:**
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/)

**Istio:**
- [Istio Documentation](https://istio.io/latest/docs/)
- [Sail Operator (Red Hat)](https://github.com/istio-ecosystem/sail-operator)

**vLLM:**
- [vLLM Documentation](https://docs.vllm.ai/)
- [vLLM Grafana Dashboard](https://grafana.com/grafana/dashboards/23991-vllm/)

**NVIDIA GPU Operator:**
- [GPU Operator Documentation](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/)
- [GPU Operator Helm Chart](https://github.com/NVIDIA/gpu-operator)

**Cloud Kubernetes Services:**
- [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine)
- [Amazon Elastic Kubernetes Service (EKS)](https://aws.amazon.com/eks/)
- [Azure Kubernetes Service (AKS)](https://azure.microsoft.com/en-us/products/kubernetes-service)
- [Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)

### E. Red Hat Operator Deployment Reference

#### Quick Reference: llm-d-infra-xks Meta Helmfile

**Repository:** https://github.com/aneeshkp/llm-d-infra-xks

| Command | Description |
|---------|-------------|
| `make deploy` | Deploy cert-manager + Istio |
| `make deploy-all` | Deploy all 3 operators (cert-manager + Istio + LWS) |
| `make deploy-cert-manager` | Deploy only cert-manager operator |
| `make deploy-istio` | Deploy only sail-operator (Istio) |
| `make deploy-lws` | Deploy only lws-operator |
| `make undeploy` | Remove all operators |
| `make status` | Show deployment status |

#### Individual Operator Chart Repositories

| Operator | Namespace | Repository | Deploy Command | Test Command |
|----------|-----------|------------|----------------|--------------|
| cert-manager | cert-manager-operator | https://github.com/aneeshkp/cert-manager-operator-chart | `make deploy` | `make test` |
| sail-operator | istio-system | https://github.com/aneeshkp/sail-operator-chart | `make deploy` | `make test` |
| lws-operator | openshift-lws-operator | https://github.com/aneeshkp/lws-operator-chart | `make deploy` | `make test` |

#### Red Hat Registry Images

| Component | Image |
|-----------|-------|
| cert-manager-operator | `registry.redhat.io/cert-manager/cert-manager-operator-rhel9` |
| cert-manager | `registry.redhat.io/cert-manager/cert-manager-rhel9` |
| sail-operator | `registry.redhat.io/openshift-service-mesh/servicemesh-operator3-rhel9` |
| Istio control plane | `registry.redhat.io/openshift-service-mesh/pilot-rhel9` |
| Istio proxy | `registry.redhat.io/openshift-service-mesh/istio-proxyv2-rhel9` |
| lws-operator | `registry.redhat.io/openshift-lws-operator/lws-operator-rhel9` |

#### Cleanup Red Hat Operators

```bash
# Cleanup all operators (in reverse order)
cd ~/llm-d-infra-xks
make undeploy

# Or cleanup individually
cd ~/lws-operator-chart && make undeploy
cd ~/sail-operator-chart && make undeploy
cd ~/cert-manager-operator-chart && make undeploy
```

#### Makefile Targets (Common Across All Operator Charts)

All operator charts support these Makefile targets:
- `make deploy` - Deploy operator and wait for readiness
- `make undeploy` - Remove operator
- `make test` - Run integration tests
- `make help` - Show all available targets

---

**Document Version:** 1.0.0
**Last Updated:** 2026-02-03
**Tested On:**
- GKE 1.33.5-gke.2019000
- Istio 1.24.1
- llm-d 1.2.0
- Gateway API Inference Extension v1.2.0

**Author:** Cloud-Agnostic LLM Deployment Guide
**License:** This documentation is provided as-is for educational and deployment purposes.
