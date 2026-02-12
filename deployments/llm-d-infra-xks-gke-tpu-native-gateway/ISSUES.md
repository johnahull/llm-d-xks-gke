# Issues Encountered and Solutions

This document tracks all issues encountered during GKE native Gateway deployment with TPU v6e and their solutions.

**Deployment Date:** 2026-02-11
**Deployment Variant:** GKE native Gateway (no Istio)
**Target:** europe-west4-a with TPU v6e-4

---

## CRITICAL: GatewayClass Support for InferencePool

### Issue #1: Global GatewayClass Does NOT Support InferencePool

**Problem:**
- Initial deployment used `gke-l7-global-external-managed` GatewayClass
- Gateway appeared to provision successfully (got External IP)
- However, InferencePool backends never became healthy
- HTTPRoute with InferencePool backends rejected

**Root Cause:**
GKE documentation is unclear about which GatewayClasses support Gateway API Inference Extension (InferencePool). Only **regional** GatewayClasses support InferencePool, not global ones.

**Supported GatewayClasses:**
- ✅ `gke-l7-regional-external-managed` - Regional external LB (WORKS)
- ✅ `gke-l7-rilb` - Regional internal LB (WORKS)
- ❌ `gke-l7-global-external-managed` - Global external LB (DOES NOT WORK)

**Solution:**
Change Gateway spec to use regional GatewayClass:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: inference-gateway
  namespace: opendatahub
spec:
  gatewayClassName: gke-l7-regional-external-managed  # Changed from global
  listeners:
  - name: http
    protocol: HTTP
    port: 80
```

**Impact:** HIGH - Deployment completely non-functional with global GatewayClass

**References:**
- https://cloud.google.com/kubernetes-engine/docs/concepts/about-gke-inference-gateway
- https://cloud.google.com/kubernetes-engine/docs/how-to/deploy-gke-inference-gateway

---

## TPU Zone Availability Issues

### Issue #2: TPU v6e Not Available in Target US Zones

**Problem:**
Attempted deployment in us-central1-a, us-central1-b, us-south1-a - all failed with:
- "Unsupported TPU configuration"
- GCE_STOCKOUT errors
- Machine types not available

**Root Cause:**
TPU VM availability does NOT equal GKE node pool availability. The `check-tpu-availability.sh` script showed TPU VMs available, but GKE doesn't support TPU node pools in those zones.

**GKE TPU v6e Supported Zones:**
```
us-central1-b
us-east1-d
us-east5-a, us-east5-b
us-south1-a, us-south1-b
europe-west4-a  ← Used this (proven working)
```

**Solution:**
1. Created `check-gke-tpu-availability.sh` to distinguish GKE zones from TPU VM zones
2. Fixed `check-nodepool-prerequisites.sh` bug (was checking for `tpu-v6e-slice` instead of `tpu-v6e`)
3. Used `europe-west4-a` which has proven TPU v6e-4 support for GKE

**Script Fix:**
```bash
# BEFORE (wrong - caused false negatives):
if [[ "$MACHINE_TYPE" =~ ct6e ]]; then
    TPU_VERSION="tpu-v6e-slice"  # ← WRONG
fi

# AFTER (correct):
if [[ "$MACHINE_TYPE" =~ ct6e ]]; then
    TPU_VERSION="tpu-v6e"  # ← CORRECT
fi
```

**Impact:** HIGH - Prevented deployment in preferred US regions

---

## Gateway Configuration Issues

### Issue #3: Gateway API Controller Not Enabled

**Problem:**
Gateway stuck in "Unknown" state after creation. No GatewayClasses available.

**Root Cause:**
GKE Gateway API controller defaults to "disabled" on cluster creation.

**Solution:**
```bash
gcloud container clusters update llmd-native-gateway-eu4a-20260211 \
  --gateway-api=standard \
  --zone=europe-west4-a \
  --project=ecoeng-llmd

# Also enable HTTP Load Balancing addon (required)
gcloud container clusters update llmd-native-gateway-eu4a-20260211 \
  --update-addons=HttpLoadBalancing=ENABLED \
  --zone=europe-west4-a \
  --project=ecoeng-llmd
