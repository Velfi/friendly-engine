#!/usr/bin/env python3
"""Capture Friendly Engine editor UI states through the MCP control surface."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MCP = REPO_ROOT / "zig-out" / "bin" / "friendly_engine_mcp"
DEFAULT_OUT = REPO_ROOT / ".friendly-engine" / "ui-screenshots"


@dataclass(frozen=True)
class UiState:
    group: str
    label: str
    commands: tuple[str, ...] = ()
    tools: tuple[tuple[str, dict[str, Any]], ...] = ()


MODE_COMMANDS = {
    "world": "ed-mode-world-creation",
    "layout": "ed-mode-layout",
    "architecture": "ed-mode-architecture-creation",
    "prop": "ed-mode-prop-creation",
    "life": "ed-mode-life",
}

UI_STATES: tuple[UiState, ...] = (
    UiState("mode", "world", (MODE_COMMANDS["world"],)),
    UiState("mode", "layout", (MODE_COMMANDS["layout"],)),
    UiState("mode", "architecture", (MODE_COMMANDS["architecture"],)),
    UiState("mode", "prop", (MODE_COMMANDS["prop"],)),
    UiState("mode", "life", (MODE_COMMANDS["life"],)),
    UiState("left-tab", "scene", (MODE_COMMANDS["world"], "ed-left-scene")),
    UiState("left-tab", "add", (MODE_COMMANDS["world"], "ed-left-add")),
    UiState("left-tab", "world", (MODE_COMMANDS["world"], "ed-left-world")),
    UiState("left-tab", "assets", (MODE_COMMANDS["world"], "ed-left-assets")),
    UiState("world-tool", "terrain", (MODE_COMMANDS["world"], "ed-world-terrain")),
    UiState("world-tool", "paint", (MODE_COMMANDS["world"], "ed-world-paint")),
    UiState("world-tool", "roads", (MODE_COMMANDS["world"], "ed-world-roads")),
    UiState("world-tool", "scatter", (MODE_COMMANDS["world"], "ed-world-scatter")),
    UiState("world-tool", "atmosphere", (MODE_COMMANDS["world"], "ed-world-atmosphere")),
    UiState("world-tool", "ocean", (MODE_COMMANDS["world"], "ed-world-ocean")),
    UiState("world-tool", "water", (MODE_COMMANDS["world"], "ed-world-water")),
    UiState("world-tool", "measure", (MODE_COMMANDS["world"], "ed-world-measure")),
    UiState("world-road-tool", "draw", (MODE_COMMANDS["world"], "ed-world-roads", "ed-world-road-mode-draw")),
    UiState("world-road-tool", "select", (MODE_COMMANDS["world"], "ed-world-roads", "ed-world-road-mode-select")),
    UiState("world-road-tool", "shape", (MODE_COMMANDS["world"], "ed-world-roads", "ed-world-road-mode-shape")),
    UiState("world-road-tool", "join", (MODE_COMMANDS["world"], "ed-world-roads", "ed-world-road-mode-join")),
    UiState("world-road-tool", "surface", (MODE_COMMANDS["world"], "ed-world-roads", "ed-world-road-mode-surface")),
    UiState("world-road-draw", "point", (MODE_COMMANDS["world"], "ed-world-roads", "ed-world-road-mode-draw", "ed-world-road-point")),
    UiState("world-road-draw", "freehand", (MODE_COMMANDS["world"], "ed-world-roads", "ed-world-road-mode-draw", "ed-world-road-freehand")),
    UiState("layout-tool", "select", (MODE_COMMANDS["layout"], "ed-object-select")),
    UiState("layout-tool", "move", (MODE_COMMANDS["layout"], "ed-object-move")),
    UiState("layout-tool", "rotate", (MODE_COMMANDS["layout"], "ed-object-rotate")),
    UiState("layout-tool", "scale", (MODE_COMMANDS["layout"], "ed-object-scale")),
    UiState("architecture-tool", "brush", (MODE_COMMANDS["architecture"], "ed-architecture-brush")),
    UiState("architecture-tool", "floor", (MODE_COMMANDS["architecture"], "ed-architecture-floorplan")),
    UiState("architecture-tool", "wall", (MODE_COMMANDS["architecture"], "ed-architecture-wall")),
    UiState("architecture-tool", "door", (MODE_COMMANDS["architecture"], "ed-architecture-door")),
    UiState("architecture-tool", "window", (MODE_COMMANDS["architecture"], "ed-architecture-window")),
    UiState("architecture-tool", "curve", (MODE_COMMANDS["architecture"], "ed-architecture-curve")),
    UiState("architecture-tool", "add", (MODE_COMMANDS["architecture"], "ed-architecture-add")),
    UiState("architecture-tool", "subtract", (MODE_COMMANDS["architecture"], "ed-architecture-subtract")),
    UiState("architecture-tool", "ramp", (MODE_COMMANDS["architecture"], "ed-architecture-ramp")),
    UiState("architecture-tool", "vertex", (MODE_COMMANDS["architecture"], "ed-architecture-vertex")),
    UiState("architecture-tool", "edge", (MODE_COMMANDS["architecture"], "ed-architecture-edge")),
    UiState("architecture-tool", "face", (MODE_COMMANDS["architecture"], "ed-architecture-face")),
    UiState("architecture-tool", "extrude", (MODE_COMMANDS["architecture"], "ed-architecture-extrude")),
    UiState("architecture-tool", "inset", (MODE_COMMANDS["architecture"], "ed-architecture-inset")),
    UiState("architecture-tool", "material", (MODE_COMMANDS["architecture"], "ed-architecture-material")),
    UiState("prop-tool", "select", (MODE_COMMANDS["prop"], "ed-prop-select")),
    UiState("prop-tool", "create", (MODE_COMMANDS["prop"], "ed-prop-create")),
    UiState("prop-tool", "asset", (MODE_COMMANDS["prop"], "ed-prop-asset")),
    UiState("prop-tool", "primitive", (MODE_COMMANDS["prop"], "ed-prop-primitive")),
    UiState("prop-tool", "edit", (MODE_COMMANDS["prop"], "ed-prop-edit")),
    UiState("prop-tool", "material", (MODE_COMMANDS["prop"], "ed-prop-material")),
    UiState("prop-tool", "collider", (MODE_COMMANDS["prop"], "ed-prop-collider")),
    UiState("prop-tool", "variants", (MODE_COMMANDS["prop"], "ed-prop-variants")),
    UiState("prop-render", "wireframe", (MODE_COMMANDS["prop"], "ed-prop-edit"), (("prop_render_mode", {"object": "wireframe"}),)),
    UiState("prop-render", "solid", (MODE_COMMANDS["prop"], "ed-prop-edit"), (("prop_render_mode", {"object": "solid"}),)),
    UiState("prop-render", "material-preview", (MODE_COMMANDS["prop"], "ed-prop-edit"), (("prop_render_mode", {"object": "material_preview"}),)),
    UiState("prop-render", "rendered", (MODE_COMMANDS["prop"], "ed-prop-edit"), (("prop_render_mode", {"object": "rendered"}),)),
    UiState("life-tool", "select", (MODE_COMMANDS["life"], "ed-life-select")),
    UiState("life-tool", "pose", (MODE_COMMANDS["life"], "ed-life-pose")),
    UiState("life-tool", "keyframe", (MODE_COMMANDS["life"], "ed-life-keyframe")),
    UiState("life-tool", "record", (MODE_COMMANDS["life"], "ed-life-record")),
    UiState("life-tool", "playback", (MODE_COMMANDS["life"], "ed-life-playback")),
    UiState("life-tool", "clips", (MODE_COMMANDS["life"], "ed-life-clips")),
    UiState("life-tool", "bones", (MODE_COMMANDS["life"], "ed-life-bones")),
    UiState("life-tool", "curves", (MODE_COMMANDS["life"], "ed-life-curves")),
)


class McpClient:
    def __init__(self, mcp_path: Path, timeout: float) -> None:
        self.mcp_path = mcp_path
        self.timeout = timeout
        self.next_id = 1

    def call(self, name: str, arguments: dict[str, Any] | None = None) -> Any:
        request = {
            "jsonrpc": "2.0",
            "id": self.next_id,
            "method": "tools/call",
            "params": {"name": name, "arguments": arguments or {}},
        }
        self.next_id += 1
        return self._send(request)

    def list_tools(self) -> Any:
        request = {"jsonrpc": "2.0", "id": self.next_id, "method": "tools/list"}
        self.next_id += 1
        return self._send(request)

    def _send(self, request: dict[str, Any]) -> Any:
        proc = subprocess.run(
            [str(self.mcp_path)],
            input=json.dumps(request, separators=(",", ":")) + "\n",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=self.timeout,
            cwd=REPO_ROOT,
            check=False,
        )
        if proc.returncode != 0:
            raise RuntimeError(f"MCP exited {proc.returncode}: {proc.stderr.strip()}")
        response = parse_jsonrpc_response(proc.stdout, request["id"])
        if "error" in response:
            raise RuntimeError(f"MCP {request.get('method')} failed: {response['error']}")
        result = response.get("result")
        if isinstance(result, dict) and result.get("isError"):
            tool_name = request.get("params", {}).get("name", request.get("method"))
            raise RuntimeError(f"MCP tool {tool_name} failed: {extract_tool_payload(result)!r}")
        payload = extract_tool_payload(result)
        if isinstance(payload, dict) and payload.get("ok") is False:
            tool_name = request.get("params", {}).get("name", request.get("method"))
            raise RuntimeError(f"MCP tool {tool_name} failed: {payload!r}")
        return result


def parse_jsonrpc_response(stdout: str, request_id: int) -> dict[str, Any]:
    for line in stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if payload.get("id") == request_id:
            return payload
    raise RuntimeError(f"No JSON-RPC response for id {request_id}. Output was:\n{stdout}")


def extract_tool_payload(result: Any) -> Any:
    if not isinstance(result, dict):
        return result
    content = result.get("content")
    if isinstance(content, list):
        texts = [item.get("text") for item in content if isinstance(item, dict) and item.get("type") == "text"]
        if len(texts) == 1 and isinstance(texts[0], str):
            return parse_embedded_json(texts[0])
        return [parse_embedded_json(text) for text in texts if isinstance(text, str)]
    return result


def parse_embedded_json(text: str) -> Any:
    text = text.strip()
    if text.startswith("{") or text.startswith("["):
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text
    return text


def find_png_path(payload: Any) -> str:
    paths: list[str] = []

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, inner in value.items():
                if isinstance(inner, str) and key in {"path", "png_path", "screenshot_path", "file"}:
                    if inner.endswith(".png"):
                        paths.append(inner)
                walk(inner)
        elif isinstance(value, list):
            for inner in value:
                walk(inner)
        elif isinstance(value, str):
            for match in re.findall(r"[/A-Za-z0-9_. -]+\.png", value):
                paths.append(match.strip())

    walk(payload)
    if not paths:
        raise RuntimeError(f"Screenshot result did not contain a PNG path: {payload!r}")
    return paths[0]


def slug(text: str) -> str:
    lowered = text.lower()
    return re.sub(r"[^a-z0-9]+", "-", lowered).strip("-")


def command_set(payload: Any) -> set[str]:
    commands: set[str] = set()

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            ident = value.get("id")
            if isinstance(ident, str):
                commands.add(ident)
            for inner in value.values():
                walk(inner)
        elif isinstance(value, list):
            for inner in value:
                walk(inner)

    walk(payload)
    return commands


def tool_set(payload: Any) -> set[str]:
    if not isinstance(payload, dict):
        return set()
    tools = payload.get("tools")
    if not isinstance(tools, list):
        return set()
    return {tool["name"] for tool in tools if isinstance(tool, dict) and isinstance(tool.get("name"), str)}


def required_tools() -> set[str]:
    values = {"commands_list", "command_run", "editor_describe", "screenshot_editor"}
    for state in UI_STATES:
        values.update(name for name, _ in state.tools)
    return values


def capture(
    client: McpClient,
    out_dir: Path,
    state: UiState,
    delay: float,
    include_viewport: bool,
) -> dict[str, Any]:
    for command in state.commands:
        client.call("command_run", {"command": command})
        if delay > 0:
            time.sleep(delay)
    for name, arguments in state.tools:
        client.call(name, arguments)
        if delay > 0:
            time.sleep(delay)

    describe = extract_tool_payload(client.call("editor_describe"))

    state_slug = f"{slug(state.group)}-{slug(state.label)}"
    editor_src = Path(find_png_path(extract_tool_payload(client.call("screenshot_editor"))))
    editor_dst = out_dir / f"{state_slug}.png"
    shutil.copy2(editor_src, editor_dst)

    entry: dict[str, Any] = {
        "group": state.group,
        "label": state.label,
        "commands": list(state.commands),
        "tools": [{"name": name, "arguments": arguments} for name, arguments in state.tools],
        "describe": describe,
        "editor_screenshot": str(editor_dst),
        "editor_source": str(editor_src),
    }

    if include_viewport:
        viewport_src = Path(find_png_path(extract_tool_payload(client.call("screenshot_viewport"))))
        viewport_dst = out_dir / f"{state_slug}-viewport.png"
        shutil.copy2(viewport_src, viewport_dst)
        entry["viewport_screenshot"] = str(viewport_dst)
        entry["viewport_source"] = str(viewport_src)

    return entry


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture documentation/test screenshots for every editor mode, tab, and tool.",
    )
    parser.add_argument("--mcp", type=Path, default=DEFAULT_MCP, help="Path to friendly_engine_mcp.")
    parser.add_argument("--project", help="Project object/name to open before capture.")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="Output directory for copied screenshots and manifest.")
    parser.add_argument("--delay", type=float, default=0.08, help="Seconds to wait after changing UI state.")
    parser.add_argument("--timeout", type=float, default=10.0, help="Seconds before an MCP call fails.")
    parser.add_argument("--viewport", action="store_true", help="Also capture viewport-only screenshots.")
    parser.add_argument("--dry-run", action="store_true", help="Validate command/tool coverage without capturing.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.mcp.exists():
        raise SystemExit(f"MCP executable does not exist: {args.mcp}")

    client = McpClient(args.mcp, args.timeout)
    tools = tool_set(client.list_tools())
    missing_tools = sorted(required_tools() - tools)
    if missing_tools:
        raise SystemExit(f"Missing required MCP tools: {', '.join(missing_tools)}")

    if args.project:
        client.call("open_project", {"object": args.project})
        if args.delay > 0:
            time.sleep(args.delay)

    if args.dry_run:
        print(f"Validated {len(required_tools())} MCP tools.")
        return 0

    run_dir = args.out / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir.mkdir(parents=True, exist_ok=False)

    manifest: dict[str, Any] = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "mcp": str(args.mcp),
        "project": args.project,
        "output_dir": str(run_dir),
        "states": [],
    }

    for index, state in enumerate(UI_STATES, start=1):
        print(f"[{index:02d}/{len(UI_STATES)}] {state.group}: {state.label}", flush=True)
        manifest["states"].append(capture(client, run_dir, state, args.delay, args.viewport))

    manifest_path = run_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {manifest_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as err:
        print(f"error: {err}", file=sys.stderr)
        raise SystemExit(1)
