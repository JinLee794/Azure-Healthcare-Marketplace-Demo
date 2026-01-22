#!/bin/bash
# postdeploy hook for azd - Sets up MCP servers in APIM after deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "  Post-Deploy: Setting up MCP Servers in APIM"
echo "=============================================="

# Check if Python script dependencies are installed
if ! python3 -c "import azure.identity" 2>/dev/null; then
    echo "Installing Python dependencies..."
    pip install -q -r "$SCRIPT_DIR/requirements.txt"
fi

# Run the setup script
python3 "$SCRIPT_DIR/setup_mcp_servers.py"

echo ""
echo "✅ Post-deploy MCP setup complete!"
