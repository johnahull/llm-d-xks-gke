# Operator Deployment Verification Guide

Comprehensive verification steps for cert-manager, Istio/sail-operator, and LWS operators.

---

## Quick Health Check

**One-liner to check all operators:**

```bash
kubectl get pods -A | grep -E "(cert-manager|istio|lws)"
```

**Expected:** All pods should show `Running` status with `1/1` or `2/2` in READY column.

---

## 1. cert-manager Verification

### 1.1 Check Pods

**Upstream (Jetstack):**
```bash
kubectl get pods -n cert-manager
```

**Expected output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-xxxxx                        1/1     Running   0          Xm
cert-manager-cainjector-xxxxx             1/1     Running   0          Xm
cert-manager-webhook-xxxxx                1/1     Running   0          Xm
```

**Red Hat Operator:**
```bash
# Check operator
kubectl get pods -n cert-manager-operator

# Check cert-manager components
kubectl get pods -n cert-manager
```

**Expected output:**
```
# cert-manager-operator namespace
NAME                                                  READY   STATUS    RESTARTS   AGE
cert-manager-operator-controller-manager-xxxxx        1/1     Running   0          Xm

# cert-manager namespace
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-xxxxx                        1/1     Running   0          Xm
cert-manager-cainjector-xxxxx             1/1     Running   0          Xm
cert-manager-webhook-xxxxx                1/1     Running   0          Xm
```

### 1.2 Verify CRDs

```bash
kubectl get crd | grep cert-manager
```

**Expected output (6 CRDs):**
```
certificaterequests.cert-manager.io
certificates.cert-manager.io
challenges.acme.cert-manager.io
clusterissuers.cert-manager.io
issuers.cert-manager.io
orders.acme.cert-manager.io
```

### 1.3 Test cert-manager Functionality

Create a self-signed certificate:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: test-selfsigned
  namespace: default
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-certificate
  namespace: default
spec:
  secretName: test-certificate-secret
  duration: 2160h # 90d
  renewBefore: 360h # 15d
  subject:
    organizations:
      - test-org
  commonName: test.example.com
  isCA: false
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
  usages:
    - server auth
    - client auth
  dnsNames:
    - test.example.com
  issuerRef:
    name: test-selfsigned
    kind: Issuer
    group: cert-manager.io
EOF
```

**Verify certificate was created:**
```bash
kubectl get certificate -n default
kubectl describe certificate test-certificate -n default
```

**Expected:** Certificate shows `Ready=True`

**Cleanup test resources:**
```bash
kubectl delete certificate test-certificate -n default
kubectl delete issuer test-selfsigned -n default
kubectl delete secret test-certificate-secret -n default
```

✅ **cert-manager is working if:** All pods Running, CRDs exist, test certificate created successfully

---

## 2. Istio / sail-operator Verification

### 2.1 Check Pods

**Upstream sail-operator:**
```bash
# Check operator
kubectl get pods -n sail-operator

# Check Istio control plane
kubectl get pods -n istio-system
```

**Expected output:**
```
# sail-operator namespace
NAME                             READY   STATUS    RESTARTS   AGE
sail-operator-xxxxx              1/1     Running   0          Xm

# istio-system namespace
NAME                      READY   STATUS    RESTARTS   AGE
istiod-xxxxx              1/1     Running   0          Xm
```

**Red Hat sail-operator:**
```bash
kubectl get pods -n istio-system
```

**Expected output:**
```
NAME                                    READY   STATUS    RESTARTS   AGE
servicemesh-operator3-xxxxx             1/1     Running   0          Xm
istiod-xxxxx                            1/1     Running   0          Xm
```

### 2.2 Check Istio Custom Resource

**Upstream:**
```bash
kubectl get istio -n sail-operator
```

**Expected output:**
```
NAME      REVISIONS   READY   IN USE   ACTIVE REVISIONS   AGE
default   1           True    1        default            Xm
```

**Red Hat:**
```bash
kubectl get istio -n istio-system
```

**Expected output:**
```
NAME      STATE   VERSION   READY   IN USE   ACTIVE REVISIONS   AGE
default   Healthy v1.24.1   True    1        default            Xm
```

### 2.3 Verify Istio CRDs

```bash
kubectl get crd | grep istio
```

