#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GODOT_PROJECT="${REPO_ROOT}/godot_project"
GODOT_BIN="${GODOT_BIN:-godot}"
DEFAULT_FIXTURE_ROOT="$(
	python3 - <<'PY'
import tempfile
from pathlib import Path
print(Path(tempfile.gettempdir()) / "cainos_basic_fixture")
PY
)"
FIXTURE_ROOT="${FIXTURE_ROOT:-${DEFAULT_FIXTURE_ROOT}}"
OUTPUT_ROOT="${OUTPUT_ROOT:-res://cainos_imports/basic_regression}"

python3 "${GODOT_PROJECT}/tests/generate_synthetic_basic_fixture.py" --output-root "${FIXTURE_ROOT}"

"${GODOT_BIN}" --headless --path "${GODOT_PROJECT}" --script res://tests/run_basic_regressions.gd -- \
	--fixture-root "${FIXTURE_ROOT}" \
	--output-root "${OUTPUT_ROOT}"

"${GODOT_BIN}" --headless --import --path "${GODOT_PROJECT}"

"${GODOT_BIN}" --headless --path "${GODOT_PROJECT}" --script res://tests/validate_generated_outputs.gd -- \
	--fixture-root "${FIXTURE_ROOT}" \
	--output-root "${OUTPUT_ROOT}"

echo "Basic importer synthetic regression suite passed."
