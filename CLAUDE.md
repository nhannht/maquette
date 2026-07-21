# maquette

Drop a photo, get a sculpted 3D model. A Mac-native BYOK client that industrializes
the img2threejs idea (MIT, credited): a coder LLM writes procedural Three.js geometry
from the photo, a built-in WKWebView renderer screenshots it, a vision LLM scores it
against the photo, and the loop iterates to a threshold. Then GLB + USDZ export.

- Task home: YouTrack project IMG3D, epic IMG3D-10.
- Zero package dependencies: subject lift is vendored in
  `MaquetteKit/SubjectLift.swift` (Apple Vision foreground mask, on-device).
  Sibling `../depthcard` is the separate relief pipeline; do not merge them.
- Idea source for prompts and gates: `../img2threejs/` (SKILL.md + references/).

## Architecture (v1)

photo(s) -> subject lift per view (DepthCardKit, on-device)
         (ReferenceSet: 1 primary + up to 3 extra views of the SAME object,
          labels optional - References.swift)
      -> recognize: suggested plain-language build brief (vision slot)
         [GATE 1 - the input gate: user edits the brief AND the reference set
          (add/remove/relabel/re-prime); intent beyond the photo enters here]
      -> spec JSON compiled from photo(s) + brief (vision slot, internal)
      -> Three.js factory code (coder slot; fresh builds attach the reference
         photos when coderSeesRenders is on, spec stays authoritative)
      -> render + screenshots (bundled three.js in WKWebView, fixed viewpoints)
      -> comparison sheet (primary hero + labeled REF strip)
      -> score + critique (vision slot) -> pairwise gate
         [GATE 2: suggested next instruction, user edits or continues; can also
          edit references - subjects re-lift, spec recompiles keeping the
          incumbent, all stored sheets rebuild from disk renders; skipped
          when the run is ending or Settings > Auto-continue is on]
      -> loop (cap 5 cycles)
      -> GLB + USDZ (three.js exporter addons in the WKWebView) -> AR Quick Look

Every cycle exports cycle-N/model.usdz; the app's result column embeds a
SceneKit viewer with a Sheet|3D toggle - click any cycle card to inspect that
cycle's model (selection follows the run when untouched).

The judge receives the spec: parts the brief adds beyond the photo (interior,
open state) are scored against the spec, never punished against the photo.

## Hard rules

- BYOK: keys live in the Keychain only (MaquetteKit/Keychain.swift). Never in
  UserDefaults, files, or logs.
- Model-agnostic: two slots (coder, vision), any OpenAI-compatible endpoint.
  Defaults: api.moonshot.ai/v1 + kimi-k2.5 (multimodal - one model fills both slots).
- The WKWebView page must be fully offline: bundle three.js, no CDN loads.
- v1 scope: objects only (no character/anatomy track). Relief instant-preview is
  v1.1, not v1.
- No new geometry features before the repo is public (user directive 2026-07-20).

## Design (source of truth: design/maquette.sketch)

The app icon design lives in `design/maquette.sketch` - that file is the design
source of truth; keep this structure map in sync with structural changes.

- Page "App Icon"
  - Frame "Icon/Default 1024" (done): source artwork + light preview
- Concept: a photo card holding a flat pale hexagon subject, with the same
  subject popping out front as a low-poly terracotta gem (photo -> 3D story).
- Final icon pipeline: Apple Icon Composer. It generates dark/tinted variants
  from the layered source art, so the Sketch file carries NO dark variant -
  only the source glyph layers (Photo Card group, Gem group) and a light
  composite preview. The squircle background in the frame is preview-only;
  Icon Composer supplies the real background.
- Components: `App Icons/Custom/Default` from the Apple macOS 27 UI Kit is kept
  in the frame as a hidden icon-grid alignment template. The kit ships no blank
  squircle-background component (its Custom symbol is only the grid bitmap), so
  the preview squircle is hand-built: 1024 rounded rect, radius 232.
- Palette: terracotta facets #E8A075/#D97E52/#C96F4A/#A34F31/#8F4227, gold
  highlight facet #E9B564 (brand gold), photo blues #AFC6DA->#6E8CA8, flat
  subject #D3E0EB, card white #FBFAF7; preview squircle #F8F8FA->#E7E7ED.
- Final icon home: `design/icon-composer.icon/` (Icon Composer project).
  Assets/Gem.svg + Assets/Photo Card.svg are the glyph groups exported from
  the Sketch frame; icon.json layers the Gem (glass on) over the Photo Card
  on an extended-gray gradient fill. After any glyph edit in Sketch,
  re-export both groups as SVG into Assets/ with the same filenames.
- `design/icon-default-1024.png` is the composite marketing preview only.

## Build and test

- Build: `./build.sh 2>&1 | tail -20` - builds AND signs both executables with
  the Apple Development cert. Plain `swift build` leaves ad-hoc signatures whose
  identity changes every rebuild, so Keychain "Always Allow" never sticks and
  key prompts return on every launch. Always build via the script.
- Tests: `swift test 2>&1 | tail -20`
- Run app: background Bash `.build/debug/MaquetteApp > <scratchpad>/app.log 2>&1`

## Phases (IMG3D-10)

1. DONE: scaffold, ChatClient (SSE streaming, multimodal), Keychain,
   settings UI with per-slot test connection.
2. DONE: render harness - bundled three.js r185 (min builds served via custom
   maquette:// scheme, no file:// quirks), offscreen-window WKWebView snapshots,
   comparison sheet compositing.
3. DONE: the loop - 3-stage prompt pack (SculptPrompts) + SculptLoop controller +
   headless maquette-cli (set-key/render-test/sculpt). Validated on OpenRouter
   2026-07-20 (IMG3D-11): earbuds ACCEPTED 0.78 in 1 cycle at ~$0.002 with
   qwen3-coder + qwen3-vl-30b; chest missed threshold on an adversarial
   two-object screenshot reference. Whole validation under $0.10. Known gaps:
   reasoning models crash ChatClient (IMG3D-12), multi-object references confuse
   the loop (IMG3D-13), judge calibration varies by VLM tier.
4. DONE: export + UX. GLB + USDZ from the bundled three.js r185 exporter
   addons inside the WKWebView (GLTFExporter + USDZExporter + fflate, NOT
   DepthCardKit's texture-flattening path); runs keep and export the
   best-scoring cycle, not the last. Reasoning models fixed (IMG3D-12):
   ChatClient caps reasoning via OpenRouter reasoning.max_tokens, truncation
   is a first-class error, and non-code responses throw instead of reaching
   new Function - gemini-3.1-pro-preview earbuds ACCEPTED 0.78 in 1 cycle.
   App UI: drop zone, live per-cycle cards (score, action, critique,
   comparison sheet), SceneKit preview of the USDZ, Quick Look. Run
   artifacts land in ~/Library/Application Support/Maquette/runs/.
5. Benchmarks (clean single-object photo set + portrait) + launch prep
   (README, GIF, showcase/).