**Expected output (should see multiple Istio CRDs):**
```
authorizationpolicies.security.istio.io
destinationrules.networking.istio.io
envoyfilters.networking.istio.io
gateways.networking.istio.io
peerauthentications.security.istio.io
proxyconfigs.networking.istio.io
requestauthentications.security.istio.io
serviceentries.networking.istio.io
sidecars.networking.istio.io
telemetries.telemetry.istio.io
virtualservices.networking.istio.io
wasmplugins.extensions.istio.io
workloadentries.networking.istio.io
workloadgroups.networking.istio.io
```

### 2.4 Check Istio Version

```bash
kubectl exec -n istio-system deploy/istiod -- pilot-discovery version
```

**Expected:** Shows Istio version (e.g., `1.24.1`)

### 2.5 Test Istio Sidecar Injection

**Label a namespace for sidecar injection:**
```bash
kubectl label namespace default istio-injection=enabled --overwrite
```

**Deploy a test pod:**
```bash
kubectl run test-sidecar --image=nginx --restart=Never -n default
```

**Check for sidecar:**
```bash
kubectl get pod test-sidecar -n default -o jsonpath='{.spec.containers[*].name}'
```

**Expected output:** `nginx istio-proxy` (two containers)

**Cleanup:**
```bash
kubectl delete pod test-sidecar -n default
kubectl label namespace default istio-injection-
```

✅ **Istio is working if:** istiod Running, Istio CR shows Ready=True, CRDs exist, sidecar injection works

---

## 3. LWS (LeaderWorkerSet) Verification

### 3.1 Check Pods

**Upstream (kubernetes-sigs):**
```bash
kubectl get pods -n lws-system
```

**Expected output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
lws-controller-manager-xxxxx              2/2     Running   0          Xm
```

**Red Hat:**
```bash
kubectl get pods -n openshift-lws-operator
```

**Expected output:**
```
NAME                                      READY   STATUS    RESTARTS   AGE
openshift-lws-operator-xxxxx              1/1     Running   0          Xm
lws-controller-manager-xxxxx              2/2     Running   0          Xm  # May be in lws-system namespace
```

> **Note:** Red Hat LWS operator may deploy the controller manager in either `openshift-lws-operator` or `lws-system` namespace.

### 3.2 Verify LWS CRD

```bash
kubectl get crd leaderworkersets.leaderworkerset.x-k8s.io
```

**Expected output:**
```
NAME                                           CREATED AT
leaderworkersets.leaderworkerset.x-k8s.io      2026-02-XXThh:mm:ssZ
```

### 3.3 Check CRD Details

```bash
kubectl describe crd leaderworkersets.leaderworkerset.x-k8s.io
```

**Expected:** CRD definition with group `leaderworkerset.x-k8s.io`

### 3.4 Test LWS Functionality

Create a test LeaderWorkerSet:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: leaderworkerset.x-k8s.io/v1
kind: LeaderWorkerSet
metadata:
  name: test-lws
  namespace: default
spec:
  replicas: 1
  leaderWorkerTemplate:
    size: 2
    restartPolicy: RecreateGroupOnPodRestart
    leaderTemplate:
      metadata:
        labels:
          role: leader
      spec:
        containers:
        - name: leader
          image: nginx:latest
          command: ["sleep", "3600"]
    workerTemplate:
      metadata:
        labels:
          role: worker
      spec:
        containers:
        - name: worker
          image: nginx:latest
          command: ["sleep", "3600"]
EOF
```

**Verify LeaderWorkerSet created pods:**
```bash
kubectl get leaderworkerset test-lws -n default
kubectl get pods -n default -l leaderworkerset.sigs.k8s.io/name=test-lws
```

**Expected:**
- LeaderWorkerSet shows `REPLICAS: 1`
- 2 pods created (1 leader + 1 worker)

**Cleanup:**
```bash
kubectl delete leaderworkerset test-lws -n default
```

✅ **LWS is working if:** Controller manager Running (2/2), CRD exists, test LeaderWorkerSet creates pods

---

## 4. Integrated Operator Health Check

### 4.1 All Operators at Once

```bash
echo "=== cert-manager ==="
kubectl get pods -n cert-manager-operator 2>/dev/null || echo "Using upstream"
kubectl get pods -n cert-manager
echo ""

echo "=== Istio ==="
kubectl get pods -n sail-operator 2>/dev/null || echo "Operator in istio-system"
kubectl get pods -n istio-system
echo ""

echo "=== LWS ==="
kubectl get pods -n openshift-lws-operator 2>/dev/null || kubectl get pods -n lws-system
echo ""

echo "=== CRDs Count ==="
echo "cert-manager CRDs: $(kubectl get crd | grep -c cert-manager)"
echo "Istio CRDs: $(kubectl get crd | grep -c istio)"
echo "LWS CRDs: $(kubectl get crd | grep -c leaderworkerset)"
```

