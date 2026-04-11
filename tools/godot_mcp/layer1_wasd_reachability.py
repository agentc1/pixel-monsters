#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import argparse
import json
import os
import sys
from collections import deque
from pathlib import Path
from typing import Any

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


REPO_ROOT = Path(__file__).resolve().parents[2]
RUNTIME_SCENE = "res://cainos_imports/basic_real_acceptance/scenes/unity/SC Demo Runtime.tscn"
RUNTIME_ROOT = "/root/GodotMcpRuntime/SceneHost/SC Demo Runtime"
PLAYER_PATH = f"{RUNTIME_ROOT}/RuntimePlayer"
OVERLAY_PATH = f"{RUNTIME_ROOT}/NavigationOverlay"
ARTIFACT_DIR = REPO_ROOT / "godot_project" / "tmp"

DIRECTIONS = ("north", "south", "east", "west")
KEY_FOR_DIRECTION = {
    "north": "W",
    "south": "S",
    "east": "D",
    "west": "A",
}
OPPOSITE_DIRECTION = {
    "north": "south",
    "south": "north",
    "east": "west",
    "west": "east",
}


State = tuple[str, tuple[int, int]]


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate inferred overlay reachability by replaying real WASD routes from the runtime player origin."
    )
    parser.add_argument(
        "--layer",
        default="Layer 1",
        help='Target overlay layer to audit, for example "Layer 1", "Layer 2", or just "2".',
    )
    parser.add_argument(
        "--window-mode",
        default="headless",
        choices=["headless", "windowed"],
        help="Run the Godot MCP scene headlessly or in a visible window.",
    )
    parser.add_argument(
        "--hold-ms",
        type=int,
        default=80,
        help="Milliseconds to hold each WASD key press.",
    )
    parser.add_argument(
        "--frames-after",
        type=int,
        default=12,
        help="Physics/process frames to wait after each key release.",
    )
    parser.add_argument(
        "--hold-open-sec",
        type=float,
        default=0.0,
        help="Keep the visible Godot session open for this many seconds after the audit completes.",
    )
    return parser.parse_args()


def _normalize_layer_name(value: str) -> str:
    normalized = value.strip()
    if normalized.isdigit():
        return "Layer %s" % normalized
    lower = normalized.lower().replace("_", " ")
    if lower.startswith("level "):
        return "Layer %s" % lower[6:].strip()
    if lower.startswith("layer "):
        number = lower[6:].strip()
        return "Layer %s" % number
    return normalized


def _artifact_path_for_layer(layer_name: str) -> Path:
    slug = layer_name.lower().replace(" ", "")
    return ARTIFACT_DIR / ("%s_wasd_reachability.json" % slug)


def _server_params() -> StdioServerParameters:
    return StdioServerParameters(
        command=sys.executable,
        args=["-m", "godot_mcp.server"],
        cwd=REPO_ROOT,
        env=dict(os.environ),
    )


def _structured(result) -> dict[str, Any]:
    if getattr(result, "isError", False):
        raise RuntimeError(f"Tool returned error: {result}")
    payload = getattr(result, "structuredContent", None)
    if payload is None:
        raise RuntimeError(f"Tool returned no structured content: {result}")
    if not payload.get("ok", True):
        raise RuntimeError(f"Tool returned failure: {payload}")
    return payload


def _cell_from_payload(value: Any) -> tuple[int, int]:
    if isinstance(value, dict):
        return (int(round(float(value.get("x", 0)))), int(round(float(value.get("y", 0)))))
    raise TypeError(f"Unsupported cell payload: {value!r}")


def _state_key(state: State) -> str:
    layer, cell = state
    return f"{layer}:{cell[0]},{cell[1]}"


def _sorted_cells(cells: set[tuple[int, int]]) -> list[dict[str, int]]:
    return [{"x": x, "y": y} for x, y in sorted(cells, key=lambda cell: (cell[1], cell[0]))]


def _sorted_state_keys(states: set[State]) -> list[str]:
    return sorted((_state_key(state) for state in states), key=lambda key: (key.split(":")[0], key.split(":")[1]))


