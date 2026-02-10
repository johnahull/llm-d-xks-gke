# LLM API Benchmark Suite

Universal benchmark suite for testing any OpenAI-compatible LLM API, including:
- **vLLM** (NVIDIA GPUs, Google TPUs, AMD GPUs, Intel XPUs)
- **Ollama** (local deployments)
- **LM Studio** (local deployments)
- **llama.cpp** server
- **OpenAI API** (for comparison)
- **Any OpenAI-compatible endpoint**

Follows MLPerf 2025-2026 standards for comprehensive performance measurement (TTFT, TPOT, throughput, latency percentiles).

## Quick Start

### Option A: Use Predefined Target

**1. Configure target** in `benchmarks/config/targets.yaml` (examples included for vLLM, Ollama, LM Studio):

```yaml
targets:
  my-deployment:
    name: "My LLM Deployment"
    base_url: "http://localhost:8000"
    model: "Qwen/Qwen2.5-3B-Instruct"
    max_tokens: 2048
    backend: "vLLM"
```

**2. Run benchmark:**
```bash
python benchmarks/python/benchmark_async.py --target my-deployment --scenario latency_benchmark
```

### Option B: Benchmark Any Endpoint Directly

```bash
# Quick test
./benchmarks/scripts/quick_test.sh http://localhost:8000 "Qwen/Qwen2.5-3B-Instruct"

# Full benchmark
python benchmarks/python/benchmark_async.py \
    --base-url http://localhost:8000 \
    --model "Qwen/Qwen2.5-3B-Instruct" \
    --num-requests 100 \
    --concurrency 10
```

## Supported LLM Providers

### vLLM Deployments
- **GKE with NVIDIA GPUs** - Kubernetes-based (T4, A100, H100)
- **Google Cloud TPUs** - v5e, v6e (with llm-d Gateway)
- **AMD GPUs** - MI250, MI300 series
- **Intel XPUs** - Gaudi accelerators

### Local LLM Servers
- **Ollama** - Default port 11434
- **LM Studio** - Default port 1234
- **llama.cpp server** - Default port 8080

### Cloud APIs
- **OpenAI API** - GPT-4, GPT-3.5 (requires API key)

### 1. Setup Environment

```bash
cd /home/jhull/devel/rhaiis-test
source /home/jhull/devel/venv/bin/activate
./benchmarks/scripts/setup_env.sh
```

### 2. Configure Your Target (Optional)

See `benchmarks/config/targets.yaml` for pre-configured examples:
- `gke-t4` - vLLM on NVIDIA T4 GPU
- `tpu-v6e` - vLLM on Google TPU v6e
- `ollama-local` - Local Ollama deployment
- `lmstudio-local` - Local LM Studio
- `openai-gpt4` - OpenAI API (requires API key)

Add your own target:
```yaml
targets:
  my-deployment:
    name: "My Custom Deployment"
    base_url: "http://my-server.com:8000"
    model: "meta-llama/Llama-3.1-8B-Instruct"
    max_tokens: 8192
    backend: "vLLM"
```

### 3. Examples for Different Providers

**vLLM on GKE (TPU v6e):**
```bash
# Quick test
./benchmarks/scripts/quick_test.sh http://35.214.154.17 "Qwen/Qwen2.5-3B-Instruct"

# Full benchmark
python benchmarks/python/benchmark_async.py --target tpu-v6e --scenario latency_benchmark --html
```

**Ollama (Local):**
```bash
# Start Ollama and pull a model first: ollama pull llama3.2:3b

# Quick test
./benchmarks/scripts/quick_test.sh http://localhost:11434 "llama3.2:3b"

# Full benchmark
python benchmarks/python/benchmark_async.py --target ollama-local --scenario quick_validation
```

**LM Studio (Local):**
```bash
# Load a model in LM Studio and start the server first

# Quick test
./benchmarks/scripts/quick_test.sh http://localhost:1234 "local-model"

# Full benchmark
python benchmarks/python/benchmark_async.py --target lmstudio-local --num-requests 50 --concurrency 5
```

