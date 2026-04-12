# Godot Runtime MCP Bridge

This package provides a repo-local MCP server for driving the runtime Godot project under `godot_project/`.

## Install

```bash
python3 -m venv tools/godot_mcp/.venv
tools/godot_mcp/.venv/bin/pip install -e tools/godot_mcp
```

If `venv` is unavailable on the machine, install into the user site instead:

```bash
python3 -m pip install --break-system-packages --user -e tools/godot_mcp
```

## Run

```bash
tools/godot_mcp/.venv/bin/godot-mcp
```

The server speaks MCP over stdio and launches Godot on demand.

Installed without a virtualenv:

```bash
python3 -m godot_mcp.server
```

## Register with MCP clients

Example stdio registration:

```json
{
  "mcpServers": {
    "godot-runtime": {
      "command": "/home/parallels/src/github.com/agentc1/pixel-monsters/tools/godot_mcp/.venv/bin/godot-mcp",
      "cwd": "/home/parallels/src/github.com/agentc1/pixel-monsters"
    }
  }
}
```

## Intended workflow

1. `godot_play_scene("res://tests/mcp/runtime_probe.tscn")`
2. `godot_capture_viewport("probe-before")`
3. `godot_scene_tree()`
4. `godot_node_info("/root/GodotMcpRuntime/SceneHost/RuntimeProbe/ProbeActor")`
5. `godot_press_keys(["D"], hold_ms=250, frames_after=2)`
6. `godot_capture_viewport("probe-after")`

The bridge is runtime-only in v1. It does not automate the Godot editor.

## Repo-local audit scripts

These scripts run the imported Basic demo scene through the MCP bridge and write JSON artifacts under `godot_project/tmp/`.

```bash
python3 tools/godot_mcp/navigation_inventory_report.py --window-mode headless
python3 tools/godot_mcp/navigation_override_acceptance.py --window-mode headless
python3 tools/godot_mcp/layer1_wasd_reachability.py --layer 1 --window-mode headless
python3 tools/godot_mcp/layer1_wasd_reachability.py --layer 2 --window-mode headless
python3 tools/godot_mcp/layer1_wasd_reachability.py --layer 3 --window-mode headless
```

`navigation_inventory_report.py` is the fast diagnostic pass. It reports total walkable/navigable/reachable cells per elevation layer and classifies each stair transition as reachable, source-unreachable, target-unreachable, or blocked.

`navigation_override_acceptance.py` validates the runtime navigation edit path by force-blocking a cell, proving real WASD movement respects it, saving the override resource, reloading the scene, and then clearing the temporary override.

## Runtime Navigation Edit Controls

The generated SC Demo runtime scene includes an overlay edit mode:

- `N`: toggle navigation edit mode.
- `WASD` / arrow keys: move the opaque layer-colored edit cursor north/west/south/east while edit mode is active.
- `Q/E`: cycle the active edit layer.
- `Insert`: force the cursor cell navigable.
- `Delete`: force the cursor cell blocked. Backspace is intentionally not mapped.
- `C`: clear the cursor cell override.
- `V`: save overrides.
- `G`: snap the cursor to the player cell.
- `1/2/3`: toggle layer visibility.

Overrides apply to the active edit layer only. To edit the same coordinate on multiple elevations, use `Q/E` to switch layers and repeat the action intentionally on each layer.

The same command list is also generated as a visible `CommandLegendHUD` panel at the bottom of the running scene and as a world-space `CommandLegend` panel below the imported SC Demo runtime map.
