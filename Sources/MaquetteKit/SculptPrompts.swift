import Foundation

// The 3-stage prompt pack, distilled from img2threejs (MIT) references:
// pre-spec-assessment + detail-inventory -> spec prompt, procedural-patterns ->
// codegen prompt, self-correction-loop + browser-screenshot-feedback -> review
// prompt. One prompt per stage instead of the original 15-script pipeline.

public enum SculptPrompts {

    // MARK: - Stage 0: recognize (vision slot)

    // The human-facing document: a short plain-language brief the user
    // confirms or edits before any coder token is spent. The spec JSON stays
    // internal machinery compiled from photo + brief.

    public static let briefTemperature = 0.3
    /// Stage ceilings are shared by thinking and answer on most providers
    /// (Moonshot documents max_tokens >= 16000 for K2.5). Thinking is
    /// uncapped by default, so every LLM stage gets 16384 of headroom;
    /// only tokens actually spent are billed.
    public static let briefMaxTokens = 16384

    public static let briefSystem = """
    You look at one or more photos of a single object - every photo shows the \
    SAME object, the first is the primary view - and write a build brief for a \
    procedural 3D modeler: 2 to 4 plain sentences naming the object and its \
    identity-defining shape, parts, proportions, colors, and materials. \
    Describe only what is visible. Respond with ONLY the brief text - no \
    markdown, no JSON, no preamble.
    """

    public static func briefUser(extraViews: [String?] = []) -> String {
        guard !extraViews.isEmpty else {
            return "Write the build brief for this object photo."
        }
        return "Write the build brief for this object. All \(extraViews.count + 1) "
            + "attached photos show the SAME object - the first is the primary "
            + "view, \(viewList(extraViews))."
    }

    /// "photo 2: back, photo 3: another view" - the user's per-view labels,
    /// resolved so every extra photo is explicitly tied to the same object.
    static func viewList(_ labels: [String?]) -> String {
        labels.enumerated().map { index, label in
            "photo \(index + 2): \(label ?? "another view")"
        }.joined(separator: ", ")
    }

    // MARK: - Stage 1: analyze + spec (vision slot)

    public static let specTemperature = 0.3
    public static let specMaxTokens = 16384

    public static let specSystem = """
    You are a 3D reconstruction analyst. You receive one or more photos of a \
    single object - every photo shows the SAME object, the first is the primary \
    view - and produce one compact build spec for a procedural three.js modeler.

    Respond with ONLY a JSON object, no prose, no markdown fences, with fields:
    - "object": one line naming the object and its identity-defining traits.
    - "overallProportions": {"width", "height", "depth"} relative numbers, largest = 1.0.
    - "components": array ordered macro to micro. Each: {"name", "primitive" \
    (box|sphere|cylinder|cone|capsule|torus|lathe|extrude|tube|instanced|plane), \
    "relativeSize", "position", "orientation", "material": {"baseColor" (hex), \
    "roughness" 0-1, "metalness" 0-1, "notes"}}. Include every visible sub-assembly; \
    repeated small parts (rivets, buttons, teeth) become one instanced component.
    - "criticalFeatures": 3 to 5 named identity-defining subsystems a reviewer must \
    check (e.g. "curved lid profile", "metal clasp", "corner trim straps").
    - "hints": camera angle of the photo, symmetry, and anything the hidden side \
    must mirror.

    Be concrete with proportions: measure against the photo, do not idealize. \
    If a side is hidden, infer it from symmetry and say so in hints.
    """

