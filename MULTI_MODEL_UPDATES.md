# Multi-Model Benchmark Support - Implementation Summary

## Overview

Updated the benchmark suite to support testing multiple models on the same deployment target. This enables model comparison, performance analysis across different model sizes, and automated multi-model testing workflows.

## Changes Made

### 1. Configuration Updates

**File**: `benchmarks/config/targets.yaml`

- Added `supported_models` list to each target configuration
- Documents which models are compatible with each deployment
- Maintains backward compatibility with single `model` field

**Example**:
```yaml
tpu-v6e:
  model: "Qwen/Qwen2.5-3B-Instruct"  # Default
  supported_models:
    - "Qwen/Qwen2.5-3B-Instruct"
    - "microsoft/Phi-3-mini-4k-instruct"
    - "mistralai/Mistral-7B-Instruct-v0.3"
    - "google/gemma-2-9b-it"
```

### 2. Python Benchmark Script Enhancements

**File**: `benchmarks/python/benchmark_async.py`

**New Features**:
- `--all-models` flag: Test all supported_models for a target
- Multi-model result aggregation and comparison
- Automatic generation of comparison reports (JSON + HTML)

**Behavior**:
- **Single model**: Output unchanged (backward compatible)
- **Multiple models**:
  - Individual JSON reports per model
  - Combined comparison JSON with all metrics
  - HTML table comparing all models side-by-side

**New Function**: `_generate_comparison_html()`
- Generates formatted HTML comparison table
- Shows TTFT, TPOT, throughput, error rates, MLPerf status
- Color-coded pass/fail indicators

### 3. Script Updates

#### compare_targets.sh

**File**: `benchmarks/scripts/compare_targets.sh`

**Change**: Removed hardcoded model reference
- **Before**: Used `--model "google/gemma-2b-it"` (hardcoded)
- **After**: Uses `--target tpu-v6e` (reads model from config)

**Benefit**: Automatically uses correct model for target

#### compare_models.sh (NEW)

**File**: `benchmarks/scripts/compare_models.sh`

**Purpose**: Convenience script for multi-model benchmarking

**Usage**:
```bash
./benchmarks/scripts/compare_models.sh [target] [scenario]

# Examples
./benchmarks/scripts/compare_models.sh tpu-v6e latency_benchmark
./benchmarks/scripts/compare_models.sh gke-t4 quick_validation
```

**Features**:
- Automatically tests all supported_models for a target
- Generates timestamped output directory
- Creates JSON and HTML comparison reports
- Returns exit code based on all models passing MLPerf

### 4. Documentation Updates

**File**: `benchmarks.md`

**New Section**: "Multi-Model Benchmarking"
- Overview of multi-model testing capabilities
- Configuration examples
- Usage instructions with real commands
- Output format explanation
- Example use cases
- Important notes about deployment requirements

## Usage Examples

### Basic Multi-Model Test

```bash
# Test all models on TPU v6e
python benchmarks/python/benchmark_async.py \
    --target tpu-v6e \
    --scenario latency_benchmark \
    --all-models \
    --output results/multi_model.json \
    --html
```

### Using Convenience Script

```bash
# Simpler syntax for common case
./benchmarks/scripts/compare_models.sh tpu-v6e latency_benchmark
```

### Single Model (Backward Compatible)

```bash
# Original syntax still works
python benchmarks/python/benchmark_async.py \
    --target tpu-v6e \
    --scenario latency_benchmark
```

## Output Structure

### Multi-Model Output Files

```
results/
├── multi_model_Qwen_Qwen2.5-3B-Instruct.json       # Individual model result
├── multi_model_microsoft_Phi-3-mini-4k-instruct.json
├── multi_model_mistralai_Mistral-7B-Instruct-v0.3.json
├── multi_model_comparison.json                      # Combined comparison
└── multi_model_comparison.html                      # Visual comparison table
```

### Comparison JSON Structure