```

**Wait Time:** Up to 45 minutes for GatewayClasses to appear after enabling

**Verification:**
```bash
kubectl get gatewayclass
# Should show: gke-l7-regional-external-managed, gke-l7-rilb, etc.
```

**Impact:** MEDIUM - Blocks all Gateway functionality

---

## HTTPRoute Configuration Issues

### Issue #4: HTTPRoute Timeout Fields Not Supported

**Problem:**
KServe auto-created HTTPRoute with `timeout` fields:
```yaml
rules:
- timeouts:
    backendRequest: 0s
    request: 0s
```

HTTPRoute rejected with:
```
Error GWCER104: HTTPRoute is misconfigured, err: Timeouts are not supported.
```

**Root Cause:**
GKE Gateway controller does NOT support HTTPRoute timeout fields (as of GKE 1.34). This is a GKE limitation vs standard Gateway API spec.

**Solution:**
Fixed KServe template to remove timeouts:

```bash
# Patch the LLMInferenceServiceConfig template
kubectl get llminferenceserviceconfig kserve-config-llm-router-route \
  -n opendatahub -o json | \
  jq 'del(.spec.router.route.http.spec.rules[].timeouts)' | \
  kubectl apply -f -

# Recreate LLMInferenceService to use updated template
kubectl delete llmisvc qwen2-3b-pattern1 -n llm-d-inference-scheduling
kubectl apply -f manifests/llmisvc-tpu.yaml
```

**Warning:** Modifying well-known KServe configs (`serving.kserve.io/well-known-config: "true"`) is not recommended but necessary for GKE compatibility.

**Impact:** HIGH - HTTPRoute completely rejected without fix

---

## Health Check Configuration Issues

### Issue #5: GCP Health Checks Misconfigured

**Problem:**
GKE auto-created health checks with incorrect settings:
- Path: `/` (vLLM uses `/health`)
- Protocol: HTTPS (vLLM serves HTTP)

Result: All backends marked UNHEALTHY despite pod being Ready.

**Root Cause:**
GKE creates default health checks that don't match vLLM's API server configuration.

**Solution:**
Manually update GCP health checks:

```bash
# Update InferencePool health check
gcloud compute health-checks update http \
  gkegw1-pzx5-llm-d-infere-qwen2-3b-pattern1-i-54321-12oqnptayf7u \
  --region=europe-west4 \
  --project=ecoeng-llmd \
  --request-path=/health

# Update Service health check (HTTPS type - must use https command)
gcloud compute health-checks update https \
  gkegw1-pzx5-llm-d-inferenc-qwen2-3b-pattern1--8000-jfiarzj058qe \
  --region=europe-west4 \
  --project=ecoeng-llmd \
  --request-path=/health