    public static func specUser(critique: String?, previousSpec: String?,
                                brief: String? = nil,
                                extraViews: [String?] = []) -> String {
        var text = extraViews.isEmpty
            ? "Analyze this object photo and produce the build spec JSON."
            : "Analyze these \(extraViews.count + 1) photos - all the SAME "
              + "object, the first is the primary view, \(viewList(extraViews)) "
              + "- and produce one build spec JSON for that single object."
        if let brief, !brief.isEmpty {
            text += """
            \n\nBUILD BRIEF - approved by the user, authoritative. Where it goes \
            beyond what the photo can show (interior, open state, hidden side), \
            follow the brief: translate those parts into concrete components with \
            sizes and positions, and note in "hints" that they come from the brief:
            \(brief)
            """
        }
        if let previousSpec, let critique {
            text += """
            \n\nA previous spec produced a rejected model. Revise the spec to fix the critique.
            PREVIOUS SPEC:\n\(previousSpec)
            REVIEWER CRITIQUE:\n\(critique)
            """
        }
        return text
    }

    // MARK: - Stage 2: codegen (coder slot)

    public static let codegenTemperature = 0.4
    /// Shared budget for reasoning + code. Thinking is uncapped by default
    /// (and a user thinkingCap is advisory upstream anyway - Gemini overshoots
    /// ~4x), so the total must absorb heavy thinking and still leave room for
    /// a full factory (~3k tokens); truncation retries double it.
    public static let codegenMaxTokens = 16384

    public static let codegenSystem = """
    You are a senior three.js procedural modeler (three r185). You receive a build \
    spec JSON and write JavaScript that constructs the object.

    Respond with ONLY JavaScript code (a single ```javascript fence is allowed) that \
    defines exactly:

        function buildModel(THREE) {
          // build and return a THREE.Group
        }

    Hard rules:
    - Core three.js API only. No imports, no await, no fetch, no texture or asset \
    loading, no scene/camera/lights/renderer - geometry and materials only.
    - MeshStandardMaterial everywhere; set color, roughness, metalness, flatShading \
    per the spec.
    - Unit scale: the largest overall dimension is about 1.0. Center the model at \
    the origin, y up, and the photo's visible face looks toward +z.
    - Build EVERY component in the spec. Compose primitives: BoxGeometry, Sphere, \
    Cylinder, Cone, Capsule, Torus, LatheGeometry, ExtrudeGeometry with Shape, \
    TubeGeometry along curves, InstancedMesh for repeated parts.
    - Curved identity-defining profiles use LatheGeometry or ExtrudeGeometry with \
    real curve points, not stretched boxes.
    - Enough radial/height segments that curves read smooth at 768px.
    - Small local features that define identity (seams, straps, clasps, grooves) \
    are real geometry, not implied.
    """

    public static func codegenUser(spec: String, previousCode: String?,
                                   critique: String?, jsError: String?,
                                   incumbentScore: Double? = nil,
                                   layerScores: [String: Double]? = nil,
                                   rendersAttached: Bool = false,
                                   referencesAttached: Bool = false,
                                   regressed: Bool = false) -> String {
        var text = "SPEC:\n\(spec)"
        if let previousCode {
            if let incumbentScore {
                var header = "BEST CODE SO FAR (reviewer score "
                    + String(format: "%.2f", incumbentScore)
                if let layerScores, !layerScores.isEmpty {
                    header += "; " + layerScores.sorted { $0.key < $1.key }
                        .map { "\($0.key) \(String(format: "%.2f", $0.value))" }
                        .joined(separator: ", ")
                }
                text += "\n\n\(header)):\n\(previousCode)"
            } else {
                text += "\n\nPREVIOUS CODE:\n\(previousCode)"
            }
        }
        if rendersAttached {
            text += """
            \n\nThe attached image shows the reference photo beside four renders of \
            the best code. Compare them yourself and fix what visibly differs.
            """
        }
        if referencesAttached {
            text += """
            \n\nThe attached image(s) are the reference photo(s) the spec was \
            written from - all views of the same object. Use them for the \
            proportions and details the spec compresses away. The SPEC remains \
            authoritative: where the photos and the spec conflict, follow the spec.
            """
        }
        if let jsError {
            text += """
            \n\nYOUR CODE CRASHED. Fix the error and return the complete corrected code.
            ERROR:\n\(jsError)
            """
        } else if let critique {
            text += """
            \n\nA vision reviewer compared the last render against the reference photo. \
            Return the complete improved code fixing every point.
            CRITIQUE:\n\(critique)
            """
            if regressed {
                text += """
                \n\nYour latest attempt was judged WORSE than the best code above and \
                was discarded. Start from the best code and take a different approach \
                to the critique than the discarded attempt.
                """
            }
        }
        return text
    }

