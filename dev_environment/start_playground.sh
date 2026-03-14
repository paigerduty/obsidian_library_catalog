#!/usr/bin/env bash
# start-playground.sh
# Run this on your LAPTOP to resume your persistent Iximiuz coding-agent-base
# playground and open it in VS Code (Remote SSH).
#
# First-time setup:
#   1. Set PLAYGROUND_ID below (find it with: labctl playground list)
#   2. Run once: ./claude-auth.sh <playground-id>   ← do Claude auth first
#   3. Then use this script for daily startup
#
# Usage:
#   ./start-playground.sh [playground-id]
#
# If playground-id is omitted, PLAYGROUND_ID below is used.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
# Set your persistent playground ID here so you don't have to pass it each time.
# Find it with: labctl playground list
DEFAULT_PLAYGROUND_ID="${IXIMIUZ_PLAYGROUND_ID:-}"   # or hardcode: "my-playground-abc123"

# The playground type (used when starting a fresh one — not needed for persistent)
PLAYGROUND_TYPE="coding-agent-base"

# ── Colours ───────────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[playground]${RESET} $*"; }
success() { echo -e "${GREEN}[playground]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[playground]${RESET} $*"; }
error()   { echo -e "${RED}[playground]${RESET} $*" >&2; }

# ── Resolve playground ID ─────────────────────────────────────────────────────
PLAYGROUND_ID="${1:-$DEFAULT_PLAYGROUND_ID}"

if [[ -z "$PLAYGROUND_ID" ]]; then
  error "No playground ID set."
  error "Either:"
  error "  1. Edit DEFAULT_PLAYGROUND_ID in this script, or"
  error "  2. Set env var: export IXIMIUZ_PLAYGROUND_ID=<id>, or"
  error "  3. Pass it as an argument: $0 <playground-id>"
  echo ""
  error "Your playgrounds:"
  labctl playground list
  exit 1
fi

# ── Preflight ─────────────────────────────────────────────────────────────────
if ! command -v labctl &>/dev/null; then
  error "labctl not found. Install: curl -sf https://labs.iximiuz.com/cli/install.sh | sh"
  exit 1
fi

if ! command -v code &>/dev/null; then
  warn "VS Code CLI ('code') not found in PATH."
  warn "Install it: VS Code → Command Palette → 'Shell Command: Install code in PATH'"
  warn "Skipping VS Code launch."
  OPEN_VSCODE=false
else
  OPEN_VSCODE=true
fi

# ── Check / restart playground ────────────────────────────────────────────────
info "Checking playground ${BOLD}${PLAYGROUND_ID}${RESET}..."

PLAY_STATUS=$(labctl playground list --format json 2>/dev/null \
  | python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data:
    if p.get('id') == '${PLAYGROUND_ID}' or p.get('name') == '${PLAYGROUND_ID}':
        print(p.get('status', 'unknown'))
        sys.exit(0)
print('not-found')
" 2>/dev/null || echo "unknown")

case "$PLAY_STATUS" in
  running)
    success "Playground is already running."
    ;;
  stopped)
    info "Playground is stopped. Restarting..."
    labctl playground restart "$PLAYGROUND_ID"
    info "Waiting for playground to come up..."
    sleep 10
    ;;
  not-found|unknown)
    warn "Could not determine playground status (status: ${PLAY_STATUS})."
    warn "Attempting to connect anyway..."
    ;;
esac

# ── Wait until SSH is responsive ──────────────────────────────────────────────
info "Waiting for SSH to be ready..."
TIMEOUT=90
ELAPSED=0
until labctl ssh "$PLAYGROUND_ID" -- echo "ready" &>/dev/null; do
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    error "Timed out waiting for playground SSH. Try: labctl playground list"
    exit 1
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done
success "Playground SSH is ready."

# ── Check if Claude is already authenticated ──────────────────────────────────
info "Checking Claude auth status in sandbox..."
CLAUDE_AUTHED=$(labctl ssh "$PLAYGROUND_ID" -- \
  bash -c 'claude --version &>/dev/null && claude config get | grep -q "oauth\|token\|logged" && echo yes || echo no' \
  2>/dev/null || echo "unknown")

if [[ "$CLAUDE_AUTHED" == "no" || "$CLAUDE_AUTHED" == "unknown" ]]; then
  echo ""
  warn "Claude does not appear to be authenticated in the sandbox."
  warn "Run this to authenticate (in a separate terminal):"
  warn ""
  warn "  ${BOLD}./claude-auth.sh ${PLAYGROUND_ID}${RESET}"
  warn ""
  warn "Continuing with VS Code launch anyway..."
  echo ""
fi

# ── Start SSH proxy for VS Code ───────────────────────────────────────────────
info "Starting labctl SSH proxy for VS Code..."

# Pick a random local port for the SSH proxy to avoid collisions
SSH_PROXY_PORT=$(python3 -c "
import socket
s = socket.socket()
s.bind(('', 0))
print(s.getsockname()[1])
s.close()
")

# Write a temporary SSH config snippet
TMPDIR_SCRIPT=$(mktemp -d)
SSH_CONFIG="${TMPDIR_SCRIPT}/ssh_config"
SSH_KEY="${HOME}/.ssh/iximiuz_labs_user"

cat > "$SSH_CONFIG" <<EOF
Host iximiuz-playground
  HostName 127.0.0.1
  Port ${SSH_PROXY_PORT}
  User laborant
  IdentityFile ${SSH_KEY}
  AddKeysToAgent yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF

cleanup() {
  info "Stopping SSH proxy..."
  kill "$PROXY_PID" 2>/dev/null || true
  wait "$PROXY_PID" 2>/dev/null || true
  rm -rf "$TMPDIR_SCRIPT"
}
trap cleanup EXIT INT TERM

# Start the proxy in the background
labctl ssh-proxy "$PLAYGROUND_ID" --port "$SSH_PROXY_PORT" &>/tmp/labctl-proxy.log &
PROXY_PID=$!
sleep 3

if ! kill -0 "$PROXY_PID" 2>/dev/null; then
  error "SSH proxy failed to start. Check /tmp/labctl-proxy.log"
  exit 1
fi

success "SSH proxy running on port ${SSH_PROXY_PORT} (pid ${PROXY_PID})"

# ── Open VS Code ──────────────────────────────────────────────────────────────
if [[ "$OPEN_VSCODE" == "true" ]]; then
  REMOTE_URI="vscode-remote://ssh-remote+laborant@127.0.0.1:${SSH_PROXY_PORT}/home/laborant/workspace"
  info "Opening VS Code at: ${REMOTE_URI}"
  code --folder-uri "$REMOTE_URI"
  success "VS Code launched. The SSH proxy will stay up until you Ctrl+C this script."
else
  info "SSH proxy is running. Connect manually with:"
  echo ""
  echo "  ssh -F ${SSH_CONFIG} iximiuz-playground"
  echo ""
  echo "  # or open VS Code:"
  echo "  code --folder-uri vscode-remote://ssh-remote+laborant@127.0.0.1:${SSH_PROXY_PORT}/home/laborant/workspace"
  echo ""
fi

echo ""
info "Press ${BOLD}Ctrl+C${RESET} to stop the SSH proxy and exit."
echo ""

# Keep the proxy alive until user exits
wait "$PROXY_PID"
