# Network Policies

This directory contains NetworkPolicy manifests for securing the llm-d inference workload.

## Security Model

The security model follows a **default-deny** approach with explicit allow rules:

```
┌─────────────────────────────────────────────────────────┐
│              Network Policy Stack                       │
│                                                         │
│  1. default-deny-all.yaml                               │
│     - Deny all ingress/egress by default               │
│     - Applied to all pods in namespace                 │
│                                                         │
│  2. allow-gateway-to-vllm.yaml                          │
│     - Allow Istio Gateway → vLLM pods (port 8000)      │
│     - Allow kubelet → vLLM health probes               │
│                                                         │
│  3. allow-vllm-egress.yaml                              │
│     - Allow vLLM → HuggingFace Hub (model downloads)   │
│     - Allow vLLM → kube-apiserver (metrics)            │
│     - Allow vLLM → DNS (name resolution)               │
└─────────────────────────────────────────────────────────┘
```

## Policy Files

### 1. default-deny.yaml

**Purpose**: Deny all traffic by default (ingress and egress)

**Applied to**: All pods in `llm-d-inference-scheduling` namespace

**Why**: Defense-in-depth - start from zero-trust and explicitly allow only required traffic

### 2. allow-gateway-to-vllm.yaml

**Purpose**: Allow traffic from Istio Gateway to vLLM pods

**Allowed traffic**:
- Source: Pods in `opendatahub` namespace with label `gateway.networking.k8s.io/gateway-name=inference-gateway`
- Destination: Pods with label `app.kubernetes.io/name=qwen2-3b-pattern1`
- Port: TCP/8000 (vLLM HTTP API)

**Also allows**: Health probes from kubelet (all namespaces, all pods)

**Production note**: In production, restrict health probe source to kubelet IP ranges

### 3. allow-vllm-egress.yaml

**Purpose**: Allow vLLM pods to make outbound connections

**Current configuration**: Allow all egress (PoC)

**Production configuration** (commented in file):
- DNS queries to kube-dns (UDP/53)
- HTTPS to HuggingFace Hub (TCP/443)
- HTTPS to Kubernetes API server (TCP/6443)

## Applying Policies

```bash
# Apply all policies
kubectl apply -f manifests/networkpolicies/

# Verify policies
kubectl get networkpolicies -n llm-d-inference-scheduling

# Describe a specific policy
kubectl describe networkpolicy allow-gateway-to-vllm -n llm-d-inference-scheduling
```

## Testing Network Policies

### Test 1: Gateway → vLLM (Should Succeed)

```bash
# From outside the cluster (through Gateway)
curl http://<GATEWAY_IP>/llm-d-inference-scheduling/qwen2-3b-pattern1/v1/models

# Expected: 200 OK with model list
```

### Test 2: Direct Pod Access (Should Fail)

```bash
# Get vLLM pod IP
VLLM_POD_IP=$(kubectl get pod -n llm-d-inference-scheduling \
  -l app.kubernetes.io/name=qwen2-3b-pattern1 \
  -o jsonpath='{.items[0].status.podIP}')

# Try to access from a test pod in a different namespace
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -m 5 http://$VLLM_POD_IP:8000/v1/models

# Expected: Connection timeout (blocked by NetworkPolicy)
```

### Test 3: Health Probes (Should Succeed)

```bash
# Health probes from kubelet should always work
kubectl get pods -n llm-d-inference-scheduling

# Expected: All pods show "Ready" status
```

## Production Hardening

For production deployments, consider these additional restrictions:

### 1. Restrict Health Probe Source

```yaml
# Replace "allow all pods" with specific kubelet IP ranges
- from:
  - ipBlock:
      cidr: 10.0.0.0/8  # GKE node CIDR
```

### 2. Restrict Egress to Specific Destinations

Uncomment the production example in `allow-vllm-egress.yaml` and customize:

```yaml
# HuggingFace Hub
- to:
  - podSelector: {}
    namespaceSelector: {}
  ports:
  - protocol: TCP
    port: 443
  # Optional: Add specific CIDR blocks for huggingface.co
```

### 3. Add Egress Policy for EPP Scheduler

Create a new policy if EPP scheduler needs to communicate with vLLM:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-epp-to-vllm
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: scheduler
  egress:
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: qwen2-3b-pattern1
    ports:
    - protocol: TCP
      port: 8000
```

### 4. Add Monitoring Egress

If using Prometheus scraping:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: qwen2-3b-pattern1
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
      podSelector:
        matchLabels:
          app.kubernetes.io/name: prometheus
    ports:
    - protocol: TCP
      port: 8000
```

## Troubleshooting

### Pod Can't Download Model

**Symptom**: vLLM pod logs show "Connection timeout" when downloading model

**Diagnosis**: Check egress policy allows HTTPS (TCP/443)

```bash
kubectl describe networkpolicy allow-vllm-egress -n llm-d-inference-scheduling
```

### Gateway Returns 503

**Symptom**: Requests to Gateway return 503 Service Unavailable

**Diagnosis**: Check ingress policy allows Gateway → vLLM

```bash
# Verify Gateway pod labels
kubectl get pods -n opendatahub -l gateway.networking.k8s.io/gateway-name=inference-gateway

# Verify vLLM pod labels
kubectl get pods -n llm-d-inference-scheduling -l app.kubernetes.io/name=qwen2-3b-pattern1

# Check policy
kubectl describe networkpolicy allow-gateway-to-vllm -n llm-d-inference-scheduling
```

### Health Probes Failing

**Symptom**: Pod shows "Not Ready" despite vLLM server running

**Diagnosis**: Check ingress policy allows kubelet probes

```bash
# Check pod events
kubectl describe pod -n llm-d-inference-scheduling <pod-name> | grep -A 10 "Events:"

# Look for "Liveness probe failed" or "Readiness probe failed"
```

## References

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [GKE NetworkPolicy Guide](https://cloud.google.com/kubernetes-engine/docs/how-to/network-policy)
- [Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
