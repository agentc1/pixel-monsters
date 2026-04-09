#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GODOT_PROJECT="${REPO_ROOT}/godot_project"
GODOT_BIN="${GODOT_BIN:-godot}"
SOURCE_PATH="${1:-${BASIC_SOURCE:-}}"
OUTPUT_ROOT="${OUTPUT_ROOT:-res://cainos_imports/basic_real_acceptance}"

if [[ -z "${SOURCE_PATH}" ]]; then
	echo "Usage: $0 /absolute/path/to/basic.unitypackage" >&2
	echo "Or set BASIC_SOURCE to a licensed Basic .unitypackage or extracted metadata folder." >&2
	exit 1
fi

SOURCE_PATH="$(
	python3 - "${SOURCE_PATH}" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve())
PY
)"

if [[ ! -e "${SOURCE_PATH}" ]]; then
	echo "Source path does not exist: ${SOURCE_PATH}" >&2
	exit 1
fi

if ! SCAN_OUTPUT="$("${GODOT_BIN}" --headless --path "${GODOT_PROJECT}" --script res://tools/headless_basic_import.gd -- --mode scan --source "${SOURCE_PATH}" --output-root "${OUTPUT_ROOT}")"; then
	echo "${SCAN_OUTPUT}"
	exit 1
fi
echo "${SCAN_OUTPUT}"

python3 - <<'PY' "${SCAN_OUTPUT}"
import json
import sys

raw = sys.argv[1]
start = raw.find("{")
if start < 0:
    raise SystemExit("Scan output did not contain JSON.")
payload = json.loads(raw[start:])
if not payload.get("ok", False):
    raise SystemExit("Scan failed.")
if not payload.get("summary", {}).get("semantic_available", False):
    raise SystemExit("Semantic mode was not active for the provided source.")
PY

"${GODOT_BIN}" --headless --path "${GODOT_PROJECT}" --script res://tools/headless_basic_import.gd -- --mode import --source "${SOURCE_PATH}" --output-root "${OUTPUT_ROOT}"
"${GODOT_BIN}" --headless --import --path "${GODOT_PROJECT}"
"${GODOT_BIN}" --headless --path "${GODOT_PROJECT}" --script res://tests/validate_real_basic_outputs.gd -- --output-root "${OUTPUT_ROOT}"

echo "Basic importer real-pack acceptance passed."
