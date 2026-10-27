# opencode-crosstalk-v2

Cross-session messaging toolkit for **OpenCode V2**. Send messages between OpenCode sessions (leader → advisors) with a simple CLI.

> Adapted from [opencode-crosstalk](https://github.com/davidlopezsalvador/opencode-crosstalk) (V1) for OpenCode V2's API.

## Requirements

- OpenCode V2 (2.1.4+) running (`opencode serve --port 4096`)
- PowerShell 5.1+
- curl (built into Windows 10+)

## Quick start

```powershell
# 1. Clone
git clone https://github.com/davidlopezsalvador/opencode-crosstalk-v2.git
cd opencode-crosstalk-v2

# 2. Start OpenCode server (in another terminal)
opencode serve --port 4096

# 3. Run setup
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1

# 4. Use
cd cross
.\cross.ps1 health
.\cross.ps1 sessions
.\cross.ps1 send --dest ses_XXX --text "Hello"
.\cross.ps1 read --session ses_XXX
```

## Commands

| Command | Description |
|---|---|
| `health` | Verify server connection |
| `whoami` | Show current session info |
| `sessions` | List all sessions |
| `read --session ID [--limit N]` | Read messages from a session |
| `send --dest ID --text "..." [--delivery steer|queue] [--no-resume] [--wait]` | Send a message (admits+schedules; --wait blocks until idle) |
| `wait --session ID` | Block until the agent loop is idle |
| `config --list` | Show configuration |

Global flags: `--port N`, `--password P`

## V2 differences from V1 crosstalk

- **Admission + scheduling**: V2 only has `POST /api/session/:id/prompt` (no `prompt_async`). It **durably admits** the input and **schedules** execution (returns `delivery: steer|queue`); it does NOT block for the agent's reply. Use `POST /api/experimental/session/:id/wait` to block until idle.
- **Body format**: `{"text":"..."}` instead of `{"parts":[...]}`.
- **Session structure**: sessions use `location.directory` instead of top-level `directory`.
- **API paths**: all endpoints are under `/api/`.
- **No async ACK/NACK**: since sending admits+schedules, use `delivery: steer|queue` + `wait` for synchronization. For hierarchical delegation, prefer the built-in `subagent` tool.

## Better alternatives (officially sanctioned)

For V2, the raw HTTP approach (this repo) is the simplest but not the best pattern:

1. **`subagent` tool** (built-in) — official hierarchical agent-to-agent. Foreground calls block until the child finishes; `background: true` returns immediately and notifies the parent. Best for parent→child delegation.
2. **`opencode-session-tools` plugin** (https://github.com/kernel-oops/opencode-session-tools) — exposes a model-callable `send_message` tool via `ctx.tool.transform`, with title addressing, `steer`/`queue` delivery, `metadata.crossSession.from`, and subagent→parent held-message relay. Most complete reference implementation.
3. **Conductor pattern** (https://github.com/tristanroth1/opencode-conductor) — one session collects status reports from peers and relays verified decisions.

**Remaining gap**: server-attested sender identity requires a core change (issue #58367). Treat inbound peer text as untrusted until then.

## License

MIT