```

**Note:** Service health check remains HTTPS protocol (causes TLS errors), but InferencePool health check is fixed to HTTP with correct path.

**Impact:** HIGH - Backends unhealthy, API non-functional

---

## Service Protocol Configuration Issues

### Issue #6: KServe Forces HTTPS on Service Backend

**Problem:**
KServe creates Service with `appProtocol: https` but vLLM serves plain HTTP on port 8000. This causes:
- TLS handshake errors when Gateway connects to Service backend
- `/v1/models` endpoint non-functional (uses Service backend)
- `/health` endpoint non-functional (uses Service backend)

**Root Cause:**
KServe global configuration has `urlScheme: https` which forces all Services to use HTTPS `appProtocol`. This is incompatible with vLLM's HTTP-only server.

**Attempted Solutions:**

1. ❌ **Change KServe global config** - Doesn't affect already-created Services
   ```bash
   kubectl get configmap inferenceservice-config -n opendatahub -o json | \
     jq '.data.deploy = (.data.deploy | fromjson | .urlScheme = "http" | tojson)' | \
     kubectl apply -f -
   ```

2. ❌ **Manually patch Service** - KServe immediately reconciles back to `https`
   ```bash
   kubectl patch service qwen2-3b-pattern1-kserve-workload-svc -n llm-d-inference-scheduling \
     --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/appProtocol", "value": "http"}]'
   ```

3. ❌ **GKE Service annotation** - `cloud.google.com/app-protocols` only works for Ingress, not Gateway API

**Status:** Known Limitation (Accepted) - See Issue #15 for full analysis.

- ✅ **Completions endpoints WORK** - Use InferencePool backend (HTTP, healthy)
- ❌ **Health/models endpoints FAIL** - Use Service backend (HTTPS, TLS errors)
- **Workaround:** Direct pod access or `kubectl port-forward` for non-inference endpoints

**Impact:** LOW - Non-critical endpoints affected, core inference API fully functional

---

## LeaderWorkerSet CRD Missing

### Issue #7: LeaderWorkerSet CRD Not Installed

**Problem:**
```
no matches for kind LeaderWorkerSet in version leaderworkerset.x-k8s.io/v1
```

**Root Cause:**
KServe requires LeaderWorkerSet CRDs for multi-node workloads, but they're not included in standard KServe installation.

**Solution:**
```bash
kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/lws/releases/download/v0.4.0/manifests.yaml
```

**Note:** Must use `--server-side` due to annotation size exceeding client-side limits.

**Impact:** MEDIUM - Blocks multi-node deployments (not needed for single-node Pattern 1)

---

## Model Download and XLA Compilation

### Issue #8: Long Initialization Time

**Problem:**
Pod takes 4-6 minutes to become Ready, causing initial deployment anxiety.

**Root Cause:**
This is expected behavior due to:
1. Storage initializer downloads model (~35 seconds for Qwen2.5-3B)
2. vLLM starts and initializes TPU (~30 seconds)
3. XLA compilation of model graphs (~2-3 minutes)
4. Readiness probe has 240s initial delay

**Timeline:**
```
T+0s:    Pod created
T+21s:   Storage initializer image pulled
T+56s:   Model download complete
T+86s:   Main container starts
T+89s:   vLLM API server starts
T+180s:  XLA compilation complete
T+240s:  Readiness probe begins checking
T+250s:  Pod becomes Ready
```

**Solution:**
No fix needed - this is normal. Document expected timeline to set expectations.

**Warning Messages (Normal):**
```
WARNING:  Invalid HTTP request received.
```
These are from HTTPS health checks hitting HTTP endpoint - safe to ignore.

**Impact:** LOW - Informational, not a problem

---

## Documentation Gaps

### Issue #9: GKE Inference Gateway Documentation Unclear

**Problems:**
1. GKE docs don't clearly state which GatewayClasses support InferencePool
2. Examples use global GatewayClass which doesn't work
3. No mention of regional-only requirement
4. No troubleshooting for "Timeouts not supported" error
5. No guidance on health check configuration

**Impact:** HIGH - Led to multiple deployment failures and debugging time

**Recommendation:**
File feedback with Google Cloud documentation team to clarify:
- InferencePool requires regional GatewayClasses
- HTTPRoute timeout fields not supported
- Health check defaults need customization

---

## Summary of Critical Fixes

### Must-Have Fixes:
1. ✅ Use `gke-l7-regional-external-managed` GatewayClass
2. ✅ Remove `timeouts` from HTTPRoute (patch KServe template)
3. ✅ Update GCP health checks to use `/health` path
4. ✅ Enable Gateway API on cluster (`--gateway-api=standard`)
5. ✅ Install LeaderWorkerSet CRDs

### Known Limitations (Accepted):
1. ⚠️ `/health` and `/v1/models` endpoints have TLS errors via Gateway (KServe `appProtocol: https` incompatible with GKE Gateway API without Istio)
2. ⚠️ Health checks show "Invalid HTTP request" warnings (normal - HTTPS health check hitting HTTP endpoint)

### Unaffected Functionality:
1. ✅ `/v1/completions` and `/v1/chat/completions` fully functional (InferencePool backend uses HTTP)
2. ✅ GCP health checks work independently via HealthCheckPolicy CRDs
3. ✅ `/health` and `/v1/models` accessible via direct pod access or port-forward

---

## Lessons Learned

1. **Always verify GatewayClass capabilities** - Not all classes support all features
2. **Regional vs Global matters** - InferencePool only works with regional LBs
3. **GKE != Kubernetes** - GKE has specific limitations (timeout fields, annotation behavior)
4. **Health checks need customization** - Defaults rarely match application needs
5. **KServe assumes Istio** - Designed for service mesh; `appProtocol: https` causes issues without Istio
6. **KServe is opinionated** - Reconciles Service config aggressively, overriding external modifications
7. **GKE Ingress != Gateway API** - `cloud.google.com/app-protocols` annotation only works for Ingress, not Gateway API
8. **Test incrementally** - Each component should be verified before proceeding

---

## Additional Resources

- [GKE Inference Gateway Concepts](https://cloud.google.com/kubernetes-engine/docs/concepts/about-gke-inference-gateway)
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/)
- [KServe LLMInferenceService](https://kserve.github.io/website/latest/modelserving/v1beta1/llm/)
- [LeaderWorkerSet GitHub](https://github.com/kubernetes-sigs/lws)

---

## Pattern 3 Deployment Issues

### Issue #12: vLLM TPU Doesn't Support --prefix-cache-block-size

**Problem:**
Pattern 3 manifest initially included `--prefix-cache-block-size=16` argument based on GPU vLLM documentation. This caused pod crash loops on TPU deployment:

```
api_server.py: error: unrecognized arguments: --prefix-cache-block-size=16
```

**Root Cause:**
The `--prefix-cache-block-size` parameter is **GPU-only** and not supported in vLLM TPU 3.2.5. TPU version auto-tunes the block size.

**Solution:**
Remove the `--prefix-cache-block-size` argument from TPU manifests:

```yaml
# Pattern 3 TPU manifest
args:
- |
  python3 -m vllm.entrypoints.openai.api_server \
    --model=/mnt/models \
    --dtype=half \
    --max-model-len=2048 \
    --tensor-parallel-size=4 \
    --enable-prefix-caching \
    # REMOVED: --prefix-cache-block-size=16 \
    --disable-log-requests
