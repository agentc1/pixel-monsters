#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

from mcp import ClientSession
from mcp.client.stdio import stdio_client

from layer1_wasd_reachability import (
    ARTIFACT_DIR,
    DIRECTIONS,
    OVERLAY_PATH,
    PLAYER_PATH,
    RUNTIME_SCENE,
    State,
    WasdReachabilityProbe,
    _cell_from_payload,
    _normalize_layer_name,
    _server_params,
    _sorted_cells,
    _state_key,
)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Try to enter every runtime-supported grid cell on a layer that the "
            "navigation overlay does not mark reachable from the player origin."
        )
    )
    parser.add_argument("--layer", default="Layer 1", help='Target layer, for example "Layer 1" or "1".')
    parser.add_argument(
        "--window-mode",
        default="headless",
        choices=["headless", "windowed"],
        help="Run Godot headlessly or in a visible window.",
    )
    parser.add_argument("--hold-ms", type=int, default=80, help="Milliseconds to hold each WASD key press.")
    parser.add_argument("--frames-after", type=int, default=12, help="Frames to wait after each key release.")
    parser.add_argument(
        "--hold-open-sec",
        type=float,
        default=0.0,
        help="Keep the visible Godot session open after the audit completes.",
    )
    return parser.parse_args()


def _artifact_path_for_layer(layer_name: str) -> Path:
    slug = layer_name.lower().replace(" ", "")
    return ARTIFACT_DIR / ("%s_unreachable_wasd_attempts.json" % slug)


class LayerUnreachableAttemptProbe(WasdReachabilityProbe):
    async def supported_unreachable_cells(self, target_layer: str, reachable_cells: set[tuple[int, int]]) -> set[tuple[int, int]]:
        min_x, min_y = self.bounds_position
        size_x, size_y = self.bounds_size
        cells: set[tuple[int, int]] = set()
        for y in range(min_y, min_y + size_y):
            for x in range(min_x, min_x + size_x):
                cell = (x, y)
                if cell in reachable_cells:
                    continue
                if await self.is_grid_cell_navigable(cell, target_layer):
                    cells.add(cell)
        return cells

    async def is_grid_cell_navigable(self, cell: tuple[int, int], layer_name: str) -> bool:
        result = await self.call(
            "godot_call_node_method",
            {
                "node_path": PLAYER_PATH,
                "method_name": "is_grid_cell_navigable",
                "args": [{"x": cell[0], "y": cell[1]}, layer_name],
                "frames_after": 0,
            },
        )
        if not result.get("called"):
            raise AssertionError(result)
        return bool(result.get("result", False))

    async def inbound_attempts_by_target(
        self,
        parent: dict[State, tuple[State | None, str]],
        targets: set[tuple[int, int]],
        target_layer: str,
    ) -> dict[tuple[int, int], list[dict[str, Any]]]:
        inbound: dict[tuple[int, int], list[dict[str, Any]]] = defaultdict(list)
        target_set = set(targets)
        for state in sorted(parent.keys(), key=lambda item: (item[0], item[1][1], item[1][0])):
            for direction in DIRECTIONS:
                probe = await self.can_step_from_state(state, direction)
                to_layer = str(probe.get("to_layer", state[0]))
                to_cell = _cell_from_payload(probe.get("to_cell", {}))
                if to_layer != target_layer or to_cell not in target_set:
                    continue
                inbound[to_cell].append(
                    {
                        "from_state": state,
                        "direction": direction,
                        "predicted": probe,
                        "route_length": self.route_length(parent, state),
                    }
                )
        for attempts in inbound.values():
            attempts.sort(key=lambda item: (int(item.get("route_length", 0)), _state_key(item["from_state"]), item["direction"]))
        return inbound

    def route_length(self, parent: dict[State, tuple[State | None, str]], target: State) -> int:
        length = 0
        state = target
        while state in parent:
            previous, _direction = parent[state]
            if previous is None:
                return length
            length += 1
            state = previous
        return 999999

    async def attempt_inbound_edge(
        self,
        parent: dict[State, tuple[State | None, str]],
        target_layer: str,
        target_cell: tuple[int, int],
        inbound: dict[str, Any],
    ) -> dict[str, Any]:
        from_state: State = inbound["from_state"]
        direction = str(inbound["direction"])
        route = self.route_from_parent(parent, from_state)
        await self.reload_origin()
        route_mismatch: dict[str, Any] | None = None
        for route_direction, expected_state in route:
            actual_state = await self.tap(route_direction)
            if actual_state != expected_state:
                route_mismatch = {
                    "direction": route_direction,
                    "expected_state": _state_key(expected_state),
                    "actual_state": _state_key(actual_state),
                }
                break
        if route_mismatch is not None:
            return {
                "from_state": _state_key(from_state),
                "direction": direction,
                "route": [route_direction for route_direction, _state in route],
                "route_mismatch": route_mismatch,
                "predicted": inbound["predicted"],
                "result": "route_mismatch",
            }

        before_state = await self.player_state()
        after_state = await self.tap(direction)
        target_state: State = (target_layer, target_cell)
        result_name = "confirmed_blocked"
        if after_state == target_state:
            result_name = "unexpectedly_reached"
        elif after_state != before_state:
            result_name = "unexpected_state_change"
        return {
            "from_state": _state_key(from_state),
            "direction": direction,
            "route": [route_direction for route_direction, _state in route],
            "before_state": _state_key(before_state),
            "after_state": _state_key(after_state),
            "predicted": inbound["predicted"],
            "result": result_name,
        }

    async def audit_supported_unreachable_cells(self, target_layer: str) -> dict[str, Any]:
        reachable_cells = await self.inferred_cells_for_layer(target_layer)
        parent = await self.inferred_paths_from_origin()
        candidates = await self.supported_unreachable_cells(target_layer, reachable_cells)
        inbound_by_target = await self.inbound_attempts_by_target(parent, candidates, target_layer)

        attempted_cells: list[dict[str, Any]] = []
        no_inbound_cells = sorted(candidates - set(inbound_by_target.keys()), key=lambda item: (item[1], item[0]))
        unexpectedly_reached: set[tuple[int, int]] = set()
        confirmed_unreached: set[tuple[int, int]] = set()
        route_failures: list[dict[str, Any]] = []
        unexpected_state_changes: list[dict[str, Any]] = []

        for target_cell in sorted(inbound_by_target.keys(), key=lambda item: (item[1], item[0])):
            target_attempts: list[dict[str, Any]] = []
            reached = False
            for inbound in inbound_by_target[target_cell]:
                attempt = await self.attempt_inbound_edge(parent, target_layer, target_cell, inbound)
                target_attempts.append(attempt)
                if attempt["result"] == "unexpectedly_reached":
                    unexpectedly_reached.add(target_cell)
                    reached = True
                    break
                if attempt["result"] == "route_mismatch":
                    route_failures.append({"target": {"x": target_cell[0], "y": target_cell[1]}, "attempt": attempt})
                elif attempt["result"] == "unexpected_state_change":
                    unexpected_state_changes.append({"target": {"x": target_cell[0], "y": target_cell[1]}, "attempt": attempt})
            if not reached:
                confirmed_unreached.add(target_cell)
            attempted_cells.append(
                {
                    "target": {"x": target_cell[0], "y": target_cell[1]},
                    "attempt_count": len(target_attempts),
                    "attempts": target_attempts,
                    "result": "unexpectedly_reached" if reached else "confirmed_unreached",
                }
            )

        return {
            "reachable_cells": _sorted_cells(reachable_cells),
            "supported_unreachable_cells": _sorted_cells(candidates),
            "attempted_cells": attempted_cells,
            "no_reachable_inbound_edge_cells": _sorted_cells(set(no_inbound_cells)),
            "confirmed_unreached_cells": _sorted_cells(confirmed_unreached | set(no_inbound_cells)),
            "unexpectedly_reached_cells": _sorted_cells(unexpectedly_reached),
            "route_failures": route_failures,
            "unexpected_state_changes": unexpected_state_changes,
            "inferred_state_count": len(parent),
        }


