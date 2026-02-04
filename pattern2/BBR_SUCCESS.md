# BBR (Body Based Router) Implementation - GPU Cluster SUCCESS

## Summary

**Status:** ✅ **WORKING** - BBR architecture successfully deployed on GPU cluster achieving 100% routing accuracy without retry logic.

**Date:** 2026-01-27
**Cluster:** nvidia-test-cluster (us-central1-a)
**Gateway IP:** 35.209.92.117
**Success Rate:** 20/20 (100%)

---

## Architecture Overview

BBR (Body Based Router) extracts the `"model"` field from request body JSON and injects it as HTTP headers for intelligent routing:

```
Client Request
  ↓ {"model": "microsoft/Phi-3-mini-4k-instruct", ...}
BBR (Body Based Router)
  ↓ Injects headers:
    - X-Gateway-Model-Name: microsoft/Phi-3-mini-4k-instruct
    - X-Gateway-Base-Model-Name: microsoft/Phi-3-mini-4k-instruct
HTTPRoute (Header Matching)
  ↓ Routes based on X-Gateway-Base-Model-Name
InferencePool (phi-pool or gemma-pool)
  ↓ Single backend per pool
Backend Pod
  ↓ Returns response
```

**Key Benefits:**
- ✅ 100% routing accuracy (no retry required)
- ✅ Deterministic routing based on request body
- ✅ Each model has dedicated InferencePool
- ✅ Simple client implementation (no retry logic)

---

## Critical Component: Model Allowlist ConfigMaps

**The Key to Success:** BBR requires ConfigMaps with `inference.networking.k8s.io/bbr-managed: "true"` label to map request model names to base model names.

**Without allowlist ConfigMaps:**
- BBR sets `X-Gateway-Base-Model-Name` header with **EMPTY VALUE**
- HTTPRoute header matching fails (requires exact value match)
- All requests return 404 "fault filter abort"

**With allowlist ConfigMaps:**
- BBR populates `X-Gateway-Base-Model-Name` with actual model name
- HTTPRoute matches header value and routes correctly
- 100% success rate

### Allowlist ConfigMap Structure

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: phi-allowlist
  namespace: llm-d
  labels:
    inference.networking.k8s.io/bbr-managed: "true"  # ← CRITICAL LABEL
data:
  baseModel: "microsoft/Phi-3-mini-4k-instruct"
  adapters: |
    # No adapters for base model
```

**BBR Discovery:**
- BBR watches for ConfigMaps with `inference.networking.k8s.io/bbr-managed: "true"` label
- Automatically reconciles when new allowlist ConfigMaps are created
- Uses `baseModel` field to populate `X-Gateway-Base-Model-Name` header

---

## Deployment Components

### 1. BBR Deployment with RBAC

**File:** `pattern2/manifests/bbr-deployment.yaml`

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: body-based-router
  namespace: llm-d
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: body-based-router
  namespace: llm-d
spec:
  replicas: 1
  selector:
    matchLabels:
      app: body-based-router
  template:
    metadata:
      labels:
        app: body-based-router
    spec:
      serviceAccountName: body-based-router
      containers:
      - name: bbr
        image: us-central1-docker.pkg.dev/k8s-staging-images/gateway-api-inference-extension/bbr:main
        args:
          - --streaming
          - --v
          - "5"
        ports:
        - containerPort: 9004
          name: ext-proc
        - containerPort: 9005
          name: health
---
apiVersion: v1
kind: Service
metadata:
  name: body-based-router
  namespace: llm-d
spec:
  type: ClusterIP
  selector:
    app: body-based-router
  ports:
  - name: ext-proc
    port: 9004
    targetPort: 9004
    protocol: TCP
    appProtocol: HTTP2  # ← CRITICAL for GKE Gateway acceptance
  - name: health
    port: 9005
    targetPort: 9005
    protocol: TCP
---
apiVersion: networking.gke.io/v1
kind: GCPRoutingExtension
metadata:
  name: body-based-router
  namespace: llm-d
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: infra-pattern2-inference-gateway
  extensionChains:
  - name: chain1
    extensions:
    - name: ext1
      authority: myext.com
      backendRef:
        kind: Service
        name: body-based-router
        port: 9004
      timeout: 1s
      requestBodySendMode: FullDuplexStreamed
      supportedEvents:
      - RequestHeaders
      - RequestBody
      - RequestTrailers
```