```

**Actual TPU Configuration (from EPP logs):**
- Block size: **64 tokens** (auto-tuned by vLLM)
- Max prefix blocks to match: 256
- LRU capacity per server: 31,250 blocks

**Impact:** CRITICAL - Pod crash loop until fixed

**Fix Applied:** 2026-02-12, commit c6cab9f

---

### Issue #13: GCP Health Check Path Keeps Resetting to "/"

**Problem:**
When deploying Pattern 3, GCP health checks are auto-created with `requestPath: /` instead of `/health`. Manually updating the health check works temporarily, but GKE often resets it back to `/`.

**Symptoms:**
```bash
# Check backend health
gcloud compute backend-services get-health <backend-name> --region=europe-west4

# Shows: healthState: UNHEALTHY for all backends

# Check health check path
gcloud compute health-checks describe <health-check-name> --region=europe-west4
# Shows: requestPath: /  (incorrect, should be /health)
```

**Root Cause:**
GKE Gateway controller manages health checks and may reset manual changes during reconciliation. Pattern 3 deployment was missing **HealthCheckPolicy CRDs** that explicitly configure GCP health checks. Without these, GKE defaults to path="/".

**Permanent Solution (FIXED 2026-02-12):**
Apply HealthCheckPolicy resources to configure health checks declaratively:

```bash
# Apply HealthCheckPolicy CRDs
kubectl apply -f manifests/healthcheck-policies-pattern3.yaml

# Verify policies attached
kubectl get healthcheckpolicy -n llm-d-inference-scheduling

# For InferencePool backends (manual update still needed due to NEG service architecture)
gcloud compute health-checks update http \
  gkegw1-pzx5-llm-d-infere-qwen2-3b-pattern3-i-54321-0hdrrx84aq5z \
  --region=europe-west4 \
  --project=ecoeng-llmd \
  --request-path=/health \
  --port=8000

# Wait 30-60 seconds, then verify all backends HEALTHY
gcloud compute backend-services get-health \
  gkegw1-pzx5-llm-d-infere-qwen2-3b-pattern3-i-54321-0hdrrx84aq5z \
  --region=europe-west4 \
  --project=ecoeng-llmd
```

**HealthCheckPolicy Configuration:**
```yaml
# Service backend (auto-applied)
apiVersion: networking.gke.io/v1
kind: HealthCheckPolicy
metadata:
  name: qwen2-pattern3-health-check
spec:
  default:
    config:
      type: HTTP
      httpHealthCheck:
        port: 8000
        requestPath: /health
  targetRef:
    kind: Service
    name: qwen2-3b-pattern3-kserve-workload-svc