### 4.2 Check All Custom Resources

```bash
# cert-manager
kubectl get issuer,clusterissuer,certificate --all-namespaces

# Istio
kubectl get istio --all-namespaces
kubectl get gateway,virtualservice,destinationrule --all-namespaces

# LWS
kubectl get leaderworkerset --all-namespaces
```

### 4.3 Verify Operator Versions

**cert-manager:**
```bash
kubectl get deployment -n cert-manager cert-manager -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Istio:**
```bash
kubectl get deployment -n istio-system istiod -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**LWS:**
```bash
kubectl get deployment -n lws-system lws-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || \
kubectl get deployment -n openshift-lws-operator -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'
```

---

## 5. Troubleshooting Commands

### 5.1 Pod Not Running

```bash
# Get pod details
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# For multi-container pods (like LWS controller)
kubectl logs <pod-name> -n <namespace> -c <container-name>
```

### 5.2 CRD Issues

```bash
# List all CRDs
kubectl get crd

# Check CRD status
kubectl describe crd <crd-name>

# Verify API resources are available
kubectl api-resources | grep -E "(cert-manager|istio|leaderworkerset)"
```

### 5.3 Operator Logs

**cert-manager:**
```bash
kubectl logs -n cert-manager-operator deployment/cert-manager-operator-controller-manager --tail=100
# Or for upstream:
kubectl logs -n cert-manager deployment/cert-manager --tail=100
```

**Istio:**
```bash
kubectl logs -n istio-system deployment/istiod --tail=100
# Check operator logs:
kubectl logs -n istio-system deployment/servicemesh-operator3 --tail=100
# Or for upstream:
kubectl logs -n sail-operator deployment/sail-operator --tail=100
```

**LWS:**
```bash
kubectl logs -n openshift-lws-operator deployment/openshift-lws-operator --tail=100
# Or:
kubectl logs -n lws-system deployment/lws-controller-manager -c manager --tail=100
```

### 5.4 Check Events

```bash
# All events in operator namespaces
kubectl get events -n cert-manager --sort-by='.lastTimestamp'
kubectl get events -n istio-system --sort-by='.lastTimestamp'
kubectl get events -n lws-system --sort-by='.lastTimestamp'
kubectl get events -n openshift-lws-operator --sort-by='.lastTimestamp'
```

### 5.5 Restart Operators

```bash
# cert-manager
kubectl rollout restart deployment -n cert-manager cert-manager
kubectl rollout restart deployment -n cert-manager cert-manager-cainjector
kubectl rollout restart deployment -n cert-manager cert-manager-webhook

# Istio
kubectl rollout restart deployment -n istio-system istiod

# LWS
kubectl rollout restart deployment -n lws-system lws-controller-manager
```

---

## 6. Red Hat Operator Specific Checks

### 6.1 Verify Red Hat Registry Authentication

```bash
# Check if pull secret exists
cat ~/.config/containers/auth.json | jq -r '.auths | keys[]' | grep registry.redhat.io
```

**Expected:** `registry.redhat.io`

### 6.2 Test Red Hat Image Pull

```bash
podman pull registry.redhat.io/ubi8/ubi-minimal --quiet && echo "✅ Red Hat registry access OK"
```

### 6.3 Check Red Hat Operator Custom Resources

**cert-manager operator:**
```bash
kubectl get certmanager --all-namespaces
```

**sail-operator:**
```bash
kubectl get istio -n istio-system
kubectl get istiorevision --all-namespaces
```

**LWS operator:**
```bash
kubectl get leaderworkersetoperator --all-namespaces 2>/dev/null || echo "CRD may not exist for this operator"
```

### 6.4 llm-d-infra-xks Status (if used)

```bash
cd ~/llm-d-infra-xks
helmfile status
```

---

## 7. Success Criteria Checklist

### ✅ cert-manager
- [ ] All 3 pods Running (cert-manager, cainjector, webhook)
- [ ] 6 CRDs exist
- [ ] Test certificate creation succeeds
- [ ] Webhook responding (check logs for webhook calls)

### ✅ Istio / sail-operator
- [ ] istiod pod Running
- [ ] Istio CR shows Ready=True
- [ ] 14+ Istio CRDs exist
- [ ] Sidecar injection works in labeled namespaces
- [ ] `pilot-discovery version` returns Istio version