**RBAC Requirements:**

```bash
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: body-based-router-configmap-reader
  namespace: llm-d
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: body-based-router-configmap-reader
  namespace: llm-d
subjects:
- kind: ServiceAccount
  name: body-based-router
  namespace: llm-d
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: body-based-router-configmap-reader
EOF
```

### 2. Model Allowlist ConfigMaps

**File:** `pattern2/manifests/bbr-allowlists.yaml`

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: phi-allowlist
  namespace: llm-d
  labels:
    inference.networking.k8s.io/bbr-managed: "true"
data:
  baseModel: "microsoft/Phi-3-mini-4k-instruct"
  adapters: |
    # No adapters for base model

---
apiVersion: v1
kind: ConfigMap
metadata:
  name: gemma-allowlist
  namespace: llm-d
  labels:
    inference.networking.k8s.io/bbr-managed: "true"
data:
  baseModel: "google/gemma-2b-it"
  adapters: |
    # No adapters for base model
```

### 3. InferencePools (Separate per Model)

**File:** `pattern2/manifests/pattern2-bbr-gpu-working.yaml`

```yaml
---
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
metadata:
  name: phi-pool
  namespace: llm-d
spec:
  endpointPickerRef:
    failureMode: FailClose
    kind: Service
    name: gaie-pattern2-epp
    port:
      number: 9002
  selector:
    matchLabels:
      llm-d.ai/model-name: phi-3-mini  # Only Phi-3-mini pod
  targetPorts:
  - number: 8000

---
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
metadata:
  name: gemma-pool
  namespace: llm-d
spec:
  endpointPickerRef:
    failureMode: FailClose
    kind: Service
    name: gaie-pattern2-epp
    port:
      number: 9002
  selector:
    matchLabels:
      llm-d.ai/model-name: gemma-2b  # Only Gemma-2B pod
  targetPorts:
  - number: 8000
```

### 4. HTTPRoutes (Header-Based Matching)

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: phi-model-route
  namespace: llm-d
spec:
  parentRefs:
  - name: infra-pattern2-inference-gateway
    namespace: llm-d
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /v1/
      headers:
      - type: Exact
        name: X-Gateway-Base-Model-Name
        value: "microsoft/Phi-3-mini-4k-instruct"  # Matches BBR-injected header
    backendRefs:
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: phi-pool
      weight: 100

---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: gemma-model-route
  namespace: llm-d
spec:
  parentRefs:
  - name: infra-pattern2-inference-gateway
    namespace: llm-d
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /v1/
      headers:
      - type: Exact
        name: X-Gateway-Base-Model-Name
        value: "google/gemma-2b-it"  # Matches BBR-injected header
    backendRefs:
    - group: inference.networking.k8s.io
      kind: InferencePool
      name: gemma-pool
      weight: 100
```

### 5. HealthCheckPolicies

**File:** `pattern2/manifests/healthcheck-policies-gpu.yaml`