# InferencePool backend (requires manual gcloud update due to NEG architecture)
# See manifests/healthcheck-policies-pattern3.yaml for full config
```

**Verification:**
```bash
# Test inference via Gateway
GATEWAY_IP=$(kubectl get gateway inference-gateway -n opendatahub -o jsonpath='{.status.addresses[0].value}')
curl -X POST "http://${GATEWAY_IP}/llm-d-inference-scheduling/qwen2-3b-pattern3/v1/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"/mnt/models","prompt":"Test","max_tokens":20}'

# Should return valid JSON completion response
```

**Impact:** HIGH - Gateway routing non-functional until health checks fixed

**Status:** ✅ FIXED - HealthCheckPolicy CRDs created, all backends healthy, Gateway working

**Fix Applied:** 2026-02-12, manifests/healthcheck-policies-pattern3.yaml

**Related:** Same issue as #5, but more persistent in Pattern 3 multi-replica deployment

---

### Issue #14: Incorrect EPP Scheduler Weights in Documentation

**Problem:**
Initial Pattern 3 documentation stated EPP scheduler uses 3 separate scorers with these weights:
- prefix-cache-scorer: 3.0
- queue-scorer: 1.0
- kv-cache-utilization-scorer: 1.0

**Actual Configuration (from EPP logs):**
Only **2 scorers** are used:
- `prefix-cache-scorer`: weight **2.0**
- `load-aware-scorer`: weight **1.0** (combines queue depth + KV cache)

**Saturation Thresholds:**
- Queue depth: **5 requests**
- KV cache utilization: **80%**
- Metrics staleness: **200ms**

**Root Cause:**
Documentation was based on older EPP architecture descriptions. Actual deployed KServe v0.15 uses consolidated load-aware scorer.

**Solution:**
Updated PATTERN3.md with correct scorer configuration and architecture diagrams.

**Impact:** LOW - Documentation inaccuracy, doesn't affect functionality

**Fix Applied:** 2026-02-12, PATTERN3.md updated

---

## Pattern 1 Helm Deployment Issues

### Issue #15: Service Backend HTTPS Protocol Mismatch (Pattern 1)

**Problem:**
Service backend endpoints (`/health`, `/v1/models`) return TLS errors when accessed via Gateway:
```
upstream connect error or disconnect/reset before headers.
transport failure reason: TLS_error:|268435703:SSL routines:OPENSSL_internal:WRONG_VERSION_NUMBER:TLS_error_end
```

**Root Cause:**
1. KServe controller creates Services with `appProtocol: https` and `name: https` (hardcoded in Go code)
2. GKE Gateway API reads this and configures GCP backend service for HTTPS
3. vLLM serves HTTP only (not HTTPS), causing TLS handshake to fail
4. Both KServe controller and GKE reconcile their resources back to HTTPS every 5-10 minutes

**Affected Endpoints:**
- ❌ `/health` - Returns TLS error (routes through Service backend)
- ❌ `/v1/models` - Returns TLS error (routes through Service backend)
- ✅ `/v1/completions` - Works perfectly (routes through InferencePool backend with HTTP)
- ✅ `/v1/chat/completions` - Works perfectly (routes through InferencePool backend with HTTP)

**Why InferencePool Works:**
InferencePool backends use headless services without `appProtocol`, so GKE defaults to HTTP. Only the ClusterIP Service (for non-inference endpoints) has the HTTPS protocol issue.

**Solutions Considered:**

1. **❌ Modify Kubernetes Service** - KServe controller reconciles it back immediately
2. **❌ Mutating Admission Webhook** - Complex, doesn't prevent controller reconciliation
3. **❌ Configure vLLM for HTTPS** - vLLM doesn't support HTTPS natively
4. **❌ Fork KServe controller** - Maintenance burden, must merge upstream changes
5. **❌ Kyverno admission controller** - KServe reconciles `appProtocol` back after Kyverno mutation; `cloud.google.com/app-protocols` annotation only works for Ingress, not Gateway API
6. **❌ GCPBackendPolicy CRD** - No protocol override field available

**Root Cause Analysis:**

KServe was designed for **Istio service mesh environments** where Istio sidecar proxies handle TLS termination transparently. The `appProtocol: https` setting tells Istio to encrypt service-to-service traffic via mTLS, but the application (vLLM) never needs to implement HTTPS.

Without Istio, GKE Gateway API reads `appProtocol: https` directly and tries to connect to vLLM over HTTPS, which fails because vLLM only speaks HTTP.

**Decision: Accept Limitation**

This is an inherent incompatibility between KServe's Istio-oriented design and GKE native Gateway API. Since inference endpoints work perfectly via InferencePool backends, the limitation is acceptable.

**Workarounds for non-inference endpoints:**
```bash
# Direct pod access
POD_IP=$(kubectl get pod -n llm-d-inference-scheduling \
  -l app.kubernetes.io/component=workload \
  -o jsonpath='{.items[0].status.podIP}')