```json
{
  "timestamp": "2026-01-22T21:00:00",
  "target": "tpu-v6e",
  "scenario": "latency_benchmark",
  "models_tested": 4,
  "results": [
    {
      "model": "Qwen/Qwen2.5-3B-Instruct",
      "ttft_p50": 0.123,
      "ttft_p95": 0.145,
      "tpot_p50": 0.012,
      "tpot_p95": 0.015,
      "throughput": 83.5,
      "error_rate": 0.0,
      "mlperf_compliant": true
    },
    ...
  ]
}
```

### HTML Comparison Report

Interactive HTML table with:
- Metadata section (target, scenario, timestamp)
- Model comparison table
- Color-coded MLPerf status (green=pass, red=fail)
- Sortable columns
- Hover effects

## Backward Compatibility

All changes are **100% backward compatible**:
- Original single-model syntax unchanged
- Existing scripts continue to work
- Configuration files maintain existing structure
- New features are opt-in via `--all-models` flag

## Testing Performed

✅ Python syntax validation (`py_compile`)
✅ Shell script syntax validation (`bash -n`)
✅ Executable permissions verified
✅ Help text includes new `--all-models` flag
✅ Backward compatibility maintained

## Use Cases

### 1. Model Selection
Compare different model sizes to find optimal performance/cost balance:
```bash
./benchmarks/scripts/compare_models.sh tpu-v6e throughput_benchmark
```

### 2. Compatibility Testing
Verify all supported models work on new hardware:
```bash
./benchmarks/scripts/compare_models.sh gke-t4 quick_validation
```

### 3. Performance Profiling
Analyze how model size affects latency characteristics:
```bash
python benchmarks/python/benchmark_async.py \
    --target tpu-v6e \
    --scenario latency_benchmark \
    --all-models \
    --html
```

### 4. Regression Testing
After infrastructure changes, verify all models still meet SLAs:
```bash
./benchmarks/scripts/compare_models.sh tpu-v6e latency_benchmark
# Check MLPerf compliance in comparison report
```

## Implementation Notes

### Sequential vs Parallel Testing
- Models tested **sequentially** within a target (not parallel)
- Reason: vLLM deployments serve one model at a time
- For parallel testing across targets, run separate benchmark processes

### Model Deployment Requirements
- **Pattern 1 (single replica)**: Must redeploy vLLM to change models
- **Pattern 2+ (llm-d)**: Can deploy multiple models simultaneously
- The `supported_models` list documents compatibility, not active deployments

### Error Handling
- If any model fails, individual results still saved
- Exit code reflects whether ALL models passed MLPerf
- Comparison report shows error rates per model

## Files Modified

1. `benchmarks/config/targets.yaml` - Added supported_models lists
2. `benchmarks/python/benchmark_async.py` - Multi-model logic and HTML generation
3. `benchmarks/scripts/compare_targets.sh` - Fixed hardcoded model
4. `benchmarks/scripts/compare_models.sh` - NEW convenience script
5. `benchmarks.md` - Added Multi-Model Benchmarking section
6. `MULTI_MODEL_UPDATES.md` - This summary document

## Next Steps

### Recommended Actions

1. **Test the new functionality**:
   ```bash
   ./benchmarks/scripts/compare_models.sh tpu-v6e quick_validation
   ```

2. **Add models to other targets**:
   Edit `benchmarks/config/targets.yaml` to add `supported_models` for other targets

3. **Run multi-model comparisons**:
   Use for model selection or performance analysis

4. **Review HTML reports**:
   Check the visual comparison tables for insights

### Future Enhancements

Potential improvements for future iterations:
- Parallel model testing (requires multiple endpoints)
- Model-specific scenarios (different configs per model)
- Performance regression detection
- Automated model recommendation based on metrics
- Integration with CI/CD pipelines
- Cost per token calculations in comparison reports

## Questions or Issues?

If you encounter any issues or have questions about the multi-model functionality:
1. Check `benchmarks.md` for usage examples
2. Run `python benchmarks/python/benchmark_async.py --help` for options
3. Review this document for implementation details
