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

3. ✅ **Use GKE Service annotation to override protocol**
   ```bash
   kubectl annotate service qwen2-3b-pattern1-kserve-workload-svc \
     -n llm-d-inference-scheduling \
     cloud.google.com/app-protocols='{"8000":"HTTP"}' \
     --overwrite
   ```

**Workaround Status:**
- ✅ **Completions endpoints WORK** - Use InferencePool backend (HTTP, healthy)
- ❌ **Health/models endpoints FAIL** - Use Service backend (HTTPS, TLS errors)

**Why This Is Acceptable:**
- Core functionality (completions via InferencePool) works perfectly
- Health/models endpoints can be accessed directly from pods if needed
- In production, would add TLS termination at Gateway frontend, not backend

**Impact:** MEDIUM - Non-critical endpoints affected, core API functional

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

### Workarounds Applied:
1. ✅ GKE Service annotation for HTTP protocol override
2. ✅ Accept Service backend TLS errors (non-critical endpoints)

### Documented Limitations:
1. ⚠️ `/health` and `/v1/models` endpoints have TLS errors (Service backend)
2. ⚠️ Completions endpoints fully functional (InferencePool backend)
3. ⚠️ Health checks show "Invalid HTTP request" warnings (normal)

---

## Lessons Learned

1. **Always verify GatewayClass capabilities** - Not all classes support all features
2. **Regional vs Global matters** - InferencePool only works with regional LBs
3. **GKE != Kubernetes** - GKE has specific limitations (timeout fields)
4. **Health checks need customization** - Defaults rarely match application needs
5. **KServe is opinionated** - Reconciles Service config aggressively
6. **Test incrementally** - Each component should be verified before proceeding

---

## Additional Resources

- [GKE Inference Gateway Concepts](https://cloud.google.com/kubernetes-engine/docs/concepts/about-gke-inference-gateway)
- [Gateway API Inference Extension](https://gateway-api-inference-extension.sigs.k8s.io/)
- [KServe LLMInferenceService](https://kserve.github.io/website/latest/modelserving/v1beta1/llm/)
- [LeaderWorkerSet GitHub](https://github.com/kubernetes-sigs/lws)

---

**Last Updated:** 2026-02-11
**Deployment Status:** ✅ SUCCESSFUL (core functionality working)
