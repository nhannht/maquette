import { useEffect, useRef, useState } from "react";
import ModelViewer from "./ModelViewer";
import { timelineCycles, TIMELINE_SUBJECT } from "../lib/runData";
import type { ModelViewer as Viewer } from "../lib/modelViewer";
import { useReducedMotion } from "../lib/useReducedMotion";

const LAYER_LABELS: Record<string, string> = {
  componentStructure: "Component structure",
  formDetail: "Form detail",
  materialSurface: "Material & surface",
  silhouetteProportion: "Silhouette & proportion",
};

export default function Timeline() {
  const [idx, setIdx] = useState(0);
  const [playing, setPlaying] = useState(false);
  const viewerRef = useRef<Viewer | null>(null);
  const loadedIdx = useRef(0);
  const reduced = useReducedMotion();

  const cycle = timelineCycles[idx];
  const prev = idx > 0 ? timelineCycles[idx - 1] : null;
  const delta = prev ? cycle.overall - prev.overall : 0;

  // Crossfade the model when the active cycle changes.
  useEffect(() => {
    const v = viewerRef.current;
    if (!v) return;
    if (loadedIdx.current === idx) return;
    loadedIdx.current = idx;
    v.setModel(timelineCycles[idx].model);
  }, [idx]);

  // Autoplay advances through the cycles and loops.
  useEffect(() => {
    if (!playing || reduced) return;
    const id = window.setInterval(() => {
      setIdx((i) => (i + 1) % timelineCycles.length);
    }, 3000);
    return () => window.clearInterval(id);
  }, [playing, reduced]);

  const onReady = (v: Viewer) => {
    viewerRef.current = v;
    v.setAutoRotate(true);
  };

  return (
    <section className="section sculpt-section" id="sculpt" aria-labelledby="sculpt-title">
      <div className="section-head">
        <p className="eyebrow">The differentiator - watch it sculpt itself</p>
        <h2 id="sculpt-title">Every cycle is judged. The best one wins.</h2>
        <p className="section-sub">
          A real run, three cycles, no edits. The vision model scored each attempt against the
          photo and wrote the coder its next instruction. Scrub the cycles and watch the model -
          and the score - climb. These are the actual numbers from the run&apos;s{" "}
          <code>review.json</code>.
        </p>
      </div>

      <div className="sculpt-grid">
        <div className="sculpt-viewer-col">
          <div className="sculpt-viewer-frame">
            <ModelViewer
              src={timelineCycles[0].model}
              poster="/img/poster-iphone.png"
              ariaLabel={`3D model at cycle ${cycle.n}. ${TIMELINE_SUBJECT} Drag to orbit.`}
              autoRotate
              autoRotateSpeed={0.55}
              distance={1.15}
              className="sculpt-viewer"
              onReady={onReady}
            />
            <div className="sculpt-cycle-tag" aria-hidden="true">
              Cycle {cycle.n}
              {cycle.best && <span className="best-pill">Best - exported</span>}
            </div>
          </div>

          <div className="scrubber">
            <button
              type="button"
              className="scrub-play"
              onClick={() => setPlaying((p) => !p)}
              aria-label={playing ? "Pause autoplay" : "Play through cycles"}
              disabled={reduced}
            >
              {playing ? (
                <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
                  <rect x="6" y="5" width="4" height="14" rx="1.3" fill="currentColor" />
                  <rect x="14" y="5" width="4" height="14" rx="1.3" fill="currentColor" />
                </svg>
              ) : (
                <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
                  <path d="M8 5.5v13l11-6.5z" fill="currentColor" />
                </svg>
              )}
            </button>

            <div className="scrub-track-wrap">
              <input
                className="scrub-range"
                type="range"
                min={1}
                max={timelineCycles.length}
                step={1}
                value={cycle.n}
                aria-label="Refinement cycle"
                aria-valuetext={`Cycle ${cycle.n} of ${timelineCycles.length}, score ${cycle.overall.toFixed(2)}`}
                onChange={(e) => {
                  setPlaying(false);
                  setIdx(Number(e.target.value) - 1);
                }}
              />
              <div className="scrub-ticks" aria-hidden="true">
                {timelineCycles.map((c, i) => (
                  <button
                    key={c.n}
                    type="button"
                    className={`scrub-tick ${i === idx ? "is-active" : ""} ${c.best ? "is-best" : ""}`}
                    onClick={() => {
                      setPlaying(false);
                      setIdx(i);
                    }}
                    tabIndex={-1}
                  >
                    <span className="scrub-tick-dot" />
                    <span className="scrub-tick-label">
                      {c.n}
                      <em>{c.overall.toFixed(2)}</em>
                    </span>
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>

        <div className="sculpt-readout">
          <div className="score-block">
            <div className="score-head">
              <span className="score-label">Judge score</span>
              <span className={`action-chip action-${cycle.action}`}>{cycle.action}</span>
            </div>
            <div className="score-big">
              <span className="score-num" key={cycle.n}>
                {cycle.overall.toFixed(2)}
              </span>
              {delta !== 0 && (
                <span className={`score-delta ${delta > 0 ? "up" : "down"}`}>
                  {delta > 0 ? "+" : ""}
                  {delta.toFixed(2)}
                </span>
              )}
            </div>
            <div className="score-bar">
              <span className="score-bar-fill" style={{ width: `${cycle.overall * 100}%` }} />
            </div>

            <div className="layer-scores">
              {(Object.keys(LAYER_LABELS) as (keyof typeof cycle.layers)[]).map((k) => (
                <div className="layer-row" key={k}>
                  <span className="layer-name">{LAYER_LABELS[k]}</span>
                  <span className="layer-track">
                    <span className="layer-fill" style={{ width: `${cycle.layers[k] * 100}%` }} />
                  </span>
                  <span className="layer-val">{cycle.layers[k].toFixed(2)}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="critique-block">
            <div className="critique-head">
              <span className="critique-label">The judge&apos;s critique</span>
              <span className="critique-cycle">Cycle {cycle.n}</span>
            </div>
            <p className="critique-text">{cycle.critique}</p>
          </div>
        </div>
      </div>

      <p className="sculpt-foot">
        Scores are a compass, not a caliper - the same inputs can land anywhere from 0.65 to 0.84
        across runs. That is exactly why every cycle stays exportable and the human can grab the
        wheel at each gate.
      </p>
    </section>
  );
}
