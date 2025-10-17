#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

export PYTHONPATH="${PYTHONPATH:-}:${ROOT_DIR}"

ENV_FILE="${ROOT_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "${ENV_FILE}"
    set +a
fi

REQUIREMENTS_FILE="${ROOT_DIR}/requirements.txt"

if command -v uv >/dev/null 2>&1; then
    if uv run --with-requirements "${REQUIREMENTS_FILE}" python "${ROOT_DIR}/app.py"; then
        exit 0
    fi
    echo "uv run failed; falling back to system Python" >&2
fi

python -m pip install --upgrade pip
python -m pip install -r "${REQUIREMENTS_FILE}"
python "${ROOT_DIR}/app.py"