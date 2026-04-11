from __future__ import annotations

import asyncio
from typing import Any

from mcp.server.fastmcp import FastMCP

from .session import GodotBridgeError, GodotBridgeSession


mcp = FastMCP("godot-runtime", json_response=True)
session = GodotBridgeSession()


def _ok(result: dict[str, Any]) -> dict[str, Any]:
    payload = dict(result)
    payload.setdefault("ok", True)
    return payload


def _err(error: Exception) -> dict[str, Any]:
    if isinstance(error, GodotBridgeError):
        return {
            "ok": False,
            "error": {
                "code": error.code,
                "message": error.message,
            },
        }
    return {
        "ok": False,
        "error": {
            "code": "unexpected_error",
            "message": str(error),
        },
    }


@mcp.tool()
async def godot_play_scene(scene_path: str, reuse_existing: bool = True, window_mode: str = "windowed") -> dict[str, Any]:
    """Launch the Godot runtime bridge and load a scene under the bridge host."""
    try:
        result = await session.play_scene(scene_path, reuse_existing=reuse_existing, window_mode=window_mode)
        return _ok(result)
    except Exception as exc:  # pragma: no cover - surfaced as tool result
        return _err(exc)


@mcp.tool()
async def godot_stop() -> dict[str, Any]:
    """Stop the active Godot bridge session."""
    try:
        await session.stop()
        return {"ok": True, "stopped": True}
    except Exception as exc:  # pragma: no cover
        return _err(exc)


@mcp.tool()
async def godot_status() -> dict[str, Any]:
    """Return process and runtime status for the active Godot session."""
    try:
        return _ok(await session.status())
    except Exception as exc:  # pragma: no cover
        return _err(exc)


@mcp.tool()
async def godot_scene_tree(
    root_path: str = "/root/GodotMcpRuntime/SceneHost",
    max_depth: int = 3,
    include_internal: bool = False,
) -> dict[str, Any]:
    """Return a serialized live scene tree under the given root path."""
    try:
        return _ok(await session.scene_tree(root_path, max_depth=max_depth, include_internal=include_internal))
    except Exception as exc:  # pragma: no cover
        return _err(exc)


@mcp.tool()
async def godot_node_info(node_path: str) -> dict[str, Any]:
    """Return runtime details for a single node path."""
    try:
        return _ok(await session.node_info(node_path))
    except Exception as exc:  # pragma: no cover
        return _err(exc)


@mcp.tool()
async def godot_set_node_property(node_path: str, property_name: str, value: Any, frames_after: int = 1) -> dict[str, Any]:
    """Set a runtime node property, then advance a small number of frames."""
    try:
        return _ok(await session.set_node_property(node_path, property_name, value, frames_after=frames_after))
    except Exception as exc:  # pragma: no cover
        return _err(exc)


@mcp.tool()
async def godot_call_node_method(node_path: str, method_name: str, args: list[Any] | None = None, frames_after: int = 1) -> dict[str, Any]:
    """Call a runtime node method, then advance a small number of frames."""
    try:
        return _ok(await session.call_node_method(node_path, method_name, args or [], frames_after=frames_after))
    except Exception as exc:  # pragma: no cover
        return _err(exc)


@mcp.tool()
async def godot_capture_viewport(label: str = "capture") -> dict[str, Any]:
    """Capture the active viewport to a PNG on disk and return its metadata."""
    try:
        return _ok(await session.capture_viewport(label=label))
    except Exception as exc:  # pragma: no cover
        return _err(exc)


@mcp.tool()
async def godot_press_keys(keys: list[str], hold_ms: int = 120, frames_after: int = 2) -> dict[str, Any]:
    """Inject key press events into the running Godot scene."""
    try:
        return _ok(await session.press_keys(keys, hold_ms=hold_ms, frames_after=frames_after))
    except Exception as exc:  # pragma: no cover
        return _err(exc)


@mcp.tool()
async def godot_advance_frames(frames: int = 1) -> dict[str, Any]:
    """Advance the running scene by a number of frames."""
    try:
        return _ok(await session.advance_frames(frames=frames))
    except Exception as exc:  # pragma: no cover
        return _err(exc)


@mcp.tool()
async def godot_logs(since_seq: int = 0, limit: int = 200) -> dict[str, Any]:
    """Return captured stdout/stderr lines from the Godot process."""
    try:
        return session.logs(since_seq=since_seq, limit=limit)
    except Exception as exc:  # pragma: no cover
        return _err(exc)


def main() -> None:
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
