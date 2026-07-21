import { useCallback, useRef, useState } from "react";
import { JUXTAPOSE } from "../lib/runData";

export default function Juxtapose() {
  const [pos, setPos] = useState(52);
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const dragging = useRef(false);

  const setFromClientX = useCallback((clientX: number) => {
    const el = wrapRef.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    const p = ((clientX - r.left) / r.width) * 100;
    setPos(Math.max(0, Math.min(100, p)));
  }, []);

  const onPointerDown = (e: React.PointerEvent) => {
    dragging.current = true;
    (e.currentTarget as HTMLElement).setPointerCapture?.(e.pointerId);
    setFromClientX(e.clientX);
  };
  const onPointerMove = (e: React.PointerEvent) => {
    if (!dragging.current) return;
    setFromClientX(e.clientX);
  };
  const onPointerUp = () => {
    dragging.current = false;
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowLeft") {
      setPos((p) => Math.max(0, p - 4));
      e.preventDefault();
    } else if (e.key === "ArrowRight") {
      setPos((p) => Math.min(100, p + 4));
      e.preventDefault();
    } else if (e.key === "Home") {
      setPos(0);
      e.preventDefault();
    } else if (e.key === "End") {
      setPos(100);
      e.preventDefault();
    }
  };

  return (
    <section className="section juxtapose-section" id="juxtapose" aria-labelledby="jx-title">
      <div className="section-head">
        <p className="eyebrow">This photo became this model</p>
        <h2 id="jx-title">A single reference photo in. A sculpted 3D model out.</h2>
        <p className="section-sub">
          Left is the iPhone 17 photo you drop in. Right is one of the four angles Maquette
          rendered from the model it built - the exact renders its judge scored. Drag to compare.
        </p>
      </div>

      <div
        className="jx"
        ref={wrapRef}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
      >
        <img
          className="jx-img jx-render"
          src={JUXTAPOSE.render}
          alt="Maquette's rendered 3D model of the iPhone 17, front angle"
          draggable={false}
        />
        <img
          className="jx-img jx-photo"
          src={JUXTAPOSE.photo}
          alt="The reference iPhone 17 photo dropped into Maquette"
          draggable={false}
          style={{ clipPath: `inset(0 ${100 - pos}% 0 0)` }}
        />

        <span className="jx-badge jx-badge-l" style={{ opacity: pos > 14 ? 1 : 0 }}>
          Photo
        </span>
        <span className="jx-badge jx-badge-r" style={{ opacity: pos < 86 ? 1 : 0 }}>
          Sculpted model
        </span>

        <div
          className="jx-handle"
          style={{ left: `${pos}%` }}
          role="slider"
          tabIndex={0}
          aria-label="Compare reference photo and rendered model"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={Math.round(pos)}
          aria-valuetext={`${Math.round(pos)}% photo`}
          onKeyDown={onKeyDown}
        >
          <span className="jx-grip" aria-hidden="true">
            <svg viewBox="0 0 24 24" width="20" height="20">
              <path
                d="M9 7l-4 5 4 5M15 7l4 5-4 5"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </span>
        </div>
      </div>
    </section>
  );
}
