# Model directory

Place `qwen2.5-coder-1.5b-instruct-q4_k_m.gguf` in this directory before
building, or let the app download it into app-private storage on first run
(see `lib/services/llama_service.dart`). The `.gguf` file itself is
git-ignored — it is a multi-hundred-megabyte binary and must not be
committed to the repository.

Recommended source: the `Qwen2.5-Coder-1.5B-Instruct-GGUF` repository on
Hugging Face, `Q4_K_M` quantization.