    // MARK: - Stage 3: review (vision slot)

    public static let reviewTemperature = 0.2
    public static let reviewMaxTokens = 16384

    public static let reviewSystem = """
    You are a strict 3D visual QA judge. You receive one comparison sheet: the \
    REFERENCE photo on the left (smaller REF panels below it, when present, are \
    further views of the SAME object - use them to check hidden sides), four \
    labeled renders of a procedural model on the \
    right (front, threeQuarter, side, top). You also receive the build SPEC JSON: \
    the spec is the authoritative target and the photo is its visual reference. \
    Where the spec deliberately goes beyond what the photo can show (interior \
    parts, an open state, the hidden side), score those parts against the spec - \
    never punish the model for depicting them.

    Score layers 0 to 1 against the reference:
    - "silhouetteProportion": outer contour, mass distribution, width/height/depth.
    - "componentStructure": every visible sub-assembly present, placed, attached.
    - "formDetail": curvature, tapers, bevels, grooves, local geometry.
    - "materialSurface": albedo zones, roughness/metalness read, color match.

    Anchors: 0.2 rough placeholder, 0.4 silhouette recognizable, 0.6 macro and meso \
    forms correct, 0.75 object reads correctly with approximate detail, 0.85 strong \
    match. Do not hide a failed critical layer inside a high average.

    Respond with ONLY a JSON object, no prose, no markdown fences:
    {"overallScore": number, "layerScores": {"silhouetteProportion": n, \
    "componentStructure": n, "formDetail": n, "materialSurface": n}, \
    "critique": "concrete mismatches and the fix for each, in 3D modeling terms", \
    "action": "continue|refine-code|refine-spec|stop"}

    Action guide: "refine-code" when the spec is right but geometry/materials miss \
    it; "refine-spec" when a component is missing, invented, or misproportioned in \
    the spec itself; "stop" only when more cycles cannot help; "continue" when the \
    model already meets the bar.
    """

    public static func reviewUser(spec: String) -> String {
        """
        Left: reference photo(s) of one object. Right: four renders of the current \
        procedural model. Score it and return the JSON verdict.

        SPEC:
        \(spec)
        """
    }

    // MARK: - Stage 4: pairwise gate (vision slot)

    // Absolute VLM scores drift +/-0.1 between identical runs; head-to-head
    // comparison is far more stable, so the incumbent model is only replaced
    // by a challenger that wins this call.

    public static let pairwiseTemperature = 0.1
    public static let pairwiseMaxTokens = 16384

    public static let pairwiseSystem = """
    You are a strict 3D visual QA judge. You receive two comparison sheets for \
    the SAME reference set. Each sheet shows the reference photo(s) of one \
    object on the left \
    and four labeled renders of a procedural model on the right. The first image \
    is model A, the second image is model B. You also receive the build SPEC \
    JSON both models target: the spec is authoritative, and where it deliberately \
    goes beyond what the photo can show (interior parts, an open state, the \
    hidden side), fidelity to the spec wins - never count those parts against a \
    model.

    Decide which model matches the target better overall, weighing silhouette \
    and proportions, component structure, form detail, and materials.

    Respond with ONLY a JSON object, no prose, no markdown fences:
    {"winner": "A" or "B", "reason": "one concrete sentence"}
    """

    public static func pairwiseUser(spec: String) -> String {
        """
        First image: model A. Second image: model B. Same reference set in both. \
        Which model matches the target better? Return the JSON verdict.

        SPEC:
        \(spec)
        """
    }
}
