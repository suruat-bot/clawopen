# ClawOpen - Project Plan

## Vision

ClawOpen is a multi-platform LLM chat app that seamlessly connects to both **local models** (via Ollama) and **cloud-backed AI** (via OpenClaw Gateway). Users get the best of both worlds: privacy-first local inference when available, and powerful cloud models when needed.

**Target platforms:** iOS, Android, macOS, Windows, Linux

## Why Fork Reins?

[Reins](https://github.com/ibrahimcetin/reins) is a polished, open-source Ollama client with:
- Clean Flutter codebase
- Multi-platform support
- Per-chat configurations (system prompts, model selection, options)
- Streaming, image support, multiple chat management
- Already on App Store and Flathub

Instead of building from scratch, we extend Reins to also support OpenClaw Gateway as a backend.

---

## Phased Development Plan

### Phase 1: Core OpenClaw Integration ✅ (Complete)
**Goal:** OpenClaw Gateway works as a backend alongside Ollama.

- [x] Fork Reins codebase
- [x] Create `OpenClawService` (OpenAI-compatible API)
- [x] Add connection type abstraction (Ollama vs OpenClaw)
- [x] Settings UI: Add/edit OpenClaw connections
  - Gateway URL
  - Auth token
  - Agent ID (default: main)
- [x] Connection test ("Test Connection" button)
- [x] Switch between Ollama and OpenClaw in chat
- [x] Per-chat backend routing (model name based)
- [x] Fix SSE streaming duplication bug

**Deliverable:** Users can add an OpenClaw Gateway connection and chat with it.

---

### Phase 2: Multi-Connection Management ✅ (Complete)
**Goal:** Manage multiple connections (multiple Ollama servers + multiple gateways).

- [x] Connection list in Settings (ConnectionsSettings widget)
- [x] Add/edit/delete connections (ConnectionEditDialog)
- [x] Connection types: Ollama, OpenClaw Gateway, Generic OpenAI-Compatible
- [x] Per-chat connection selection (connectionId stored per chat)
- [x] Default connection preference (star toggle in connections list)
- [x] Connection status indicators (online/offline dots)
- [x] OpenAI-Compatible provider support (OpenAI, Groq, OpenRouter, NVIDIA NIM, etc.)
- [x] "My Models" system — two-step model selection:
  - Model Library page: browse all models from all connections, add/remove
  - Model picker only shows "My Models" for quick selection
  - Per-connection add/remove all toggle
  - Search/filter in both model picker and library
- [x] Migration from Phase 1 flat settings to Connection model

**Deliverable:** Users can configure and switch between multiple backends.

**Key files created/modified:**
- `lib/Providers/connection_provider.dart` — manages connections, service caching, status
- `lib/Providers/model_provider.dart` — "My Models" persistence
- `lib/Models/connection.dart` — Connection model with types enum
- `lib/Services/openai_compatible_service.dart` — generic OpenAI-compatible API
- `lib/Pages/model_library_page.dart` — full-page model browser
- `lib/Pages/settings_page/subwidgets/connections_settings.dart` — connection list UI
- `lib/Pages/settings_page/subwidgets/connection_edit_dialog.dart` — add/edit dialog

---

### Phase 3: OpenClaw-Specific Features ✅ (Complete)
**Goal:** Leverage OpenClaw Gateway's unique capabilities.

- [x] Stable session persistence
  - `user` field in chat completions → gateway derives stable session key
  - `effectiveSessionUser` defaults to `clawopen:<chatId>`
  - DB migration v2→v3 (openclaw_session_user, thinking_level columns)
- [x] Thinking level control
  - Enum: off, minimal, low, medium, high, xhigh
  - Dropdown in chat configure sheet (conditional on OpenClaw connection)
  - Persisted per-chat in database
  - `thinking_level` sent in request body to gateway (non-off values only)
- [x] Session management
  - Sessions page listing active gateway sessions
  - Session detail page with transcript viewer
  - `invokeTool()` for sessions_list and sessions_history
- [x] WebSocket service
  - Challenge/response handshake with OpenClaw protocol
  - Request/response pattern with Completers
  - Auto-reconnect with exponential backoff (1s→30s max)
  - Event broadcasting via StreamController
- [x] OpenClaw Provider
  - WebSocket lifecycle per OpenClaw connection
  - Node awareness (list, describe, online/offline)
  - Tool approval requests (approve/deny from chat)
  - App lifecycle handling (reconnect on resume)
- [x] UI surfaces
  - WebSocket status dot (green/orange/red) in chat app bar
  - Nodes page with capabilities chips
  - Approval banner in chat page
  - Sessions + Nodes cards in settings (conditional on OpenClaw connections)
- [x] Tokens per second display on assistant messages
- [x] Bug fixes (post-audit)
  - `getAllChats()` now SELECTs `openclaw_session_user` and `thinking_level` columns
  - `thinking_level` actually sent in both `chat()` and `chatStream()` request bodies
- [ ] Push notifications (deferred to Phase 5)

**Deliverable:** Full OpenClaw Gateway feature integration.

**Key files created/modified:**
- `lib/Services/openclaw_websocket_service.dart` — WebSocket with handshake, reconnect
- `lib/Providers/openclaw_provider.dart` — WS lifecycle, nodes, approvals
- `lib/Models/openclaw_event.dart` — WS state enum, event model
- `lib/Models/openclaw_node.dart` — device node model
- `lib/Models/openclaw_approval.dart` — tool approval request model
- `lib/Models/openclaw_session.dart` — session + transcript models
- `lib/Pages/sessions_page.dart` — session list + detail
- `lib/Pages/nodes_page.dart` — paired device nodes
- `lib/Widgets/approval_banner.dart` — tool approval banner

---

### Phase 3.5: OpenClaw Native Protocol ✅ (Complete)
**Goal:** Use the native OpenClaw WebSocket protocol correctly for chat.

- [x] Fix WS protocol version: `protocolVersion: 1` → `minProtocol: 3, maxProtocol: 3`
- [x] Device token persistence
  - Extract `deviceToken` from `hello-ok` handshake response
  - Persist per-connection in Hive (`deviceToken_<connectionId>`)
  - Send stored token on reconnect via `device.token` param in `connect` request
- [x] Native `chat.send` over WebSocket
  - `chatSendStream()` method on `OpenClawWebSocketService`
  - Handles streaming tokens via `chat.token` events and non-streaming via `res` frame
  - Passes full conversation history + sessionKey + systemPrompt + thinkingLevel
  - `OpenClawProvider.chatSendStream()` exposes WS chat per connection
  - `ChatProvider` routes through WS when connected, falls back to HTTP otherwise

**Deliverable:** ClawOpen uses the correct protocol and native WS chat path.

**Key files modified:**
- `lib/Services/openclaw_websocket_service.dart` — protocol fix, deviceToken, chatSendStream
- `lib/Providers/openclaw_provider.dart` — deviceToken storage, chatSendStream delegation
- `lib/Providers/chat_provider.dart` — WS routing with HTTP fallback
- `lib/main.dart` — inject OpenClawProvider into ChatProvider

---

### Phase 3.6: Channel Management ✅ (Complete)
**Goal:** Let users enable/disable gateway chat channels directly from the app.

- [x] `config.get` + `config.patch` + `channels.status` WS methods on `OpenClawWebSocketService`
- [x] `OpenClawChannel` model (name, enabled, connectionId, connectionName, icon, displayName)
- [x] `OpenClawProvider.getChannels()` — reads channel config from all connected gateways
- [x] `OpenClawProvider.setChannelEnabled()` — patches gateway config to toggle a channel
- [x] `ChannelsPage` — list of configured channels with enable/disable toggles
  - Grouped by connection when multiple gateways are connected
  - Optimistic UI update with revert on failure
  - Refresh button, error + empty states
- [x] Channels card in Settings (under Sessions/Nodes, OpenClaw connections only)
- [x] `/channels` route in main.dart

**Deliverable:** Users can manage gateway channels (Telegram, WhatsApp, Discord, etc.) in-app.

**Key files created/modified:**
- `lib/Models/openclaw_channel.dart` — channel model
- `lib/Pages/channels_page.dart` — channels list page
- `lib/Services/openclaw_websocket_service.dart` — getConfig, patchConfig, getChannelsStatus
- `lib/Providers/openclaw_provider.dart` — getChannels, setChannelEnabled
- `lib/Pages/settings_page/settings_page.dart` — Channels card
- `lib/main.dart` — /channels route + import

---

### Phase 4: Branding & Polish ✅ (Complete)
**Goal:** ClawOpen identity and app store readiness.

- [x] Rename Dart package: `reins` → `clawopen` (pubspec.yaml + all 40+ imports)
- [x] Rename bundle ID: `dev.ibrahimcetin.reins` → `ai.clawopen.app` (all platforms)
- [x] Update app name: "Reins" → "ClawOpen" (all platforms + UI strings)
- [x] Rename Dart class names (`ReinsApp` → `ClawOpenApp`, `ReinsMainPage` → `ClawOpenMainPage`, etc.)
- [x] Update settings about section (`reins_settings.dart` → `clawopen_settings.dart`)
  - URLs: `https://clawopen.ai` and `https://github.com/clawopen/clawopen`
- [x] Privacy policy updated (`PRIVACY` file)
- [x] Linux flatpak metadata (`ai.clawopen.app.desktop`, `ai.clawopen.app.metainfo.xml`)
- [x] Windows RC file (CompanyName, ProductName, OriginalFilename, etc.)
- [x] Web manifest (name, short_name, description)
- [ ] New app icon (deferred — awaiting assets)
- [ ] Splash screen (deferred — awaiting assets)
- [ ] App Store screenshots and metadata (deferred)

**Deliverable:** Publishable app with ClawOpen branding.
**Build output:** `ClawOpen.app` (50MB, macOS Release)

---

### Phase 5: Advanced Features (Future)
**Goal:** Power-user and enterprise features.

- [ ] Push notifications (from OpenClaw Gateway)
- [ ] Markdown rendering improvements
- [ ] Code syntax highlighting
- [ ] File attachments (documents, not just images)
- [ ] Voice input/output (TTS integration)
- [ ] Chat export (JSON, Markdown)
- [ ] Keyboard shortcuts (desktop)
- [ ] Widget support (iOS/Android home screen)
- [ ] Apple Watch / WearOS companion

---

## Architecture

```
lib/
├── Services/
│   ├── ollama_service.dart              # Ollama API
│   ├── openclaw_service.dart            # OpenClaw Gateway HTTP API
│   ├── openclaw_websocket_service.dart  # OpenClaw Gateway WebSocket
│   ├── openai_compatible_service.dart   # Generic OpenAI-compatible API
│   ├── database_service.dart            # SQLite chat/message storage (v3)
│   ├── permission_service.dart          # Platform permissions
│   ├── image_service.dart               # Image handling
│   └── services.dart                    # Barrel export
├── Models/
│   ├── connection.dart                  # Connection config + ConnectionType enum
│   ├── ollama_model.dart                # Model metadata
│   ├── ollama_chat.dart                 # Chat with connectionId, thinkingLevel
│   ├── openclaw_event.dart              # WS state enum, event model
│   ├── openclaw_node.dart               # Device node model
│   ├── openclaw_approval.dart           # Tool approval request
│   ├── openclaw_session.dart            # Session + transcript models
│   └── ...existing models...
├── Providers/
│   ├── connection_provider.dart         # Manage connections, service routing
│   ├── model_provider.dart              # "My Models" persistence
│   ├── chat_provider.dart               # Chat state, streaming, model fetching
│   ├── openclaw_provider.dart           # WS lifecycle, nodes, approvals
│   └── ...existing providers...
├── Pages/
│   ├── model_library_page.dart          # Browse all models, add/remove
│   ├── sessions_page.dart               # OpenClaw session list + detail
│   ├── nodes_page.dart                  # OpenClaw paired device nodes
│   ├── settings_page/
│   │   └── subwidgets/
│   │       ├── connections_settings.dart # Connection list UI
│   │       ├── connection_edit_dialog.dart # Add/edit connection
│   │       └── ...
│   └── ...existing pages...
├── Widgets/
│   ├── selection_bottom_sheet.dart       # Model picker with search
│   ├── chat_app_bar.dart                # Connection-aware app bar + WS status
│   ├── approval_banner.dart             # Tool approval approve/deny banner
│   └── ...
└── main.dart
```

## Tech Stack

- **Framework:** Flutter
- **State Management:** Provider
- **Local Storage:** Hive (settings), SQLite (chat history)
- **Networking:** http package
- **Platforms:** iOS, Android, macOS, Windows, Linux, (Web possible)

## Repository

- **Origin:** https://github.com/suruat-bot/reins (to be renamed clawopen)
- **Upstream:** https://github.com/ibrahimcetin/reins (original Reins)

## Contributing

This is a fork of Reins. We maintain compatibility with upstream where possible and contribute back improvements that aren't OpenClaw-specific.

## License

GPL-3.0 (inherited from Reins)
