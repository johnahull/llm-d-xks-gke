#!/usr/bin/env python3
"""
Async LLM API Benchmark

Main benchmarking tool for measuring TTFT, TPOT, throughput, and latency
of any OpenAI-compatible LLM API (vLLM, Ollama, LM Studio, OpenAI, etc.)
using async HTTP requests.
"""

import argparse
import asyncio
import time
from pathlib import Path
from typing import Dict, Any, List
import yaml

import aiohttp

# Import utility modules
import sys
sys.path.insert(0, str(Path(__file__).parent))

from utils.metrics import (
    calculate_ttft, calculate_tpot, aggregate_metrics, format_metrics_for_display
)
from utils.prompts import get_prompts_for_benchmark
from utils.report_generator import generate_json_report, generate_html_report


class AsyncBenchmarker:
    """Async benchmarker for any OpenAI-compatible LLM API"""

    def __init__(self, base_url: str, model: str, config: Dict[str, Any]):
        self.base_url = base_url.rstrip('/')
        self.model = model
        self.config = config
        self.timeout = aiohttp.ClientTimeout(
            total=config.get('timeout', 300),
            connect=config.get('connect_timeout', 30)
        )

    async def send_completion_request(self, session: aiohttp.ClientSession,
                                      prompt: str, max_tokens: int) -> Dict[str, Any]:
        """Send a completion request and measure TTFT/TPOT

        Args:
            session: aiohttp ClientSession
            prompt: Prompt text
            max_tokens: Maximum tokens to generate

        Returns:
            Dict with timing metrics and response data
        """
        request_start = time.time()

        payload = {
            "model": self.model,
            "prompt": prompt,
            "max_tokens": max_tokens,
            "temperature": self.config.get('temperature', 0.7),
            "top_p": self.config.get('top_p', 0.9),
            "stream": False
        }

        try:
            async with session.post(
                f"{self.base_url}/v1/completions",
                json=payload,
                timeout=self.timeout
            ) as response:
                first_byte_time = time.time()
                ttft = first_byte_time - request_start

                result = await response.json()
                end_time = time.time()

                # Check for errors
                if response.status != 200 or "error" in result:
                    error_msg = result.get("error", {}).get("message", f"HTTP {response.status}")
                    return {
                        "success": False,
                        "error": error_msg,
                        "total_latency": end_time - request_start
                    }

                # Extract metrics
                total_latency = end_time - request_start
                usage = result.get("usage", {})
                prompt_tokens = usage.get("prompt_tokens", 0)
                completion_tokens = usage.get("completion_tokens", 0)

                # Calculate TPOT
                generation_time = total_latency - ttft
                tpot = generation_time / max(completion_tokens - 1, 1) if completion_tokens > 1 else 0.0

                return {
                    "success": True,
                    "ttft": ttft,
                    "tpot": tpot,
                    "total_latency": total_latency,
                    "prompt_tokens": prompt_tokens,
                    "completion_tokens": completion_tokens,
                    "response_text": result.get("choices", [{}])[0].get("text", "")
                }

        except asyncio.TimeoutError:
            return {
                "success": False,
                "error": "Request timeout",
                "total_latency": time.time() - request_start
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "total_latency": time.time() - request_start
            }

    async def run_benchmark(self, num_requests: int, concurrency: int,
                           prompts: List[str], max_tokens: int,
                           warmup_requests: int = 0) -> Dict[str, Any]:
        """Run benchmark with specified concurrency

        Args:
            num_requests: Total number of requests
            concurrency: Maximum concurrent requests
            prompts: List of prompts to use
            max_tokens: Maximum tokens per request
            warmup_requests: Number of warmup requests (not counted in metrics)

        Returns:
            Aggregated metrics dictionary
        """
        print(f"\nRunning benchmark:")
        print(f"  Requests: {num_requests}")
        print(f"  Concurrency: {concurrency}")
        print(f"  Max tokens: {max_tokens}")
        print(f"  Warmup: {warmup_requests}")
        print()

        async with aiohttp.ClientSession() as session:
            # Warmup phase
            if warmup_requests > 0:
                print(f"Warming up with {warmup_requests} requests...")
                warmup_prompts = prompts[:warmup_requests]
                warmup_tasks = [
                    self.send_completion_request(session, prompt, max_tokens)
                    for prompt in warmup_prompts
                ]
                await asyncio.gather(*warmup_tasks)
                print("Warmup complete.\n")

            # Main benchmark
            print("Running main benchmark...")
            semaphore = asyncio.Semaphore(concurrency)

            async def limited_request(prompt):
                async with semaphore:
                    return await self.send_completion_request(session, prompt, max_tokens)

            # Cycle through prompts if needed
            benchmark_prompts = []
            for i in range(num_requests):
                benchmark_prompts.append(prompts[i % len(prompts)])

            # Track progress
            benchmark_start = time.time()
            tasks = [limited_request(prompt) for prompt in benchmark_prompts]

            # Execute with progress tracking
            results = []
            completed = 0
            for coro in asyncio.as_completed(tasks):
                result = await coro
                results.append(result)
                completed += 1
                if completed % max(1, num_requests // 10) == 0 or completed == num_requests:
                    elapsed = time.time() - benchmark_start
                    rate = completed / elapsed if elapsed > 0 else 0
                    print(f"  Progress: {completed}/{num_requests} ({completed/num_requests*100:.1f}%) - {rate:.2f} req/s")

            benchmark_end = time.time()
            total_elapsed = benchmark_end - benchmark_start

            print(f"\nBenchmark complete in {total_elapsed:.2f}s")

        # Aggregate metrics
        metrics = aggregate_metrics(results, total_elapsed)
        return metrics


def load_config(config_dir: Path) -> tuple:
    """Load targets and scenarios configuration

    Args:
        config_dir: Path to config directory

    Returns:
        Tuple of (targets, scenarios, defaults)
    """
    with open(config_dir / "targets.yaml") as f:
        targets_config = yaml.safe_load(f)

    with open(config_dir / "test_scenarios.yaml") as f:
        scenarios_config = yaml.safe_load(f)

    return (
        targets_config["targets"],
        scenarios_config["scenarios"],
        targets_config.get("defaults", {})
    )


def main():
    # Determine paths early for loading config
    script_dir = Path(__file__).parent
    config_dir = script_dir.parent / "config"

    # Load configuration to get available targets
    try:
        targets, scenarios, defaults = load_config(config_dir)
        available_targets = list(targets.keys())
        available_scenarios = list(scenarios.keys())
    except Exception as e:
        print(f"Warning: Could not load config: {e}")
        print("Using default target/scenario options")
        available_targets = ['gke-t4', 'tpu-v6e']  # Fallback
        available_scenarios = ['quick_validation', 'latency_benchmark', 'throughput_benchmark', 'load_test']

    parser = argparse.ArgumentParser(
        description="Async benchmark for any OpenAI-compatible LLM API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Examples:
  # Run latency benchmark on a configured target
  python benchmark_async.py --target tpu-v6e --scenario latency_benchmark

  # Test all supported models for a target (multi-model benchmark)
  python benchmark_async.py --target tpu-v6e --scenario latency_benchmark --all-models --output results/multi_model.json --html

  # Benchmark a local Ollama deployment
  python benchmark_async.py --target ollama-local --scenario quick_validation

  # Custom benchmark with specific URL and model
  python benchmark_async.py --base-url http://localhost:8000 --model "my-model" --num-requests 100 --concurrency 10

  # Output to specific file with HTML report
  python benchmark_async.py --target tpu-v6e --output results/my_test.json --html

Available targets: {', '.join(available_targets)}
Available scenarios: {', '.join(available_scenarios)}
        """
    )

    parser.add_argument('--target', choices=available_targets,
                       help='Target deployment from config')
    parser.add_argument('--scenario', choices=available_scenarios,
                       help='Test scenario from config')
    parser.add_argument('--base-url', help='Base URL (overrides target config)')
    parser.add_argument('--model', help='Model name (overrides target config)')
    parser.add_argument('--all-models', action='store_true',
                       help='Test all supported_models for the target (requires --target)')
    parser.add_argument('--num-requests', type=int, help='Number of requests')
    parser.add_argument('--concurrency', type=int, help='Concurrent requests')
    parser.add_argument('--max-tokens', type=int, help='Max tokens per request')
    parser.add_argument('--output', help='Output file path (.json or .html)')
    parser.add_argument('--html', action='store_true', help='Also generate HTML report')

    args = parser.parse_args()

    # Configuration already loaded earlier for argparse
    # targets, scenarios, defaults already available from above

    # Validate --all-models flag
    if args.all_models and not args.target:
        parser.error("--all-models requires --target to be specified")

    # Determine base URL and model(s)
    if args.target:
        target_config = targets[args.target]
        base_url = args.base_url or target_config["base_url"]

        # Get models to test
        if args.all_models:
            models_to_test = target_config.get("supported_models", [target_config["model"]])
            if not models_to_test:
                models_to_test = [target_config["model"]]
        elif args.model:
            models_to_test = [args.model]
        else:
            models_to_test = [target_config["model"]]
    else:
        if not args.base_url or not args.model:
            parser.error("Either --target or both --base-url and --model must be specified")
        base_url = args.base_url
        models_to_test = [args.model]

    # Determine test parameters
    if args.scenario:
        scenario_config = scenarios[args.scenario]
        num_requests = args.num_requests or scenario_config["num_requests"]
        concurrency = args.concurrency or scenario_config["concurrency"]

        # Handle max_tokens (can be int or list)
        scenario_max_tokens = scenario_config["max_tokens"]
        if isinstance(scenario_max_tokens, list):
            max_tokens = args.max_tokens or scenario_max_tokens[0]
        else:
            max_tokens = args.max_tokens or scenario_max_tokens

        warmup_requests = scenario_config.get("warmup_requests", 0)

        # Get prompts (use first prompt_tokens value)
        if isinstance(scenario_config.get("prompt_tokens"), list):
            prompt_length = scenario_config["prompt_tokens"][0]
        else:
            prompt_length = scenario_config.get("prompt_tokens", 100)
    else:
        num_requests = args.num_requests or 10
        concurrency = args.concurrency or 1
        max_tokens = args.max_tokens or 100
        warmup_requests = 0
        prompt_length = 100

    # Merge defaults with config
    config = defaults.copy()
    config.update({
        'timeout': defaults.get('timeout', 300),
        'temperature': defaults.get('temperature', 0.7),
        'top_p': defaults.get('top_p', 0.9),
    })

    # Generate prompts
    prompts = get_prompts_for_benchmark(max(num_requests, 20), distribution="mixed")

    # Store results for all models
    all_results = []

    # Run benchmark for each model
    for idx, model in enumerate(models_to_test):
        if len(models_to_test) > 1:
            print(f"\n\n{'='*60}")
            print(f"  Testing Model {idx+1}/{len(models_to_test)}: {model}")
            print(f"{'='*60}\n")

        # Create benchmarker and run
        print("="*60)
        print("  LLM API Async Benchmark")
        print("="*60)
        print(f"\nTarget: {base_url}")
        print(f"Model: {model}")
        if args.target:
            target_info = targets.get(args.target, {})
            if 'backend' in target_info:
                print(f"Backend: {target_info['backend']}")

        benchmarker = AsyncBenchmarker(base_url, model, config)

        # Run benchmark
        try:
            metrics = asyncio.run(
                benchmarker.run_benchmark(
                    num_requests,
                    concurrency,
                    prompts,
                    max_tokens,
                    warmup_requests
                )
            )
        except KeyboardInterrupt:
            print("\n\nBenchmark interrupted by user")
            return 1

        # Display results
        print(format_metrics_for_display(metrics))

        # Store results
        all_results.append({
            "model": model,
            "metrics": metrics,
            "metadata": {
                "target": args.target or "custom",
                "scenario": args.scenario or "custom",
                "base_url": base_url,
                "model": model,
                "num_requests": num_requests,
                "concurrency": concurrency,
                "max_tokens": max_tokens,
            }
        })

    # Save results
    if args.output:
        output_path = Path(args.output)

        if len(models_to_test) == 1:
            # Single model - save as before
            metadata = all_results[0]["metadata"]
            metrics = all_results[0]["metrics"]

            if args.output.endswith('.json') or not args.html:
                generate_json_report(metrics, args.output, metadata)

            if args.output.endswith('.html') or args.html:
                html_path = str(output_path.with_suffix('.html'))
                generate_html_report(metrics, html_path, metadata)
        else:
            # Multiple models - save comparison report
            import json
            from datetime import datetime

            # Save individual JSON reports
            for result in all_results:
                model_name_safe = result["model"].replace("/", "_")
                json_path = output_path.parent / f"{output_path.stem}_{model_name_safe}.json"
                generate_json_report(result["metrics"], str(json_path), result["metadata"])

            # Save combined comparison report
            comparison_data = {
                "timestamp": datetime.now().isoformat(),
                "target": args.target or "custom",
                "scenario": args.scenario or "custom",
                "base_url": base_url,
                "models_tested": len(models_to_test),
                "results": [
                    {
                        "model": r["model"],
                        "ttft_p50": r["metrics"]["ttft_p50"],
                        "ttft_p95": r["metrics"]["ttft_p95"],
                        "tpot_p50": r["metrics"]["tpot_p50"],
                        "tpot_p95": r["metrics"]["tpot_p95"],
                        "throughput": r["metrics"]["throughput_tokens_per_sec"],
                        "error_rate": r["metrics"]["error_rate"],
                        "mlperf_compliant": r["metrics"]["mlperf_compliant"]
                    }
                    for r in all_results
                ]
            }

            comparison_path = output_path.parent / f"{output_path.stem}_comparison.json"
            with open(comparison_path, 'w') as f:
                json.dump(comparison_data, f, indent=2)

            print(f"\n\nMulti-model comparison saved to: {comparison_path}")

            # Generate HTML comparison if requested
            if args.html or args.output.endswith('.html'):
                html_path = output_path.parent / f"{output_path.stem}_comparison.html"
                _generate_comparison_html(comparison_data, html_path)
                print(f"HTML comparison report saved to: {html_path}")

    # Return success if all models passed
    return 0 if all(r["metrics"]['mlperf_compliant'] for r in all_results) else 1


def _generate_comparison_html(comparison_data: Dict[str, Any], output_path: Path):
    """Generate HTML comparison report for multiple models"""
    html_content = f"""<!DOCTYPE html>
<html>
<head>
    <title>Multi-Model Benchmark Comparison</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
        h1 {{ color: #333; }}
        .metadata {{ background: #fff; padding: 20px; border-radius: 8px; margin-bottom: 20px; }}
        table {{ border-collapse: collapse; width: 100%; background: #fff; border-radius: 8px; }}
        th, td {{ padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }}
        th {{ background-color: #4CAF50; color: white; }}
        tr:hover {{ background-color: #f5f5f5; }}
        .mlperf-pass {{ color: green; font-weight: bold; }}
        .mlperf-fail {{ color: red; font-weight: bold; }}
    </style>
</head>
<body>
    <h1>Multi-Model Benchmark Comparison</h1>
    <div class="metadata">
        <p><strong>Target:</strong> {comparison_data.get('target', 'N/A')}</p>
        <p><strong>Scenario:</strong> {comparison_data.get('scenario', 'N/A')}</p>
        <p><strong>Base URL:</strong> {comparison_data.get('base_url', 'N/A')}</p>
        <p><strong>Timestamp:</strong> {comparison_data.get('timestamp', 'N/A')}</p>
        <p><strong>Models Tested:</strong> {comparison_data.get('models_tested', 0)}</p>
    </div>
    <table>
        <tr>
            <th>Model</th>
            <th>TTFT p50 (s)</th>
            <th>TTFT p95 (s)</th>
            <th>TPOT p50 (s)</th>
            <th>TPOT p95 (s)</th>
            <th>Throughput (tok/s)</th>
            <th>Error Rate</th>
            <th>MLPerf</th>
        </tr>
"""
    for result in comparison_data.get('results', []):
        mlperf_class = "mlperf-pass" if result.get('mlperf_compliant') else "mlperf-fail"
        mlperf_text = "✓ Pass" if result.get('mlperf_compliant') else "✗ Fail"

        html_content += f"""
        <tr>
            <td>{result.get('model', 'N/A')}</td>
            <td>{result.get('ttft_p50', 0):.3f}</td>
            <td>{result.get('ttft_p95', 0):.3f}</td>
            <td>{result.get('tpot_p50', 0):.3f}</td>
            <td>{result.get('tpot_p95', 0):.3f}</td>
            <td>{result.get('throughput', 0):.2f}</td>
            <td>{result.get('error_rate', 0)*100:.1f}%</td>
            <td class="{mlperf_class}">{mlperf_text}</td>
        </tr>
"""

    html_content += """
    </table>
</body>
</html>
"""

    with open(output_path, 'w') as f:
        f.write(html_content)

    print(f"HTML report saved to: {output_path}")


if __name__ == '__main__':
    sys.exit(main())
