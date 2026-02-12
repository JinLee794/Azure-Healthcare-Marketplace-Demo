#!/bin/bash
# Quick start script for local MCP server testing
set -e

SERVER=${1:-npi-lookup}
PORT=${2:-7071}

pick_supported_python() {
    local candidates=("python3.12" "python3.11" "python3.10" "python3.9" "/usr/bin/python3")
    local py
    local minor
    local max_minor

    max_minor=$(detect_func_max_python_minor)

    for py in "${candidates[@]}"; do
        if ! command -v "$py" >/dev/null 2>&1; then
            continue
        fi
        minor=$("$py" -c 'import sys; print(sys.version_info.minor)' 2>/dev/null || echo "")
        if [ -n "$minor" ] && [ "$minor" -ge 9 ] && [ "$minor" -le "$max_minor" ]; then
            echo "$py"
            return 0
        fi
    done

    echo ""
    return 1
}

detect_func_max_python_minor() {
    local default_max=11
    local func_path
    local func_real
    local worker_root
    local dir
    local base
    local minor
    local max_minor

    max_minor=$default_max
    func_path=$(command -v func 2>/dev/null || true)
    if [ -z "$func_path" ]; then
        echo "$max_minor"
        return 0
    fi

    func_real=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$func_path" 2>/dev/null || echo "$func_path")
    worker_root="$(cd "$(dirname "$func_real")/.." && pwd)/workers/python"

    if [ -d "$worker_root" ]; then
        for dir in "$worker_root"/3.*; do
            [ -d "$dir" ] || continue
            base=$(basename "$dir")
            minor=${base#3.}
            if [[ "$minor" =~ ^[0-9]+$ ]] && [ "$minor" -gt "$max_minor" ]; then
                max_minor=$minor
            fi
        done
    fi

    echo "$max_minor"
    return 0
}

venv_is_valid() {
    [ -x ".venv/bin/python" ] && [ -f ".venv/bin/activate" ] && [ -x ".venv/bin/pip" ]
}

# Map server name to port if not specified
if [ -z "$2" ]; then
    case "$SERVER" in
        npi-lookup) PORT=7071 ;;
        icd10-validation) PORT=7072 ;;
        cms-coverage) PORT=7073 ;;
        fhir-operations) PORT=7074 ;;
        pubmed) PORT=7075 ;;
        clinical-trials) PORT=7076 ;;
        *) PORT=7071 ;;
    esac
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SERVER_DIR="$PROJECT_ROOT/src/mcp-servers/$SERVER"

if [ ! -d "$SERVER_DIR" ]; then
    echo "Error: Server '$SERVER' not found at $SERVER_DIR"
    echo ""
    echo "Available servers:"
    ls -1 "$PROJECT_ROOT/src/mcp-servers"
    exit 1
fi

echo "============================================"
echo "Healthcare MCP Server - Local Testing"
echo "============================================"
echo ""
echo "Server:     $SERVER"
echo "Port:       $PORT"
echo ""

cd "$SERVER_DIR"

PYTHON_CMD=$(pick_supported_python || true)
if [ -z "$PYTHON_CMD" ]; then
    FUNC_MAX_MINOR=$(detect_func_max_python_minor)
    echo "Error: No supported Python interpreter found (need Python 3.9-3.$FUNC_MAX_MINOR for this Azure Functions Core Tools install)."
    exit 1
fi
FUNC_MAX_MINOR=$(detect_func_max_python_minor)

# Create/repair venv if needed (for IDE support and direct Python execution)
RECREATE_VENV=0
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment in $SERVER_DIR/.venv ..."
    RECREATE_VENV=1
elif ! venv_is_valid; then
    echo "Detected incomplete/corrupted venv in $SERVER_DIR/.venv."
    echo "Recreating venv with $PYTHON_CMD ..."
    RECREATE_VENV=1
else
    VENV_MINOR=$(.venv/bin/python -c 'import sys; print(sys.version_info.minor)' 2>/dev/null || echo "")
    if [ -n "$VENV_MINOR" ] && { [ "$VENV_MINOR" -lt 9 ] || [ "$VENV_MINOR" -gt "$FUNC_MAX_MINOR" ]; }; then
        echo "Detected unsupported venv Python 3.$VENV_MINOR in $SERVER_DIR/.venv (this Azure Functions Core Tools install supports up to 3.$FUNC_MAX_MINOR)."
        echo "Recreating venv with $PYTHON_CMD ..."
        RECREATE_VENV=1
    fi
fi

if [ "$RECREATE_VENV" -eq 1 ]; then
    rm -rf .venv
    "$PYTHON_CMD" -m venv .venv
    if ! venv_is_valid; then
        echo "Error: virtual environment creation failed or produced incomplete venv at $SERVER_DIR/.venv"
        exit 1
    fi
fi

echo "Activating virtual environment: $SERVER_DIR/.venv"
source .venv/bin/activate

# Verify we're using the correct venv
PYTHON_PATH=$(which python)
echo "Python: $PYTHON_PATH"

# Ensure Azure Functions uses the venv Python (and its site-packages)
export languageWorkers__python__defaultExecutablePath="$SERVER_DIR/.venv/bin/python"
echo "Azure Functions Python: $languageWorkers__python__defaultExecutablePath"

# Ensure the worker can import deps even if it uses a different python executable
VENV_SITE_PACKAGES=$(python -c 'import site; print(next(p for p in site.getsitepackages() if p.endswith("site-packages")))')
export PYTHONPATH="$VENV_SITE_PACKAGES:$SERVER_DIR/.python_packages/lib/site-packages:${PYTHONPATH:-}"
echo "PYTHONPATH: $PYTHONPATH"

# Install/upgrade dependencies only when requirements change (or first run)
REQ_HASH=$(shasum requirements.txt | awk '{print $1}')
REQ_HASH_FILE=".venv/.requirements.sha"

if [ ! -f "$REQ_HASH_FILE" ] || [ "$(cat "$REQ_HASH_FILE" 2>/dev/null || true)" != "$REQ_HASH" ]; then
    echo "Installing dependencies from requirements.txt..."
    pip install --upgrade pip -q

    # Install to venv (for IDE support)
    pip install -r requirements.txt -q

    # IMPORTANT: Azure Functions worker uses its own Python process
    # We must install packages to .python_packages for func to find them
    echo "Installing packages for Azure Functions worker..."
    pip install -r requirements.txt --target=".python_packages/lib/site-packages" --upgrade -q

    echo "$REQ_HASH" > "$REQ_HASH_FILE"
else
    echo "Dependencies already up to date (requirements hash match). Skipping pip install."
fi

# Verify httpx is installed in both locations
echo ""
echo "Verifying httpx installation..."
python -c "import httpx; print(f'httpx version (venv): {httpx.__version__}')" || {
    echo "ERROR: httpx not found in venv"
}

# Check .python_packages
if [ -d ".python_packages/lib/site-packages/httpx" ]; then
    echo "httpx found in .python_packages ✓"
else
    echo "WARNING: httpx not found in .python_packages"
fi

echo ""
echo "============================================"
echo "Endpoints:"
echo "============================================"
echo "Discovery:  http://localhost:$PORT/.well-known/mcp"
echo "Messages:   http://localhost:$PORT/mcp"
echo "Health:     http://localhost:$PORT/health"
echo ""
echo "Test commands:"
echo "  curl http://localhost:$PORT/.well-known/mcp | jq"
echo "  curl http://localhost:$PORT/health | jq"
echo ""
echo "Starting Azure Functions host..."
echo "============================================"
echo ""

func start -p $PORT
