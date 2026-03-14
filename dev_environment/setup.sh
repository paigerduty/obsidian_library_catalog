#!/usr/bin/env bash
# dev_environment/setup.sh
# Run once inside the Iximiuz Labs sandbox at the start of each fresh session.
#
# Usage (from repo root):
#   bash dev_environment/setup.sh
#
# What it does:
#   1. Installs VS Code extensions via code-server
#   2. Runs npm install in ~/workspace

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[setup]${RESET} $*"; }
success() { echo -e "${GREEN}[setup]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[setup]${RESET} $*"; }

# ── VS Code extensions ────────────────────────────────────────────────────────
# Add extension IDs here as your setup grows.
VSCODE_EXTENSIONS=(
  "anthropic.claude-code"
)

info "Installing VS Code extensions..."
for ext in "${VSCODE_EXTENSIONS[@]}"; do
  code-server --install-extension "$ext"
done
success "VS Code extensions ready. Reload the IDE tab if this was a fresh install."

# ── npm install ───────────────────────────────────────────────────────────────
WORKSPACE_DIR="${HOME}/workspace"

if [[ -f "${WORKSPACE_DIR}/package.json" ]]; then
  info "Running npm install in ${WORKSPACE_DIR}..."
  (cd "$WORKSPACE_DIR" && npm install)
  success "npm install complete."
else
  warn "No package.json found in ${WORKSPACE_DIR}, skipping npm install."
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
success "☻ Setup complete!"
echo -e "  Next: run ${BOLD}./claude-auth.sh <playground-id>${RESET} from your laptop to authenticate."
