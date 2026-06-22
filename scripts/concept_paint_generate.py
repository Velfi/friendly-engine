#!/usr/bin/env python3
"""Generate a Concept Paint styled image from an editor request package."""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
from pathlib import Path
import sys
import urllib.error
import urllib.request
import uuid


OPENAI_URL = "https://api.openai.com/v1/images/edits"
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path, help="Concept Paint request package JSON")
    parser.add_argument("--provider", choices=("openai", "nanobanana"), help="Override package provider")
    parser.add_argument("--project", type=Path, help="Project directory for relative output paths")
    parser.add_argument("--openai-model", default=os.environ.get("OPENAI_IMAGE_MODEL", "gpt-image-1"))
    parser.add_argument("--nanobanana-model", default=os.environ.get("NANOBANANA_MODEL", "gemini-2.5-flash-image-preview"))
    args = parser.parse_args()

    package_path = args.package.resolve()
    package = json.loads(package_path.read_text(encoding="utf-8"))
    project_dir = (args.project or package_path.parents[2]).resolve()
    provider = (args.provider or package.get("provider") or "openai").lower()
    if provider == "external":
        provider = "openai"

    screenshot_path = resolve_path(project_dir, package["screenshot_path"])
    output_path = resolve_path(project_dir, package["output_path"])
    prompt = build_prompt(package)

    if provider == "openai":
        image_bytes = generate_openai(args.openai_model, screenshot_path, prompt)
    elif provider in ("nanobanana", "nano-banana", "gemini"):
        image_bytes = generate_nanobanana(args.nanobanana_model, screenshot_path, prompt)
        provider = "nanobanana"
    else:
        raise SystemExit(f"unsupported provider: {provider}")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(image_bytes)
    print(json.dumps({"ok": True, "provider": provider, "output_path": str(output_path)}))
    return 0


def resolve_path(project_dir: Path, value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else project_dir / path


def build_prompt(package: dict) -> str:
    prompt = package.get("prompt") or ""
    style = package.get("desired_style") or ""
    parts = [
        prompt,
        f"Desired style: {style}" if style else "",
        "Preserve the source camera framing and major geometry.",
        "Do not add game/editor UI, toolbars, icons, labels, text, cursors, or overlays.",
        "Return only the stylized in-game viewport image.",
    ]
    return "\n".join(part for part in parts if part)


def generate_openai(model: str, screenshot_path: Path, prompt: str) -> bytes:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise SystemExit("OPENAI_API_KEY is not set")

    fields = {
        "model": model,
        "prompt": prompt,
        "size": os.environ.get("OPENAI_IMAGE_SIZE", "1536x1024"),
        "quality": os.environ.get("OPENAI_IMAGE_QUALITY", "medium"),
    }
    body, content_type = multipart_form(fields, "image", screenshot_path)
    request = urllib.request.Request(
        OPENAI_URL,
        data=body,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": content_type},
        method="POST",
    )
    response = request_json(request)
    try:
        return base64.b64decode(response["data"][0]["b64_json"])
    except (KeyError, IndexError) as exc:
        raise SystemExit(f"OpenAI response did not contain data[0].b64_json: {response}") from exc


def multipart_form(fields: dict[str, str], file_field: str, file_path: Path) -> tuple[bytes, str]:
    boundary = f"----friendly-engine-{uuid.uuid4().hex}"
    chunks: list[bytes] = []
    for name, value in fields.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode("utf-8"),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"),
                str(value).encode("utf-8"),
                b"\r\n",
            ]
        )
    mime = mimetypes.guess_type(file_path.name)[0] or "image/png"
    chunks.extend(
        [
            f"--{boundary}\r\n".encode("utf-8"),
            f'Content-Disposition: form-data; name="{file_field}"; filename="{file_path.name}"\r\n'.encode("utf-8"),
            f"Content-Type: {mime}\r\n\r\n".encode("utf-8"),
            file_path.read_bytes(),
            b"\r\n",
            f"--{boundary}--\r\n".encode("utf-8"),
        ]
    )
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def generate_nanobanana(model: str, screenshot_path: Path, prompt: str) -> bytes:
    api_key = os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise SystemExit("GOOGLE_API_KEY or GEMINI_API_KEY is not set")

    mime = mimetypes.guess_type(screenshot_path.name)[0] or "image/png"
    image_b64 = base64.b64encode(screenshot_path.read_bytes()).decode("ascii")
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": prompt},
                    {"inline_data": {"mime_type": mime, "data": image_b64}},
                ],
            }
        ],
        "generationConfig": {"responseModalities": ["IMAGE"]},
    }
    url = GEMINI_URL.format(model=model, key=api_key)
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    response = request_json(request)
    for candidate in response.get("candidates", []):
        for part in candidate.get("content", {}).get("parts", []):
            inline = part.get("inlineData") or part.get("inline_data")
            if inline and inline.get("data"):
                return base64.b64decode(inline["data"])
    raise SystemExit(f"Nano Banana response did not contain inline image data: {response}")


def request_json(request: urllib.request.Request) -> dict:
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {exc.code}: {body}") from exc


if __name__ == "__main__":
    sys.exit(main())
