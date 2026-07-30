# Pagai

**Pagai** — Pocket Agentic AI — is an autonomous AI coding agent for
Android that runs entirely on-device via `llama.cpp`. It runs a
quantized Qwen2.5-Coder-1.5B model by default in a background
Reason/Act/Observe loop, can fetch whatever it decides it needs to
finish a task (Claude-Code-style, via its `download_resource` tool),
and pings you on the lock screen when it needs approval for risky
actions or has finished a task.

See `CLAUDE.md` for the full project specification this implementation
follows.

## Architecture

```
lib/
  core/                      Fixed system prompt, tool enum, THOUGHT/ACTION/PARAMS parser, storage keys
  models/                    AgentState, LogEntry, ChatSessionMeta, HfModelSummary/HfGgufFile
  services/
    llama_service.dart       flutter_llama wrapper (2048 ctx, 4 threads, temp 0.15)
    huggingface_service.dart Search Hugging Face, list .gguf files, stream a download
    session_service.dart     CRUD for chats + their per-chat state/log
    settings_service.dart    App-wide toggles (network downloads on/off)
    workspace_service.dart   Sandboxed read_file / write_file
    brain_service.dart       Second Brain (knowledge_graph.md) append/search
    notification_service.dart  Approve/Deny + reply-input notifications
    background_agent_service.dart  The ReAct loop (flutter_background_service)
  ui/
    chat_list_page.dart      Home screen: the list of chats, "+" to start one
    chat_page.dart            One chat's transcript, model chip, input, stop
    model_manager_page.dart  Recommended model + Hugging Face search/download
    settings_page.dart       Network-downloads toggle
    widgets/                 AgentLogView, ApprovalBanner, TaskInputBar
```

### The loop

Each iteration: build a prompt from `CURRENT_TASK` + `WORKSPACE_STATE` +
`LAST_OBSERVATION` → run inference → parse
`<THOUGHT>/<ACTION>/<PARAMS>` → if the action is `write_file` (RISKY) or
`ask_human`, pause and notify; otherwise execute the tool immediately
(including `download_resource`, gated on the Settings network toggle
rather than a per-call approval) → persist state → sleep 10s → repeat.
`done` ends the task and sends a completion notification.

State (`AgentState`, the log, and the approval/reply flags) lives in
`SharedPreferences` because the UI isolate, the background service
isolate, and the notification-action callback isolate share no memory —
it's the IPC layer, polled by whichever side needs to react.

### PARAMS convention for `write_file` and `download_resource`

The spec's system prompt has a single free-text `PARAMS` slot, so
multi-field tools use the first line for one field and the rest for the
other: `write_file` is path, then a newline, then the full file contents
(`ReactResponseParser.splitWriteFileParams`); `download_resource` is a
URL, then an optional second line with the save-as path
(`splitDownloadResourceParams`) — it defaults to the URL's filename.

### Chats

The home screen is a chat list, not one running conversation — tap "+"
to start a new chat, tap a row to open it. Every chat keeps its own
transcript and task independently, but only one chat's agent loop can
actually be running at a time (one on-device model, one background
service); starting a task in a chat while another is busy logs a
message telling you to stop the other one first. A chat currently
running shows a green "Running" chip in the list.

### Settings

The gear icon on the chat list opens Settings, currently just one
toggle: **Allow the agent to download resources**, on by default. It
gates every network call the app makes — the agent's own
`download_resource` tool calls mid-task, and the Model Manager's
Hugging Face search/download. Turn it off if you're fully offline or on
a limited data plan; already-downloaded files keep working either way.

### Getting the model

The chat list shows a banner right at the top whenever the model isn't
loaded yet — "Set up", "Load now", or "Retry" depending on whether it's
never been downloaded, downloaded but not loaded, or failed — so you
don't have to go hunting for the small "Loaded/Unloaded" chip in the app
bar first. Both lead to the **Model Manager**:

- **Recommended**: a one-tap download of the exact model CLAUDE.md
  specifies — `Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF`,
  `qwen2.5-coder-1.5b-instruct-q4_k_m.gguf`.
- **Search Hugging Face**: look up any other repo; only its `.gguf`
  files are ever listed (that's the one format `flutter_llama` can
  load), each downloadable straight into the app's private storage.

Picking or downloading a model loads it immediately — no separate step.
Loading a ~1GB model natively can take anywhere from several seconds to
a couple of minutes depending on the device, and both the banner and the
Model Manager show live elapsed time while it's in progress instead of
a bare spinner, so a slow load doesn't look like a hang.

Both this and the agent's own downloads are behind the same Settings
toggle above. You can still sideload a model file by hand instead (see
`assets/models/README.md`).

## Installing / updating

CI builds and publishes a debug APK to [GitHub Releases](../../releases)
on every push to `main` (or a manual workflow dispatch). Every build gets
its own release — a unique version tag (`v0.1.0-<commit>-<run>`) and an
APK filename that bakes in the release codename and commit hash
(`Pagai-<codename>-0.1.0-<commit>.apk`) — so re-running the workflow, or
reusing a codename like "Dead Dog" for a later build, never overwrites
or collides with a file you already downloaded. The newest release is
always flagged `latest`. All builds share the same checked-in debug
signing key (`android/app/debug.keystore`), so installing a new release
over an old one is a normal in-place update, not a reinstall.

To get automatic update notifications, add this repo to
[Obtainium](https://github.com/ImranR98/Obtainium) as a GitHub source
(`https://github.com/Zexolver/Claco`) — Obtainium tracks the repo's
latest release and prompts you to update whenever a new one is
published, same as it would for an F-Droid or Play Store app.

## Setup

1. Install Flutter (stable channel) and Android SDK/NDK.
2. Copy `android/local.properties.example` to `android/local.properties`
   and fill in your `sdk.dir` / `flutter.sdk`.
3. `flutter pub get && flutter run`, then use the in-app Model Manager
   (above) to fetch a `.gguf` model — or sideload one by hand:
   ```
   adb push qwen2.5-coder-1.5b-instruct-q4_k_m.gguf \
     /sdcard/Android/data/com.pagai.app/files/models/
   ```
   (or `adb shell run-as com.pagai.app` to copy directly into
   app-private storage if external storage isn't accessible on your
   device).

## Notes / known limitations

- `flutter_llama`'s Android build needs a real device or an x86_64
  emulator with several GB of RAM free; a 1.5B Q4_K_M model is roughly
  1GB and CPU-only inference at 2048 ctx will be slow on low-end phones.
- This was built and code-reviewed without a Flutter SDK available in
  the authoring sandbox; run `flutter pub get && flutter analyze` after
  cloning to catch any dependency-version drift before shipping.
