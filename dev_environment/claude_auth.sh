#!/usr/bin/env bash
# claude-auth.sh
# Run this on your LAPTOP to authenticate Claude (CLI + VS Code extension)
# in an Iximiuz Labs playground via OAuth/Claude.ai Pro subscription.
#
# Usage:
#   ./claude-auth.sh <playground-id>
#
# Example:
#   ./claude-auth.sh my-playground-abc123
#
# What it does:
#   1. Snapshots which ports are already open in the sandbox before you trigger auth
#   2. Polls every second until a new localhost port appears (that's Claude's callback server)
#   3. Forwards that port to your laptop into the sandbox via labctl port-forward so the browser redirect works
#   3. Prompts you to trigger auth inside the sandbox (CLI or VS Code)
#   4. Watches for the port to disappear (Claude's server closes after receiving the redirect)
#   5. Tears down the tunnel automatically

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[claude-auth]${RESET} $*"; }
success() { echo -e "${GREEN}[claude-auth]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[claude-auth]${RESET} $*"; }
error()   { echo -e "${RED}[claude-auth]${RESET} $*" >&2; }

# ── Args ─────────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  error "Usage: $0 <playground-id>"
  error "Find your playground ID with: labctl playground list"
  exit 1
fi

PLAYGROUND_ID="$1"

# ── Preflight checks ─────────────────────────────────────────────────────────
if ! command -v labctl &>/dev/null; then
  error "labctl not found. Install it with:"
  error "  curl -sf https://labs.iximiuz.com/cli/install.sh | sh"
  exit 1
fi

info "Checking playground ${BOLD}${PLAYGROUND_ID}${RESET} is reachable..."
if ! labctl ssh "$PLAYGROUND_ID" -- echo "ok" &>/dev/null; then
  error "Cannot reach playground '${PLAYGROUND_ID}'."
  error "Make sure it is running: labctl playground list"
  exit 1
fi
success "Playground is up."

# ── Port detection ────────────────────────────────────────────────────────────
# Claude CLI and the VS Code extension both bind a short-lived localhost server
# to receive the OAuth redirect. The port is chosen dynamically each time.
# We poll ss/netstat inside the sandbox until we see it appear.

CLAUDE_AUTH_PORT_PATTERN="127\.0\.0\.1:[0-9]\+"   # any localhost port
FORWARD_PID=""

cleanup() {
  if [[ -n "$FORWARD_PID" ]]; then
    info "Tearing down port-forward (pid ${FORWARD_PID})..."
    kill "$FORWARD_PID" 2>/dev/null || true
    wait "$FORWARD_PID" 2>/dev/null || true
  fi
  info "Done."
}
trap cleanup EXIT INT TERM

detect_claude_port() {
  # List LISTEN ports on localhost inside the sandbox, filter out well-known
  # ports that are always present (22 SSH, etc.), and look for something new
  # that appeared after we started watching.
  labctl ssh "$PLAYGROUND_ID" -- \
    ss -tlnH 'src 127.0.0.1' 2>/dev/null \
    | awk '{print $4}' \
    | grep -oP '(?<=:)\d+$' \
    | grep -v '^22$' \
    | sort -n
}

# Snapshot ports that are already open before auth starts
info "Snapshotting pre-existing sandbox ports..."
PORTS_BEFORE=$(detect_claude_port || true)

# ── Instructions ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD} Claude OAuth Auth Helper${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "Now go into your sandbox and trigger Claude auth. For example:"
echo ""
echo -e "  ${BOLD}Claude Code CLI:${RESET}"
echo -e "  ${CYAN}  claude${RESET}   (then choose 'Claude.ai Pro' / OAuth login)"
echo ""
echo -e "  ${BOLD}VS Code extension:${RESET}"
echo -e "  ${CYAN}  Open VS Code → Claude extension → Sign in with Claude.ai${RESET}"
echo ""
echo -e "This script will detect the callback port and forward it automatically."
echo -e "Once your browser completes the OAuth flow, the tunnel closes itself."
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# ── Wait for new port ─────────────────────────────────────────────────────────
info "Waiting for Claude to open its OAuth callback port in the sandbox..."

NEW_PORT=""
TIMEOUT=120   # seconds to wait for Claude to start its local server
ELAPSED=0
POLL_INTERVAL=1

while [[ -z "$NEW_PORT" && $ELAPSED -lt $TIMEOUT ]]; do
  PORTS_NOW=$(detect_claude_port || true)
  # Find ports that are in PORTS_NOW but not in PORTS_BEFORE
  NEW_PORT=$(comm -13 \
    <(echo "$PORTS_BEFORE" | sort) \
    <(echo "$PORTS_NOW"   | sort) \
    | head -1)
  if [[ -z "$NEW_PORT" ]]; then
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
  fi
done

if [[ -z "$NEW_PORT" ]]; then
  error "Timed out waiting for Claude's OAuth port to appear."
  error "Did you trigger the auth flow in the sandbox?"
  exit 1
fi

success "Detected OAuth callback port: ${BOLD}${NEW_PORT}${RESET}"

# ── Start port-forward ────────────────────────────────────────────────────────
info "Starting port-forward: localhost:${NEW_PORT} → sandbox:${NEW_PORT}"
labctl port-forward "$PLAYGROUND_ID" -L "${NEW_PORT}:${NEW_PORT}" &
FORWARD_PID=$!
sleep 1  # give labctl a moment to establish the tunnel

if ! kill -0 "$FORWARD_PID" 2>/dev/null; then
  error "Port-forward failed to start. Is port ${NEW_PORT} already in use locally?"
  exit 1
fi

success "Tunnel is live. Your browser redirect will now reach the sandbox."
echo ""
warn "Complete the OAuth flow in your browser now."
warn "This script will close the tunnel once auth is done (port disappears)."
echo ""

# ── Wait for auth to complete ─────────────────────────────────────────────────
# Claude's local callback server shuts down after receiving the redirect.
# We detect this by watching for the port to disappear from the sandbox.
AUTH_TIMEOUT=300  # 5 minutes to complete browser flow
ELAPSED=0

while [[ $ELAPSED -lt $AUTH_TIMEOUT ]]; do
  PORTS_NOW=$(detect_claude_port || true)
  STILL_OPEN=$(echo "$PORTS_NOW" | grep -x "$NEW_PORT" || true)
  if [[ -z "$STILL_OPEN" ]]; then
    success "OAuth callback received! Auth complete."
    break
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

if [[ $ELAPSED -ge $AUTH_TIMEOUT ]]; then
  warn "Timed out waiting for auth to complete."
  warn "If you finished in the browser, auth may still have worked — check inside the sandbox."
fi

# cleanup() runs on EXIT and kills the forward
