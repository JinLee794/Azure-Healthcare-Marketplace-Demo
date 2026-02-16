#!/bin/bash
# ============================================================================
# mcp-local-start-and-proxy.sh
# Ensures a local MCP server is running, then bridges stdio ↔ HTTP.
#
# Used by .vscode/mcp.json so VS Code can auto-start servers on
# connect / restart.
#
# Usage:
#   ./scripts/mcp-local-start-and-proxy.sh <make-target-suffix> <port>
#   ./scripts/mcp-local-start-and-proxy.sh reference-data 7071
#   ./scripts/mcp-local-start-and-proxy.sh clinical-research 7072
#   ./scripts/mcp-local-start-and-proxy.sh cosmos-rag 7073
#   ./scripts/mcp-local-start-and-proxy.sh document-reader 7078
# ============================================================================
set -e

TARGET="${1:?Usage: $0 <make-target-suffix> <port>}"
PORT="${2:?Usage: $0 <make-target-suffix> <port>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Only start the server if the port is not already listening.
# This avoids killing/restarting a server that's already healthy.
if ! lsof -ti tcp:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT not listening — running make local-start-$TARGET ..." >&2
  make "local-start-$TARGET" >&2

  # Belt-and-suspenders wait (make target already waits, but just in case)
  for _ in $(seq 1 10); do
    lsof -ti tcp:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 && break
    sleep 1
  done
fi

if ! lsof -ti tcp:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "ERROR: Server failed to start on port $PORT" >&2
  exit 1
fi

echo "Server ready on port $PORT — starting stdio proxy" >&2

# Bridge stdio ↔ HTTP
exec node "$SCRIPT_DIR/mcp-local-proxy.js" "http://localhost:$PORT/mcp"