class WasdReachabilityProbe:
    def __init__(self, session: ClientSession, *, window_mode: str, hold_ms: int, frames_after: int) -> None:
        self.session = session
        self.window_mode = window_mode
        self.hold_ms = max(1, hold_ms)
        self.frames_after = max(0, frames_after)
        self.origin: State | None = None
        self.observed_states: set[State] = set()
        self.visited: set[State] = set()
        self.success_edges: dict[State, dict[str, State]] = {}
        self.blocked_edges: dict[State, set[str]] = {}
        self.anomalies: list[str] = []
        self.out_of_bounds_moves: list[str] = []
        self.bounds_position: tuple[int, int] = (0, 0)
        self.bounds_size: tuple[int, int] = (0, 0)
        self.tap_count = 0

    async def call(self, tool_name: str, args: dict[str, Any]) -> dict[str, Any]:
        return _structured(await self.session.call_tool(tool_name, args))

    async def start(self) -> None:
        play = await self.call("godot_play_scene", {"scene_path": RUNTIME_SCENE, "window_mode": self.window_mode})
        if play.get("loaded_scene_path") != RUNTIME_SCENE:
            raise AssertionError(play)
        rebuild = await self.call(
            "godot_call_node_method",
            {"node_path": OVERLAY_PATH, "method_name": "rebuild_navigation_overlay", "frames_after": 2},
        )
        if not rebuild.get("called") or not rebuild.get("result", {}).get("ok"):
            raise AssertionError(rebuild)
        overlay_info = await self.call("godot_node_info", {"node_path": OVERLAY_PATH})
        meta = overlay_info.get("node", {}).get("meta", {})
        bounds = meta.get("grid_navigation_bounds", {})
        bounds_position = bounds.get("position", {})
        bounds_size = bounds.get("size", {})
        self.bounds_position = _cell_from_payload(bounds_position)
        self.bounds_size = _cell_from_payload(bounds_size)
        self.origin = await self.player_state()
        self.observed_states.add(self.origin)

    async def inferred_cells_for_layer(self, layer_name: str) -> set[tuple[int, int]]:
        result = await self.call(
            "godot_call_node_method",
            {
                "node_path": OVERLAY_PATH,
                "method_name": "reachable_cells_for_layer",
                "args": [layer_name],
                "frames_after": 1,
            },
        )
        if not result.get("called"):
            raise AssertionError(result)
        return {_cell_from_payload(cell) for cell in result.get("result", [])}

    async def inferred_paths_from_origin(self) -> dict[State, tuple[State | None, str]]:
        if self.origin is None:
            raise AssertionError("Probe was not started.")
        queue: deque[State] = deque([self.origin])
        parent: dict[State, tuple[State | None, str]] = {self.origin: (None, "")}
        while queue:
            state = queue.popleft()
            for direction in DIRECTIONS:
                step = await self.can_step_from_state(state, direction)
                if not step.get("allowed", False):
                    continue
                next_state = (str(step.get("to_layer", state[0])), _cell_from_payload(step.get("to_cell", {})))
                if not self.in_bounds(next_state) or next_state in parent:
                    continue
                parent[next_state] = (state, direction)
                queue.append(next_state)
        return parent

    async def can_step_from_state(self, state: State, direction: str) -> dict[str, Any]:
        result = await self.call(
            "godot_call_node_method",
            {
                "node_path": PLAYER_PATH,
                "method_name": "can_grid_step_from_cell",
                "args": [state[0], {"x": state[1][0], "y": state[1][1]}, direction],
                "frames_after": 0,
            },
        )
        if not result.get("called"):
            raise AssertionError(result)
        return dict(result.get("result", {}))

    async def reload_origin(self) -> State:
        play = await self.call("godot_play_scene", {"scene_path": RUNTIME_SCENE, "window_mode": self.window_mode})
        if play.get("loaded_scene_path") != RUNTIME_SCENE:
            raise AssertionError(play)
        await self.call(
            "godot_call_node_method",
            {"node_path": OVERLAY_PATH, "method_name": "rebuild_navigation_overlay", "frames_after": 2},
        )
        state = await self.player_state()
        self.observed_states.add(state)
        if self.origin is not None and state != self.origin:
            raise AssertionError(f"Reloaded to {_state_key(state)}, expected {_state_key(self.origin)}")
        return state

    def route_from_parent(self, parent: dict[State, tuple[State | None, str]], target: State) -> list[tuple[str, State]]:
        if self.origin is None:
            raise AssertionError("Probe was not started.")
        if target not in parent:
            raise AssertionError(f"No inferred route to {_state_key(target)}")
        steps: list[tuple[str, State]] = []
        state = target
        while state != self.origin:
            previous, direction = parent[state]
            if previous is None:
                break
            steps.append((direction, state))
            state = previous
        steps.reverse()
        return steps

    async def audit_inferred_layer_routes(self, target_layer: str, inferred_cells: set[tuple[int, int]]) -> dict[str, Any]:
        parent = await self.inferred_paths_from_origin()
        successful: set[tuple[int, int]] = set()
        failures: list[dict[str, Any]] = []
        for target_cell in sorted(inferred_cells, key=lambda item: (item[1], item[0])):
            target: State = (target_layer, target_cell)
            if target not in parent:
                failures.append({
                    "target": {"x": target_cell[0], "y": target_cell[1]},
                    "reason": "no_inferred_route_from_origin",
                })
                continue
            route = self.route_from_parent(parent, target)
            await self.reload_origin()
            mismatch: dict[str, Any] | None = None
            for direction, expected_state in route:
                actual_state = await self.tap(direction)
                if actual_state != expected_state:
                    mismatch = {
                        "direction": direction,
                        "expected_state": _state_key(expected_state),
                        "actual_state": _state_key(actual_state),
                    }
                    break
            final_state = await self.player_state()
            if mismatch != None or final_state != target:
                failures.append({
                    "target": {"x": target_cell[0], "y": target_cell[1]},
                    "route": [direction for direction, _state in route],
                    "final_state": _state_key(final_state),
                    "mismatch": mismatch,
                })
            else:
                successful.add(target_cell)
        return {
            "successful_cells": _sorted_cells(successful),
            "failed_routes": failures,
            "inferred_state_count": len(parent),
        }

    async def player_state(self) -> State:
        info = await self.call("godot_node_info", {"node_path": PLAYER_PATH})
        if not info.get("found"):
            raise AssertionError(info)
        node = info["node"]
        meta = node.get("meta", {})
        layer = str(meta.get("cainos_runtime_collision_layer_name", "Layer 1"))
        position = node.get("global_position", {"x": 0.0, "y": 0.0})
        cell_result = await self.call(
            "godot_call_node_method",
            {
                "node_path": PLAYER_PATH,
                "method_name": "grid_cell_for_position",
                "args": [position],
                "frames_after": 0,
            },
        )
        if not cell_result.get("called"):
            raise AssertionError(cell_result)
        return (layer, _cell_from_payload(cell_result["result"]))

    async def tap(self, direction: str) -> State:
        self.tap_count += 1
        pressed = await self.call(
            "godot_press_keys",
            {
                "keys": [KEY_FOR_DIRECTION[direction]],
                "hold_ms": self.hold_ms,
                "frames_after": self.frames_after,
            },
        )
        if not pressed.get("ok", False):
            raise AssertionError(pressed)
        state = await self.player_state()
        self.observed_states.add(state)
        return state

    async def explore_from_origin(self) -> None:
        if self.origin is None:
            raise AssertionError("Probe was not started.")
        await self._explore(self.origin)

    async def _explore(self, state: State) -> None:
        if not self.in_bounds(state):
            return
        current = await self.player_state()
        if current != state:
            await self.navigate_to(state)
        self.visited.add(state)
        for direction in DIRECTIONS:
            current = await self.player_state()
            if current != state:
                await self.navigate_to(state)
            if direction in self.success_edges.get(state, {}) or direction in self.blocked_edges.get(state, set()):
                continue

            after = await self.tap(direction)
            if after == state:
                self.blocked_edges.setdefault(state, set()).add(direction)
                continue

            self.success_edges.setdefault(state, {})[direction] = after
            if not self.in_bounds(after):
                self.visited.add(after)
                self.out_of_bounds_moves.append(
                    "%s from %s escaped overlay bounds to %s"
                    % (direction, _state_key(state), _state_key(after))
                )
            reverse_direction = OPPOSITE_DIRECTION[direction]
            returned = await self.tap(reverse_direction)
            if returned != state:
                self.anomalies.append(
                    "Could not reverse %s from %s through %s; landed at %s"
                    % (direction, _state_key(state), _state_key(after), _state_key(returned))
                )
                await self.recover_to(state)
                continue
            self.success_edges.setdefault(after, {})[reverse_direction] = state

            if self.in_bounds(after) and after not in self.visited:
                moved_again = await self.tap(direction)
                if moved_again != after:
                    self.anomalies.append(
                        "Could not replay %s from %s to %s; landed at %s"
                        % (direction, _state_key(state), _state_key(after), _state_key(moved_again))
                    )
                    await self.recover_to(state)
                    continue
                await self._explore(after)
                await self.navigate_to(state)

    def in_bounds(self, state: State) -> bool:
        _layer, cell = state
        min_x, min_y = self.bounds_position
        size_x, size_y = self.bounds_size
        return min_x <= cell[0] < min_x + size_x and min_y <= cell[1] < min_y + size_y

    async def recover_to(self, target: State) -> None:
        current = await self.player_state()
        if current == target:
            return
        if self.origin is None:
            raise AssertionError("Probe was not started.")
        path = self.find_path(current, target)
        if path is not None:
            await self.follow_path(path, target)
            return

        play = await self.call("godot_play_scene", {"scene_path": RUNTIME_SCENE, "window_mode": "headless"})
        if play.get("loaded_scene_path") != RUNTIME_SCENE:
            raise AssertionError(play)
        await self.call(
            "godot_call_node_method",
            {"node_path": OVERLAY_PATH, "method_name": "rebuild_navigation_overlay", "frames_after": 2},
        )
        current = await self.player_state()
        if current != self.origin:
            raise AssertionError(f"Reloaded to {current}, expected origin {self.origin}")
        path = self.find_path(self.origin, target)
        if path is None:
            raise AssertionError(f"No discovered path from origin to {target}")
        await self.follow_path(path, target)

    async def navigate_to(self, target: State) -> None:
        current = await self.player_state()
        if current == target:
            return
        path = self.find_path(current, target)
        if path is None:
            await self.recover_to(target)
            return
        await self.follow_path(path, target)

    async def follow_path(self, path: list[str], target: State) -> None:
        for direction in path:
            await self.tap(direction)
        current = await self.player_state()
        if current != target:
            raise AssertionError(f"Navigation path landed at {_state_key(current)}, expected {_state_key(target)}")

    def find_path(self, start: State, target: State) -> list[str] | None:
        if start == target:
            return []
        queue: deque[State] = deque([start])
        parent: dict[State, tuple[State, str] | None] = {start: None}
        while queue:
            state = queue.popleft()
            for direction, next_state in self.success_edges.get(state, {}).items():
                if next_state in parent:
                    continue
                parent[next_state] = (state, direction)
                if next_state == target:
                    return self._path_from_parent(parent, start, target)
                queue.append(next_state)
        return None

    def _path_from_parent(self, parent: dict[State, tuple[State, str] | None], start: State, target: State) -> list[str]:
        path: list[str] = []
        state = target
        while state != start:
            previous = parent[state]
            if previous is None:
                break
            state, direction = previous
            path.append(direction)
        path.reverse()
        return path