```yaml
---
apiVersion: networking.gke.io/v1
kind: HealthCheckPolicy
metadata:
  name: phi-pool-healthcheck
  namespace: llm-d
spec:
  default:
    checkIntervalSec: 15
    timeoutSec: 15
    healthyThreshold: 1
    unhealthyThreshold: 2
    config:
      type: HTTP
      httpHealthCheck:
        port: 8000
        requestPath: /health
  targetRef:
    group: inference.networking.k8s.io
    kind: InferencePool
    name: phi-pool

---
apiVersion: networking.gke.io/v1
kind: HealthCheckPolicy
metadata:
  name: gemma-pool-healthcheck
  namespace: llm-d
spec:
  default:
    checkIntervalSec: 15
    timeoutSec: 15
    healthyThreshold: 1
    unhealthyThreshold: 2
    config:
      type: HTTP
      httpHealthCheck:
        port: 8000
        requestPath: /health
  targetRef:
    group: inference.networking.k8s.io
    kind: InferencePool
    name: gemma-pool

---
apiVersion: networking.gke.io/v1
kind: HealthCheckPolicy
metadata:
  name: bbr-healthcheck
  namespace: llm-d
spec:
  default:
    config:
      type: GRPC
      grpcHealthCheck:
        port: 9005
        portSpecification: USE_FIXED_PORT
    logConfig:
      enabled: true
  targetRef:
    group: ""
    kind: Service
    name: body-based-router
```

---

## Deployment Procedure

### Step 1: Deploy BBR Component

```bash
# Apply BBR deployment
kubectl apply -f pattern2/manifests/bbr-deployment.yaml

# Wait for pod to become Running
kubectl wait --for=condition=Ready pod -l app=body-based-router -n llm-d --timeout=120s

# Verify BBR pod is running
kubectl get pods -n llm-d -l app=body-based-router
```

**Expected Output:**
```
NAME                                READY   STATUS    RESTARTS   AGE
body-based-router-xxxxxxxxx-xxxxx   1/1     Running   0          30s
```

### Step 2: Create RBAC Permissions

```bash
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: body-based-router-configmap-reader
  namespace: llm-d
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: body-based-router-configmap-reader
  namespace: llm-d
subjects:
- kind: ServiceAccount
  name: body-based-router
  namespace: llm-d
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: body-based-router-configmap-reader
EOF
```

### Step 3: Verify Gateway Accepts GCPRoutingExtension

```bash
kubectl get gateway infra-pattern2-inference-gateway -n llm-d -o yaml | grep -A5 "status:"
```

**Expected:** `PROGRAMMED=True` (may take 30-60 seconds)

### Step 4: Apply Model Allowlist ConfigMaps

```bash
kubectl apply -f pattern2/manifests/bbr-allowlists.yaml
```

**Expected Output:**
```
configmap/phi-allowlist created
configmap/gemma-allowlist created
```

**Verify BBR Reconciliation:**
```bash
kubectl logs -n llm-d -l app=body-based-router --tail=20 | grep "Reconciling ConfigMap"
```

**Expected:**
```
Reconciling ConfigMap phi-allowlist
Reconcile successful
Reconciling ConfigMap gemma-allowlist
Reconcile successful
```

### Step 5: Apply InferencePools and HTTPRoutes

```bash
kubectl apply -f pattern2/manifests/pattern2-bbr-gpu-working.yaml
```

**Verify InferencePools:**
```bash
kubectl get inferencepool -n llm-d
```

**Expected:**
```
NAME         AGE
phi-pool     30s
gemma-pool   30s
```

### Step 6: Apply HealthCheckPolicies

```bash
kubectl apply -f pattern2/manifests/healthcheck-policies-gpu.yaml
```

**Wait 2-3 minutes for GKE health checks to propagate.**

### Step 7: Test Routing

```bash
# Get Gateway IP
GATEWAY_IP=$(kubectl get gateway infra-pattern2-inference-gateway -n llm-d -o jsonpath='{.status.addresses[0].value}')

# Test Phi-3-mini
curl -X POST http://${GATEWAY_IP}/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "microsoft/Phi-3-mini-4k-instruct", "prompt": "Hello", "max_tokens": 10}'

# Test Gemma-2B
curl -X POST http://${GATEWAY_IP}/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "google/gemma-2b-it", "prompt": "Hello", "max_tokens": 10}'
```

**Expected:** Both requests return HTTP 200 with model-specific responses.

---

## Verification

### Check BBR Header Injection

```bash
kubectl logs -n llm-d -l app=body-based-router --tail=30 | grep "Response generated"
```

