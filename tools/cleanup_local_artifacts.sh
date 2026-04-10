#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

rm -rf \
	"${REPO_ROOT}/godot_project/.godot" \
	"${REPO_ROOT}/godot_project/cainos_imports"

echo "Removed local Godot cache and generated import outputs."