**Custom Endpoint:**
```bash
python benchmarks/python/benchmark_async.py \
    --base-url http://my-server:8000 \
    --model "my-model" \
    --num-requests 100 \
    --concurrency 10 \
    --output results/my_test.json \
    --html
```

## Benchmark Types

### 1. Quick Validation (`quick_test.sh`)

**Purpose**: Fast health check and basic performance validation

**Duration**: 10-20 seconds

**Output**: Console with response time and basic metrics

**When to use**: Verify deployment is working after changes

```bash
# Usage: ./quick_test.sh [base_url] [model_name]
./benchmarks/scripts/quick_test.sh http://localhost:8000 "Qwen/Qwen2.5-3B-Instruct"

# Examples for different providers
./benchmarks/scripts/quick_test.sh http://localhost:11434 "llama3.2:3b"  # Ollama
./benchmarks/scripts/quick_test.sh http://localhost:1234 "local-model"  # LM Studio
./benchmarks/scripts/quick_test.sh http://35.214.154.17 "Qwen/Qwen2.5-3B-Instruct"  # vLLM on GKE
```

### 2. Apache Bench (`ab_benchmark.sh`)

**Purpose**: Simple HTTP load testing with minimal setup

**Duration**: 1-3 minutes

**Output**: Apache Bench statistics, TSV file for analysis

**When to use**: Quick baseline throughput measurement

```bash
# Usage: ./ab_benchmark.sh [base_url] [num_requests] [concurrency] [model_name]
./benchmarks/scripts/ab_benchmark.sh http://localhost:8000 100 10 "Qwen/Qwen2.5-3B-Instruct"

# Examples
./benchmarks/scripts/ab_benchmark.sh http://localhost:11434 50 5 "llama3.2:3b"  # Ollama
./benchmarks/scripts/ab_benchmark.sh http://35.214.154.17 200 20  # Uses default model
```

### 3. Async Python Benchmark (`benchmark_async.py`)

**Purpose**: Comprehensive metrics collection (TTFT, TPOT, throughput, percentiles)

**Duration**: 5-20 minutes (depends on scenario)

**Output**: JSON and/or HTML reports with detailed metrics

**When to use**: Detailed performance analysis, MLPerf compliance validation

```bash
# Using predefined target and scenario
python benchmarks/python/benchmark_async.py \
    --target my-cluster \
    --scenario latency_benchmark \
    --output results/latency.json \
    --html

# Custom parameters
python benchmarks/python/benchmark_async.py \
    --base-url http://$EXTERNAL_IP:8000 \
    --model google/gemma-2b-it \
    --num-requests 100 \
    --concurrency 10 \
    --max-tokens 100 \
    --output results/custom_test.json
```

### 4. Locust Load Test (`locustfile.py`)

**Purpose**: Sustained load with realistic user behavior patterns

**Duration**: 10+ minutes (configurable)

**Output**: HTML report, real-time web UI, CSV time-series data

**When to use**: Production readiness testing, sustained load validation

```bash
# Web UI mode (interactive)
locust -f benchmarks/python/locustfile.py \
       --host http://$EXTERNAL_IP:8000
# Then open http://localhost:8089

# Headless mode (automated)
locust -f benchmarks/python/locustfile.py \
       --host http://$EXTERNAL_IP:8000 \
       --users 50 \
       --spawn-rate 10 \
       --run-time 10m \
       --html benchmarks/results/locust_report.html
```

## Test Scenarios

### Available Scenarios

Scenarios are defined in `benchmarks/config/test_scenarios.yaml`:

- **quick_validation**: 10 requests, fast health check
- **latency_benchmark**: 100 requests, focused TTFT/TPOT measurement
- **throughput_benchmark**: 500 requests with progressive concurrency
- **load_test**: Sustained load with mixed prompt sizes
- **stress_test**: Progressive load increase to find breaking point

### Using Scenarios