**Expected Output:**
```
Response generated: "request_headers:{response:{header_mutation:{set_headers:{header:{key:\"X-Gateway-Model-Name\"  raw_value:\"microsoft/Phi-3-mini-4k-instruct\"}}  set_headers:{header:{key:\"X-Gateway-Base-Model-Name\"  raw_value:\"microsoft/Phi-3-mini-4k-instruct\"}}}  clear_route_cache:true}}"
```

**Key Observations:**
- `X-Gateway-Model-Name` header: Exact model name from request
- `X-Gateway-Base-Model-Name` header: **MUST HAVE raw_value populated** (from allowlist ConfigMap)

### Check InferencePool Endpoints

```bash
kubectl get inferencepool phi-pool -n llm-d -o yaml | grep -A20 "status:"
kubectl get inferencepool gemma-pool -n llm-d -o yaml | grep -A20 "status:"
```

**Expected:** Each pool shows 1 backend endpoint with IP address.

### Check HTTPRoute Status

```bash
kubectl get httproute -n llm-d -o wide
```

**Expected:**
```
NAME               HOSTNAMES   AGE
phi-model-route    *           5m
gemma-model-route  *           5m
```

Both routes should show `Accepted=True, ResolvedRefs=True, Reconciled=True`.

---

## Test Results

### Success Rate Testing (20 requests, alternating models)

```
✓ Request 1: google/gemma-2b-it
✓ Request 2: microsoft/Phi-3-mini-4k-instruct
✓ Request 3: google/gemma-2b-it
✓ Request 4: microsoft/Phi-3-mini-4k-instruct
✓ Request 5: google/gemma-2b-it
✓ Request 6: microsoft/Phi-3-mini-4k-instruct
✓ Request 7: google/gemma-2b-it
✓ Request 8: microsoft/Phi-3-mini-4k-instruct
✓ Request 9: google/gemma-2b-it
✓ Request 10: microsoft/Phi-3-mini-4k-instruct
✓ Request 11: google/gemma-2b-it
✓ Request 12: microsoft/Phi-3-mini-4k-instruct
✓ Request 13: google/gemma-2b-it
✓ Request 14: microsoft/Phi-3-mini-4k-instruct
✓ Request 15: google/gemma-2b-it
✓ Request 16: microsoft/Phi-3-mini-4k-instruct
✓ Request 17: google/gemma-2b-it
✓ Request 18: microsoft/Phi-3-mini-4k-instruct
✓ Request 19: google/gemma-2b-it
✓ Request 20: microsoft/Phi-3-mini-4k-instruct

Success rate: 20/20 (100.0%)
```

**Comparison with Previous Approaches:**

| Configuration | Success Rate | Notes |
|---------------|--------------|-------|
| **BBR with allowlist ConfigMaps** | **100%** | ✅ Current implementation |
| BBR without allowlist ConfigMaps | 0% | Header value empty, routing fails |
| Unified InferencePool with retry | 100% | Requires 2-2.2 retry attempts avg |
| Unified InferencePool without retry | 50% | EPP discovery limitation |

---

## Troubleshooting

### Issue: BBR Pod CrashLoopBackOff

**Symptom:** BBR pod restarts repeatedly

**Diagnosis:**
```bash
kubectl logs -n llm-d -l app=body-based-router
```

**Expected Error:**
```
Failed to watch: configmaps is forbidden: User "system:serviceaccount:llm-d:body-based-router" cannot list resource "configmaps"
```

**Solution:** Apply RBAC Role and RoleBinding for ConfigMap access (see Step 2 in Deployment Procedure)

### Issue: Gateway PROGRAMMED=False

**Symptom:** GCPRoutingExtension not accepted

**Diagnosis:**
```bash
kubectl get gateway infra-pattern2-inference-gateway -n llm-d -o yaml | grep -A10 "conditions:"
```

**Expected Error:**
```
service llm-d/body-based-router in GCPRoutingExtension does not have port 9004 with protocol HTTP2
```

**Solution:** Add `appProtocol: HTTP2` to BBR service port:
```bash
kubectl patch service body-based-router -n llm-d --type='json' -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value":"HTTP2"}]'
```