async def main() -> int:
    args = _parse_args()
    target_layer = _normalize_layer_name(str(args.layer))
    artifact_path = _artifact_path_for_layer(target_layer)
    exit_code = 0
    async with stdio_client(_server_params()) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            probe = WasdReachabilityProbe(
                session,
                window_mode=str(args.window_mode),
                hold_ms=int(args.hold_ms),
                frames_after=int(args.frames_after),
            )
            try:
                await probe.start()
                inferred_cells = await probe.inferred_cells_for_layer(target_layer)
                audit = await probe.audit_inferred_layer_routes(target_layer, inferred_cells)
                successful_cells = {
                    (int(cell["x"]), int(cell["y"]))
                    for cell in audit.get("successful_cells", [])
                    if isinstance(cell, dict)
                }
                missing_from_actual = inferred_cells - successful_cells
                artifact = {
                    "scene": RUNTIME_SCENE,
                    "target_layer": target_layer,
                    "window_mode": str(args.window_mode),
                    "hold_ms": int(args.hold_ms),
                    "frames_after": int(args.frames_after),
                    "proof_scope": "Every inferred %s overlay cell is tested as reachable from origin via real WASD input. This route audit does not claim exhaustive discovery of non-inferred cells." % target_layer,
                    "origin": {
                        "layer": probe.origin[0] if probe.origin else "",
                        "cell": {"x": probe.origin[1][0], "y": probe.origin[1][1]} if probe.origin else {},
                    },
                    "tap_count": probe.tap_count,
                    "observed_state_count": len(probe.observed_states),
                    "inferred_state_count": int(audit.get("inferred_state_count", 0)),
                    "successful_target_count": len(successful_cells),
                    "inferred_target_count": len(inferred_cells),
                    "bounds": {
                        "position": {"x": probe.bounds_position[0], "y": probe.bounds_position[1]},
                        "size": {"x": probe.bounds_size[0], "y": probe.bounds_size[1]},
                    },
                    "missing_from_actual": _sorted_cells(missing_from_actual),
                    "failed_routes": audit.get("failed_routes", []),
                    "anomalies": probe.anomalies,
                    "out_of_bounds_moves": probe.out_of_bounds_moves,
                    "successful_cells": audit.get("successful_cells", []),
                }
                artifact_path.parent.mkdir(parents=True, exist_ok=True)
                artifact_path.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
                print(json.dumps(artifact, indent=2))
                if (
                    missing_from_actual
                    or audit.get("failed_routes", [])
                    or probe.anomalies
                    or probe.out_of_bounds_moves
                ):
                    exit_code = 1
                if float(args.hold_open_sec) > 0.0:
                    await asyncio.sleep(float(args.hold_open_sec))
            finally:
                await session.call_tool("godot_stop", {})
    return exit_code


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
