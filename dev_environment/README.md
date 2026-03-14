## Dev Environment (Iximiuz Labs)

This plugin is developed in a disposable [Iximiuz Labs Coding Agent Base](https://labs.iximiuz.com/playgrounds/coding-agent-base) playground. The setup is designed so each fresh session takes under a minute to get coding.

### Prerequisites (one-time, on your machine)

- [`labctl`](https://labs.iximiuz.com/docs/playgrounds/how-to-use-playgrounds#cli) installed and authenticated
- `claude-auth.sh` from this repo in a convenient location (e.g. `~/scripts/`)

### Session workflow

**1. Start the playground**

In the browser, go to the [Coding Agent Base playground](https://labs.iximiuz.com/playgrounds/coding-agent-base), enter this repo URL in the Repository field, and click Start. The repo will be cloned to `~/workspace` automatically.

Or via CLI:
```bash
labctl playground start coding-agent-base --open
```

**2. Open the IDE tab**

Click the IDE tab. Wait a few seconds for it to fully load, this initializes `code-server`.

**3. Run setup**

In the playground terminal:
```bash
bash ~/workspace/dev_environment/setup.sh
```

This will:
- Install the Claude Code for VS Code extension
- Run `npm install`

**4. Authenticate Claude**
Note: this assumes local machine is macOS and preferred browser Safari.

On your laptop:
```bash
./claude-auth.sh <playground-id>
```

Follow the prompts the script detects Claude's OAuth callback port, forwards it via `labctl`, and opens the auth URL in Safari automatically.

**5. Reload IDE**

Reload the IDE tab in the browser. The Claude Code extension will be active and authenticated.

---

### What's in `dev_environment/`

| File | Purpose | Where it runs |
|------|---------|---------------|
| `setup.sh` | Installs extensions, runs npm install | Inside sandbox |
| `claude-auth.sh` | Handles Claude OAuth flow | On your laptop |

### Future automation backlog

Items to add to `setup.sh` as needs grow:

| # | Item | Notes |
|---|------|-------|
| 1 | More VS Code extensions | Add IDs to `VSCODE_EXTENSIONS` array in `setup.sh` |
| 2 | `settings.json` / keybindings | Commit to `dev_environment/`, copy to `~/.local/share/code-server/User/` in `setup.sh` |
| 3 | Shell dotfiles / aliases | Add a dotfiles section to `setup.sh` |
| 4 | Custom playground image | Once `setup.sh` is stable, bake into a Dockerfile so setup is instant at boot |
