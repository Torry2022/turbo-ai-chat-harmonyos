# AGENTS.md

This file is for AI coding agents working on Turbo AI Chat. It records project-specific rules that are easy to forget during automated edits.

## Project Context

Turbo AI Chat is a HarmonyOS NEXT native local AI chat app.

Current core stack:

- ArkTS / ArkUI frontend.
- HarmonyOS Node-API bridge.
- C++ native inference layer.
- MNN Runtime for local LLM / multimodal inference.
- Local model management, model market download, model import, streaming chat, Markdown rendering, thinking-block rendering, image input, and runtime monitoring.

The main inference path is:

```text
ArkTS UI
-> Native service / Node-API
-> C++ runner
-> MNN Runtime
-> CPU backend
-> local MNN model directory
```

Do not describe the app as cloud AI or assume server-side inference unless the user explicitly changes the architecture.

## High-Risk Files And Directories

- `build-profile.json5`
  - May contain local signing configuration.
  - Do not commit signing credentials by default.
  - If the user explicitly asks to commit it, verify that the included signing data is intended for the repository.

- `models/`
  - Contains large local model directories.
  - Model weights should not be committed unless the user explicitly requests it.
  - Keep `.gitignore` behavior in mind before adding anything under this directory.

- `entry/src/main/cpp/`
  - Native inference, image path, streaming callback, stop handling, token stats, and raw output debug logic live here.
  - Small changes can affect all models. Avoid speculative rewrites.

- `entry/src/main/ets/`
  - App state, tabs, model management, Markdown rendering, download flow, monitoring UI, and chat orchestration live here.
  - ArkTS reactivity is sensitive. Avoid changing decorators, state ownership, or render keys unless directly required.

- `README.md` and `README_EN.md`
  - Keep both files aligned when changing user-facing setup, model download, model import, release, or runtime behavior.

## Model Handling Rules

- Built-in and downloaded models are expected to be MNN model directories, not single `.mnn` files.
- A valid model directory normally includes `llm_config.json` and the files referenced by that config.
- Prefer using the model directory's own `llm_config.json` / chat template behavior instead of hardcoding prompt templates in ArkTS.
- Do not casually change stop-word handling, prompt formatting, thinking-block parsing, or streaming post-processing. These affect Gemma, Qwen, MiniCPM, DeepSeek, and user-imported models differently.
- Imported models may come from a pushed MNN directory or a zip import flow. Large zip imports can be fragile; README instructions should distinguish zip import from manual directory push.
- If a model is not installed or its directory is incomplete, UI should guide the user to install/download/scan rather than silently failing.

## Development Rules

- Keep changes surgical. Do not refactor adjacent code unless needed for the requested task.
- Prefer existing project patterns over new abstractions.
- For HarmonyOS work, prefer DevEco/ArkTS checks through the available MCP or DevEco tooling.
- After editing `.ets` or C/C++ files, run the relevant syntax check when practical:
  - ArkTS files: `mcp__deveco_mcp.check`
  - C/C++ files: `mcp__deveco_mcp.check`
- If building or installing is required, use the project's DevEco/HarmonyOS workflow. The user often tests on a real device.
- Do not assume the app should auto-load a model on startup; current behavior may intentionally show a load dialog without auto-loading for easier debugging.

## Git Rules

- Do not revert user changes.
- Do not run destructive Git commands unless the user explicitly asks.
- `build-profile.json5`, `.npmrc`, `AGENTS.md`, generated HAPs, logs, layout dumps, and temporary scripts require extra care before staging.
- When the user asks for a feature/fix/refactor commit, follow the established pattern:
  - create an appropriate branch such as `feature/...`, `fix/...`, or `refactor/...`;
  - commit there with a clear subject and body when useful;
  - merge back to `main` when requested;
  - push only when requested.
- If README changes are related to the code change, include both `README.md` and `README_EN.md`.

## Documentation And Release Notes

- User-facing changes that affect setup, model installation, model market, import flow, signing, HAP packaging, or device testing should be documented.
- Every GitHub Release that distributes a HAP must also provide a ZIP containing that HAP together with the `LICENSE` and `NOTICE` files from the tagged commit. Do not leave a bare HAP as the only binary download. This is a release-packaging requirement and does not by itself require an app code change, version bump, new commit, or new tag; an existing Release may be supplemented with the compliant ZIP asset.
- Every version bump or release tag must leave a local-only `docs/archive/vX.Y.Z相对vA.B.C变更说明.md` document for drafting the GitHub Release. Keep it ignored and do not stage, commit, or push it unless the user explicitly requests otherwise.
- Other release helper documents belong under `docs/archive/` only when the user asks for them. Do not commit temporary release notes unless requested.
- The study log skill writes learning logs, not release notes. Keep those concepts separate.

## Issue Tracker

Issues and PRDs, when needed, should be created in the user's fork:

```text
https://github.com/Torry2022/turbo-ai-chat-harmonyos.git
```

The original upstream repository is:

```text
https://github.com/Turbo1123/turbo-ai-chat-harmonyos.git
```

Do not create, edit, label, comment on, or close issues in the upstream repository unless the user explicitly asks for that target and confirms write permissions.

If GitHub authentication is unavailable, draft the issue or PRD content locally instead of pretending it was published.
