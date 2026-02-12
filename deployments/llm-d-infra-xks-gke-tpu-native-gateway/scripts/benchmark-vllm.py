#!/usr/bin/env python3
"""
Comprehensive benchmark for vLLM on GKE with TPU
Tests throughput, latency, and EPP prefix caching performance
"""

import argparse
import json
import time
import statistics
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
import requests
from typing import List, Dict, Tuple

class VLLMBenchmark:
    def __init__(self, base_url: str, model: str = "/mnt/models"):
        self.base_url = base_url
        self.model = model
        self.session = requests.Session()

    def send_completion(self, prompt: str, max_tokens: int = 50) -> Tuple[float, bool, str]:
        """Send a completion request and measure latency"""
        start = time.time()
        try:
            response = self.session.post(
                f"{self.base_url}/v1/completions",
                json={
                    "model": self.model,
                    "prompt": prompt,
                    "max_tokens": max_tokens,
                    "temperature": 0.7
                },
                timeout=60
            )
            latency = (time.time() - start) * 1000  # Convert to ms

            if response.status_code == 200:
                data = response.json()
                text = data['choices'][0]['text']
                return latency, True, text
            else:
                return latency, False, f"HTTP {response.status_code}"
        except Exception as e:
            latency = (time.time() - start) * 1000
            return latency, False, str(e)

    def benchmark_throughput(self, num_requests: int, concurrency: int, prompt: str) -> Dict:
        """Benchmark throughput with concurrent requests"""
        print(f"\n{'='*60}")
        print(f"Scenario: {num_requests} requests, concurrency {concurrency}")
        print(f"{'='*60}")

        latencies = []
        success_count = 0

        start_time = time.time()

        with ThreadPoolExecutor(max_workers=concurrency) as executor:
            futures = [
                executor.submit(self.send_completion, prompt)
                for _ in range(num_requests)
            ]

            for i, future in enumerate(as_completed(futures), 1):
                latency, success, result = future.result()
                latencies.append(latency)
                if success:
                    success_count += 1

                # Progress indicator
                if i % max(1, num_requests // 10) == 0:
                    print(f"  Progress: {i}/{num_requests} ({success_count} successful)")

        total_time = time.time() - start_time

        # Calculate metrics
        latencies.sort()
        metrics = {
            'total_requests': num_requests,
            'concurrency': concurrency,
            'successful_requests': success_count,
            'failed_requests': num_requests - success_count,
            'total_time_sec': total_time,
            'throughput_rps': num_requests / total_time,
            'latency_mean_ms': statistics.mean(latencies),
            'latency_median_ms': statistics.median(latencies),
            'latency_p95_ms': latencies[int(len(latencies) * 0.95)],
            'latency_p99_ms': latencies[int(len(latencies) * 0.99)],
            'latency_min_ms': min(latencies),
            'latency_max_ms': max(latencies),
            'latency_stddev_ms': statistics.stdev(latencies) if len(latencies) > 1 else 0
        }

        # Print results
        print(f"\n  Results:")
        print(f"    Total time: {metrics['total_time_sec']:.2f} sec")
        print(f"    Throughput: {metrics['throughput_rps']:.2f} req/sec")
        print(f"    Success rate: {success_count}/{num_requests} ({success_count/num_requests*100:.1f}%)")
        print(f"\n  Latency Distribution:")
        print(f"    Mean:   {metrics['latency_mean_ms']:.0f} ms")
        print(f"    Median: {metrics['latency_median_ms']:.0f} ms")
        print(f"    P95:    {metrics['latency_p95_ms']:.0f} ms")
        print(f"    P99:    {metrics['latency_p99_ms']:.0f} ms")
        print(f"    Min:    {metrics['latency_min_ms']:.0f} ms")
        print(f"    Max:    {metrics['latency_max_ms']:.0f} ms")
        print(f"    StdDev: {metrics['latency_stddev_ms']:.0f} ms")

        return metrics

    def test_prefix_caching(self, prompt: str, num_requests: int = 5) -> Dict:
        """Test EPP prefix caching by sending identical requests"""
        print(f"\n{'='*60}")
        print(f"EPP Prefix Cache Test")
        print(f"{'='*60}")
        print(f"Prompt: \"{prompt}\"")
        print(f"Sending {num_requests} identical requests...\n")

        latencies = []
        results = []

        for i in range(num_requests):
            latency, success, text = self.send_completion(prompt, max_tokens=30)
            latencies.append(latency)

            status = "✓" if success else "✗"
            print(f"  Request {i+1}: {status} {latency:.0f} ms")

            results.append({
                'request_num': i + 1,
                'latency_ms': latency,
                'success': success
            })

        # Calculate cache effectiveness
        first_latency = latencies[0]
        avg_subsequent = statistics.mean(latencies[1:]) if len(latencies) > 1 else 0
        improvement = ((first_latency - avg_subsequent) / first_latency * 100) if first_latency > 0 else 0

        print(f"\n  Analysis:")
        print(f"    First request: {first_latency:.0f} ms (cold)")
        print(f"    Avg subsequent: {avg_subsequent:.0f} ms (warm)")
        print(f"    Cache speedup: {improvement:.1f}%")

        if improvement > 0:
            print(f"    ✓ Prefix caching is working!")
        else:
            print(f"    ⚠ No cache speedup detected")

        return {
            'first_latency_ms': first_latency,
            'avg_subsequent_ms': avg_subsequent,
            'improvement_pct': improvement,
            'requests': results
        }

def main():
    parser = argparse.ArgumentParser(description='Benchmark vLLM on GKE')
    parser.add_argument('--url', required=True, help='Base URL (e.g., http://35.214.195.39/llm-d-inference-scheduling/qwen2-3b-pattern1)')
    parser.add_argument('--model', default='/mnt/models', help='Model path (default: /mnt/models)')
    parser.add_argument('--output', help='Output directory for results (default: ../benchmarks/results)')
    args = parser.parse_args()

    # Setup
    benchmark = VLLMBenchmark(args.url, args.model)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    output_dir = Path(args.output) if args.output else Path(__file__).parent.parent / "benchmarks" / "results"
    output_dir.mkdir(parents=True, exist_ok=True)

    print("="*60)
    print("  vLLM Benchmark - GKE Native Gateway + TPU v6e")
    print("="*60)
    print(f"Endpoint: {args.url}")
    print(f"Model: {args.model}")
    print(f"Timestamp: {timestamp}")
    print()

    # Test connectivity
    print("Pre-flight check... ", end='', flush=True)
    latency, success, result = benchmark.send_completion("Hello", max_tokens=1)
    if success:
        print(f"✓ OK ({latency:.0f} ms)")
    else:
        print(f"✗ FAILED: {result}")
        return 1

    all_results = {
        'metadata': {
            'timestamp': timestamp,
            'endpoint': args.url,
            'model': args.model
        },
        'scenarios': []
    }

    # Benchmark scenarios
    scenarios = [
        (5, 1, "Baseline"),
        (20, 5, "Light load"),
        (50, 10, "Medium load"),
        (100, 20, "Heavy load"),
    ]

    prompt = "Explain quantum computing in one sentence:"

    for num_req, concurrency, description in scenarios:
        metrics = benchmark.benchmark_throughput(num_req, concurrency, prompt)
        all_results['scenarios'].append({
            'description': description,
            'metrics': metrics
        })

    # EPP prefix caching test
    cache_results = benchmark.test_prefix_caching("Explain Kubernetes in one sentence:", num_requests=5)
    all_results['cache_test'] = cache_results

    # Save results
    results_file = output_dir / f"benchmark_{timestamp}.json"
    with open(results_file, 'w') as f:
        json.dump(all_results, f, indent=2)

    # Generate summary
    summary_file = output_dir / f"benchmark_summary_{timestamp}.txt"
    with open(summary_file, 'w') as f:
        f.write("="*60 + "\n")
        f.write("  vLLM Benchmark Summary\n")
        f.write("="*60 + "\n")
        f.write(f"Date: {datetime.now()}\n")
        f.write(f"Endpoint: {args.url}\n")
        f.write(f"Model: {args.model}\n\n")

        for scenario in all_results['scenarios']:
            desc = scenario['description']
            m = scenario['metrics']
            f.write(f"\n{desc}:\n")
            f.write(f"  Requests: {m['total_requests']}, Concurrency: {m['concurrency']}\n")
            f.write(f"  Throughput: {m['throughput_rps']:.2f} req/sec\n")
            f.write(f"  Latency (mean): {m['latency_mean_ms']:.0f} ms\n")
            f.write(f"  Latency (P95): {m['latency_p95_ms']:.0f} ms\n")
            f.write(f"  Success rate: {m['successful_requests']}/{m['total_requests']}\n")

        f.write(f"\n\nEPP Prefix Cache Test:\n")
        cache = all_results['cache_test']
        f.write(f"  First request: {cache['first_latency_ms']:.0f} ms\n")
        f.write(f"  Avg subsequent: {cache['avg_subsequent_ms']:.0f} ms\n")
        f.write(f"  Speedup: {cache['improvement_pct']:.1f}%\n")

    print(f"\n{'='*60}")
    print("  Benchmark Complete!")
    print(f"{'='*60}")
    print(f"\nResults saved to:")
    print(f"  JSON: {results_file}")
    print(f"  Summary: {summary_file}")
    print()

    return 0

if __name__ == "__main__":
    exit(main())
