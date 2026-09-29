#!/usr/bin/env bash
# scripts/setup-checkers.sh -- install the Python checkers that NuttX's
# tools/checkpatch.sh runs on Python files (black, flake8, isort) into
# build/pyvenv, at fixed versions.  scripts/env.sh puts them on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m venv build/pyvenv
build/pyvenv/bin/pip install -q black==26.5.1 flake8==7.4.1 isort==9.0.2 
