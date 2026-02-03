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
Cosmos Reason1 Example Script

This script demonstrates how to interact with a deployed Cosmos Reason1 NIM
on either Amazon SageMaker or a direct HTTP endpoint (EC2/local).

Usage (SageMaker):
    python reason1_example.py --region us-east-1 --endpoint-name cosmos-cosmos-reason1-endpoint

Usage (EC2/HTTP):
    python reason1_example.py --host localhost --port 8000

Reference:
    https://github.com/NVIDIA/nim-deploy/blob/main/cloud-service-providers/aws/sagemaker/aws_marketplace_notebooks/nim_cosmos-reason1-7b_aws_marketplace.ipynb
"""

import argparse
import base64
import json
import sys
import time
from abc import ABC, abstractmethod
from typing import Iterator, Optional


def get_sample_image_base64() -> str:
    """
    Generate a simple test image (1x1 red pixel PNG) for testing.
    In production, replace with actual image data.
    """
    # Minimal 1x1 red PNG image (base64 encoded)
    # For real tests, load an actual image file
    minimal_png = (
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx"
        "0gAAAABJRU5ErkJggg=="
    )
    return minimal_png


# =============================================================================
# Client Abstraction Layer
# =============================================================================


class NIMClient(ABC):
    """Abstract base class for NIM clients."""

    @abstractmethod
    def invoke(self, payload: dict) -> dict:
        """Invoke the endpoint with a payload and return the response."""
        pass

    @abstractmethod
    def invoke_stream(self, payload: dict) -> Iterator[str]:
        """Invoke the endpoint with streaming and yield content chunks."""
        pass

    @abstractmethod
    def health_check(self) -> tuple[bool, str]:
        """Check endpoint health. Returns (is_healthy, status_message)."""
        pass

    @abstractmethod
    def get_endpoint_info(self) -> str:
        """Return a string describing the endpoint."""
        pass


class SageMakerClient(NIMClient):
    """Client for SageMaker endpoints."""

    def __init__(self, region: str, endpoint_name: str, timeout: int = 3600):
        import boto3
        from botocore.config import Config

        self.region = region
        self.endpoint_name = endpoint_name
        config = Config(read_timeout=timeout)
        self.runtime_client = boto3.client(
            "sagemaker-runtime", region_name=region, config=config
        )
        self.sm_client = boto3.client("sagemaker", region_name=region)

    def invoke(self, payload: dict) -> dict:
        response = self.runtime_client.invoke_endpoint(
            EndpointName=self.endpoint_name,
            ContentType="application/json",
            Body=json.dumps(payload),
        )
        return json.loads(response["Body"].read().decode())

    def invoke_stream(self, payload: dict) -> Iterator[str]:
        payload["stream"] = True
        response = self.runtime_client.invoke_endpoint_with_response_stream(
            EndpointName=self.endpoint_name,
            ContentType="application/json",
            Accept="application/jsonlines",
            Body=json.dumps(payload),
        )

        event_stream = response["Body"]
        accumulated_bytes = b""

        for event in event_stream:
            payload_part = event.get("PayloadPart", {})
            if "Bytes" in payload_part:
                accumulated_bytes += payload_part["Bytes"]

            decoded_data = accumulated_bytes.decode("utf-8-sig", errors="ignore")
            parts = decoded_data.rpartition("\n")
            lines_to_process = parts[0]
            accumulated_bytes = parts[2].encode("utf-8", errors="ignore")

            for line in lines_to_process.split("\n"):
                line = line.strip()
                if not line:
                    continue
                if line == "data: [DONE]":
                    return
                if line.startswith("data:"):
                    json_str = line[len("data:") :].strip()
                    if json_str:
                        try:
                            data = json.loads(json_str)
                            content = (
                                data.get("choices", [{}])[0]
                                .get("delta", {})
                                .get("content", "")
                            )
                            if content:
                                yield content
                        except json.JSONDecodeError:
                            continue

    def health_check(self) -> tuple[bool, str]:
        try:
            response = self.sm_client.describe_endpoint(EndpointName=self.endpoint_name)
            status = response["EndpointStatus"]
            arn = response["EndpointArn"]
            return status == "InService", f"Status: {status}, ARN: {arn}"
        except Exception as e:
            return False, str(e)

    def get_endpoint_info(self) -> str:
        return f"SageMaker Endpoint: {self.endpoint_name} (Region: {self.region})"


class HTTPClient(NIMClient):
    """Client for direct HTTP endpoints (EC2/local)."""

    def __init__(self, host: str, port: int, timeout: int = 3600):
        import requests

        self.host = host
        self.port = port
        self.timeout = timeout
        self.base_url = f"http://{host}:{port}"
        self.session = requests.Session()

    def invoke(self, payload: dict) -> dict:
        import requests

        response = self.session.post(
            f"{self.base_url}/v1/chat/completions",
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=self.timeout,
        )
        response.raise_for_status()
        return response.json()

    def invoke_stream(self, payload: dict) -> Iterator[str]:
        import requests

        payload["stream"] = True
        response = self.session.post(
            f"{self.base_url}/v1/chat/completions",
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=self.timeout,
            stream=True,
        )
        response.raise_for_status()

        for line in response.iter_lines(decode_unicode=True):
            if not line:
                continue
            if line == "data: [DONE]":
                return
            if line.startswith("data:"):
                json_str = line[len("data:") :].strip()
                if json_str:
                    try:
                        data = json.loads(json_str)
                        content = (
                            data.get("choices", [{}])[0]
                            .get("delta", {})
                            .get("content", "")
                        )
                        if content:
                            yield content
                    except json.JSONDecodeError:
                        continue

    def health_check(self) -> tuple[bool, str]:
        try:
            response = self.session.get(f"{self.base_url}/v1/health/ready", timeout=10)
            if response.status_code == 200:
                return True, "NIM is ready"
            else:
                return False, f"Health check returned status {response.status_code}"
        except Exception as e:
            return False, str(e)

    def get_endpoint_info(self) -> str:
        return f"HTTP Endpoint: {self.base_url}"


# =============================================================================
# Test Functions
# =============================================================================


def test_endpoint_health(client: NIMClient) -> bool:
    """Test 0: Basic endpoint health check"""
    print("\n" + "=" * 60)
    print("TEST 0: Endpoint Health Check")
    print("=" * 60)

    try:
        is_healthy, message = client.health_check()
        print(f"\n[OK] {client.get_endpoint_info()}")
        print(f"[OK] {message}")

        if is_healthy:
            print("\n[PASSED] TEST 0: Endpoint is healthy and ready")
            return True
        else:
            print(f"\n[FAILED] TEST 0: Endpoint not ready - {message}")
            return False

    except Exception as e:
        print(f"\n[FAILED] TEST 0: {e}")
        return False


def test_basic_text_inference(client: NIMClient, verbose: bool = True) -> bool:
    """Test 1: Basic text-only inference (non-streaming)"""
    print("\n" + "=" * 60)
    print("TEST 1: Basic Text Inference (Non-Streaming)")
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
        result = client.invoke(payload)
        elapsed = time.time() - start_time

        if verbose:
            print(f"\n[OK] Response received in {elapsed:.2f}s")
            print(f"\nResponse:\n{json.dumps(result, indent=2)}")

        # Extract the actual content
        if "choices" in result and len(result["choices"]) > 0:
            content = result["choices"][0].get("message", {}).get("content", "")
            print(f"\nModel Output:\n{content}")

        print("\n[PASSED] TEST 1: Basic text inference working")
        return True

    except Exception as e:
        print(f"\n[FAILED] TEST 1: {e}")
        return False


def test_streaming_inference(client: NIMClient, verbose: bool = True) -> bool:
    """Test 2: Streaming inference (recommended for reasoning models)"""
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
    }

    try:
        start_time = time.time()
        print("\nStreaming response:")
        print("-" * 40)

        full_content = ""
        for content in client.invoke_stream(payload):
            print(content, end="", flush=True)
            full_content += content

        elapsed = time.time() - start_time
        print(f"\n{'-' * 40}")
        print(f"\n[OK] Streaming completed in {elapsed:.2f}s")
        print(f"[OK] Total tokens received: ~{len(full_content.split())}")
        print("\n[PASSED] TEST 2: Streaming inference working")
        return True

    except Exception as e:
        print(f"\n[FAILED] TEST 2: {e}")
        return False


def test_reasoning_mode(client: NIMClient, verbose: bool = True) -> bool:
    """Test 3: Reasoning mode with chain-of-thought"""
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
    }

    try:
        start_time = time.time()
        print("\nReasoning response:")
        print("-" * 40)

        full_content = ""
        for content in client.invoke_stream(payload):
            print(content, end="", flush=True)
            full_content += content

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
    client: NIMClient, image_path: Optional[str] = None, verbose: bool = True
) -> bool:
    """Test 4: Multimodal inference with image"""
    print("\n" + "=" * 60)
    print("TEST 4: Multimodal Inference (Image + Text)")
    print("=" * 60)

    # Load image
    if image_path:
        try:
            with open(image_path, "rb") as f:
                image_data = base64.b64encode(f.read()).decode("utf-8")
            print(f"[OK] Loaded image from: {image_path}")
        except FileNotFoundError:
            print(f"[WARN] Image not found: {image_path}, using test image")
            image_data = get_sample_image_base64()
    else:
        print("[WARN] No image provided, using minimal test image")
        image_data = get_sample_image_base64()

    image_data_url = f"data:image/png;base64,{image_data}"

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
    }

    try:
        start_time = time.time()
        print("\nMultimodal response:")
        print("-" * 40)

        full_content = ""
        for content in client.invoke_stream(payload):
            print(content, end="", flush=True)
            full_content += content

        elapsed = time.time() - start_time
        print(f"\n{'-' * 40}")
        print(f"\n[OK] Multimodal inference completed in {elapsed:.2f}s")
        print("\n[PASSED] TEST 4: Multimodal inference working")
        return True

    except Exception as e:
        print(f"\n[FAILED] TEST 4: {e}")
        return False


# =============================================================================
# Main
# =============================================================================


def main():
    parser = argparse.ArgumentParser(
        description="Cosmos Reason1 NIM Examples (SageMaker or EC2/HTTP)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # SageMaker endpoint
  python reason1_example.py --region us-east-1 --endpoint-name cosmos-cosmos-reason1-endpoint

  # EC2/HTTP endpoint (via port forwarding or direct access)
  python reason1_example.py --host localhost --port 8000

  # Run specific test
  python reason1_example.py --host localhost --port 8000 --test streaming

  # Run with image
  python reason1_example.py --host localhost --port 8000 --image ./test.jpg --test multimodal
        """,
    )

    # Connection mode: SageMaker or HTTP
    mode_group = parser.add_argument_group("Connection Mode (choose one)")
    mode_group.add_argument(
        "--region",
        type=str,
        help="AWS region for SageMaker (e.g., us-east-1)",
    )
    mode_group.add_argument(
        "--endpoint-name",
        type=str,
        help="SageMaker endpoint name",
    )
    mode_group.add_argument(
        "--host",
        type=str,
        help="HTTP host for EC2/local (e.g., localhost)",
    )
    mode_group.add_argument(
        "--port",
        type=int,
        default=8000,
        help="HTTP port for EC2/local (default: 8000)",
    )

    # Test options
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
        "--verbose",
        action="store_true",
        default=True,
        help="Verbose output",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=3600,
        help="Request timeout in seconds (default: 3600)",
    )

    args = parser.parse_args()

    # Determine connection mode
    sagemaker_mode = args.region and args.endpoint_name
    http_mode = args.host

    if sagemaker_mode and http_mode:
        parser.error(
            "Cannot use both SageMaker (--region/--endpoint-name) and HTTP (--host) modes together"
        )
    elif sagemaker_mode:
        client = SageMakerClient(args.region, args.endpoint_name, args.timeout)
        mode_str = "SageMaker"
    elif http_mode:
        client = HTTPClient(args.host, args.port, args.timeout)
        mode_str = "HTTP (EC2/Local)"
    else:
        parser.error(
            "Must specify either SageMaker mode (--region and --endpoint-name) or HTTP mode (--host)"
        )

    print("\n" + "=" * 60)
    print("COSMOS REASON1 NIM EXAMPLES")
    print("=" * 60)
    print(f"Mode: {mode_str}")
    print(f"Endpoint: {client.get_endpoint_info()}")
    print(f"Test: {args.test}")

    # Track results
    results = {}

    # Run tests based on selection
    if args.test in ["all", "health"]:
        results["health"] = test_endpoint_health(client)

    if args.test in ["all", "basic"]:
        results["basic"] = test_basic_text_inference(client, args.verbose)

    if args.test in ["all", "streaming"]:
        results["streaming"] = test_streaming_inference(client, args.verbose)

    if args.test in ["all", "reasoning"]:
        results["reasoning"] = test_reasoning_mode(client, args.verbose)

    if args.test in ["all", "multimodal"]:
        results["multimodal"] = test_multimodal_inference(
            client, args.image, args.verbose
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
