# maquette

Drop a photo, get a sculpted 3D model. A Mac-native BYOK client that industrializes
the img2threejs idea (MIT, credited): a coder LLM writes procedural Three.js geometry
from the photo, a built-in WKWebView renderer screenshots it, a vision LLM scores it
against the photo, and the loop iterates to a threshold. Then GLB + USDZ export.

- Task home: YouTrack project IMG3D, epic IMG3D-10.
- Sibling repo `../depthcard` provides DepthCardKit (subject lift, OBJ->USDZ export)
  as a local SwiftPM dependency. depthcard stays the relief pipeline; maquette is the
  LLM sculpt client. Do not merge them.
- Idea source for prompts and gates: `../img2threejs/` (SKILL.md + references/).

## Architecture (v1)

photo -> subject lift (DepthCardKit, on-device)
      -> analyze + spec (coder slot) -> Three.js factory code (coder slot)
      -> render + screenshots (bundled three.js in WKWebView, fixed viewpoints)
      -> comparison sheet -> score + critique (vision slot) -> loop (cap 4-6 cycles)
      -> GLB (three.js exporter) + USDZ (DepthCardKit path) -> AR Quick Look

## Hard rules

- BYOK: keys live in the Keychain only (MaquetteKit/Keychain.swift). Never in
  UserDefaults, files, or logs.
- Model-agnostic: two slots (coder, vision), any OpenAI-compatible endpoint.
  Defaults: api.moonshot.ai/v1 + kimi-k2.5 (multimodal - one model fills both slots).
- The WKWebView page must be fully offline: bundle three.js, no CDN loads.
- v1 scope: objects only (no character/anatomy track). Relief instant-preview is
  v1.1, not v1.
- No new geometry features before the repo is public (user directive 2026-07-20).

## Build and test

- Build: `swift build 2>&1 | tail -20`
- Tests: `swift test 2>&1 | tail -20`
- Run app: background Bash `swift run MaquetteApp > <scratchpad>/app.log 2>&1`

## Phases (IMG3D-10)

1. DONE-when-merged: scaffold, ChatClient (SSE streaming, multimodal), Keychain,
   settings UI with per-slot test connection.
2. Render harness: bundled three.js page, factory-code injection, snapshot capture,
   comparison sheet compositing.
3. The loop: 3-stage prompt pack (analyze+spec, codegen, review+score) + controller.
4. Export + UX: GLB/USDZ, drop zone with live cycle progression.
5. Benchmarks (chest, earbuds, portrait) + launch prep (README, GIF, showcase/).
