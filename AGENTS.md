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

### Phase 3: OpenClaw-Specific Features
**Goal:** Leverage OpenClaw Gateway's unique capabilities.

- [ ] Session management
  - Persistent session keys
  - Session history (if exposed by gateway)
- [ ] Agent selection
  - List available agents from gateway
  - Switch agents mid-conversation
- [ ] Node awareness (optional)
  - Show paired nodes status
  - Camera/screen capture from nodes (if permitted)
- [ ] Push notifications
  - Register for gateway push notifications
  - Background message delivery

**Deliverable:** Full OpenClaw Gateway feature integration.

---

### Phase 4: Branding & Polish
**Goal:** ClawOpen identity and app store readiness.

- [ ] Rename package: `dev.ibrahimcetin.reins` → `ai.clawopen.app`
- [ ] Update app name: "Reins" → "ClawOpen"
- [ ] New app icon and branding
- [ ] Update splash screen
- [ ] About page with credits (original Reins + OpenClaw)
- [ ] App Store metadata (screenshots, description)
- [ ] Privacy policy update

**Deliverable:** Publishable app with ClawOpen branding.

---

### Phase 5: Advanced Features (Future)
**Goal:** Power-user and enterprise features.

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
│   ├── openclaw_service.dart            # OpenClaw Gateway API
│   ├── openai_compatible_service.dart   # Generic OpenAI-compatible API
│   ├── database_service.dart            # SQLite chat/message storage
│   ├── permission_service.dart          # Platform permissions
│   ├── image_service.dart               # Image handling
│   └── services.dart                    # Barrel export
├── Models/
│   ├── connection.dart                  # Connection config + ConnectionType enum
│   ├── ollama_model.dart                # Model metadata
│   ├── ollama_chat.dart                 # Chat with connectionId
│   └── ...existing models...
├── Providers/
│   ├── connection_provider.dart         # Manage connections, service routing
│   ├── model_provider.dart              # "My Models" persistence
│   ├── chat_provider.dart               # Chat state, streaming, model fetching
│   └── ...existing providers...
├── Pages/
│   ├── model_library_page.dart          # Browse all models, add/remove
│   ├── settings_page/
│   │   └── subwidgets/
│   │       ├── connections_settings.dart # Connection list UI
│   │       ├── connection_edit_dialog.dart # Add/edit connection
│   │       └── ...
│   └── ...existing pages...
├── Widgets/
│   ├── selection_bottom_sheet.dart       # Model picker with search
│   ├── chat_app_bar.dart                # Connection-aware app bar
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
