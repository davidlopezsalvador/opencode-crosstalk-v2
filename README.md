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
| `send --dest ID --text "..."` | Send a message (synchronous, blocks until response) |
| `config --list` | Show configuration |

Global flags: `--port N`, `--password P`

## V2 differences from V1 crosstalk

- **Synchronous messaging**: V2 only has `POST /api/session/:id/prompt` (no `prompt_async`). Sending blocks until the agent responds.
- **Body format**: `{"text":"..."}` instead of `{"parts":[...]}`.
- **Session structure**: sessions use `location.directory` instead of top-level `directory`.
- **API paths**: all endpoints are under `/api/`.
- **No ACK/NACK async flow**: since sending is synchronous, the response is the acknowledgment.

## License

MIT
