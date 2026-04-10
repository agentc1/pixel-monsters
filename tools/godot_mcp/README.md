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
