#!/usr/bin/env bash
# setup.sh
# Run inside the Iximiuz sandbox at the start of each session.
# Installs VS Code extensions and preps the dev environment.

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[setup]${RESET} $*"; }
success() { echo -e "${GREEN}[setup]${RESET} $*"; }

# ── VS Code extensions ────────────────────────────────────────────────────────
# Add more extension IDs here as your setup grows.
VSCODE_EXTENSIONS=(
  "anthropic.claude-code"
)

info "Installing VS Code extensions..."
for ext in "${VSCODE_EXTENSIONS[@]}"; do
  if code --list-extensions | grep -qi "^${ext}$"; then
    info "  ${ext} already installed, skipping."
  else
    code --install-extension "$ext" --force
    success "  Installed: ${ext}"
  fi
done

success "VS Code extensions ready."

# ── Future sections go here (see backlog below) ───────────────────────────────
# e.g. git clone, npm install, dotfiles, etc.

echo ""
success "Setup complete. Now run claude-auth.sh from your laptop."
