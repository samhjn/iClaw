# iClaw - iOS AI Agent App

An iOS AI Agent application built with SwiftUI and SwiftData (iOS 17+).

## Features

### Agent System
- **Multi-Agent Architecture**: Create and manage multiple AI agents, each with their own configuration space
- **Agent Mind Files**: Each agent has SOUL.md (personality), MEMORY.md (persistent knowledge), and USER.md (user profile)
- **Custom Configs**: Extensible markdown configuration space per agent
- **Sub-Agents**: Agents can spawn sub-agents that inherit the parent's SOUL configuration

### Code Execution
- **Python Interpreter**: Built-in Python execution via PythonKit (with mock executor for development)
- **Dual Execution Modes**: `repr` mode for expression evaluation, `script` mode for full scripts
- **Code Storage**: Save and load code snippets within an agent's config space
- **Extensible**: Protocol-based design ready for additional interpreters (JS, BusyBox, etc.)

### Session Management
- **Session-centric UI**: Each session is a conversation between a user and an agent
- **Persistence**: All sessions saved via SwiftData
- **Auto-compression**: Automatically compresses older messages when context exceeds token threshold
- **Context Injection**: Compressed summaries are injected into system prompts for continuity
- **RAG-ready**: Data model designed for future retrieval-augmented generation across sessions

### LLM Integration
- **OpenAI API Compatible**: Works with any OpenAI-compatible endpoint
- **Streaming + Non-streaming**: Full SSE streaming support with fallback to standard requests
- **Multi-provider**: Configure multiple LLM providers with custom endpoints and API keys
- **Presets**: Quick setup for OpenAI, DeepSeek, OpenRouter, and local Ollama

### Function Calling
- `read_config` / `write_config` - Read and modify agent mind files
- `execute_python` - Execute Python code
- `save_code` / `load_code` / `list_code` - Manage code snippets
- `create_sub_agent` / `message_sub_agent` - Sub-agent lifecycle management

## Requirements

- Xcode 15+
- iOS 17.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)

## Setup

```bash
# Install XcodeGen if not already installed
brew install xcodegen

# Generate Xcode project
cd iClaw
xcodegen generate

# Open in Xcode
open iClaw.xcodeproj
```

## Project Structure

```
iClaw/
├── project.yml              # XcodeGen configuration
├── iClaw/
│   ├── App/                 # App entry point and root navigation
│   ├── Models/              # SwiftData models (Agent, Session, Message, etc.)
│   ├── Services/
│   │   ├── LLM/            # LLM API client, SSE parser, message types
│   │   ├── Agent/           # Agent CRUD, sub-agent management
│   │   ├── Session/         # Session service, compression, context management
│   │   ├── Prompt/          # System prompt construction, default templates
│   │   ├── FunctionCall/    # Tool definitions, routing, implementations
│   │   └── CodeExecution/   # Python executor, mock executor, protocol
│   ├── ViewModels/          # Observable view models
│   ├── Views/               # SwiftUI views
│   └── Resources/           # Assets, default markdown templates
```

## Configuration

1. Open the app and go to **Settings** tab
2. Add an LLM provider (tap "Add Provider")
3. Enter your API endpoint, key, and model name
4. Go to **Agents** tab and create a new agent
5. Go to **Sessions** tab, create a new session with your agent
6. Start chatting!

## Architecture

- **UI Layer**: SwiftUI with declarative navigation
- **ViewModel Layer**: `@Observable` view models (Observation framework)
- **Service Layer**: Business logic separated into focused services
- **Data Layer**: SwiftData models with relationships
- **Execution Layer**: Protocol-based code execution with PythonKit integration

## Python Execution

The app includes PythonKit integration for on-device Python execution. For development, a `MockExecutor` simulates Python output. To enable real Python execution:

1. Download Python.xcframework from [BeeWare Python-Apple-support](https://github.com/beeware/Python-Apple-support)
2. Add the framework to the Xcode project
3. The `PythonExecutor` will automatically activate when PythonKit is available
