# LLM Inference Benchmarking Suite

Comprehensive benchmarking tools for measuring performance of LLM inference deployments on GKE with GPU/TPU accelerators. Supports vLLM, Ollama, LM Studio, OpenAI-compatible APIs, and llm-d multi-model deployments.

## Table of Contents

- [Quick Start](#quick-start)
- [Benchmark Tools](#benchmark-tools)
  - [Python Tools](#python-tools)
  - [Shell Scripts](#shell-scripts)
- [Test Scenarios](#test-scenarios)
- [Deployment Targets](#deployment-targets)
- [Metrics Explained](#metrics-explained)
- [Results and Reports](#results-and-reports)

---

## Quick Start

### Prerequisites

```bash
# Install Python dependencies
pip install --user numpy aiohttp pyyaml

# Make scripts executable
chmod +x scripts/*.sh
```

### Run a Quick Test

```bash
# Test a configured target
python3 python/benchmark_async.py \
  --target llm-d-pattern2-gpu \
  --scenario quick_validation

# Or test any OpenAI-compatible endpoint
scripts/quick_test.sh http://35.209.92.117 "microsoft/Phi-3-mini-4k-instruct"
```

### Run a Comprehensive Benchmark

```bash
# Latency benchmark (TTFT/TPOT focused)
python3 python/benchmark_async.py \
  --target tpu-v6e \
  --scenario latency_benchmark \
  --output results/my_test.json \
  --html

# Test all models for a multi-model deployment
python3 python/benchmark_async.py \
  --target llm-d-pattern2-gpu \
  --scenario latency_benchmark \
  --all-models \
  --output results/multi_model.json
```

---

## Benchmark Tools

### Python Tools

#### 1. `benchmark_async.py` - Main Async Benchmark

**Purpose**: Comprehensive async benchmarking tool for measuring TTFT, TPOT, throughput, and latency.

**Features**:
- Configurable targets and scenarios via YAML files
- Multi-model testing with `--all-models` flag
- JSON and HTML report generation
- MLPerf compliance checking
- Supports prompt size variations

**Usage**:
```bash
# Using configured target and scenario
python3 python/benchmark_async.py \
  --target gke-t4 \
  --scenario latency_benchmark

# Custom benchmark with specific parameters
python3 python/benchmark_async.py \
  --base-url http://localhost:8000 \
  --model "my-model" \
  --num-requests 100 \
  --concurrency 10 \
  --max-tokens 200

# Test all supported models for a target
python3 python/benchmark_async.py \
  --target llm-d-pattern2-gpu \
  --all-models \
  --scenario quick_validation
```

**Key Arguments**:
- `--target`: Pre-configured deployment target (from `config/targets.yaml`)
- `--scenario`: Pre-configured test scenario (from `config/test_scenarios.yaml`)
- `--all-models`: Test all `supported_models` for the target
- `--base-url`: Custom API endpoint (overrides target)
- `--model`: Specific model to test (overrides target default)
- `--num-requests`: Number of requests to send
- `--concurrency`: Concurrent requests
- `--max-tokens`: Tokens to generate per request
- `--output`: Save results to JSON file
- `--html`: Also generate HTML report

**Limitations**:
- No built-in retry logic for intermittent routing issues
- May show lower success rates (~40-60%) for Pattern 2 deployments

---

#### 2. `pattern2_benchmark_retry.py` - Pattern 2 with Retry Logic

**Purpose**: Custom benchmark specifically designed for Pattern 2 unified routing with built-in retry logic to handle EPP backend discovery intermittency.

**Features**:
- Exponential backoff retry logic (max 10 attempts, 2s delay)
- 100% success rate for Pattern 2 multi-model routing
- Retry statistics (avg/max attempts)
- Tests both models through single gateway

**Usage**:
```bash
# Run benchmark (defaults: 25 requests per model)
python3 python/pattern2_benchmark_retry.py
```

**What It Tests**:
- Routes requests to both `microsoft/Phi-3-mini-4k-instruct` and `google/gemma-2b-it`
- All requests go through Pattern 2 Gateway (35.209.92.117)
- Measures TTFT, TPOT, latency, and retry attempts
- Verifies unified routing accuracy

**Results**: See `PATTERN2_GPU_RESULTS.md` for detailed findings.

---

#### 3. `locustfile.py` - Load Testing with Locust

**Purpose**: Sustained load testing with realistic traffic patterns using the Locust framework.

**Features**:
- Progressive user spawn rates
- Mixed prompt size distribution
- Real-time web dashboard
- Distributed load generation support

**Usage**:
```bash
# Start Locust web interface
locust -f python/locustfile.py --host http://35.209.92.117

# Headless mode with specific parameters
locust -f python/locustfile.py \
  --host http://35.209.92.117 \
  --users 50 \
  --spawn-rate 10 \
  --run-time 10m \
  --headless
```

**Access**: Open http://localhost:8089 in browser for interactive dashboard.

---

### Shell Scripts

#### 1. `quick_test.sh` - Fast Validation

**Purpose**: Quick health check and basic inference test.

**What It Tests**:
1. `/health` endpoint availability
2. `/v1/models` endpoint and model availability
3. Single completion request
4. Response validation

**Usage**:
```bash
./scripts/quick_test.sh [base_url] [model_name]

# Examples
./scripts/quick_test.sh http://35.209.92.117 "microsoft/Phi-3-mini-4k-instruct"
./scripts/quick_test.sh http://localhost:11434 "llama3.2:3b"  # Ollama
./scripts/quick_test.sh https://api.openai.com "gpt-3.5-turbo"  # OpenAI
```

**Output**:
- ✓/✗ Health check status
- ✓/✗ Model availability
- ✓/✗ Completion request success
- Response text sample

---

#### 2. `compare_targets.sh` - GPU vs TPU Comparison

**Purpose**: Compare performance between GPU and TPU deployments using the same benchmark scenario.

**What It Tests**:
- Runs identical latency benchmark on both targets
- Generates side-by-side comparison report
- Highlights performance differences

**Usage**:
```bash
./scripts/compare_targets.sh [tpu_ip]

# Example
./scripts/compare_targets.sh 35.214.154.17
```

**Output**: Comparison results in `results/comparison_YYYYMMDD_HHMMSS/`

---

#### 3. `compare_models.sh` - Multi-Model Comparison

**Purpose**: Benchmark multiple models on the same deployment target.

**What It Tests**:
- Tests each supported model with same scenario
- Compares TTFT, TPOT, throughput across models
- Identifies best model for specific workloads

**Usage**:
```bash
./scripts/compare_models.sh [target_name]

# Example
./scripts/compare_models.sh tpu-v6e
```

---

#### 4. `ab_benchmark.sh` - Apache Bench Testing

**Purpose**: Simple HTTP load testing using Apache Bench (`ab` tool).

**What It Tests**:
- Raw HTTP request throughput
- Connection handling
- Basic latency under load

**Usage**:
```bash
./scripts/ab_benchmark.sh [base_url] [num_requests] [concurrency]

# Example
./scripts/ab_benchmark.sh http://35.209.92.117 1000 10
```

**Note**: Less sophisticated than Python tools; useful for quick load testing.

---

#### 5. `pattern3_comprehensive_benchmark.sh` - Pattern 3 Specific

**Purpose**: Comprehensive benchmark for Pattern 3 GPU caching scale-out deployment.

**What It Tests**:
- Prefix caching efficiency (warm vs cold requests)
- Scale-out performance (3 replica distribution)
- Intelligent routing with prefix-cache-scorer

**Usage**:
```bash
./scripts/pattern3_comprehensive_benchmark.sh
```

---

## Test Scenarios

Defined in `config/test_scenarios.yaml`. Each scenario has specific parameters and success criteria.

### `quick_validation`

**Purpose**: Fast health check with basic latency measurement

**Parameters**:
- 10 requests, concurrency: 1
- Prompt sizes: 50, 100, 500 tokens
- Max tokens: 100
- Duration: 60 seconds
- Warmup: 2 requests

**Use When**: Quick smoke test after deployment or configuration changes.

---

### `latency_benchmark`

**Purpose**: Measure Time to First Token (TTFT) and Time Per Output Token (TPOT)

**Parameters**:
- 100 requests, concurrency: 1
- Prompt sizes: 10, 50, 100, 500, 1000, 2000 tokens
- Max tokens: 50, 100, 200, 500
- Warmup: 5 requests

**MLPerf Targets**:
- **Standard**: TTFT p95 ≤ 2.0s, TPOT p95 ≤ 100ms
- **Interactive**: TTFT p95 ≤ 0.5s, TPOT p95 ≤ 30ms

**Use When**: Measuring responsiveness and token generation speed.

---

### `throughput_benchmark`

**Purpose**: Maximum tokens/sec and requests/sec with progressive concurrency

**Parameters**:
- 500 requests total
- Concurrency levels: 1, 5, 10, 20, 50
- Prompt sizes: 100, 500 tokens
- Max tokens: 100, 200
- Duration: 300 seconds (5 minutes)
- Error threshold: 5% (stops if exceeded)

**Use When**: Finding maximum sustainable throughput and optimal concurrency.

---

### `load_test`

**Purpose**: Sustained load with realistic traffic patterns

**Parameters**:
- Users: 10, 25, 50, 75, 100
- Spawn rate: 10 users/second
- Duration: 600 seconds (10 minutes)
- Prompt distribution: 40% short, 40% medium, 20% long
- Response distribution: 50% short, 50% long

**Use When**: Simulating production traffic patterns and sustained load.

---

### `stress_test`

**Purpose**: Progressive load increase to find breaking point

**Parameters**:
- Users: 1, 5, 10, 25, 50, 100, 150, 200 (progressive)
- Spawn rate: 5 users/second
- Step duration: 120 seconds per concurrency level
- Error threshold: 5% (stops if exceeded)
- Latency threshold: p95 > 10s (stops if exceeded)

**Use When**: Capacity planning and identifying system limits.

---

## Deployment Targets

Defined in `config/targets.yaml`. Each target represents a deployment configuration.

### GPU Deployments

#### `gke-t4`
- **Name**: GKE NVIDIA T4 (vLLM)
- **URL**: http://136.116.159.221:8000
- **Model**: google/gemma-2b-it
- **Accelerator**: T4 GPU (13.12 GiB)
- **Backend**: vLLM + XFormers
- **Expected Concurrency**: 86
- **Zone**: us-central1-a

#### `llm-d-pattern2-gpu`
- **Name**: llm-d Pattern 2 GPU Multi-Model (2x T4)
- **URL**: http://35.209.92.117
- **Model**: microsoft/Phi-3-mini-4k-instruct (default)
- **Accelerator**: 2x NVIDIA T4 GPU
- **Backend**: vLLM + XFormers
- **Routing**: Unified Scheduler (model-based routing with dynamic discovery)
- **Expected Concurrency**: 40
- **Supported Models**:
  - microsoft/Phi-3-mini-4k-instruct
  - google/gemma-2b-it
- **Special Note**: Use `pattern2_benchmark_retry.py` for reliable testing due to EPP discovery intermittency

#### `llm-d-pattern3-gpu`
- **Name**: llm-d Pattern 3 GPU (3x T4)
- **URL**: http://35.208.175.15
- **Model**: Qwen/Qwen2.5-3B-Instruct
- **Accelerator**: 3x NVIDIA T4 GPU
- **Backend**: vLLM + FLASHINFER
- **Routing**: Intelligent (prefix-cache-scorer weight 3.0)
- **Prefix Caching**: Enabled
- **Expected Concurrency**: 120
- **Zone**: us-central1-a

---

### TPU Deployments

#### `tpu-v6e`
- **Name**: TPU v6e (vLLM)
- **URL**: http://35.214.154.17
- **Model**: Qwen/Qwen2.5-3B-Instruct
- **Accelerator**: TPU v6e (4 chips)
- **Backend**: vLLM + JAX/XLA
- **Expected Concurrency**: 50
- **Zone**: europe-west4-a
- **Special Note**: XLA precompilation during startup (~151s), fast inference after Ready

---

### Local Deployments

#### `ollama-local`
- **URL**: http://localhost:11434
- **Model**: llama3.2:3b
- **Backend**: Ollama
- **Note**: Requires Ollama running locally (https://ollama.ai)

#### `lmstudio-local`
- **URL**: http://localhost:1234
- **Model**: local-model
- **Backend**: LM Studio
- **Note**: Requires LM Studio with model loaded

#### `llamacpp-local`
- **URL**: http://localhost:8080
- **Model**: gpt-3.5-turbo
- **Backend**: llama.cpp
- **Note**: Requires llama.cpp server running with --port 8080

---

### Cloud API Providers

#### `openai-gpt4`
- **URL**: https://api.openai.com
- **Model**: gpt-4-turbo-preview
- **Note**: Requires `OPENAI_API_KEY` environment variable. Costs apply.

#### `openai-gpt35`
- **URL**: https://api.openai.com
- **Model**: gpt-3.5-turbo
- **Note**: Requires `OPENAI_API_KEY` environment variable. Costs apply.

---

## Metrics Explained

### Time to First Token (TTFT)

**Definition**: Time from request sent to first token received.

**What It Measures**: Model loading, prompt processing, and initial token generation latency.

**Importance**:
- Critical for interactive applications (chatbots, assistants)
- User-perceived responsiveness
- Indicates scheduling and queueing delays

**Targets**:
- **Interactive**: p95 ≤ 500ms
- **Standard**: p95 ≤ 2.0s

**Factors**:
- Prompt length (longer = higher TTFT)
- Model size (larger = higher TTFT)
- GPU/TPU utilization
- Request queueing

---

### Time Per Output Token (TPOT)

**Definition**: Average time to generate each output token (after TTFT).

**What It Measures**: Pure generation speed of the model.

**Importance**:
- Determines streaming response speed
- Affects throughput (tokens/sec)
- Model efficiency indicator

**Targets**:
- **Interactive**: p95 ≤ 30ms
- **Standard**: p95 ≤ 100ms

**Factors**:
- Model size and architecture
- GPU/TPU compute performance
- Memory bandwidth
- KV cache efficiency

**Calculation**: `TPOT = (Total Latency - TTFT) / (Tokens Generated - 1)`

---

### End-to-End Latency

**Definition**: Total time from request sent to response complete.

**What It Measures**: Complete request processing time.

**Formula**: `Latency = TTFT + (TPOT × Tokens Generated)`

**Importance**:
- Overall user experience
- SLA compliance
- System capacity planning

---

### Throughput

**Definition**: Number of tokens or requests processed per second.

**Metrics**:
- **Tokens/sec**: Total tokens generated ÷ total time
- **Requests/sec**: Total requests ÷ total time

**What It Measures**: System capacity and efficiency.

**Importance**:
- Determines how many users can be served
- Cost efficiency (tokens per dollar)
- Resource utilization

**Factors**:
- Concurrency level
- Batch size
- Model size
- Hardware capabilities

---

### Success Rate

**Definition**: Percentage of requests that complete successfully without errors.

**What It Measures**: System reliability and stability.

**Targets**:
- **Production**: ≥ 99.9%
- **Testing**: ≥ 95%

**Common Issues**:
- Timeouts under high load
- OOM errors
- Routing failures (Pattern 2 without retry logic)
- Backend unavailability

---

### Percentiles (p50, p95, p99)

**p50 (Median)**: 50% of requests are faster than this value.
**p95**: 95% of requests are faster than this value (5% slower).
**p99**: 99% of requests are faster than this value (1% slower).

**Why p95/p99 Matter**:
- Mean can be misleading (hides outliers)
- p95 represents "typical worst case"
- p99 shows tail latency
- SLAs often use p95 or p99 targets

---

## Results and Reports

### Directory Structure

```
results/
├── comparison_YYYYMMDD_HHMMSS/     # Target comparisons
│   ├── gpu_results.json
│   ├── tpu_results.json
│   └── comparison_report.html
├── my_test.json                     # Custom benchmark results
├── my_test.html                     # HTML visualization
└── pattern3_YYYYMMDD_HHMMSS/       # Pattern-specific tests
    └── comprehensive_results.json
```

### JSON Report Format

```json
{
  "timestamp": "2026-01-26T17:01:07.665394",
  "target": "llm-d-pattern2-gpu",
  "scenario": "latency_benchmark",
  "base_url": "http://35.209.92.117",
  "model": "microsoft/Phi-3-mini-4k-instruct",
  "results": {
    "total_requests": 100,
    "successful": 100,
    "failed": 0,
    "success_rate": 100.0,
    "ttft_ms": {
      "mean": 1849.0,
      "p50": 1905.7,
      "p95": 1993.7,
      "p99": 2000.0
    },
    "tpot_ms": {
      "mean": 45.2,
      "p50": 44.8,
      "p95": 50.1,
      "p99": 55.0
    },
    "latency_s": {
      "mean": 1.85,
      "p50": 1.91,
      "p95": 1.99,
      "p99": 2.05
    },
    "throughput": {
      "tokens_per_sec": 125.5,
      "requests_per_sec": 2.5
    },
    "mlperf_compliant": true
  }
}
```

### HTML Reports

Generated with `--html` flag. Includes:
- Interactive charts (TTFT, TPOT, latency distributions)
- Percentile tables
- MLPerf compliance indicators
- Throughput graphs
- Error analysis

**View**: Open `.html` file in web browser.

---

## Common Testing Workflows

### 1. Quick Smoke Test After Deployment

```bash
# Validate deployment is healthy
./scripts/quick_test.sh http://35.209.92.117 "microsoft/Phi-3-mini-4k-instruct"

# If successful, run quick validation scenario
python3 python/benchmark_async.py \
  --target llm-d-pattern2-gpu \
  --scenario quick_validation
```

---

### 2. Compare GPU Models

```bash
# Test all supported models on a target
python3 python/benchmark_async.py \
  --target tpu-v6e \
  --scenario latency_benchmark \
  --all-models \
  --output results/model_comparison.json \
  --html

# View results
open results/model_comparison.html  # macOS
xdg-open results/model_comparison.html  # Linux
```

---

### 3. Find Optimal Concurrency

```bash
# Run throughput benchmark with progressive concurrency
python3 python/benchmark_async.py \
  --target gke-t4 \
  --scenario throughput_benchmark \
  --output results/concurrency_test.json \
  --html

# Analyze results to find sweet spot where throughput plateaus
```

---

### 4. Validate Pattern 2 Multi-Model Routing

```bash
# Use retry-aware benchmark for reliable results
python3 python/pattern2_benchmark_retry.py

# Expected: 100% success rate with both models
```

---

### 5. Stress Test to Find Limits

```bash
# Progressive load increase until breaking point
python3 python/benchmark_async.py \
  --target llm-d-pattern3-gpu \
  --scenario stress_test \
  --output results/stress_test.json

# Monitor: Success rate drops or p95 latency exceeds threshold
```

---

### 6. Production Readiness Check

```bash
# 1. Latency benchmark
python3 python/benchmark_async.py \
  --target my-deployment \
  --scenario latency_benchmark \
  --output results/prod_readiness_latency.json

# 2. Load test (sustained traffic)
python3 python/benchmark_async.py \
  --target my-deployment \
  --scenario load_test \
  --output results/prod_readiness_load.json

# 3. Review results
# - TTFT p95 < 2.0s?
# - Success rate > 99%?
# - p95 latency stable under load?
```

---

## Troubleshooting

### Low Success Rates (Pattern 2)

**Problem**: `benchmark_async.py` shows 40-60% success rate for Pattern 2

**Cause**: EPP backend discovery intermittency

**Solution**: Use `pattern2_benchmark_retry.py` instead, which includes retry logic.

---

### High TTFT Values

**Possible Causes**:
1. **Cold start**: First requests trigger model loading
2. **Queueing**: Too many concurrent requests
3. **Large prompts**: TTFT scales with prompt length
4. **XLA compilation** (TPU): First inference compiles kernels

**Solutions**:
- Run warmup requests before benchmarking
- Reduce concurrency
- Test with smaller prompts
- Wait for TPU Ready state before testing

---

### Timeout Errors

**Possible Causes**:
1. Model OOM (Out of Memory)
2. Server overloaded
3. Network issues

**Solutions**:
- Check pod logs: `kubectl logs -n llm-d <pod-name>`
- Reduce `--max-tokens` or `--concurrency`
- Increase timeout: Edit `config/targets.yaml` → `timeout: 600`

---

### Connection Refused

**Check**:
```bash
# 1. Is service running?
kubectl get pods -n llm-d

# 2. Is gateway accessible?
curl http://35.209.92.117/health

# 3. Is firewall open?
gcloud compute firewall-rules list | grep allow-llm
```

---

## Adding New Targets

Edit `config/targets.yaml`:

```yaml
my-custom-target:
  name: "My Custom Deployment"
  base_url: "http://my-server.example.com:8000"
  model: "meta-llama/Llama-3.1-8B-Instruct"
  max_tokens: 4096
  accelerator: "A100 GPU"
  backend: "vLLM"
  expected_concurrency: 50
  notes: "Custom deployment description"
  supported_models:  # Optional: for --all-models testing
    - "meta-llama/Llama-3.1-8B-Instruct"
    - "mistralai/Mistral-7B-Instruct-v0.3"
```

Test:
```bash
python3 python/benchmark_async.py --target my-custom-target --scenario quick_validation
```

---

## See Also

- **Pattern 2 GPU Results**: `PATTERN2_GPU_RESULTS.md` - Comprehensive Pattern 2 benchmarking results
- **Target Configurations**: `config/targets.yaml` - All deployment targets
- **Test Scenarios**: `config/test_scenarios.yaml` - Scenario definitions
- **Main Documentation**: `../README.md` - Repository overview

---

## Key Takeaways

1. **Start with `quick_validation`** scenario for smoke tests
2. **Use `latency_benchmark`** for TTFT/TPOT measurement (MLPerf compliance)
3. **Use `throughput_benchmark`** to find optimal concurrency
4. **Pattern 2 requires retry logic** - use `pattern2_benchmark_retry.py`
5. **Always run warmup requests** to avoid cold start skewing results
6. **Monitor p95, not just mean** - tail latency matters
7. **Generate HTML reports** (`--html`) for easy visualization
8. **Test all models** (`--all-models`) for multi-model deployments

---

**Questions or Issues?** See `../README.md` or check existing results in `results/` directory.