Then recreate GCPRoutingExtension.

### Issue: Requests Return 404 "fault filter abort"

**Symptom:** All requests fail with HTTP 404 and body "fault filter abort"

**Diagnosis:**
```bash
kubectl logs -n llm-d -l app=body-based-router --tail=20 | grep "Response generated"
```

**Check for:**
```
set_headers:{header:{key:\"X-Gateway-Base-Model-Name\"}}  # ← NO raw_value!
```

**Root Cause:** Missing allowlist ConfigMaps, BBR cannot populate header value

**Solution:** Apply `pattern2/manifests/bbr-allowlists.yaml` (see Step 4 in Deployment Procedure)

### Issue: Requests Timeout or No Response

**Symptom:** Requests hang or timeout without response

**Diagnosis:**
```bash
# Check InferencePool endpoints
kubectl get inferencepool -n llm-d -o yaml | grep -A10 "endpoints:"

# Check HealthCheckPolicy status
kubectl get healthcheckpolicy -n llm-d
```

**Root Cause:** GKE load balancer health checks not configured

**Solution:** Apply HealthCheckPolicies and wait 2-3 minutes for propagation

---

## Key Differences: GPU vs TPU BBR

| Aspect | GPU (nvidia-test-cluster) | TPU (tpu-test-cluster) |
|--------|---------------------------|------------------------|
| **Namespace** | llm-d | llm-d-inference-scheduling |
| **Models** | Phi-3-mini, Gemma-2B | Qwen2.5-3B, Phi-3-mini |
| **Allowlist ConfigMaps** | phi-allowlist, gemma-allowlist | qwen-allowlist, phi-allowlist |
| **BBR Image** | us-central1-docker.pkg.dev/k8s-staging-images/gateway-api-inference-extension/bbr:main | Same |
| **GCPRoutingExtension** | Required | Required |
| **RBAC** | ConfigMap read permissions required | Same |
| **HealthCheckPolicy** | HTTP health checks on port 8000 | Same |

**Common Architecture:**
- Both use BBR to inject headers from request body
- Both use separate InferencePools per model
- Both use header-based HTTPRoute matching
- Both require allowlist ConfigMaps for BBR to work

---

## Conclusion

**BBR architecture is now fully functional on GPU cluster**, achieving the same 100% routing accuracy as TPU cluster.

**Critical Success Factors:**
1. ✅ BBR deployment with proper RBAC permissions
2. ✅ `appProtocol: HTTP2` on BBR service
3. ✅ **Model allowlist ConfigMaps with `inference.networking.k8s.io/bbr-managed: "true"` label**
4. ✅ Separate InferencePools with single-model selectors
5. ✅ Header-based HTTPRoutes matching `X-Gateway-Base-Model-Name`
6. ✅ HealthCheckPolicies for GKE load balancer configuration

**This eliminates the retry requirement** documented in `benchmarks/EPP_BACKEND_DISCOVERY_LIMITATION.md` and provides deterministic routing for multi-model serving on GPU infrastructure.

---

## References

- **Working Configuration:** `pattern2/manifests/pattern2-bbr-gpu-working.yaml`
- **BBR Deployment:** `pattern2/manifests/bbr-deployment.yaml`
- **Allowlist ConfigMaps:** `pattern2/manifests/bbr-allowlists.yaml`
- **Health Check Policies:** `pattern2/manifests/healthcheck-policies-gpu.yaml`
- **TPU BBR Reference:** `pattern2/llm-d-pattern2-tpu-setup.md`
- **Previous Limitation:** `benchmarks/EPP_BACKEND_DISCOVERY_LIMITATION.md`
- **Failed Attempt (Missing Allowlists):** `benchmarks/BBR_IMPLEMENTATION_ATTEMPT.md`

---

## Timestamp

- **Date:** 2026-01-27
- **BBR Deployed:** 15:28 UTC
- **Allowlist ConfigMaps Created:** 15:33 UTC
- **100% Success Achieved:** 15:35 UTC
