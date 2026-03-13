<p align="center">
  <img src="icon.PNG" width="128" height="128" alt="iClaw Logo" />
</p>

<h1 align="center">iClaw</h1>

<p align="center">
  <strong>Your AI Agents, In Your Pocket</strong><br/>
  A native iOS AI Agent app — multiple customizable AI assistants, right on your phone
</p>

<p align="center">
  <a href="https://iclaw.shadow.mov">Website</a> ·
  <a href="#features">Features</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="LICENSE">MIT License</a> ·
  <a href="README.zh-hans.md">中文文档</a>
</p>

---

## Why iClaw?

Most AI chat apps are just chat boxes. **iClaw is different** — it's a full-blown **AI Agent platform** where every agent has its own soul, memory, and skills, and can execute code directly on your device.

| | Typical AI Chat | iClaw |
|---|---|---|
| **Personas** | Single conversation | Multiple agents, each with independent personality & memory |
| **Code Execution** | Not supported | Built-in Python & JavaScript interpreters |
| **Web Automation** | Not supported | In-App Browser with agent-driven automation |
| **Context** | Long conversations lose context | Auto-compression + summary injection — never forgets |
| **Extensibility** | Closed | Skill system + Cron jobs + Sub-agents |
| **Privacy** | Cloud-stored | All data stays on-device via SwiftData |

---

## Inspired by OpenClaw

iClaw is inspired by [OpenClaw](https://github.com/openclaw/openclaw) — the open-source personal AI assistant. We share the same vision of giving users a truly personal, customizable AI agent. Some shared DNA:

- **Soul-driven agents** — OpenClaw pioneered the Brain-Body-Soul model; iClaw adopts a similar philosophy with SOUL.md / MEMORY.md / USER.md mind files
- **Multi-provider LLM** — both let you swap models freely without losing context
- **Cron scheduling** — both support scheduled agent tasks
- **Function calling & tool use** — agents can take real actions, not just chat

### How iClaw differs

| | OpenClaw | iClaw |
|---|---|---|
| **Architecture** | Client-Server — requires a Gateway running on Mac/Linux/Windows | Fully standalone — everything runs natively on iOS, no server needed |
| **Tech stack** | TypeScript + Node.js | Swift + SwiftUI + SwiftData |
| **Channels** | 29+ messaging platforms (WhatsApp, Telegram, Slack…) | Dedicated native iOS experience, optimized for mobile |
| **Code execution** | Server-side shell & Docker sandboxing | On-device Python (MicroPython) & JavaScript (JSCore), works offline |
| **Data storage** | JSONL transcripts + vector DB on Gateway | SwiftData on-device, zero cloud dependency |
| **Setup** | Install Node ≥22, run Gateway, pair clients | Open Xcode, build, done |
| **Target** | Power users running a home server or VPS | Anyone with an iPhone who wants AI agents on the go |

**In short**: OpenClaw is your AI command center on a server; iClaw puts the same power directly into your pocket — no infrastructure required.

---

<a id="features"></a>
## Features

### 🧠 Multi-Agent Architecture
- Create multiple AI agents, each with its own **SOUL.md** (personality), **MEMORY.md** (persistent knowledge), and **USER.md** (user profile)
- Agents can spawn **sub-agents** that inherit the parent's soul configuration
- Flexible Markdown config space — you define how each agent behaves

### ⚡ On-Device Code Execution
- **Python interpreter** — powered by MicroPython, runs offline
- **JavaScript interpreter** — powered by JSCore, native performance
- Two execution modes: `repr` (expression evaluation) and `script` (full scripts)
- Save and reuse code snippets — build your mobile code library

### 💬 Smart Session Management
- Session-centric interaction design
- SwiftData persistence — your data is safe and never lost
- **Auto context compression** — when token limits are exceeded, older messages are compressed and summaries are injected into system prompts
- RAG-ready data model, prepared for cross-session retrieval

### 🔌 Multi-Provider LLM Support
- Compatible with any **OpenAI API**-compatible endpoint
- Full **SSE streaming** support with real-time typewriter output
- Built-in presets: OpenAI / DeepSeek / OpenRouter / Ollama (local)
- Configure multiple providers and switch freely

### 🌐 In-App Browser & Web Automation
- Built-in browser powered by WKWebView — browse the web without leaving the app
- **Agent-driven automation**: agents can navigate pages, click elements, fill forms, extract data, and execute JavaScript — all through function calling
- 9 browser tools: `browser_navigate`, `browser_click`, `browser_input`, `browser_extract`, `browser_execute_js`, `browser_get_page_info`, `browser_select`, `browser_wait`, `browser_scroll`
- **Mutex lock** ensures only one agent session controls the browser at a time; users see a live banner and can take over at any time
- Simplified DOM extraction gives agents a readable view of page structure (links, forms, buttons, text)

### 🛠 Powerful Function Calling
- `read_config` / `write_config` — read and modify agent mind files
- `execute_python` / `execute_javascript` — run code
- `save_code` / `load_code` / `list_code` — manage code snippets
- `create_sub_agent` / `message_sub_agent` — sub-agent lifecycle management
- `schedule_cron` / `unschedule_cron` — scheduled task management
- `browser_*` — 9 browser automation tools (see In-App Browser section above)

### 📦 Skill System
- Installable skill library to give agents new capabilities
- Flexibly attach skills — one skill can serve multiple agents

### ⏰ Cron Jobs
- Create scheduled tasks for agents with automatic background execution
- Built on `BGTaskScheduler` for system-level reliable scheduling
- Deep Link triggers: `iclaw://cron/trigger/{jobId}`

---

<a id="quick-start"></a>
## Quick Start

### Requirements

- Xcode 15+
- iOS 17.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build & Run

```bash
# Install XcodeGen
brew install xcodegen

# Generate the Xcode project
cd iClaw
xcodegen generate

# Open in Xcode
open iClaw.xcodeproj
```

### First Launch

1. Open the app → **Settings** → Add an LLM provider (enter API endpoint, key, and model name)
2. Go to **Agents** → Create your first agent
3. Go to **Sessions** → Start a new session → Chat away!

---

## Project Structure

```
iClaw/
├── project.yml              # XcodeGen config
├── iClaw/
│   ├── App/                 # App entry point & root navigation
│   ├── Models/              # SwiftData models
│   ├── Services/
│   │   ├── LLM/            # LLM API client, SSE parser
│   │   ├── Agent/           # Agent management
│   │   ├── Session/         # Session service, context compression
│   │   ├── Prompt/          # System prompt construction
│   │   ├── FunctionCall/    # Tool definitions & routing
│   │   ├── CodeExecution/   # Code execution engines
│   │   ├── Browser/         # In-App Browser service & automation
│   │   ├── CronJob/         # Cron job scheduling
│   │   └── Skill/           # Skill management
│   ├── ViewModels/          # Observable view models
│   ├── Views/               # SwiftUI views
│   └── Resources/           # Assets & default templates
```

## Tech Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI + Declarative Navigation |
| State | Observation Framework (`@Observable`) |
| Persistence | SwiftData |
| Code Execution | MicroPython · JavaScriptCore |
| Web Automation | WKWebView + Agent-driven function calling |
| Networking | URLSession + SSE Streaming |
| Project Gen | XcodeGen |

---

## License

This project is open-sourced under the [MIT License](LICENSE).

Copyright (c) 2026 ShadowMov

---

<p align="center">
  <strong>iClaw</strong> — Your AI Agents, In Your Pocket.<br/>
  <a href="https://iclaw.shadow.mov">iclaw.shadow.mov</a>
</p>
