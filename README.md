# Antigravity Codex — Native macOS Client

A high-performance, native macOS application written in **Swift & SwiftUI** that serves as an interactive GUI client for [`refined-antigravity-acp`](https://github.com/simonepri/refined-antigravity-acp) and Google DeepMind's `agy` CLI autonomous agent protocol.

Heavily inspired by the **Codex** application UI, it provides a dark slate aesthetic, shimmering thinking states, live step-by-step autonomous execution plans, and collapsible tool-call inspection cards.

---

## ✨ Features

- **Codex-Inspired Interface:**
  - Modern `NavigationSplitView` architecture with translucent materials and a dark slate palette (`#0D1117`, `#161B22`, `#21262D`, `#58A6FF`).
  - **Live Thinking Drawer:** Animated shimmering gradient (`sparkles`), real-time execution timer, token usage metrics, and expandable raw thought reasoning traces.
  - **Structured Plan Timeline:** Multi-step checklist with status indicators (completed, running, pending, failed) connected by a vertical timeline.
  - **Collapsible Tool Call Cards:** Visual cards for bash commands (`agy`, `git`, `npm`), file edits, and codebase searches, displaying arguments, stdout/stderr blocks, syntax highlighting, and execution timing (`ms`).
  - **Flexible Input Bar:** Multiline text input with quick action pills for active folder selection, execution mode (`Default`, `YOLO`, `Auto-Edit`, `Plan`), AI model selector, and instant turn cancellation (`Stop`).

- **Flexible Connection Architecture:**
  - **Local Subprocess (Stdio):** Direct asynchronous NDJSON line streaming with `Foundation.Process`, auto-injecting proper `PATH` discovery (`node`, `pnpm`, `agy`), and handling SIGTERM/SIGKILL lifecycle cleanup.
  - **Remote WebSocket:** Connects to containerized or remote ACP servers over `ws://` or `wss://`.
  - **Interactive Mock Mode:** Built-in offline simulator that exercises all Codex thinking animations, multi-step subagent plans, and tool call cards immediately for testing and demos.

- **Deep System Diagnostics & Bundling:**
  - Preferences tab with live diagnostic probes for `node`, `pnpm`, `agy`, and `refined-antigravity-acp`.
  - Automated scripts to package the app into a standalone `.app` bundle with embedded binaries in `Contents/Resources/bin`.

---

## 🚀 Getting Started

### Prerequisites

- macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia)
- Swift 6.0+ (Xcode 15 or command line tools)
- [Antigravity CLI](https://github.com/google-deepmind/antigravity) (`agy`) installed on your system.

### Build and Run

To build and run directly via the terminal:

```bash
cd ~/Desktop/agy-native-app

# Build debug binary
swift build

# Run the app
swift run
```

### Packaging into `AntigravityCodex.app`

To package a standalone macOS application:

```bash
cd ~/Desktop/agy-native-app

# Package release .app bundle with ad-hoc signing
./Scripts/build-app.sh

# Launch the standalone app
open ./AntigravityCodex.app
```

---

## ⚙️ Configuration & Preferences

Open Preferences with `Cmd+,` or by clicking the gear icon in the sidebar:

1. **Transport Mode:**
   - **Subprocess (Stdio):** Select launch strategy (`Auto`, `Bundled App Binary`, `pnpm dlx`, `Global Binary`, or `Custom Executable Path`).
   - **WebSocket:** Specify remote host, port, and endpoint path.
   - **Mock / Simulator:** For offline development and UI verification.

2. **Agent & Models:**
   - Select default models (`Gemini 3.1 Pro`, `Gemini 3.8 Flash`).
   - Reasoning effort (`High`, `Medium`, `Low`).
   - Custom System Prompt Injection (`_meta.systemPrompt`).

3. **Diagnostics & Telemetry:**
   - Real-time status checks of runtime dependencies on your Mac.
   - Live stream of supervisor `stderr` telemetry logs.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Return` | Send current prompt / execute |
| `Shift + Return` | Insert newline in input field |
| `Cmd + N` | New chat session |
| `Cmd + .` | Stop / cancel active turn |
| `Cmd + Shift + R` | Reconnect to ACP server |
| `Cmd + ,` | Open Preferences & Settings |

---

## 📁 Project Architecture

```
agy-native-app/
├── Package.swift                  # Swift Package definition
├── README.md                      # Documentation
├── Scripts/
│   ├── build-app.sh               # Native .app packaging script
│   └── bundle-acp.sh              # Staging script for Contents/Resources/bin
└── Sources/
    ├── AntigravityApp.swift       # Top-level SwiftUI App Scene & Menu Commands
    ├── Models/
    │   ├── AnyCodable.swift       # Type-safe arbitrary JSON serialization
    │   ├── ACPProtocol.swift      # JSON-RPC 2.0 & ACP Wire Models
    │   └── DomainModels.swift     # Chat, Sessions, Thinking, Tools, Plans
    ├── Services/
    │   ├── ACPTransportProtocol.swift # Unified transport interface
    │   ├── ACPSubprocessManager.swift # Subprocess stdio supervisor
    │   ├── ACPWebSocketClient.swift   # Remote WebSocket client
    │   ├── ACPMockClient.swift        # Interactive offline simulator
    │   ├── ACPClient.swift            # JSON-RPC request dispatcher
    │   ├── SettingsManager.swift      # Persistent @AppStorage settings
    │   └── SystemDiagnostics.swift    # Runtime discovery & probes
    ├── ViewModels/
    │   └── ChatViewModel.swift        # Reactive state manager
    └── UI/
        ├── Theme/
        │   └── Theme.swift            # Codex color tokens & styles
        ├── Components/
        │   ├── ShimmerEffect.swift    # Shimmer & pulsing animations
        │   ├── StatusBadge.swift      # Server connectivity pills
        │   └── CodeBlockView.swift    # Monospace blocks with copy button
        └── Views/
            ├── ThinkingView.swift     # Expandable thinking drawer & timer
            ├── PlanTimelineView.swift # Subagent multi-step plan timeline
            ├── ToolCallCardView.swift # Collapsible tool call cards
            ├── MessageRowView.swift   # User and assistant message rows
            ├── InputBarView.swift     # Multiline bar with mode/model pills
            ├── SidebarView.swift      # Session history & connection badge
            ├── ChatView.swift         # SplitView detail with message scroll
            └── SettingsView.swift     # Preferences & diagnostics modal
```