```bash
python benchmarks/python/benchmark_async.py \
    --target my-cluster \
    --scenario quick_validation
```

## Multi-Model Benchmarking

### Overview

The benchmark suite supports testing multiple models sequentially to compare performance characteristics across different model sizes and architectures.

### Configuration

Define supported models for each target in `benchmarks/config/targets.yaml`:

```yaml
targets:
  tpu-v6e:
    name: "TPU v6e (vLLM)"
    base_url: "http://35.214.154.17"
    model: "Qwen/Qwen2.5-3B-Instruct"  # Default model
    supported_models:
      - "Qwen/Qwen2.5-3B-Instruct"
      - "microsoft/Phi-3-mini-4k-instruct"
      - "mistralai/Mistral-7B-Instruct-v0.3"
      - "google/gemma-2-9b-it"
```

### Test All Models on a Target

Use the `--all-models` flag to benchmark all supported_models:

```bash
# Test all models defined for tpu-v6e target
python benchmarks/python/benchmark_async.py \
    --target tpu-v6e \
    --scenario latency_benchmark \
    --all-models \
    --output results/multi_model.json \
    --html

# Or use the convenience script
./benchmarks/scripts/compare_models.sh tpu-v6e latency_benchmark
```

### Output

Multi-model benchmarks generate:
1. **Individual reports** - One JSON file per model tested
   - `results/multi_model_Qwen_Qwen2.5-3B-Instruct.json`
   - `results/multi_model_microsoft_Phi-3-mini-4k-instruct.json`
   - etc.

2. **Comparison report** - Combined analysis
   - `results/multi_model_comparison.json` - JSON with all results
   - `results/multi_model_comparison.html` - HTML table comparing metrics

### HTML Comparison Report

The HTML comparison report includes:
- **Side-by-side comparison** of all models tested
- **Key metrics**: TTFT (p50, p95), TPOT (p50, p95), throughput
- **Error rates** and MLPerf compliance status
- **Visual indicators** for pass/fail criteria

### Example Use Cases

**Compare model sizes on same hardware:**
```bash
# Test 2B, 3B, 7B, and 9B models on TPU
./benchmarks/scripts/compare_models.sh tpu-v6e latency_benchmark
```

**Test model compatibility:**
```bash
# Quick validation that all models work
python benchmarks/python/benchmark_async.py \
    --target gke-t4 \
    --scenario quick_validation \
    --all-models
```

**Find optimal model for workload:**
```bash
# Compare throughput across models
python benchmarks/python/benchmark_async.py \
    --target tpu-v6e \
    --scenario throughput_benchmark \
    --all-models \
    --output results/model_selection.json \
    --html
```

### Notes

- Models must be **deployed individually** (only one model per vLLM deployment)
- To test a different model, **redeploy vLLM** with the new model
- For llm-d Pattern 2+, multiple models can be deployed simultaneously
- Multi-model testing is **sequential** (not parallel) within a single target

## Understanding Metrics

### Time to First Token (TTFT)

**Definition**: Time from request submission to receiving the first token

**Includes**:
- Request queueing time
- Prompt processing (prefill) time
- Network latency

**What affects it**:
- Prompt length (longer prompts = higher TTFT)
- Queue depth (more concurrent requests = higher TTFT)
- Model size

**MLPerf Standards**:
- Standard: TTFT p95 ≤ 2.0 seconds
- Interactive: TTFT p95 ≤ 0.5 seconds

### Time Per Output Token (TPOT)

**Definition**: Average time to generate each output token (excluding TTFT)

**Calculation**: (Generation time - TTFT) / (Number of output tokens - 1)

**What affects it**:
- Model size
- Batch size
- KV cache efficiency

**MLPerf Standards**:
- Standard: TPOT p95 ≤ 100 milliseconds
- Interactive: TPOT p95 ≤ 30 milliseconds

### Throughput

**Definition**: Total tokens generated per second across all requests

