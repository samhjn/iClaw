<p align="center">
  <img src="icon.PNG" width="128" height="128" alt="iClaw Logo" />
</p>

<h1 align="center">iClaw</h1>

<p align="center">
  <strong>把 AI Agent 装进口袋，随时随地释放智能</strong><br/>
  一款原生 iOS AI Agent 应用，让你在手机上拥有多个可定制的 AI 助手
</p>

<p align="center">
  <a href="https://iclaw.shadow.mov">官网</a> ·
  <a href="#features">功能特性</a> ·
  <a href="#quick-start">快速开始</a> ·
  <a href="LICENSE">MIT License</a> ·
  <a href="README.md">English</a>
</p>

---

## 为什么选择 iClaw？

市面上的 AI 聊天应用只是对话框。**iClaw 不一样**——它是一个完整的 **AI Agent 平台**，每个 Agent 都有自己的灵魂、记忆和技能，还能直接在手机上运行代码。

| 维度 | 普通 AI 聊天 | iClaw |
|------|------------|-------|
| **多角色** | 单一对话 | 多 Agent，各有独立人格与记忆 |
| **代码执行** | 不支持 | 内置 Python & JavaScript 解释器 |
| **上下文管理** | 超长对话丢失上下文 | 自动压缩 + 摘要注入，永不遗忘 |
| **可扩展性** | 封闭 | 技能系统 + 定时任务 + 子 Agent |
| **数据隐私** | 云端存储 | 全部数据存于本地 SwiftData |

---

## 灵感来源：OpenClaw

iClaw 的灵感来自 [OpenClaw](https://github.com/openclaw/openclaw) —— 开源个人 AI 助手。我们共享同一个愿景：让用户拥有真正属于自己的、可定制的 AI Agent。一些共同的设计基因：

- **灵魂驱动的 Agent** — OpenClaw 首创了 Brain-Body-Soul 模型；iClaw 采用类似理念，通过 SOUL.md / MEMORY.md / USER.md 心智文件定义 Agent
- **多 LLM 提供商** — 两者都支持自由切换模型，不丢失上下文
- **定时任务调度** — 两者都支持 Agent 定时任务（Cron）
- **Function Calling & 工具调用** — Agent 不只是聊天，还能执行真实操作

### iClaw 的不同之处

| | OpenClaw | iClaw |
|---|---|---|
| **架构** | C/S 架构 — 需要在 Mac/Linux/Windows 上运行 Gateway 服务 | 完全独立 — 一切原生运行在 iOS 上，无需服务器 |
| **技术栈** | TypeScript + Node.js | Swift + SwiftUI + SwiftData |
| **渠道** | 29+ 消息平台（WhatsApp、Telegram、Slack…） | 专注原生 iOS 体验，为移动端深度优化 |
| **代码执行** | 服务端 Shell 命令 & Docker 沙盒 | 端侧 Python（MicroPython）& JavaScript（JSCore），离线可用 |
| **数据存储** | JSONL 日志 + 向量数据库，存于 Gateway 服务器 | SwiftData 本地存储，零云端依赖 |
| **上手门槛** | 安装 Node ≥22，运行 Gateway，配对客户端 | 打开 Xcode，编译，完成 |
| **目标用户** | 拥有家庭服务器或 VPS 的高级用户 | 任何想随身携带 AI Agent 的 iPhone 用户 |

**一句话总结**：OpenClaw 是你服务器上的 AI 指挥中心；iClaw 把同样的能力直接装进口袋——无需任何基础设施。

---

<a id="features"></a>
## 核心功能

### 🧠 多 Agent 架构
- 创建多个 AI Agent，每个都有独立的 **SOUL.md**（人格）、**MEMORY.md**（记忆）、**USER.md**（用户画像）
- Agent 可以生成 **子 Agent**，子 Agent 继承父级人格配置
- 灵活的 Markdown 配置空间，完全由你定义 Agent 的行为

### ⚡ 端侧代码执行
- **Python 解释器** — 基于 MicroPython，无需网络即可运行
- **JavaScript 解释器** — 基于 JSCore，原生高性能
- 两种执行模式：`repr`（表达式求值）与 `script`（完整脚本）
- 代码片段保存与复用，打造你的移动代码库

### 💬 智能会话管理
- 以会话为中心的交互体验
- SwiftData 持久化，数据安全不丢失
- **自动上下文压缩**——超出 Token 阈值时自动压缩历史消息，摘要注入系统提示
- RAG-ready 数据模型，为跨会话检索做好准备

### 🔌 多 LLM 提供商支持
- 兼容任何 **OpenAI API** 格式的接口
- 完整的 **SSE 流式响应** 支持，打字机效果实时输出
- 内置预设：OpenAI / DeepSeek / OpenRouter / Ollama（本地部署）
- 自由配置多个 Provider，一键切换

### 🛠 强大的 Function Calling
- `read_config` / `write_config` — 读写 Agent 心智文件
- `execute_python` / `execute_javascript` — 执行代码
- `save_code` / `load_code` / `list_code` — 管理代码片段
- `create_sub_agent` / `message_sub_agent` — 子 Agent 生命周期管理
- `schedule_cron` / `unschedule_cron` — 定时任务调度

### 📦 技能系统
- 可安装的技能库，为 Agent 赋予新能力
- 灵活挂载，一个技能可服务多个 Agent

### ⏰ 定时任务（Cron Jobs）
- 为 Agent 创建定时任务，后台自动执行
- 基于 `BGTaskScheduler`，系统级可靠调度
- 支持 Deep Link 触发：`iclaw://cron/trigger/{jobId}`

---

<a id="quick-start"></a>
## 快速开始

### 环境要求

- Xcode 15+
- iOS 17.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### 构建 & 运行

```bash
# 安装 XcodeGen
brew install xcodegen

# 生成 Xcode 工程
cd iClaw
xcodegen generate

# 打开项目
open iClaw.xcodeproj
```

### 首次使用

1. 打开 App → **设置** → 添加一个 LLM 提供商（填入 API 端点、密钥、模型名称）
2. 前往 **Agents** → 创建你的第一个 Agent
3. 前往 **Sessions** → 新建会话 → 开始对话！

---

## 项目结构

```
iClaw/
├── project.yml              # XcodeGen 配置
├── iClaw/
│   ├── App/                 # 应用入口和根导航
│   ├── Models/              # SwiftData 数据模型
│   ├── Services/
│   │   ├── LLM/            # LLM API 客户端、SSE 解析
│   │   ├── Agent/           # Agent 管理
│   │   ├── Session/         # 会话服务、上下文压缩
│   │   ├── Prompt/          # 系统提示词构建
│   │   ├── FunctionCall/    # 工具定义与路由
│   │   ├── CodeExecution/   # 代码执行引擎
│   │   ├── CronJob/         # 定时任务调度
│   │   └── Skill/           # 技能管理
│   ├── ViewModels/          # Observable 视图模型
│   ├── Views/               # SwiftUI 视图层
│   └── Resources/           # Assets、默认模板
```

## 技术栈

| 层级 | 技术选型 |
|------|---------|
| UI | SwiftUI + Declarative Navigation |
| 状态管理 | Observation Framework (`@Observable`) |
| 数据持久化 | SwiftData |
| 代码执行 | MicroPython · JavaScriptCore |
| 网络 | URLSession + SSE Streaming |
| 工程管理 | XcodeGen |

---

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。

Copyright (c) 2026 ShadowMov

---

<p align="center">
  <strong>iClaw</strong> — 把 AI Agent 装进口袋<br/>
  <a href="https://iclaw.shadow.mov">iclaw.shadow.mov</a>
</p>