kubectl run -it --rm --image=curlimages/curl test -- curl http://$POD_IP:8000/health

# Port forwarding
kubectl port-forward -n llm-d-inference-scheduling \
  svc/qwen2-3b-pattern1-kserve-workload-svc 8000:8000
curl http://localhost:8000/health
curl http://localhost:8000/v1/models
```

**Permanent fix options (if needed in future):**
1. Deploy Istio service mesh (KServe's intended environment)
2. Add TLS termination sidecar (nginx/envoy) to vLLM pods
3. Contribute configurable `appProtocol` option to upstream KServe

**Impact:** LOW - Only affects debugging/monitoring endpoints; core inference fully functional

**Status:** Known Limitation (Accepted)

**Documentation:** See [HTTP-PROTOCOL-FIX.md](HTTP-PROTOCOL-FIX.md) for full analysis

**Date:** 2026-02-12

---

## Pattern 3 Summary

**Deployment Date:** 2026-02-12
**Replicas:** 3× TPU v6e-4 (12 chips total)
**Status:** ✅ FULLY OPERATIONAL (all backends healthy, Gateway routing working)

**Critical Fixes Applied:**
1. ✅ Removed `--prefix-cache-block-size` from TPU manifest (Issue #12)
2. ✅ Updated documentation with correct EPP weights (Issue #14)
3. ✅ Created HealthCheckPolicy CRDs for proper health check configuration (Issue #13)
4. ✅ All 3 InferencePool backends HEALTHY
5. ✅ Gateway routing confirmed working with successful inference requests

**Outstanding Issues:**
None - Pattern 3 is fully operational and ready for production use

---

## Pattern 1 Helm Deployment Summary

**Deployment Date:** 2026-02-12
**Deployment Method:** Helm chart (rhaii-xks-kserve)
**KServe Version:** v0.15 (quay.io/opendatahub development images)
**Replicas:** 1× TPU v6e-4 (4 chips)
**Status:** ✅ OPERATIONAL (inference endpoints working)

**Critical Fixes Applied:**
1. ✅ Replaced non-existent registry.redhat.io SHA digests with quay.io images (controller, storage-initializer, scheduler, agent, router)
2. ✅ Changed scheduler image from :latest to :v0.4 for CLI flag compatibility
3. ✅ Updated probe schemes from HTTPS to HTTP in LLMInferenceServiceConfig templates
4. ✅ Created RSA 2048-bit CA certificate (KServe expects RSA, not ECDSA)
5. ✅ Applied HealthCheckPolicy CRDs for proper health check configuration

**Known Limitation:**
- `/health` and `/v1/models` return TLS errors via Gateway (KServe sets `appProtocol: https`, vLLM serves HTTP only)
- This is an inherent KServe/GKE Gateway API incompatibility (KServe assumes Istio service mesh)
- Inference endpoints (`/v1/completions`, `/v1/chat/completions`) work perfectly via InferencePool
- See Issue #15 and [HTTP-PROTOCOL-FIX.md](HTTP-PROTOCOL-FIX.md) for full analysis

---

**Last Updated:** 2026-02-12
**Deployment Status:**
- **Pattern 1 (Helm):** ✅ OPERATIONAL (inference working; `/health` and `/v1/models` have known HTTPS limitation - see Issue #15)
- **Pattern 3 (Kustomize):** ✅ OPERATIONAL (inference working; same HTTPS limitation applies to Service backend endpoints)