**What affects it**:
- Concurrency level
- Prompt/output length distribution
- Error rate

### Percentiles (p50, p90, p95, p99)

- **p50 (median)**: 50% of requests are faster
- **p90**: 90% of requests are faster
- **p95**: 95% of requests are faster (MLPerf uses this)
- **p99**: 99% of requests are faster

## Expected Performance Baselines

These baselines are for reference. Your actual performance will vary based on cluster configuration.

### GKE GPU (NVIDIA T4) - Example

**Configuration**:
- Model: google/gemma-2b-it
- GPU: NVIDIA T4 (13.12 GiB memory)
- Max context: 4096 tokens
- Backend: XFormers

**Expected Performance**:
- TTFT (p50): 0.3-0.8s (varies with prompt length)
- TTFT (p95): < 2.0s ✓ MLPerf compliant
- TPOT (p50): 20-50ms
- TPOT (p95): < 100ms ✓ MLPerf compliant
- Throughput: 500-1500 tokens/sec (depends on concurrency)
- Max concurrency: ~86 (based on KV cache)
- Error rate: < 1% under normal load

### GKE TPU (v6e Trillium) - Example

**Configuration**:
- Model: google/gemma-2b-it
- Accelerator: TPU v6e (4 chips, 2x2 topology)
- Max context: 2048 tokens
- Backend: JAX/XLA

**Expected Performance**:
- TTFT (p50): 0.5-2.0s
- TTFT (first request): 5-10s (XLA compilation)
- TPOT (p50): 30-80ms
- Throughput: 400-1200 tokens/sec
- Max concurrency: ~50 (estimated)

## Comparing Different Clusters

```bash
./benchmarks/scripts/compare_targets.sh

# Or manually:
# 1. Run benchmark on first cluster
python benchmarks/python/benchmark_async.py \
    --target cluster-1 \
    --scenario latency_benchmark \
    --output results/cluster1_results.json

# 2. Run benchmark on second cluster
python benchmarks/python/benchmark_async.py \
    --target cluster-2 \
    --scenario latency_benchmark \
    --output results/cluster2_results.json

# 3. Compare results manually or use compare script
```

## Interpreting Results

### Good Performance Indicators

- ✓ Success rate > 99%
- ✓ TTFT p95 < 2.0s (MLPerf standard)
- ✓ TPOT p95 < 100ms (MLPerf standard)
- ✓ Error rate < 1%
- ✓ Consistent performance across percentiles (p95/p50 ratio < 3)

### Warning Signs

- ⚠ Success rate < 95%
- ⚠ TTFT p95 > 5s
- ⚠ TPOT p95 > 200ms
- ⚠ High variance (p99 >> p95)
- ⚠ Error rate > 5%

### Red Flags

- ✗ Success rate < 90%
- ✗ TTFT p95 > 10s
- ✗ TPOT increasing with concurrency
- ✗ Timeout errors
- ✗ Error rate > 10%

## Troubleshooting

### High TTFT

**Possible causes**:
- High queue depth (too many concurrent requests)
- Long prompts
- Network latency

**Solutions**:
- Reduce concurrency
- Check `num_requests_running` metric
- Verify network connectivity

### High TPOT

**Possible causes**:
- KV cache full (memory pressure)
- Too many concurrent requests
- Model size vs. available memory

**Solutions**:
- Reduce `max_tokens`
- Lower concurrency
- Check KV cache usage: `curl http://$EXTERNAL_IP:8000/metrics | grep kv_cache`

### Low Throughput

**Possible causes**:
- Concurrency too low
- Network bottleneck
- High error rate

**Solutions**:
- Increase concurrency gradually
- Check network bandwidth
- Verify error logs

### TPU First Request Slow

**Expected behavior**: First request to TPU triggers XLA compilation (5-10s)

**Solution**: Run warmup requests before benchmarking

### Errors and Timeouts

**Check**:
1. Server logs: `kubectl logs $POD_NAME` (GKE) or `podman logs $CONTAINER_NAME` (standalone)
2. Server health: `curl http://$EXTERNAL_IP:8000/health`
3. Network connectivity
4. Firewall rules

