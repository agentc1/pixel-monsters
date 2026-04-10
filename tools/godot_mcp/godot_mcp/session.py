from __future__ import annotations

import asyncio
import contextlib
import json
import os
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_BRIDGE_HOST = "127.0.0.1"
DEFAULT_RESPONSE_TIMEOUT = 15.0


class GodotBridgeError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass
class GodotLogEntry:
    seq: int
    source: str
    line: str
    timestamp: float


class GodotBridgeSession:
    def __init__(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[3]
        self.godot_project = self.repo_root / "godot_project"
        self.godot_bin = os.environ.get("GODOT_BIN", "godot")
        self.runtime_scene = "res://tools/godot_mcp/runtime_bridge.tscn"

        self._server: asyncio.AbstractServer | None = None
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._process: asyncio.subprocess.Process | None = None
        self._stdout_task: asyncio.Task[None] | None = None
        self._stderr_task: asyncio.Task[None] | None = None
        self._bridge_read_task: asyncio.Task[None] | None = None
        self._pending: dict[int, asyncio.Future[dict[str, Any]]] = {}
        self._request_id = 0
        self._logs: list[GodotLogEntry] = []
        self._log_seq = 0
        self._connected_future: asyncio.Future[None] | None = None
        self._ready_future: asyncio.Future[dict[str, Any]] | None = None
        self._ready_payload: dict[str, Any] = {}
        self._lock = asyncio.Lock()

    async def ensure_running(self, *, window_mode: str = "windowed", reuse_existing: bool = True) -> None:
        async with self._lock:
            if reuse_existing and await self._is_session_ready():
                return
            await self._restart(window_mode=window_mode)

    async def stop(self) -> None:
        async with self._lock:
            await self._stop_locked()

    async def status(self) -> dict[str, Any]:
        if not await self._is_session_ready():
            return {
                "ok": True,
                "running": False,
                "connected": False,
                "godot_pid": None,
                "loaded_scene_path": "",
                "loaded_scene_root_path": "",
                "current_camera_path": "",
                "viewport_size": {},
                "frame": 0,
            }
        payload = await self.call("get_status", {})
        payload["running"] = True
        payload["connected"] = True
        payload["godot_pid"] = self._process.pid if self._process else None
        return payload

    async def call(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        if not await self._is_session_ready():
            raise GodotBridgeError("session_not_running", "Godot runtime bridge is not running.")
        assert self._writer is not None
        self._request_id += 1
        request_id = self._request_id
        future: asyncio.Future[dict[str, Any]] = asyncio.get_running_loop().create_future()
        self._pending[request_id] = future
        payload = {"id": request_id, "method": method, "params": params}
        message = (json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8")
        self._writer.write(message)
        await self._writer.drain()
        try:
            response = await asyncio.wait_for(future, timeout=DEFAULT_RESPONSE_TIMEOUT)
        except TimeoutError as exc:
            self._pending.pop(request_id, None)
            raise GodotBridgeError("timeout", f"Timed out waiting for Godot response to {method}.") from exc
        if not response.get("ok", False):
            error = response.get("error", {})
            raise GodotBridgeError(str(error.get("code", "bridge_error")), str(error.get("message", "Unknown Godot bridge error.")))
        return dict(response.get("result", {}))

    async def play_scene(self, scene_path: str, *, reuse_existing: bool = True, window_mode: str = "windowed") -> dict[str, Any]:
        normalized_scene = self.normalize_scene_path(scene_path)
        await self.ensure_running(window_mode=window_mode, reuse_existing=reuse_existing)
        return await self.call("load_scene", {"scene_path": normalized_scene, "wait_frames": 3})

    async def capture_viewport(self, label: str = "capture") -> dict[str, Any]:
        safe_label = re.sub(r"[^A-Za-z0-9._-]+", "_", label).strip("_") or "capture"
        return await self.call("capture_viewport", {"label": safe_label})

    async def scene_tree(self, root_path: str, *, max_depth: int = 3, include_internal: bool = False) -> dict[str, Any]:
        return await self.call("scene_tree", {"root_path": root_path, "max_depth": max_depth, "include_internal": include_internal})

    async def node_info(self, node_path: str) -> dict[str, Any]:
        return await self.call("node_info", {"node_path": node_path})

    async def press_keys(self, keys: list[str], *, hold_ms: int = 120, frames_after: int = 2) -> dict[str, Any]:
        return await self.call("press_keys", {"keys": keys, "hold_ms": hold_ms, "frames_after": frames_after})

    async def advance_frames(self, frames: int = 1) -> dict[str, Any]:
        return await self.call("advance_frames", {"frames": max(1, frames)})

    def logs(self, *, since_seq: int = 0, limit: int = 200) -> dict[str, Any]:
        entries = [
            {
                "seq": entry.seq,
                "source": entry.source,
                "line": entry.line,
                "timestamp": entry.timestamp,
            }
            for entry in self._logs
            if entry.seq > since_seq
        ]
        return {
            "ok": True,
            "running": self._process is not None and self._process.returncode is None,
            "entries": entries[: max(1, limit)],
            "next_since_seq": entries[-1]["seq"] if entries else since_seq,
        }

    def normalize_scene_path(self, scene_path: str) -> str:
        scene = scene_path.strip()
        if not scene:
            raise GodotBridgeError("invalid_scene_path", "Scene path is required.")
        if scene.startswith("res://"):
            return scene
        candidate = Path(scene).expanduser()
        if candidate.is_absolute():
            try:
                relative = candidate.resolve().relative_to(self.godot_project.resolve())
            except ValueError as exc:
                raise GodotBridgeError("invalid_scene_path", f"Scene path must be under {self.godot_project}.") from exc
            return "res://" + relative.as_posix()
        return "res://" + scene.lstrip("/")

    async def _is_session_ready(self) -> bool:
        if self._process is None or self._process.returncode is not None:
            return False
        if self._writer is None or self._writer.is_closing():
            return False
        if self._bridge_read_task is None or self._bridge_read_task.done():
            return False
        return bool(self._ready_payload)

    async def _restart(self, *, window_mode: str) -> None:
        await self._stop_locked()
        self._connected_future = asyncio.get_running_loop().create_future()
        self._ready_future = asyncio.get_running_loop().create_future()
        self._ready_payload = {}
        self._server = await asyncio.start_server(self._on_bridge_client, host=DEFAULT_BRIDGE_HOST, port=0)
        assert self._server.sockets
        port = int(self._server.sockets[0].getsockname()[1])
        args = [self.godot_bin]
        if window_mode == "headless":
            args.append("--headless")
        args.extend(
            [
                "--path",
                str(self.godot_project),
                "--scene",
                self.runtime_scene,
                "--",
                "--bridge-host",
                DEFAULT_BRIDGE_HOST,
                "--bridge-port",
                str(port),
            ]
        )
        self._process = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=str(self.repo_root),
        )
        self._stdout_task = asyncio.create_task(self._consume_stream(self._process.stdout, "stdout"))
        self._stderr_task = asyncio.create_task(self._consume_stream(self._process.stderr, "stderr"))
        try:
            await asyncio.wait_for(self._connected_future, timeout=10.0)
            await asyncio.wait_for(self._ready_future, timeout=10.0)
        except Exception as exc:
            await self._stop_locked()
            raise GodotBridgeError("startup_failed", f"Godot runtime bridge failed to start: {exc}") from exc

    async def _stop_locked(self) -> None:
        for future in self._pending.values():
            if not future.done():
                future.set_exception(GodotBridgeError("session_stopped", "Godot runtime bridge stopped."))
        self._pending.clear()
        if self._writer is not None:
            with contextlib.suppress(Exception):
                self._writer.close()
                await self._writer.wait_closed()
        self._writer = None
        self._reader = None
        if self._bridge_read_task is not None:
            self._bridge_read_task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await self._bridge_read_task
        self._bridge_read_task = None
        for task in (self._stdout_task, self._stderr_task):
            if task is not None:
                task.cancel()
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await task
        self._stdout_task = None
        self._stderr_task = None
        if self._process is not None and self._process.returncode is None:
            self._process.terminate()
            try:
                await asyncio.wait_for(self._process.wait(), timeout=5.0)
            except TimeoutError:
                self._process.kill()
                await self._process.wait()
        self._process = None
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
        self._server = None
        self._connected_future = None
        self._ready_future = None
        self._ready_payload = {}

    async def _on_bridge_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        if self._reader is not None or self._writer is not None:
            writer.close()
            await writer.wait_closed()
            return
        self._reader = reader
        self._writer = writer
        if self._connected_future is not None and not self._connected_future.done():
            self._connected_future.set_result(None)
        self._bridge_read_task = asyncio.create_task(self._read_bridge_messages())

    async def _read_bridge_messages(self) -> None:
        assert self._reader is not None
        try:
            while True:
                raw_line = await self._reader.readline()
                if not raw_line:
                    break
                try:
                    message = json.loads(raw_line.decode("utf-8"))
                except json.JSONDecodeError:
                    self._append_log("bridge", f"Invalid JSON from Godot bridge: {raw_line!r}")
                    continue
                if "event" in message:
                    if message.get("event") == "ready":
                        self._ready_payload = dict(message.get("payload", {}))
                        if self._ready_future is not None and not self._ready_future.done():
                            self._ready_future.set_result(self._ready_payload)
                    continue
                request_id = int(message.get("id", 0))
                future = self._pending.pop(request_id, None)
                if future is not None and not future.done():
                    future.set_result(message)
        finally:
            self._reader = None
            if self._writer is not None:
                with contextlib.suppress(Exception):
                    self._writer.close()
                    await self._writer.wait_closed()
            self._writer = None
            if self._ready_future is not None and not self._ready_future.done():
                self._ready_future.set_exception(GodotBridgeError("bridge_disconnected", "Godot bridge disconnected before becoming ready."))

    async def _consume_stream(self, stream: asyncio.StreamReader | None, source: str) -> None:
        if stream is None:
            return
        while True:
            line = await stream.readline()
            if not line:
                break
            text = line.decode("utf-8", errors="replace").rstrip()
            self._append_log(source, text)

    def _append_log(self, source: str, line: str) -> None:
        self._log_seq += 1
        self._logs.append(GodotLogEntry(seq=self._log_seq, source=source, line=line, timestamp=time.time()))
        if len(self._logs) > 1000:
            self._logs = self._logs[-1000:]
