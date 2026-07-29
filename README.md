# Pocket Agent

An autonomous, fully offline AI coding agent for Android. It runs a
quantized Qwen2.5-Coder-1.5B model on-device via `llama.cpp`, in a
background Reason/Act/Observe loop, and pings you on the lock screen when
it needs approval for risky actions or has finished a task.

See `CLAUDE.md` for the full project specification this implementation
follows.

## Architecture

```
lib/
  core/                      Fixed system prompt, tool enum, THOUGHT/ACTION/PARAMS parser, storage keys
  models/                    AgentState, LogEntry
  services/
    llama_service.dart       flutter_llama wrapper (2048 ctx, 4 threads, temp 0.15)
    workspace_service.dart   Sandboxed read_file / write_file
    brain_service.dart       Second Brain (knowledge_graph.md) append/search
    notification_service.dart  Approve/Deny + reply-input notifications
    background_agent_service.dart  The ReAct loop (flutter_background_service)
  ui/
    home_page.dart           App bar (model status), transcript, input, stop
    widgets/                 AgentLogView, ApprovalBanner, TaskInputBar
```

### The loop

Each iteration: build a prompt from `CURRENT_TASK` + `WORKSPACE_STATE` +
`LAST_OBSERVATION` → run inference → parse
`<THOUGHT>/<ACTION>/<PARAMS>` → if the action is `write_file` (RISKY) or
`ask_human`, pause and notify; otherwise execute the tool immediately →
persist state → sleep 10s → repeat. `done` ends the loop and sends a
completion notification.

State (`AgentState`, the log, and the approval/reply flags) lives in
`SharedPreferences` because the UI isolate, the background service
isolate, and the notification-action callback isolate share no memory —
it's the IPC layer, polled by whichever side needs to react.

### PARAMS convention for `write_file`

The spec's system prompt has a single free-text `PARAMS` slot, so
`write_file` uses: first line = file path, everything after the first
newline = file contents (see `ReactResponseParser.splitWriteFileParams`).

## Setup

1. Install Flutter (stable channel) and Android SDK/NDK.
2. Copy `android/local.properties.example` to `android/local.properties`
   and fill in your `sdk.dir` / `flutter.sdk`.
3. Get the model weights (not committed — see `assets/models/README.md`):
   `Qwen2.5-Coder-1.5B-Instruct`, `Q4_K_M` GGUF quantization.
4. Install the app once (`flutter run`), then push the model into its
   private storage:
   ```
   adb push qwen2.5-coder-1.5b-instruct-q4_k_m.gguf \
     /sdcard/Android/data/com.pocketagent.app/files/models/
   ```
   (or use `adb shell run-as com.pocketagent.app` to copy directly into
   app-private storage if external storage isn't accessible on your
   device).
5. `flutter pub get && flutter run`.

## Notes / known limitations

- `flutter_llama`'s Android build needs a real device or an x86_64
  emulator with several GB of RAM free; a 1.5B Q4_K_M model is roughly
  1GB and CPU-only inference at 2048 ctx will be slow on low-end phones.
- This was built and code-reviewed without a Flutter SDK available in
  the authoring sandbox; run `flutter pub get && flutter analyze` after
  cloning to catch any dependency-version drift before shipping.
