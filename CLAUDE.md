# Project Specification: Pagai (Pocket Agentic AI) for Android

## 1. Project Overview
The objective is to build a Flutter application for Android — **Pagai** (Pocket Agentic AI) — that functions as an autonomous, on-device AI coding agent (similar to a localized, offline version of Claude Code, but not Claude). The app must utilize a quantized 1.5 Billion parameter model (Qwen 2.5 Coder 1.5B) running completely offline via a `llama.cpp` Dart bridge. The agent itself may reach the network only to fetch resources it decides it needs to complete a task (or a replacement model), gated by a user-controlled Settings toggle for offline/limited-data use — inference and the ReAct loop stay fully on-device either way.

The agent should operate in a continuous background ReAct (Reason/Act/Observe) loop, autonomously executing tool calls, managing its own "Second Brain" memory, and pinging the user via Android lock screen notifications when it requires approval for risky actions or has completed a task.

## 2. Core Architecture & Tech Stack
*   **Framework:** Flutter (Dart) utilizing Material 3 design (Dark mode preferred).
*   **LLM Inference:** `llama_flutter_android` (or `flutter_llama`) to run `.gguf` models directly on the Android CPU using C++ bindings.
*   **Background Execution:** `flutter_background_service` to maintain the autonomous isolate loop while the app is backgrounded or the screen is off.
*   **Notifications:** `flutter_local_notifications` to push approval requests to the user.
*   **Storage/Memory:** Local device storage (`path_provider`) to manage the model file and the agent's Markdown-based "Second Brain".

## 3. The Model
*   **Recommended Model:** `Qwen2.5-Coder-1.5B-Instruct`
*   **Format:** `.gguf` (Specifically `Q4_K_M` quantization)
*   **Configuration:** Constrain context window to 2048 tokens and use ~4 threads (optimized for mobile ARM cores). Keep temperature low (0.1 - 0.2) to maintain strict formatting.

## 4. Feature Requirements

### 4.1 The ReAct Loop (Background Service)
The core of the app is a background isolate that runs a continuous loop.
1.  **State Management:** The loop must track `current_task`, `workspace_state`, and `is_waiting_for_approval`.
2.  **Prompt Construction:** The loop feeds the LLM a rigid system prompt enforcing XML-based tool calling.
3.  **Parsing:** The loop must parse the LLM's streaming response for the following XML tags:
    *   `<THOUGHT>`: The agent's reasoning.
    *   `<ACTION>`: The tool to execute.
    *   `<PARAMS>`: The arguments for the tool.
4.  **Execution & Loop Delay:** To prevent thermal throttling and extreme battery drain, the loop MUST enforce an artificial delay (e.g., 10 seconds) between each iteration.

### 4.2 Tool Specifications
The agent must have access to the following actions:
*   `read_file`: Reads a file from the local workspace.
*   `write_file`: Writes/overwrites a file in the workspace. (Flagged as RISKY).
*   `write_brain`: Appends a markdown entry to the "Second Brain" file (e.g., `knowledge_graph.md`).
*   `search_brain`: Performs a simple text search against the "Second Brain" file to retrieve context.
*   `download_resource`: Fetches a URL (a library, dataset, reference doc, etc.) and saves it into the workspace — this is what lets the agent get whatever it needs to reach the desired outcome, Claude-Code-style. Gated by a Settings toggle ("Allow the agent to download resources"), on by default; when off, the tool returns an error instead of pausing for approval, so a fully-offline or limited-data user only has to flip one switch, not approve every fetch.
*   `ask_human`: Pauses the loop and prompts the user for clarification.
*   `done`: Terminates the loop and sends a completion notification.

### 4.3 Human-in-the-Loop (Notifications)
*   If the agent selects a tool flagged as "RISKY" (like overwriting a file) or selects `ask_human`, the loop must pause.
*   The app must trigger a high-priority Android system notification.
*   The notification should have actionable buttons (e.g., "Approve", "Deny").
*   The loop only resumes once the user interacts with the notification.

### 4.4 The User Interface
*   **Chats:** The home screen is a list of chats (Claude-mobile-app style), not a single running conversation — each chat keeps its own independent task/transcript, though only one chat's agent loop runs at a time.
*   **App Bar:** Displays model loading status (Loaded/Unloaded).
*   **Main View:** A chat-like or terminal-like UI to display the agent's current thoughts and actions (using `flutter_markdown` for rendering).
*   **Input:** A text field to assign new tasks to the agent.
*   **Controls:** A button to forcefully stop the background agent loop.
*   **Settings:** A screen with a toggle controlling whether the agent (and the Model Manager) may reach the network to download resources.

## 5. Specific Implementation Instructions (For Claude Code)

### Prompt Engineering constraint
Since this is a 1.5B model, do not use complex JSON schemas for tool calling. Use the following exact system prompt structure:
```text
<|im_start|>system
You are a background AI coding agent running on an Android device. 
Your goal is to complete the user's task. You have access to a "Second Brain" directory to store and retrieve knowledge.

You MUST respond ONLY in the following format:
<THOUGHT>Explain what you need to do next</THOUGHT>
<ACTION>Choose ONE: read_file, write_file, search_brain, write_brain, download_resource, ask_human, done</ACTION>
<PARAMS>The file path, search query, or text to write</PARAMS>
<|im_end|>