### ✅ LWS
- [ ] lws-controller-manager Running (2/2 containers)
- [ ] LeaderWorkerSet CRD exists
- [ ] Test LeaderWorkerSet creates leader + worker pods
- [ ] Controller logs show no errors

### ✅ Integration
- [ ] All operator pods Running with no restarts
- [ ] All CRDs installed and available
- [ ] No error events in operator namespaces
- [ ] Test resources create successfully

---

## 8. Quick Verification Script

Save as `verify-operators.sh`:

```bash
#!/bin/bash
set -e

echo "========================================="
echo "Operator Verification Script"
echo "========================================="
echo ""

# cert-manager
echo "🔒 cert-manager:"
CERT_PODS=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | wc -l)
CERT_RUNNING=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -c Running || echo "0")
echo "  Pods: $CERT_RUNNING/$CERT_PODS Running"
CERT_CRDS=$(kubectl get crd 2>/dev/null | grep -c cert-manager)
echo "  CRDs: $CERT_CRDS/6"
echo ""

# Istio
echo "⛵ Istio:"
ISTIO_PODS=$(kubectl get pods -n istio-system --no-headers 2>/dev/null | wc -l)
ISTIO_RUNNING=$(kubectl get pods -n istio-system --no-headers 2>/dev/null | grep -c Running || echo "0")
echo "  Pods: $ISTIO_RUNNING/$ISTIO_PODS Running"
ISTIO_CRDS=$(kubectl get crd 2>/dev/null | grep -c istio)
echo "  CRDs: $ISTIO_CRDS/14+"
ISTIO_READY=$(kubectl get istio --all-namespaces --no-headers 2>/dev/null | grep -c True || echo "0")
echo "  Istio CR Ready: $ISTIO_READY"
echo ""

# LWS
echo "👥 LWS:"
LWS_PODS=$(kubectl get pods -n lws-system --no-headers 2>/dev/null | wc -l)
if [ "$LWS_PODS" -eq 0 ]; then
    LWS_PODS=$(kubectl get pods -n openshift-lws-operator --no-headers 2>/dev/null | wc -l)
    LWS_RUNNING=$(kubectl get pods -n openshift-lws-operator --no-headers 2>/dev/null | grep -c Running || echo "0")
    LWS_NS="openshift-lws-operator"
else
    LWS_RUNNING=$(kubectl get pods -n lws-system --no-headers 2>/dev/null | grep -c Running || echo "0")
    LWS_NS="lws-system"
fi
echo "  Namespace: $LWS_NS"
echo "  Pods: $LWS_RUNNING/$LWS_PODS Running"
LWS_CRDS=$(kubectl get crd 2>/dev/null | grep -c leaderworkerset)
echo "  CRDs: $LWS_CRDS/1"
echo ""

echo "========================================="
echo "Overall Status:"
echo "========================================="

TOTAL_EXPECTED=9  # Adjust based on your deployment
TOTAL_RUNNING=$((CERT_RUNNING + ISTIO_RUNNING + LWS_RUNNING))

if [ "$TOTAL_RUNNING" -ge "$TOTAL_EXPECTED" ] && [ "$CERT_CRDS" -eq 6 ] && [ "$ISTIO_CRDS" -ge 14 ] && [ "$LWS_CRDS" -eq 1 ]; then
    echo "✅ All operators healthy!"
    exit 0
else
    echo "⚠️  Some operators may have issues. Check details above."
    exit 1
fi
```

**Run:**
```bash
chmod +x verify-operators.sh
./verify-operators.sh
```

---

## 9. Next Steps After Verification

Once all operators are verified:

1. ✅ **Enable GKE Inference Gateway** (GKE deployments)
2. ✅ **Install Gateway Provider CRDs** (InferencePool, InferenceObjective)
3. ✅ **Deploy llm-d Pattern 1** (vLLM with intelligent routing)
4. ✅ **Configure HTTPRoute** (connect Gateway to InferencePool)
5. ✅ **Test inference endpoints**

Refer to the main deployment guides for these steps.

---

## Summary

**Quick health check:** All pods Running, all CRDs exist, test resources create successfully.

**Most common issues:**
1. Image pull errors (check Red Hat pull secret for Red Hat operators)
2. CRD installation timing (wait for CRDs before deploying CRs)
3. Namespace confusion (upstream vs Red Hat operators use different namespaces)

**If everything is healthy:** Proceed with deploying llm-d and configuring inference routing!