## Integration with Prometheus/Grafana

vLLM exposes Prometheus metrics at `/metrics`:

```bash
# View raw metrics
curl http://$EXTERNAL_IP:8000/metrics

# Filter specific metrics
curl http://$EXTERNAL_IP:8000/metrics | grep vllm
```

**Key metrics**:
- `vllm:e2e_request_latency_seconds_bucket` - Latency histogram
- `vllm:num_requests_running` - Active requests
- `vllm:kv_cache_usage_perc` - KV cache utilization
- `vllm:request_prompt_tokens` - Prompt token distribution
- `vllm:request_generation_tokens` - Generated token distribution

**Grafana Dashboard**: [https://grafana.com/grafana/dashboards/23991-vllm/](https://grafana.com/grafana/dashboards/23991-vllm/)

## Configuration Files

### Targets (`benchmarks/config/targets.yaml`)

Define deployment targets with connection details and expected performance:

```yaml
targets:
  my-cluster:
    base_url: "http://$EXTERNAL_IP:8000"
    model: "$MODEL_NAME"
    max_tokens: $MAX_TOKENS
    description: "My inference cluster"
```

**To update**: Edit `benchmarks/config/targets.yaml` with your cluster details

### Scenarios (`benchmarks/config/test_scenarios.yaml`)

Define test scenarios with parameters:

```yaml
scenarios:
  latency_benchmark:
    num_requests: 100
    concurrency: 1
    prompt_tokens: [10, 50, 100, 500]
    max_tokens: [50, 100, 200]
```

**To add custom scenario**: Edit `benchmarks/config/test_scenarios.yaml`

## Best Practices

### Before Benchmarking

1. Verify deployment is healthy: `./benchmarks/scripts/quick_test.sh`
2. Check resource utilization is normal
3. Ensure no other load on the system
4. Use warmup requests for TPU deployments

### During Benchmarking

1. Start with low concurrency, increase gradually
2. Monitor server metrics (GPU/TPU utilization, memory)
3. Watch for error rates
4. Let tests run to completion for accurate results

### After Benchmarking

1. Review all percentiles, not just averages
2. Check for outliers (p99 vs p95)
3. Correlate with server-side metrics
4. Save results with descriptive names
5. Document any changes between runs

## Common Patterns

### Daily Health Check

```bash
./benchmarks/scripts/quick_test.sh http://$EXTERNAL_IP:8000
```

### Pre-Deployment Validation

```bash
python benchmarks/python/benchmark_async.py \
    --target my-cluster \
    --scenario latency_benchmark \
    --output results/pre_deploy_$(date +%Y%m%d).json \
    --html
```

### Load Testing Before Launch

```bash
locust -f benchmarks/python/locustfile.py \
       --host http://$EXTERNAL_IP:8000 \
       --users 100 \
       --spawn-rate 10 \
       --run-time 30m \
       --html results/pre_launch_load_test.html
```

### Continuous Monitoring

```bash
# Run every hour
python benchmarks/python/benchmark_async.py \
    --target my-cluster \
    --scenario quick_validation \
    --output results/monitoring/$(date +%Y%m%d_%H%M).json
```

## References

- [vLLM Metrics Documentation](https://docs.vllm.ai/en/latest/design/metrics/)
- [MLPerf Inference 5.1](https://mlcommons.org/2025/09/small-llm-inference-5-1/)
- [Anyscale LLM Metrics Guide](https://docs.anyscale.com/llm/serving/benchmarking/metrics)
- [vLLM Prometheus/Grafana Setup](https://docs.vllm.ai/en/v0.7.2/getting_started/examples/prometheus_grafana.html)

## Support

For issues or questions:
- Check troubleshooting section above
- Review `cluster-setup.md` for GKE setup
- Review `tpu-vm-setup.md` for TPU setup
- Check vLLM server logs for errors
