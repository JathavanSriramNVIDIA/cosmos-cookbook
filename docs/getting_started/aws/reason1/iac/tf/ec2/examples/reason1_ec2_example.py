# Copyright 2025 NVIDIA CORPORATION & AFFILIATES
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

"""
Cosmos Reason1 NIM on EC2 - Example Script

This script demonstrates how to interact with a Cosmos Reason1 NIM
running on an EC2 GPU instance.

Usage:
    python reason1_ec2_example.py --host <EC2_IP_ADDRESS>
    python reason1_ec2_example.py --host localhost  # if using SSH tunnel

Requirements:
    pip install requests

Reference:
    https://docs.nvidia.com/nim/cosmos/latest/quickstart.html
"""

import argparse
import base64
import json
import sys
import time
from pathlib import Path
from typing import Optional

try:
    import requests
except ImportError:
    print("Please install requests: pip install requests")
    sys.exit(1)


def get_sample_image_base64() -> str:
    """
    Generate a simple test image (1x1 red pixel PNG) for testing.
    In production, replace with actual image data.
    """
    # Minimal 1x1 red PNG image (base64 encoded)
    minimal_png = (
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx"
        "0gAAAABJRU5ErkJggg=="
    )
    return minimal_png


def check_health(base_url: str, timeout: int = 10) -> bool:
    """
    Check if the NIM is ready to accept requests.
    """
    print("\n" + "=" * 60)
    print("HEALTH CHECK")
    print("=" * 60)

    try:
        response = requests.get(f"{base_url}/v1/health/ready", timeout=timeout)
        if response.status_code == 200:
            print(f"[OK] NIM is ready at {base_url}")
            return True
        else:
            print(f"[WARN] NIM returned status {response.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print(f"[FAIL] Cannot connect to {base_url}")
        print("       Make sure the NIM container is running.")
        return False
    except Exception as e:
        print(f"[FAIL] Health check failed: {e}")
        return False


def test_basic_inference(base_url: str, timeout: int = 120) -> bool:
    """
    Test 1: Basic text-only inference
    """
    print("\n" + "=" * 60)
    print("TEST 1: Basic Text Inference")
    print("=" * 60)

    payload = {
        "model": "nvidia/cosmos-reason1-7b",
        "messages": [
            {
                "role": "user",
                "content": "What is a robot? Answer in 2-3 sentences.",
            }
        ],
        "max_tokens": 150,
        "temperature": 0.6,
    }

    try:
        start_time = time.time()
        response = requests.post(
            f"{base_url}/v1/chat/completions",
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=timeout,
        )
        elapsed = time.time() - start_time

        if response.status_code == 200:
            result = response.json()
            print(f"\n[OK] Response received in {elapsed:.2f}s")

            if "choices" in result and len(result["choices"]) > 0:
                content = result["choices"][0].get("message", {}).get("content", "")
                print(f"\nModel Output:\n{content}")

            print("\n[PASSED] TEST 1: Basic text inference working")
            return True
        else:
            print(f"\n[FAILED] TEST 1: HTTP {response.status_code}")
            print(response.text)
            return False

    except Exception as e:
        print(f"\n[FAILED] TEST 1: {e}")
        return False


def test_streaming_inference(base_url: str, timeout: int = 120) -> bool:
    """
    Test 2: Streaming inference
    """
    print("\n" + "=" * 60)
    print("TEST 2: Streaming Inference")
    print("=" * 60)

    payload = {
        "model": "nvidia/cosmos-reason1-7b",
        "messages": [
            {
                "role": "user",
                "content": "Count from 1 to 5 and explain each number briefly.",
            }
        ],
        "max_tokens": 300,
        "temperature": 0.6,
        "stream": True,
    }

    try:
        start_time = time.time()
        response = requests.post(
            f"{base_url}/v1/chat/completions",
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=timeout,
            stream=True,
        )

        if response.status_code != 200:
            print(f"\n[FAILED] TEST 2: HTTP {response.status_code}")
            return False

        print("\nStreaming response:")
        print("-" * 40)

        full_content = ""
        for line in response.iter_lines():
            if line:
                line_str = line.decode("utf-8")
                if line_str.startswith("data: "):
                    data_str = line_str[6:]
                    if data_str == "[DONE]":
                        break
                    try:
                        data = json.loads(data_str)
                        content = (
                            data.get("choices", [{}])[0]
                            .get("delta", {})
                            .get("content", "")
                        )
                        if content:
                            print(content, end="", flush=True)
                            full_content += content
                    except json.JSONDecodeError:
                        continue

        elapsed = time.time() - start_time
        print(f"\n{'-' * 40}")
        print(f"\n[OK] Streaming completed in {elapsed:.2f}s")
        print(f"[OK] Total tokens received: ~{len(full_content.split())}")
        print("\n[PASSED] TEST 2: Streaming inference working")
        return True

    except Exception as e:
        print(f"\n[FAILED] TEST 2: {e}")
        return False


def test_reasoning_mode(base_url: str, timeout: int = 180) -> bool:
    """
    Test 3: Reasoning mode with chain-of-thought
    """
    print("\n" + "=" * 60)
    print("TEST 3: Reasoning Mode (Chain-of-Thought)")
    print("=" * 60)

    payload = {
        "model": "nvidia/cosmos-reason1-7b",
        "messages": [
            {
                "role": "system",
                "content": "Answer the question in the following format: <think>\nyour reasoning\n</think>\n\n<answer>\nyour answer\n</answer>.",
            },
            {
                "role": "user",
                "content": "If a robot needs to pick up a cup from a table, what physical considerations must it account for?",
            },
        ],
        "max_tokens": 500,
        "temperature": 0.6,
        "stream": True,
    }

    try:
        start_time = time.time()
        response = requests.post(
            f"{base_url}/v1/chat/completions",
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=timeout,
            stream=True,
        )

        if response.status_code != 200:
            print(f"\n[FAILED] TEST 3: HTTP {response.status_code}")
            return False

        print("\nReasoning response:")
        print("-" * 40)

        full_content = ""
        for line in response.iter_lines():
            if line:
                line_str = line.decode("utf-8")
                if line_str.startswith("data: "):
                    data_str = line_str[6:]
                    if data_str == "[DONE]":
                        break
                    try:
                        data = json.loads(data_str)
                        content = (
                            data.get("choices", [{}])[0]
                            .get("delta", {})
                            .get("content", "")
                        )
                        if content:
                            print(content, end="", flush=True)
                            full_content += content
                    except json.JSONDecodeError:
                        continue

        elapsed = time.time() - start_time
        print(f"\n{'-' * 40}")
        print(f"\n[OK] Reasoning completed in {elapsed:.2f}s")

        # Verify reasoning format
        has_think = "<think>" in full_content
        has_answer = "<answer>" in full_content
        print(f"[OK] Contains <think> block: {has_think}")
        print(f"[OK] Contains <answer> block: {has_answer}")

        print("\n[PASSED] TEST 3: Reasoning mode working")
        return True

    except Exception as e:
        print(f"\n[FAILED] TEST 3: {e}")
        return False


def test_multimodal_inference(
    base_url: str, image_path: Optional[str] = None, timeout: int = 180
) -> bool:
    """
    Test 4: Multimodal inference with image
    """
    print("\n" + "=" * 60)
    print("TEST 4: Multimodal Inference (Image + Text)")
    print("=" * 60)

    # Load image
    if image_path and Path(image_path).exists():
        with open(image_path, "rb") as f:
            image_data = base64.b64encode(f.read()).decode("utf-8")
        print(f"[OK] Loaded image from: {image_path}")
        image_type = "jpeg" if image_path.lower().endswith((".jpg", ".jpeg")) else "png"
    else:
        if image_path:
            print(f"[WARN] Image not found: {image_path}, using test image")
        else:
            print("[INFO] No image provided, using minimal test image")
        image_data = get_sample_image_base64()
        image_type = "png"

    image_data_url = f"data:image/{image_type};base64,{image_data}"

    payload = {
        "model": "nvidia/cosmos-reason1-7b",
        "messages": [
            {
                "role": "system",
                "content": "Answer the question in the following format: <think>\nyour reasoning\n</think>\n\n<answer>\nyour answer\n</answer>.",
            },
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Describe what you see in this image."},
                    {"type": "image_url", "image_url": {"url": image_data_url}},
                ],
            },
        ],
        "max_tokens": 300,
        "temperature": 0.6,
        "stream": True,
    }

    try:
        start_time = time.time()
        response = requests.post(
            f"{base_url}/v1/chat/completions",
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=timeout,
            stream=True,
        )

        if response.status_code != 200:
            print(f"\n[FAILED] TEST 4: HTTP {response.status_code}")
            print(response.text)
            return False

        print("\nMultimodal response:")
        print("-" * 40)

        full_content = ""
        for line in response.iter_lines():
            if line:
                line_str = line.decode("utf-8")
                if line_str.startswith("data: "):
                    data_str = line_str[6:]
                    if data_str == "[DONE]":
                        break
                    try:
                        data = json.loads(data_str)
                        content = (
                            data.get("choices", [{}])[0]
                            .get("delta", {})
                            .get("content", "")
                        )
                        if content:
                            print(content, end="", flush=True)
                            full_content += content
                    except json.JSONDecodeError:
                        continue

        elapsed = time.time() - start_time
        print(f"\n{'-' * 40}")
        print(f"\n[OK] Multimodal inference completed in {elapsed:.2f}s")
        print("\n[PASSED] TEST 4: Multimodal inference working")
        return True

    except Exception as e:
        print(f"\n[FAILED] TEST 4: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Cosmos Reason1 NIM on EC2 - Examples",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run all tests against EC2 instance
  python reason1_ec2_example.py --host 54.123.45.67

  # Run via SSH tunnel (localhost)
  python reason1_ec2_example.py --host localhost

  # Run specific test
  python reason1_ec2_example.py --host 54.123.45.67 --test streaming

  # With custom image
  python reason1_ec2_example.py --host 54.123.45.67 --image ./test.jpg
        """,
    )

    parser.add_argument(
        "--host",
        type=str,
        required=True,
        help="EC2 instance IP or hostname (use 'localhost' if SSH tunnel)",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="NIM API port (default: 8000)",
    )
    parser.add_argument(
        "--test",
        type=str,
        choices=["all", "health", "basic", "streaming", "reasoning", "multimodal"],
        default="all",
        help="Which test to run (default: all)",
    )
    parser.add_argument(
        "--image",
        type=str,
        default=None,
        help="Path to image file for multimodal test",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=180,
        help="Request timeout in seconds (default: 180)",
    )

    args = parser.parse_args()

    base_url = f"http://{args.host}:{args.port}"

    print("\n" + "=" * 60)
    print("COSMOS REASON1 NIM ON EC2 - EXAMPLES")
    print("=" * 60)
    print(f"Endpoint: {base_url}")
    print(f"Test: {args.test}")

    results = {}

    # Health check first
    if args.test in ["all", "health"]:
        results["health"] = check_health(base_url)
        if not results["health"] and args.test == "all":
            print("\n[ERROR] Health check failed. Aborting other tests.")
            print("        Make sure the NIM container is running on the EC2 instance.")
            sys.exit(1)

    # Run tests
    if args.test in ["all", "basic"]:
        results["basic"] = test_basic_inference(base_url, args.timeout)

    if args.test in ["all", "streaming"]:
        results["streaming"] = test_streaming_inference(base_url, args.timeout)

    if args.test in ["all", "reasoning"]:
        results["reasoning"] = test_reasoning_mode(base_url, args.timeout)

    if args.test in ["all", "multimodal"]:
        results["multimodal"] = test_multimodal_inference(
            base_url, args.image, args.timeout
        )

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)

    passed = sum(1 for v in results.values() if v)
    total = len(results)

    for test_name, result in results.items():
        status = "[PASSED]" if result else "[FAILED]"
        print(f"  {test_name.upper()}: {status}")

    print(f"\n  Total: {passed}/{total} tests passed")

    if passed == total:
        print("\nAll tests passed!")
        sys.exit(0)
    else:
        print(f"\n[WARN] {total - passed} test(s) failed")
        sys.exit(1)


if __name__ == "__main__":
    main()
