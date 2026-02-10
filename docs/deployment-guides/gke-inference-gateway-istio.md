# GKE LLM Inference with Inference Gateway and Istio
## End-to-End Deployment Guide: Gateway API + Istio + llm-d Pattern 1

**Production-grade LLM inference on Google Kubernetes Engine with intelligent routing**

---

## Table of Contents

1. [Introduction](#introduction)
2. [Step 1: Create GKE Cluster with GPU Support](#step-1-create-gke-cluster-with-gpu-support)
3. [Step 2: Deploy cert-manager Operator](#step-2-deploy-cert-manager-operator)
4. [Step 3: Deploy Sail Operator (Istio)](#step-3-deploy-sail-operator-istio)
5. [Step 4: Deploy LWS Operator](#step-4-deploy-lws-operator)
6. [Step 5: Verify All Operators](#step-5-verify-all-operators)
7. [Step 6: Enable GKE Inference Gateway](#step-6-enable-gke-inference-gateway)
8. [Step 7: Deploy Pattern 1 (Single Replica LLM)](#step-7-deploy-pattern-1-single-replica-llm)
9. [Step 8: Post-Deployment Gateway Fix](#step-8-post-deployment-gateway-fix)
10. [Testing & Validation](#testing--validation)
11. [Troubleshooting](#troubleshooting)
12. [Cost Management](#cost-management)
13. [Next Steps](#next-steps)
14. [Appendix: TPU Deployment Alternative](#appendix-tpu-deployment-alternative)

---

## Introduction

### What You'll Build

This guide deploys a complete LLM inference stack on Google Kubernetes Engine (GKE) featuring:

- **GKE Inference Gateway** - Kubernetes Gateway API with Inference Extensions (InferencePool CRDs, EPP intelligent routing)
- **Istio Gateway** - Service mesh integration via sail-operator for advanced traffic management
- **llm-d Pattern 1** - Single-replica vLLM deployment with intelligent request scheduling

### Architecture

```
Internet → GKE External ALB → Istio Gateway → InferencePool (EPP) → vLLM Pod
                                                    ↓
                                       Intelligent routing based on:
                                       - Queue depth scoring
                                       - KV cache utilization
                                       - Prefix cache hit optimization
```

**Key Components:**

| Component | Purpose | Technology |
|-----------|---------|------------|
| **GKE Gateway** | Regional external Application Load Balancer | Gateway API v1 |
| **InferencePool** | Intelligent endpoint selection | Gateway API Inference Extension |
| **EPP (Endpoint Picker)** | Request router with metric-based scoring | ext-proc gRPC service |
| **Istio Gateway** | Service mesh gateway | Sail Operator (Red Hat) |
| **vLLM** | Model serving engine | vLLM 0.6.3 + NVIDIA CUDA |
| **Model** | LLM model | google/gemma-2b-it (2B params) |

### Technology Stack Overview

**GKE Inference Gateway**
- **What it is:** Kubernetes Gateway API + Gateway API Inference Extensions
- **Components:**
  - `InferencePool` CRD - manages intelligent endpoint selection
  - EPP (Endpoint Picker) - routes requests based on queue depth, KV cache, prefix cache
  - Gateway API Inference Extension spec from gateway-api-inference-extension.sigs.k8s.io
- **Why:** Native Kubernetes LLM inference routing without custom load balancers

**Istio Gateway**
- **What it is:** Service mesh gateway from Istio project
- **Deployment:** Via sail-operator (Red Hat's Istio operator)
- **Integration:** Works with GKE Gateway API for L7 traffic management
- **Why:** Production-grade traffic control, observability, security

**llm-d (LLM-D)**
- **What it is:** Kubernetes-native distributed LLM inference framework
- **Pattern 1:** Single-replica baseline deployment
- **Intelligence:** Prefix cache-aware routing, KV cache optimization
- **Why:** Production LLM inference with intelligent scheduling

### Operator Deployment Options

This guide supports two approaches for deploying the required operators (cert-manager, Istio/sail-operator, LWS):

#### **Option A: Upstream Operators** (Default)
- **Source:** Community-maintained from jetstack, istio-ecosystem, kubernetes-sigs
- **Deployment:** Individual Helm charts for each operator
- **Benefits:**
  - ✅ Free and open-source
  - ✅ Maximum portability across all Kubernetes distributions
  - ✅ Community support and wide adoption
  - ✅ Latest upstream features
- **Best for:** Development, testing, maximum flexibility

#### **Option B: Red Hat Operators via llm-d-infra-xks** (Enterprise)
- **Source:** Red Hat-certified operators from registry.redhat.io
- **Deployment:** Single meta helmfile deploys all operators at once
- **Benefits:**
  - ✅ Enterprise support from Red Hat
  - ✅ Red Hat-certified container images
  - ✅ Faster deployment (single `helmfile apply` command)
  - ✅ Integrated with OpenShift ecosystem
  - ⚠️ Requires Red Hat pull secret (free with developer account)
- **Best for:** Production, enterprises with Red Hat subscriptions

**Architecturally identical:** Both options result in the same Istio service mesh, cert-manager, and LWS functionality. The choice is about operational preference (community vs enterprise support) and deployment speed.

**llm-d-infra-xks Architecture:**
```
llm-d-infra-xks (meta helmfile)
    ├── cert-manager-operator → cert-manager components
    ├── sail-operator → Istio control plane (istiod)
    └── lws-operator → LeaderWorkerSet controller
```

**Repository:** https://github.com/aneeshkp/llm-d-infra-xks

**Red Hat Registry Images:**
- cert-manager: `registry.redhat.io/cert-manager/cert-manager-operator-rhel9`
- Istio: `registry.redhat.io/openshift-service-mesh/servicemesh-operator3-rhel9`
- LWS: `registry.redhat.io/openshift-lws-operator/lws-operator-rhel9`

### Prerequisites

Before starting, ensure you have:

**Required Tools (local machine):**
- `gcloud` CLI (Google Cloud SDK) - [Install](https://cloud.google.com/sdk/docs/install)
- `kubectl` v1.28.0+ - Kubernetes CLI
- `helm` v3.12.0+ - Kubernetes package manager
- `helmfile` v1.1.0+ - Helm orchestration tool
- `git` v2.30.0+ - Version control

**GCP Access:**
- GCP project with billing enabled
- IAM roles on your account:
  - `roles/container.admin` (required for RBAC and cluster management)
  - `roles/editor` or `roles/owner` (for resource creation)

**Credentials:**
- **HuggingFace Token** - From https://huggingface.co/settings/tokens
  - Needed for downloading model (google/gemma-2b-it is public, any valid token works)
- **Red Hat Pull Secret** (Optional - for Red Hat operator deployment)
  - From https://console.redhat.com/openshift/install/pull-secret
  - Required if using Red Hat-certified operators (Step 0 shows alternative deployment)
  - Free with Red Hat developer account

### Expected Outcomes

By the end of this guide, you will have:

1. ✅ GKE cluster with GPU support (NVIDIA T4)
2. ✅ Istio service mesh deployed via sail-operator
3. ✅ GKE Inference Gateway with InferencePool CRDs
4. ✅ llm-d Pattern 1 serving google/gemma-2b-it
5. ✅ Working inference API at `http://<GATEWAY-IP>/v1/completions`
6. ✅ Intelligent routing with EPP (Endpoint Picker)
7. ✅ Performance baseline for scaling to Pattern 2/3

**Total time:** Approximately 45 minutes

---

## Step 1: Create GKE Cluster with GPU Support

**Duration:** ~10 minutes
**Goal:** Create a GKE cluster with CPU nodes and GPU node pool for running vLLM

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

> **Note:** GKE automatically installs NVIDIA GPU drivers when you create a GPU node pool. **DO NOT** install the GPU Operator manually.

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

## Step 0: Configure Red Hat Pull Secret (Optional)

**Duration:** ~2 minutes
**Goal:** Configure authentication for Red Hat registry (required for Red Hat operator deployment option)

> **Note:** This step is **only required** if you plan to use the Red Hat operator deployment approach (Option B) shown in Steps 2-4. If using upstream operators (Option A), skip to Step 2.

### Deployment Approach Choice

You can deploy the required operators using two approaches:

#### **Option A: Upstream Operators** (Default in this guide)
- Deploy each operator individually using official Helm charts
- Uses community-supported versions from jetstack, istio.io, kubernetes-sigs
- ✅ Free and open-source
- ✅ Maximum portability
- ✅ Community support

#### **Option B: Red Hat Operators via llm-d-infra-xks** (Enterprise)
- Deploy all operators at once using meta helmfile
- Uses Red Hat-certified operators from registry.redhat.io
- ✅ Enterprise support from Red Hat
- ✅ Red Hat-certified images
- ✅ Faster deployment (single command)
- ⚠️ Requires Red Hat pull secret

---

### 0.1 Download Red Hat Pull Secret

1. Go to: https://console.redhat.com/openshift/install/pull-secret
2. Login with your Red Hat account (free developer account works)
3. Click "Download pull secret"
4. Save as `~/pull-secret.txt`

### 0.2 Configure Pull Secret for Container Runtime

```bash
# Create persistent location
mkdir -p ~/.config/containers
cp ~/pull-secret.txt ~/.config/containers/auth.json
```

### 0.3 Verify Pull Secret

```bash
# Test pulling a Red Hat image
podman pull registry.redhat.io/ubi8/ubi-minimal --quiet && echo "✅ Pull secret OK"
```

**Expected output:** `✅ Pull secret OK`

### 0.4 (Optional) Quick Deploy All Operators

If using Red Hat operator approach (Option B), you can deploy all operators at once:

```bash
# Clone llm-d-infra-xks meta helmfile repository
git clone https://github.com/aneeshkp/llm-d-infra-xks.git
cd llm-d-infra-xks

# Deploy all 3 operators (cert-manager + Istio + LWS)
helmfile apply

# Verify deployment
kubectl get pods -n cert-manager-operator
kubectl get pods -n cert-manager
kubectl get pods -n istio-system
kubectl get pods -n openshift-lws-operator
```

**Expected:** All pods Running (1-2 minutes)

**If you used this quick deploy method, skip to [Step 5](#step-5-verify-all-operators)**.

Otherwise, continue with Step 2 to deploy operators individually.

✅ **Checkpoint:** Red Hat pull secret configured (if using Red Hat operators)

---

## Step 2: Deploy cert-manager Operator

**Duration:** ~3 minutes
**Goal:** Deploy cert-manager for TLS certificate management (required by Istio)

**Choose your deployment approach:**
- **Option A:** Upstream cert-manager (Jetstack) - Community-supported, maximum portability
- **Option B:** Red Hat cert-manager Operator - Enterprise support, requires Red Hat pull secret

---

### Option A: Upstream cert-manager (Jetstack)

#### 2A.1 Add Helm Repository

```bash
# Add jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

#### 2A.2 Create cert-manager Namespace

```bash
kubectl create namespace cert-manager
```

#### 2A.3 Install cert-manager CRDs

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

#### 2A.4 Deploy cert-manager with Helm

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

#### 2A.5 Verify Deployment

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

### Option B: Red Hat cert-manager Operator (llm-d-infra-xks)

> **Prerequisites:** Completed [Step 0](#step-0-configure-red-hat-pull-secret-optional) (Red Hat pull secret configured)

#### 2B.1 Clone llm-d-infra-xks Repository

```bash
# Clone meta helmfile repository
cd ~
git clone https://github.com/aneeshkp/llm-d-infra-xks.git
cd llm-d-infra-xks
```

#### 2B.2 Deploy cert-manager Operator

```bash
# Deploy using helmfile
helmfile apply --selector name=cert-manager-operator
```

**What this does:**
- Deploys cert-manager-operator in `cert-manager-operator` namespace
- Deploys cert-manager components in `cert-manager` namespace
- Installs all CRDs automatically via presync hooks
- Uses Red Hat registry images (`registry.redhat.io/cert-manager/*`)

**Expected output:**
```
Upgrading release=cert-manager-operator...
Release "cert-manager-operator" deployed successfully
```

#### 2B.3 Verify Deployment

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

---

✅ **Checkpoint:** cert-manager is deployed and ready (upstream or Red Hat operator)

---

## Step 3: Deploy Sail Operator (Istio)

**Duration:** ~5 minutes
**Goal:** Deploy Istio service mesh for advanced traffic management

**Choose your deployment approach:**
- **Option A:** Upstream Sail Operator - Community-supported from istio-ecosystem
- **Option B:** Red Hat Sail Operator - Enterprise support, requires Red Hat pull secret

---

### Option A: Upstream Sail Operator (istio-ecosystem)

#### 3A.1 Add Sail Operator Helm Repository

```bash
# Add sail-operator repository
helm repo add sail-operator https://istio-ecosystem.github.io/sail-operator
helm repo update
```

#### 3A.2 Create sail-operator Namespace

```bash
kubectl create namespace sail-operator
```

#### 3A.3 Install Sail Operator

```bash
# Deploy sail-operator
helm upgrade --install sail-operator sail-operator/sail-operator \
  --namespace sail-operator \
  --version 0.2.0 \
  --wait
```

**Expected output:**
```
Release "sail-operator" does not exist. Installing it now.
NAME: sail-operator
...
STATUS: deployed
```

#### 3A.4 Verify Operator Deployment

```bash
# Check operator pod is running
kubectl get pods -n sail-operator
```

**Expected output:**
```
NAME                             READY   STATUS    RESTARTS   AGE
sail-operator-5d8f97b46d-xxxxx   1/1     Running   0          2m
```

#### 3A.5 Deploy Istio Control Plane

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

**Expected output:**
```
istio.operator.istio.io/default created
```

#### 3A.6 Verify Istio Control Plane

```bash
# Wait for Istio control plane to be ready
kubectl get istio -n sail-operator
```

**Expected output:**
```
NAME      REVISIONS   READY   IN USE   ACTIVE REVISIONS   AGE
default   1           True    1        default            2m
```

```bash
# Check istiod deployment
kubectl get pods -n istio-system
```

**Expected output:**
```
NAME                      READY   STATUS    RESTARTS   AGE
istiod-7d6f9d4c8-xxxxx    1/1     Running   0          2m
```

**Wait until READY shows "True"** (approximately 2-3 minutes)

---

### Option B: Red Hat Sail Operator (llm-d-infra-xks)

> **Prerequisites:** Completed [Step 0](#step-0-configure-red-hat-pull-secret-optional) (Red Hat pull secret configured)

#### 3B.1 Deploy Using Meta Helmfile

```bash
# From llm-d-infra-xks directory (cloned in Step 2B)
cd ~/llm-d-infra-xks
helmfile apply --selector name=sail-operator
```

**What this does:**
- Deploys servicemesh-operator3 (Red Hat's sail-operator) in `istio-system` namespace
- Deploys Istio control plane (istiod)
- Installs all Istio CRDs automatically
- Uses Red Hat registry images (`registry.redhat.io/openshift-service-mesh/*`)

**Expected output:**
```
Upgrading release=sail-operator...
Release "sail-operator" deployed successfully
```

#### 3B.2 Verify Deployment

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

---

✅ **Checkpoint:** Istio service mesh is deployed (upstream or Red Hat operator)

---

## Step 4: Deploy LWS Operator

**Duration:** ~2 minutes
**Goal:** Deploy LeaderWorkerSet (LWS) operator for multi-pod coordination (required for advanced patterns)

> **Note:** This step is **optional** for Pattern 1 (single replica). Required for Pattern 4 (MoE) and Pattern 5 (P/D disaggregation).

**Choose your deployment approach:**
- **Option A:** Upstream LWS Operator - From kubernetes-sigs
- **Option B:** Red Hat LWS Operator - Enterprise support, requires Red Hat pull secret

---

### Option A: Upstream LWS Operator (kubernetes-sigs)

#### 4A.1 Install LWS CRDs

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

#### 4A.2 Verify LWS Operator

```bash
# Check LWS controller pod
kubectl get pods -n lws-system
```

**Expected output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
lws-controller-manager-5d7f97b46d-xxxxx   2/2     Running   0          1m
```

```bash
# Verify LeaderWorkerSet CRD is available
kubectl get crd leaderworkersets.leaderworkerset.x-k8s.io
```

**Expected output:**
```
NAME                                           CREATED AT
leaderworkersets.leaderworkerset.x-k8s.io      2025-02-03T...
```

---

### Option B: Red Hat LWS Operator (llm-d-infra-xks)

> **Prerequisites:** Completed [Step 0](#step-0-configure-red-hat-pull-secret-optional) (Red Hat pull secret configured)

#### 4B.1 Deploy Using Meta Helmfile

```bash
# From llm-d-infra-xks directory
cd ~/llm-d-infra-xks
helmfile apply --selector name=lws-operator
```

**What this does:**
- Deploys openshift-lws-operator in `openshift-lws-operator` namespace
- Deploys lws-controller-manager pods
- Installs LeaderWorkerSet CRD
- Uses Red Hat registry images (`registry.redhat.io/openshift-lws-operator/*`)

**Expected output:**
```
Upgrading release=lws-operator...
Release "lws-operator" deployed successfully
```

#### 4B.2 Verify Deployment

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

---

✅ **Checkpoint:** LWS operator is deployed and ready (upstream or Red Hat operator)

---

## Step 5: Verify All Operators

**Duration:** ~1 minute
**Goal:** Confirm all prerequisite operators are healthy before proceeding

### 5.1 Check All Operator Namespaces

```bash
# List all operator pods
kubectl get pods -A | grep -E "(cert-manager|sail-operator|istio-system|lws-system)"
```

**Expected output:**
```
cert-manager        cert-manager-5d7f97b46d-xxxxx             1/1     Running   0          10m
cert-manager        cert-manager-cainjector-69d885bf55-xxxxx  1/1     Running   0          10m
cert-manager        cert-manager-webhook-54754dcdfd-xxxxx     1/1     Running   0          10m
istio-system        istiod-7d6f9d4c8-xxxxx                    1/1     Running   0          7m
lws-system          lws-controller-manager-5d7f97b46d-xxxxx   2/2     Running   0          3m
sail-operator       sail-operator-5d8f97b46d-xxxxx            1/1     Running   0          8m
```

**All pods should be Running with READY status matching expected replicas**

### 5.2 Verify Custom Resources

```bash
# Check cert-manager CRDs
kubectl api-resources | grep cert-manager.io

# Check Istio CRDs
kubectl api-resources | grep istio.io

# Check LWS CRDs
kubectl api-resources | grep leaderworkerset
```

**You should see CRDs for certificates, gateways, virtualservices, and leaderworkersets**

✅ **Checkpoint:** All operators deployed successfully

---

## Step 6: Enable GKE Inference Gateway

**Duration:** ~5 minutes
**Goal:** Enable Gateway API on GKE cluster and install Inference Extension CRDs

### 6.1 Enable Gateway API on Cluster

```bash
# Enable Gateway API on GKE
gcloud container clusters update $CLUSTER_NAME \
  --gateway-api=standard \
  --zone $ZONE \
  --project $PROJECT_ID
```

**Expected output:**
```
Updating llm-d-cluster...
...
Updated [https://container.googleapis.com/v1/projects/.../clusters/llm-d-cluster].
```

**Wait:** ~2-3 minutes for update to complete

### 6.2 Enable Network Services API

```bash
# Enable Network Services API (required for ext-proc integration with EPP)
gcloud services enable networkservices.googleapis.com --project $PROJECT_ID
```

**Expected output:**
```
Operation "operations/acat.p2-123456789-..." finished successfully.
```

> **Note:** This API is critical for intelligent routing. Without it, you'll get "fault filter abort" errors when EPP tries to process requests.

### 6.3 Verify Gateway API Resources

```bash
# Wait for Gateway API to be available (takes 1-2 minutes)
sleep 60

# Check Gateway API resources
kubectl api-resources | grep gateway.networking.k8s.io
```

**Expected output:**
```
gatewayclasses    gc           gateway.networking.k8s.io/v1          false        GatewayClass
gateways          gtw          gateway.networking.k8s.io/v1          true         Gateway
httproutes                     gateway.networking.k8s.io/v1          true         HTTPRoute
referencegrants                gateway.networking.k8s.io/v1beta1     true         ReferenceGrant
```

### 6.4 Create Proxy-Only Subnet

GKE regional external Application Load Balancers require a dedicated proxy-only subnet.

```bash
# Create proxy-only subnet
gcloud compute networks subnets create proxy-only-subnet \
  --purpose=REGIONAL_MANAGED_PROXY \
  --role=ACTIVE \
  --region=$REGION \
  --network=default \
  --range=192.168.0.0/23 \
  --project=$PROJECT_ID
```

**Expected output:**
```
Created [https://www.googleapis.com/compute/v1/projects/.../regions/us-central1/subnetworks/proxy-only-subnet].
```

**Verify:**
```bash
gcloud compute networks subnets describe proxy-only-subnet \
  --region=$REGION \
  --project=$PROJECT_ID \
  --format="value(purpose,state)"
```

**Expected output:**
```
REGIONAL_MANAGED_PROXY
READY
```

> **Important:** Use IP range `192.168.0.0/23` (not `10.129.0.0/23`). Auto-mode VPCs reserve `10.128.0.0/9` for automatic subnets.

### 6.5 Install Gateway Provider CRDs

Clone llm-d repository and install Inference Extension CRDs:

```bash
# Clone llm-d repository
cd ~
git clone https://github.com/llm-d/llm-d.git
cd llm-d/guides/prereq/gateway-provider

# Install Gateway API Inference Extension CRDs
./install-gateway-provider-dependencies.sh
```

**Expected output:**
```
Installing Gateway API Inference Extension CRDs...
customresourcedefinition.apiextensions.k8s.io/inferencepools.inference.networking.k8s.io created
customresourcedefinition.apiextensions.k8s.io/inferenceobjectives.inference.networking.k8s.io created
```

### 6.6 Verify Inference Extension CRDs

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

**These CRDs enable:**
- **InferencePool** - Manages pools of inference endpoints with intelligent selection
- **InferenceObjective** - Defines routing objectives (load-aware, prefix-cache-aware)

✅ **Checkpoint:** GKE Inference Gateway is enabled with InferencePool CRDs

---

## Step 7: Deploy Pattern 1 (Single Replica LLM)

**Duration:** ~15 minutes
**Goal:** Deploy llm-d Pattern 1 with google/gemma-2b-it model

### 7.1 What is Pattern 1?

**Pattern 1** is the foundational llm-d deployment architecture:
- **Single replica** of vLLM serving one model (google/gemma-2b-it)
- **Intelligent routing** via EPP (Endpoint Picker)
- **Gateway API** integration for Kubernetes-native load balancing
- **Foundation** for advanced patterns (multi-model, scale-out, MoE)

**Architecture:**
```
Internet → Gateway (35.209.201.202:80)
              ↓
         HTTPRoute
              ↓
     GKE Load Balancer (ext-proc integration)
              ↓
     EPP Scheduler (gaie-pattern1-epp:9002) ← Intelligent routing plugins
              ↓ (gRPC ext-proc)
         InferencePool Backend (port 54321)
              ↓
         vLLM Pod (google/gemma-2b-it:8000)
```

**Intelligent Routing Plugins:**
1. **prefix-cache-scorer** (weight: 3) - Routes similar prompts to same backend for KV cache efficiency
2. **kv-cache-utilization-scorer** (weight: 2) - Balances based on cache usage
3. **queue-scorer** (weight: 2) - Routes based on request queue depth

### 7.2 Create Namespace and Secrets

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

### 7.3 Review llm-d Configuration

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

**View pattern1-overrides.yaml:**
```bash
cat ~/../llm-d/guides/inference-scheduling/ms-inference-scheduling/pattern1-overrides.yaml
```

**Key configuration:**
```yaml
modelArtifacts:
  uri: "hf://google/gemma-2b-it"
  name: "google/gemma-2b-it"
  size: 10Gi
  authSecretName: "huggingface-token"

decode:
  replicas: 1
  containers:
  - name: "vllm"
    args:
      - "--max-model-len"
      - "2048"          # Reduced from 4096 to fit T4 GPU
      - "--gpu-memory-utilization"
      - "0.85"          # Reduced from 0.90 to prevent OOM during CUDA graph capture
      - "--backend"
      - "xformers"      # T4 doesn't support FlashAttention-2
```

> **Note:** Context length is reduced to 2048 tokens (from 4096) to fit google/gemma-2b-it on T4 GPU (13.12 GiB). For longer contexts, use larger GPU (L4, A100) or enable quantization.

### 7.4 Deploy with Helmfile

```bash
# Set environment variables
export NAMESPACE="llm-d"
export RELEASE_NAME_POSTFIX="pattern1"

# Deploy all components (infra, gaie, modelservice)
helmfile -e gke -n $NAMESPACE apply
```

**What this deploys:**
1. **infra-pattern1** - Gateway infrastructure (Gateway resource, GatewayClass binding)
2. **gaie-pattern1** - EPP scheduler/router (InferencePool controller, ext-proc service)
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

### 7.5 Monitor Deployment

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

### 7.6 Configure HTTPRoute

Apply HTTPRoute to connect Gateway to InferencePool:

```bash
# Apply HTTPRoute manifest
kubectl apply -f ~/../llm-d/guides/inference-scheduling/patterns/pattern1-baseline/manifests/httproute-pattern1.yaml -n $NAMESPACE
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

**Verify HTTPRoute:**
```bash
kubectl get httproute -n $NAMESPACE
```

**Expected output:**
```
NAME                                    HOSTNAMES   AGE
llm-d-pattern1-inference-scheduling     ["*"]       10s
```

### 7.7 Force Gateway Reconciliation

Trigger Gateway to detect proxy-only subnet and provision load balancer:

```bash
# Annotate Gateway to force reconciliation
kubectl annotate gateway infra-pattern1-inference-gateway -n $NAMESPACE \
  force-reconcile="$(date +%s)" --overwrite
```

**Expected output:**
```
gateway.gateway.networking.k8s.io/infra-pattern1-inference-gateway annotated
```

**Wait for Gateway to provision** (2-3 minutes):
```bash
echo "Waiting for Gateway to provision..."
sleep 120

# Check Gateway status
kubectl get gateway infra-pattern1-inference-gateway -n $NAMESPACE -o wide
```

**Expected output:**
```
NAME                              CLASS                             ADDRESS          PROGRAMMED   AGE
infra-pattern1-inference-gateway  gke-l7-regional-external-managed  35.209.201.202   True         3m
```

**PROGRAMMED should be "True" and ADDRESS should show external IP**

If ADDRESS shows `<pending>`, wait another 60 seconds and check again.

### 7.8 Get Gateway IP and Test

```bash
# Get Gateway external IP
export GATEWAY_IP=$(kubectl get gateway infra-pattern1-inference-gateway \
  -n $NAMESPACE -o jsonpath='{.status.addresses[0].value}')

echo "Gateway IP: $GATEWAY_IP"
```

**Test health endpoint:**
```bash
curl http://$GATEWAY_IP/health
```

**Expected:** No output (200 OK) or empty response

**List models:**
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

**Test inference:**
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
    "text": "Kubernetes is an open-source container orchestration platform that automates deployment, scaling, and management of containerized applications...",
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

### 7.9 Verify Intelligent Routing

Check that EPP scheduler is actively routing requests:

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

**Check InferencePool status:**
```bash
kubectl get inferencepool -n $NAMESPACE -o yaml | grep -A10 status
```

**Expected:**
```yaml
status:
  backends:
  - address: 10.0.0.6:8000
    health: HEALTHY
    podName: ms-pattern1-llm-d-modelservice-decode-6f7899f5c5-xxxxx
```

✅ **Success!** Pattern 1 is fully operational with intelligent routing through EPP.

---

## Step 8: Post-Deployment Gateway Fix

**Duration:** ~2 minutes
**Goal:** Fix Istio gateway image pull permissions (optional, only if using Red Hat registry)

> **Note:** This step is only required if you're using Red Hat registry images. Skip if using upstream images.

### 8.1 Copy Pull Secret to istio-system

If you configured Red Hat registry pull secret:

```bash
# Copy pull secret from llm-d namespace to istio-system
kubectl get secret 11009103-jhull-svc-pull-secret -n $NAMESPACE -o yaml | \
  sed "s/namespace: $NAMESPACE/namespace: istio-system/" | \
  kubectl apply -f -
```

### 8.2 Patch Gateway ServiceAccount

```bash
# Patch Istio gateway ServiceAccount to use pull secret
kubectl patch serviceaccount istio-ingressgateway -n istio-system \
  -p '{"imagePullSecrets": [{"name": "11009103-jhull-svc-pull-secret"}]}'
```

### 8.3 Restart Gateway Pod

```bash
# Restart gateway pod to pick up new pull secret
kubectl rollout restart deployment istio-ingressgateway -n istio-system
```

✅ **Checkpoint:** Istio gateway can now pull images from Red Hat registry (if needed)

---

## Testing & Validation

### Complete API Test Suite

**Health Check:**
```bash
export GATEWAY_IP=$(kubectl get gateway infra-pattern1-inference-gateway \
  -n $NAMESPACE -o jsonpath='{.status.addresses[0].value}')

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
    "prompt": "Explain load-aware routing in one sentence:",
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
      {"role": "user", "content": "What are the benefits of prefix-cache-aware routing?"}
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
NAME                              CLASS                             ADDRESS          PROGRAMMED   AGE
infra-pattern1-inference-gateway  gke-l7-regional-external-managed  35.209.201.202   True         20m
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

**Check backend health (via GCP):**
```bash
# Get backend service name
kubectl get inferencepool gaie-pattern1 -n $NAMESPACE -o yaml | grep backendService

# Check health
gcloud compute backend-services get-health \
  <backend-service-name> \
  --region=$REGION \
  --project=$PROJECT_ID
```

**Expected:**
```
backend: https://www.googleapis.com/compute/v1/projects/.../zones/us-central1-a/instanceGroups/...
status:
  healthStatus:
  - healthState: HEALTHY
    ipAddress: 10.0.0.6
    port: 8000
```

---

## Troubleshooting

### Gateway Not Getting External IP

**Symptom:** Gateway stuck without external IP address

**Check:**
```bash
kubectl describe gateway infra-pattern1-inference-gateway -n $NAMESPACE
```

**Common causes:**
1. **Proxy-only subnet missing**
   ```bash
   gcloud compute networks subnets list --network=default --project=$PROJECT_ID \
     --filter="purpose:REGIONAL_MANAGED_PROXY"
   ```
   **Fix:** Create proxy-only subnet (Step 6.4)

2. **Network Services API not enabled**
   ```bash
   gcloud services list --enabled --project=$PROJECT_ID | grep networkservices
   ```
   **Fix:** Enable API (Step 6.2)

3. **Gateway API not enabled on cluster**
   ```bash
   gcloud container clusters describe $CLUSTER_NAME --zone=$ZONE --project=$PROJECT_ID \
     --format="value(addonsConfig.gatewayApiConfig.channel)"
   ```
   **Fix:** Should show "CHANNEL_STANDARD". If empty, run Step 6.1

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
   **Fix:** Scale up GPU node pool:
   ```bash
   gcloud container clusters resize $CLUSTER_NAME \
     --node-pool nvidia-t4-pool --num-nodes 1 \
     --zone $ZONE --project $PROJECT_ID
   ```

2. **Another pod using GPU**
   ```bash
   kubectl get pods -A | grep nvidia
   ```
   **Fix:** Delete or scale down conflicting pod

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

# Check secret content (token should be present)
kubectl get secret huggingface-token -n $NAMESPACE -o yaml

# Recreate if needed
kubectl delete secret huggingface-token -n $NAMESPACE
kubectl create secret generic huggingface-token \
  --from-literal=token=$HF_TOKEN \
  --namespace $NAMESPACE

# Restart deployment
kubectl rollout restart deployment ms-pattern1-llm-d-modelservice-decode -n $NAMESPACE
```

### "fault filter abort" Error

**Symptom:** Requests to Gateway fail with "fault filter abort" error

**Root cause:** Network Services API not enabled

**Fix:**
```bash
gcloud services enable networkservices.googleapis.com --project=$PROJECT_ID

# Force Gateway reconciliation
kubectl annotate gateway infra-pattern1-inference-gateway -n $NAMESPACE \
  force-reconcile="$(date +%s)" --overwrite

# Wait 2-3 minutes for load balancer to update
sleep 120
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
   **Fix:** Apply correct HTTPRoute from Step 7.6

2. **Backend not ready**
   ```bash
   kubectl get pods -n $NAMESPACE
   ```
   **Fix:** Wait for vLLM pod to be 1/1 Running

3. **InferencePool has no backends**
   ```bash
   kubectl describe inferencepool gaie-pattern1 -n $NAMESPACE
   ```
   **Fix:** Verify vLLM pod has label `llm-d.ai/inferenceServing: "true"`

### RBAC Permission Denied

**Symptom:** gaie-pattern1-epp pod fails with RBAC errors

**Error in logs:**
```
User "your-email@example.com" cannot create resource "clusterroles" in API group "rbac.authorization.k8s.io"
```

**Fix:** Ensure you have `roles/container.admin`:
```bash
# Check current roles
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:$(gcloud config get-value account)" \
  --format="table(bindings.role)"

# If missing, ask project admin to grant:
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:your-email@example.com" \
  --role="roles/container.admin"
```

---

## Cost Management

### Current Deployment Cost

**Hourly costs (Pattern 1 running):**
- 1x GPU node (n1-standard-4 + T4): ~$0.54/hour
- 2x CPU nodes (e2-standard-4): ~$0.27/hour
- GKE Gateway (regional external ALB): ~$0.025/hour
- **Total: ~$0.84/hour** (~$605/month if running 24/7)

### Scale to Zero (Idle)

When not using the deployment:

```bash
# Scale deployments to 0 replicas
kubectl scale deployment --all -n $NAMESPACE --replicas=0

# Scale GPU node pool to 0
gcloud container clusters resize $CLUSTER_NAME \
  --node-pool nvidia-t4-pool --num-nodes 0 \
  --zone $ZONE --project $PROJECT_ID

# Scale CPU nodes to 1 (keep control plane)
gcloud container clusters resize $CLUSTER_NAME \
  --node-pool default-pool --num-nodes 1 \
  --zone $ZONE --project $PROJECT_ID
```

**Idle cost:** ~$0.14/hour (~$100/month, just control plane + 1 CPU node)

**Savings:** ~$0.70/hour (~$505/month)

### Scale Back Up

When ready to use again:

```bash
# Scale GPU node pool to 1
gcloud container clusters resize $CLUSTER_NAME \
  --node-pool nvidia-t4-pool --num-nodes 1 \
  --zone $ZONE --project $PROJECT_ID

# Scale CPU nodes to 2
gcloud container clusters resize $CLUSTER_NAME \
  --node-pool default-pool --num-nodes 2 \
  --zone $ZONE --project $PROJECT_ID

# Wait for nodes to be ready (2-3 minutes)
kubectl get nodes -w

# Scale vLLM deployment to 1
kubectl scale deployment ms-pattern1-llm-d-modelservice-decode -n $NAMESPACE --replicas=1

# Scale EPP scheduler to 1
kubectl scale deployment gaie-pattern1-epp -n $NAMESPACE --replicas=1
```

### Full Cleanup

To completely remove the deployment:

```bash
# Delete llm-d deployment
helmfile -e gke -n $NAMESPACE destroy

# Delete namespace
kubectl delete namespace $NAMESPACE

# Delete cluster
gcloud container clusters delete $CLUSTER_NAME --zone $ZONE --project $PROJECT_ID

# Delete proxy-only subnet
gcloud compute networks subnets delete proxy-only-subnet --region=$REGION --project=$PROJECT_ID
```

---

## Next Steps

### 1. Benchmark Performance

Compare Gateway endpoint (with intelligent routing) vs direct LoadBalancer:

**If you created a direct LoadBalancer for comparison:**
```bash
# Test Gateway endpoint
export GATEWAY_IP=$(kubectl get gateway infra-pattern1-inference-gateway \
  -n $NAMESPACE -o jsonpath='{.status.addresses[0].value}')

# Example benchmark script (adjust to your tool)
for i in {1..100}; do
  curl -X POST http://$GATEWAY_IP/v1/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"google/gemma-2b-it\", \"prompt\": \"Test $i\", \"max_tokens\": 20}"
done
```

> **Note:** For single replica, performance is similar. Benefits of intelligent routing appear with multi-replica deployments (Pattern 3).

### 2. Pattern 2: Multi-Model Deployment

Deploy a second model alongside google/gemma-2b-it:

**Prerequisite:** Scale GPU node pool to 2
```bash
gcloud container clusters resize $CLUSTER_NAME \
  --node-pool nvidia-t4-pool --num-nodes 2 \
  --zone $ZONE --project $PROJECT_ID
```

**Deploy second model:**
```bash
# Example: Deploy microsoft/Phi-3-mini-4k-instruct
export RELEASE_NAME_POSTFIX="pattern2"

# Create custom values file for Phi-3
cat > pattern2-phi3-values.yaml <<EOF
modelArtifacts:
  uri: "hf://microsoft/Phi-3-mini-4k-instruct"
  name: "microsoft/Phi-3-mini-4k-instruct"
  authSecretName: "huggingface-token"

decode:
  replicas: 1
EOF

# Deploy with helmfile (using pattern2 postfix)
helmfile -e gke -n $NAMESPACE apply --set modelService.valuesFile=pattern2-phi3-values.yaml
```

**Test model selection:**
```bash
# Test google/gemma-2b-it
curl -X POST http://$GATEWAY_IP/v1/completions \
  -d '{"model": "google/gemma-2b-it", "prompt": "Hello", "max_tokens": 20}'

# Test microsoft/Phi-3-mini-4k-instruct
curl -X POST http://$GATEWAY_IP/v1/completions \
  -d '{"model": "microsoft/Phi-3-mini-4k-instruct", "prompt": "Hello", "max_tokens": 20}'
```

See [Pattern 2 documentation](https://github.com/llm-d/llm-d/tree/main/guides/inference-scheduling/pattern2) for header-based routing configuration.

### 3. Pattern 3: N/S-Caching Scale-Out

Scale to 3 replicas for higher throughput with prefix-cache-aware routing:

**Prerequisite:** Scale GPU node pool to 3
```bash
gcloud container clusters resize $CLUSTER_NAME \
  --node-pool nvidia-t4-pool --num-nodes 3 \
  --zone $ZONE --project $PROJECT_ID
```

**Scale vLLM deployment:**
```bash
# Scale to 3 replicas
kubectl scale deployment ms-pattern1-llm-d-modelservice-decode -n $NAMESPACE --replicas=3

# Wait for all replicas to be ready
kubectl get pods -n $NAMESPACE -l llm-d.ai/inferenceServing=true -w
```

**Verify InferencePool detects all backends:**
```bash
kubectl describe inferencepool gaie-pattern1 -n $NAMESPACE | grep -A20 backends
```

**Test concurrent requests:**
```bash
# Send 10 concurrent requests
for i in {1..10}; do
  curl -X POST http://$GATEWAY_IP/v1/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"google/gemma-2b-it\", \"prompt\": \"Request $i\", \"max_tokens\": 20}" &
done
wait
```

**Watch scheduler distribute load:**
```bash
kubectl logs -n $NAMESPACE -l inferencepool=gaie-pattern1-epp --tail=50
```

**Expected:** Requests distributed across 3 replicas based on queue depth, KV cache, and prefix cache state.

See [Pattern 3 documentation](https://github.com/llm-d/llm-d/tree/main/guides/inference-scheduling/pattern3) for N/S-caching configuration.

### 4. Monitoring with Prometheus & Grafana

**Access metrics endpoints directly:**
```bash
# EPP scheduler metrics (port 9090)
kubectl port-forward -n $NAMESPACE svc/gaie-pattern1-epp 9090:9090
curl http://localhost:9090/metrics | grep -E "(backend_health|request_count)"

# vLLM metrics (port 8000)
POD=$(kubectl get pods -n $NAMESPACE -l llm-d.ai/inferenceServing=true -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n $NAMESPACE $POD 8000:8000
curl http://localhost:8000/metrics | grep -E "(vllm:num_requests|kv_cache)"
```

**Key metrics to monitor:**
- `inference_pool_backend_health` - Backend availability
- `inference_pool_request_count` - Request routing count
- `vllm:num_requests_running` - Active inference requests
- `vllm:kv_cache_usage_perc` - KV cache utilization
- `vllm:e2e_request_latency_seconds` - End-to-end latency

**Optional: Deploy Prometheus + Grafana**

Use vLLM's official Grafana dashboard:
- Dashboard ID: 23991
- URL: https://grafana.com/grafana/dashboards/23991-vllm/

### 5. Explore Advanced Patterns

**Pattern 4: MoE with LeaderWorkerSet** (requires multi-node setup)
- Deploy Mixture of Experts models (DeepSeek-V3, Mixtral-8x7B)
- Configure data parallelism + expert parallelism
- Requires LeaderWorkerSet operator (already deployed in Step 4)

**Pattern 5: P/D Disaggregation** (prefill/decode separation)
- Deploy separate prefill pool (high throughput, batch optimization)
- Deploy separate decode pool (low latency, streaming)
- Enable KV cache transfer between phases
- **Benefits:** 40% TTFT reduction, better resource utilization

See [llm-d documentation](https://llm-d.ai/) for advanced pattern guides.

---

## Appendix: TPU Deployment Alternative

### TPU v6e Deployment Overview

For users with access to TPU v6e accelerators, Pattern 1 can be deployed on TPU instead of GPU.

**Key differences:**
- **Accelerator:** TPU v6e-1 (4 chips, 2x2 topology)
- **Model:** Qwen/Qwen2.5-3B-Instruct (3B params, better TPU fit)
- **Backend:** vLLM + JAX/XLA
- **Startup time:** 5-7 minutes (TPU initialization + XLA compilation)
- **Cost:** ~$3,760/month (significantly higher than GPU)

### TPU Deployment Steps

**1. Create TPU node pool:**
```bash
# Create TPU node pool in europe-west4-a
gcloud container node-pools create tpu-v6e-pool \
  --cluster $CLUSTER_NAME \
  --zone europe-west4-a \
  --machine-type ct6e-standard-4t \
  --num-nodes 1 \
  --project $PROJECT_ID
```

**2. Deploy with TPU environment:**
```bash
# Use gke_tpu environment instead of gke
helmfile -e gke_tpu -n $NAMESPACE apply
```

**3. Different proxy-only subnet:**
```bash
# TPU regions may require different subnet
gcloud compute networks subnets create proxy-only-subnet-tpu \
  --purpose=REGIONAL_MANAGED_PROXY \
  --role=ACTIVE \
  --region=europe-west4 \
  --network=default \
  --range=192.168.100.0/23 \
  --project=$PROJECT_ID
```

**4. XLA compilation on first request:**
- First inference request takes 60-120 seconds (XLA compilation)
- Subsequent requests are fast (~1-2 seconds)
- Expected p95 latency: ~500ms (after warmup)

For complete TPU deployment guide, see:
- [llm-d Pattern 1 TPU Setup](https://github.com/llm-d/llm-d/blob/main/guides/inference-scheduling/patterns/pattern1-baseline/docs/llm-d-tpu-setup.md)

---

## External Resources

**llm-d Documentation:**
- [llm-d Official Website](https://llm-d.ai/)
- [llm-d GitHub Repository](https://github.com/llm-d/llm-d)
- [Inference Scheduling Guide](https://github.com/llm-d/llm-d/tree/main/guides/inference-scheduling)

**Gateway API:**
- [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/)
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/)
- [GKE Gateway API Documentation](https://cloud.google.com/kubernetes-engine/docs/concepts/gateway-api)

**vLLM:**
- [vLLM Documentation](https://docs.vllm.ai/)
- [vLLM Grafana Dashboard](https://grafana.com/grafana/dashboards/23991-vllm/)

**GKE AI Resources:**
- [GKE AI Labs](https://gke-ai-labs.dev/)
- [AI on GKE GitHub](https://github.com/ai-on-gke)

---

**Last Updated:** 2026-02-03
**llm-d Version:** 1.2.0
**Gateway API Inference Extension Version:** v1.2.0
**Tested on:** GKE 1.33.5-gke.2019000
