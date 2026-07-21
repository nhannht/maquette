interface Node {
  key: string;
  title: string;
  desc: string;
  tag?: string;
  tagKind?: "gate" | "coder" | "vision" | "offline" | "auto";
  icon: React.ReactNode;
}

const I = {
  photo: (
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <rect x="3" y="5" width="18" height="14" rx="2.5" fill="none" stroke="currentColor" strokeWidth="1.7" />
      <circle cx="9" cy="10" r="1.6" fill="currentColor" />
      <path d="M4 17l5-4 4 3 3-2 4 3" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" />
    </svg>
  ),
  lift: (
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <path d="M12 3v10m0 0l-3.2-3.2M12 13l3.2-3.2" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M4 15v3a2 2 0 002 2h12a2 2 0 002-2v-3" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  ),
  gate: (
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <path d="M12 3l2.4 4.9 5.4.8-3.9 3.8.9 5.4L12 16.9 7.1 18.7l.9-5.4L4.1 8.5l5.4-.8z" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
    </svg>
  ),
  spec: (
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <path d="M6 3h8l4 4v14H6z" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" />
      <path d="M9 12h6M9 15.5h6M9 8.5h3" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  ),
  code: (
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <path d="M9 8l-4 4 4 4M15 8l4 4-4 4" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  ),
  render: (
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
      <path d="M4 7.5l8 4.5 8-4.5M12 12v9" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
    </svg>
  ),
  judge: (
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" strokeWidth="1.6" />
      <path d="M8.5 12.5l2.5 2.5 4.5-5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  ),
  export: (
    <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
      <path d="M12 15V4m0 0L8.5 7.5M12 4l3.5 3.5" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M5 13v5a2 2 0 002 2h10a2 2 0 002-2v-5" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  ),
};

const PRE: Node[] = [
  { key: "photo", title: "Drop a photo", desc: "One clean shot of one object.", icon: I.photo },
  {
    key: "lift",
    title: "Subject lift",
    desc: "Apple Vision masks the foreground on-device - no upload.",
    tag: "On-device",
    tagKind: "offline",
    icon: I.lift,
  },
  {
    key: "gate1",
    title: "Gate 1 - the build brief",
    desc: 'You edit or accept a plain-language brief. Intent beyond the photo enters here ("the box opens, earbuds inside").',
    tag: "You",
    tagKind: "gate",
    icon: I.gate,
  },
  {
    key: "spec",
    title: "Spec compiled",
    desc: "Photo plus brief become a structured spec the judge scores against.",
    tag: "Vision slot",
    tagKind: "vision",
    icon: I.spec,
  },
];

const LOOP: Node[] = [
  {
    key: "code",
    title: "Coder writes geometry",
    desc: "The coder model emits procedural Three.js factory code from the spec.",
    tag: "Coder slot",
    tagKind: "coder",
    icon: I.code,
  },
  {
    key: "render",
    title: "Render 4 angles",
    desc: "A bundled, offline Three.js renderer screenshots the model. Zero network requests.",
    tag: "Offline",
    tagKind: "offline",
    icon: I.render,
  },
  {
    key: "judge",
    title: "Gate 2 - score, critique, gate",
    desc: "The vision model scores the renders, writes the next instruction, and pairwise-gates the challenger. You edit it or hit autopilot.",
    tag: "Vision slot + You",
    tagKind: "vision",
    icon: I.judge,
  },
];

const POST: Node[] = [
  {
    key: "export",
    title: "Best cycle exports",
    desc: "The best-scoring cycle becomes model.glb and model.usdz - ready for Blender, Unity, the web, or AR Quick Look.",
    tag: "GLB + USDZ",
    tagKind: "auto",
    icon: I.export,
  },
];

function NodeCard({ n }: { n: Node }) {
  return (
    <li className={`flow-node ${n.tagKind === "gate" ? "is-gate" : ""}`}>
      <span className="flow-icon">{n.icon}</span>
      <div className="flow-body">
        <div className="flow-title-row">
          <h3>{n.title}</h3>
          {n.tag && <span className={`flow-tag tag-${n.tagKind}`}>{n.tag}</span>}
        </div>
        <p>{n.desc}</p>
      </div>
    </li>
  );
}

export default function HowItWorks() {
  return (
    <section className="section how-section" id="how" aria-labelledby="how-title">
      <div className="section-head">
        <p className="eyebrow">How it works</p>
        <h2 id="how-title">A judged loop, with two places you can grab the wheel.</h2>
        <p className="section-sub">
          Two model slots, any OpenAI-compatible endpoint, and two human gates. The loop runs
          until the judge accepts or the cycle cap is hit.
        </p>
      </div>

      <div className="flow">
        <ol className="flow-list">
          {PRE.map((n) => (
            <NodeCard key={n.key} n={n} />
          ))}
        </ol>

        <div className="flow-loop">
          <div className="flow-loop-label">
            <span className="loop-arrow" aria-hidden="true">
              <svg viewBox="0 0 24 24" width="18" height="18">
                <path d="M20 11a8 8 0 10-2.3 5.6" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" />
                <path d="M20 5v5h-5" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
            Repeats until accepted or capped
          </div>
          <ol className="flow-list">
            {LOOP.map((n) => (
              <NodeCard key={n.key} n={n} />
            ))}
          </ol>
        </div>

        <ol className="flow-list">
          {POST.map((n) => (
            <NodeCard key={n.key} n={n} />
          ))}
        </ol>
      </div>

      <div className="how-callout">
        <strong>The best cycle wins, not the last.</strong> LLM sculpting hill-climbs and
        regresses, so Maquette keeps, exports, and reports the best-scoring cycle - and every
        other cycle stays exportable too. Nothing is a dead end.
      </div>
    </section>
  );
}