async def main() -> int:
    args = _parse_args()
    target_layer = _normalize_layer_name(str(args.layer))
    artifact_path = _artifact_path_for_layer(target_layer)
    exit_code = 0
    async with stdio_client(_server_params()) as (read_stream, write_stream):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            probe = LayerUnreachableAttemptProbe(
                session,
                window_mode=str(args.window_mode),
                hold_ms=int(args.hold_ms),
                frames_after=int(args.frames_after),
            )
            try:
                await probe.start()
                audit = await probe.audit_supported_unreachable_cells(target_layer)
                artifact = {
                    "scene": RUNTIME_SCENE,
                    "target_layer": target_layer,
                    "window_mode": str(args.window_mode),
                    "hold_ms": int(args.hold_ms),
                    "frames_after": int(args.frames_after),
                    "proof_scope": (
                        "For each %s cell that is runtime-supported but absent from the reachable overlay, "
                        "all one-step inbound WASD moves from overlay-reachable states are attempted. "
                        "Cells with no reachable inbound edge cannot be first reached from origin under the current step contract."
                    )
                    % target_layer,
                    "origin": {
                        "layer": probe.origin[0] if probe.origin else "",
                        "cell": {"x": probe.origin[1][0], "y": probe.origin[1][1]} if probe.origin else {},
                    },
                    "bounds": {
                        "position": {"x": probe.bounds_position[0], "y": probe.bounds_position[1]},
                        "size": {"x": probe.bounds_size[0], "y": probe.bounds_size[1]},
                    },
                    "tap_count": probe.tap_count,
                    "reachable_target_count": len(audit["reachable_cells"]),
                    "supported_unreachable_target_count": len(audit["supported_unreachable_cells"]),
                    "attempted_target_count": len(audit["attempted_cells"]),
                    "no_reachable_inbound_edge_count": len(audit["no_reachable_inbound_edge_cells"]),
                    "confirmed_unreached_count": len(audit["confirmed_unreached_cells"]),
                    "unexpectedly_reached_count": len(audit["unexpectedly_reached_cells"]),
                    **audit,
                }
                artifact_path.parent.mkdir(parents=True, exist_ok=True)
                artifact_path.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
                print(json.dumps({
                    "artifact_path": str(artifact_path),
                    "scene": artifact["scene"],
                    "target_layer": artifact["target_layer"],
                    "tap_count": artifact["tap_count"],
                    "reachable_target_count": artifact["reachable_target_count"],
                    "supported_unreachable_target_count": artifact["supported_unreachable_target_count"],
                    "attempted_target_count": artifact["attempted_target_count"],
                    "no_reachable_inbound_edge_count": artifact["no_reachable_inbound_edge_count"],
                    "confirmed_unreached_count": artifact["confirmed_unreached_count"],
                    "unexpectedly_reached_count": artifact["unexpectedly_reached_count"],
                    "route_failure_count": len(artifact["route_failures"]),
                    "unexpected_state_change_count": len(artifact["unexpected_state_changes"]),
                }, indent=2))
                if (
                    artifact["unexpectedly_reached_count"] > 0
                    or artifact["route_failures"]
                    or artifact["unexpected_state_changes"]
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
