# Claude Auth on Iximiuz Labs Playground

These instructions cover authenticating Claude Code CLI and the VS Code Claude
extension with a **Claude.ai Pro subscription** inside an Iximiuz Labs
`coding-agent-base` playground, using the in-browser VS Code.

## New Session Workflow
```
1. labctl playground start <name>          # or open in browser
2. In sandbox terminal: ./setup.sh         # installs Claude Code ext + anything else
3. On laptop: ./claude-auth.sh <id>        # handles OAuth
4. Code                                    # you're ready
---

## First Time Setup (do this once on your laptop)

### 1. Install `labctl`

```bash
curl -sf https://labs.iximiuz.com/cli/install.sh | sh
```

Restart your terminal, then verify:

```bash
labctl version
```

### 2. Authenticate `labctl` with your Iximiuz account

```bash
labctl auth login
```

This opens a browser page. Complete the login flow. You only need to do this once.

### 3. Make `claude-auth.sh` executable

Run this from the root of the repo `./obsidian_library_catalog`

```bash
chmod +x ./dev_environment/claude_auth.sh
```

> `claude-auth.sh` handles OAuth port-forwarding
> automatically — you never need to know which port Claude picks.

---

## Starting a Persistent Playground

Use this when you have an existing playground you want to resume.

### 1. Find your playground ID

```bash
labctl playground list
```

Note the ID of your `coding-agent-base` playground (looks like `coding-agent-base-abc123`).

### 2. Resume the playground

```bash
labctl playground restart <playground-id>
```

> If it's already running, this is a no-op — safe to run either way.

### 3. Open it in the browser

Go to [labs.iximiuz.com/playgrounds](https://labs.iximiuz.com/playgrounds), find your
playground, and click **Open**. Use the in-browser VS Code tab for editing.

### 4. Authenticate Claude (if not already authenticated)

In a terminal **on your laptop**, run:

```bash
./dev_environment/claude-auth.sh <playground-id>
```

Then, **inside the sandbox** (browser terminal or VS Code terminal), trigger auth:

- **Claude Code CLI:** run `claude` and choose the Claude.ai / OAuth login option
- **VS Code extension:** open the Claude extension panel and click Sign In

Your laptop browser will open the OAuth page. Complete it. The tunnel closes itself when done.

### 5. Verify auth inside the sandbox

```bash
claude --version
claude -p "say hello"
```

---

## Starting a Fresh Playground

Use this when you want a clean environment each session.

### 1. Start a new playground

```bash
labctl playground start coding-agent-base --ssh
```

The `--ssh` flag drops you into an SSH session immediately once it's booted.
Note the playground ID printed in the output.

Alternatively, start it from the browser at:
[labs.iximiuz.com/playgrounds/coding-agent-base](https://labs.iximiuz.com/playgrounds/coding-agent-base)

### 2. Clone your plugin repo into the workspace

Inside the sandbox terminal:

```bash
cd ~/workspace
git clone https://github.com/<your-username>/obsidian_library_catalog.git
cd obsidian_library_catalog
npm install
```

### 3. Authenticate Claude

On your laptop:

```bash
./dev_environment/claude-auth.sh <new-playground-id>
```

Then trigger the auth flow inside the sandbox (same as persistent steps above).

### 4. Open in-browser VS Code

In the playground UI, switch to the VS Code tab. Your `~/workspace` directory
will already be the working folder.

### 5. After your session — push changes

Before destroying or letting the playground expire, commit and push:

```bash
cd ~/workspace/<your-plugin-repo>
git add -A
git commit -m "wip: session notes"
git push
```

> Fresh playgrounds do not persist disk state. Always push before closing.

---

## Re-authenticating Claude (auth expired or new playground)

Claude's OAuth credentials live in `~/.claude/` inside the sandbox VM.
They do not survive a fresh playground. Run this any time auth stops working:

```bash
# On your laptop:
~/scripts/claude-auth.sh <playground-id>

# Then inside the sandbox, re-trigger the login:
claude   # choose OAuth / Claude.ai login
```

---

## Notes

- **`claude-auth.sh` detects the port automatically.** Claude picks a random
  localhost port for its OAuth callback each time — the script watches for it,
  forwards it, and tears the tunnel down when auth completes.

- **`claude-auth.sh` only requires `labctl` on your laptop.**

- **For plugin UI validation:** since Obsidian has no GUI in the sandbox, use
  Obsidian Sync to push built plugin files to a test vault on your local laptop.
  The sandbox handles building; your laptop handles visual testing.
