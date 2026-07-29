# Claco — Autonomous Pocket Agent for Android

Claco is an offline, on-device AI coding agent for Android. It runs a
quantized 1.5B-parameter model (Qwen2.5-Coder-1.5B-Instruct, Q4_K_M) entirely
locally via a `llama.cpp` Dart bridge, and drives it through a continuous
background Reason/Act/Observe (ReAct) loop — reading and writing files in a
sandboxed workspace, keeping a Markdown "Second Brain", and pinging you with
Android notifications when it needs approval or has finished a task.

No network connection is required at runtime; the model never leaves the
device.

## How it works

- **ReAct loop** (`lib/services/agent_loop_service.dart`) runs inside a
  `flutter_background_service` foreground isolate, so it keeps ticking while
  the app is backgrounded or the screen is off. Each iteration: prompt the
  model → parse `<THOUGHT>/<ACTION>/<PARAMS>` → execute the tool → feed the
  observation back in → wait 10s (spec-mandated, to avoid thermal throttling
  and battery drain) → repeat.
- **Tools** (`lib/services/tool_executor.dart`): `read_file`, `write_file`
  (RISKY), `write_brain`, `search_brain`, `ask_human`, `done`. File tools are
  confined to a single sandboxed workspace directory.
- **Human-in-the-loop** (`lib/services/notification_service.dart`): a RISKY
  tool or `ask_human` pauses the loop and raises a high-priority
  notification — Approve/Deny buttons for risky actions, a text-reply action
  for questions. The loop resumes once you respond from the notification.
- **UI** (`lib/ui/`): a dark, Material 3 terminal-style log of the agent's
  thoughts/actions/observations (rendered as Markdown), a field to assign new
  tasks, and a stop button.

## Getting the model onto the device

The app does not download the model. Get a Q4_K_M-quantized
`Qwen2.5-Coder-1.5B-Instruct` GGUF file from your model source of choice and
push it to the app's external files directory, which requires no root:

```sh
adb push qwen2.5-coder-1.5b-instruct-q4_k_m.gguf \
  /storage/emulated/0/Android/data/com.zexolver.claco/files/models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf
```

The app polls for that exact path (see
`lib/core/agent_constants.dart#modelFileName`); the AppBar shows
Loaded/Unloaded and the home screen shows a banner with the exact expected
path if the file isn't found yet.

## Running

```sh
flutter pub get
flutter run
```

Requires Android SDK 35 / NDK 27, minSdk 26. Grant the notification
permission when prompted — it's how approval requests and completion pings
reach you.

## Project layout

```
lib/
  core/               tuning constants + the exact system prompt
  models/             AgentTool, ReactStep, LogEntry, AgentStatus
  services/
    react_parser.dart        XML tag parsing
    llm_service.dart         llama.cpp bridge (context/threads/temp)
    tool_executor.dart       read/write_file, brain tools
    storage_service.dart     workspace + Second Brain paths
    notification_service.dart  Approve/Deny + reply notifications
    approval_bridge.dart     cross-isolate mailbox for those responses
    agent_loop_service.dart  the ReAct loop itself
    background_service.dart  flutter_background_service wiring
  ui/                 home screen, log view, task input bar
android/              Android embedding (gradle, manifest, MainActivity)
```
