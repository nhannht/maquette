import { useEffect, useRef, useState } from "react";
import ModelViewer from "./ModelViewer";
import { gallery } from "../lib/runData";
import type { ModelViewer as Viewer } from "../lib/modelViewer";
import SpotlightCard from "./reactbits/SpotlightCard/SpotlightCard";
import { useTheme } from "../theme";

const AR_BADGE =
  "data:image/svg+xml," +
  encodeURIComponent(
    `<svg xmlns='http://www.w3.org/2000/svg' width='150' height='44'>
      <rect x='1' y='1' width='148' height='42' rx='21' fill='#0091ff'/>
      <g fill='none' stroke='#fff' stroke-width='2' stroke-linejoin='round'>
        <path d='M28 12 L40 18 L40 30 L28 36 L16 30 L16 18 Z'/>
        <path d='M28 12 L28 24 M16 18 L28 24 L40 18'/>
      </g>
      <text x='58' y='28' font-family='-apple-system,Segoe UI,Roboto,sans-serif' font-size='15' font-weight='600' fill='#fff'>View in AR</text>
    </svg>`,
  );

function useArSupport() {
  const [ok, setOk] = useState(false);
  useEffect(() => {
    const a = document.createElement("a");
    const supports = !!(a.relList && a.relList.supports && a.relList.supports("ar"));
    setOk(supports);
  }, []);
  return ok;
}

function bytes(n: number) {
  return n >= 1024 * 1024
    ? (n / 1024 / 1024).toFixed(1) + " MB"
    : Math.round(n / 1024) + " KB";
}

export default function Gallery() {
  const [sel, setSel] = useState(0);
  const viewerRef = useRef<Viewer | null>(null);
  const loaded = useRef(0);
  const arOk = useArSupport();
  const { theme } = useTheme();
  const item = gallery[sel];

  useEffect(() => {
    const v = viewerRef.current;
    if (!v || loaded.current === sel) return;
    loaded.current = sel;
    v.setModel(gallery[sel].model);
  }, [sel]);

  return (
    <section className="section gallery-section" id="gallery" aria-labelledby="gallery-title">
      <div className="section-head">
        <p className="eyebrow">Gallery</p>
        <h2 id="gallery-title">Real exports, straight from real runs.</h2>
        <p className="section-sub">
          Every model here is a GLB Maquette actually produced. Pick one to orbit it.
          {arOk ? " On your iPhone or iPad, drop it into your room in AR." : ""}
        </p>
      </div>

      <div className="gallery-grid">
        <div className="gallery-viewer-col">
          <div className="gallery-viewer-frame">
            <ModelViewer
              src={gallery[0].model}
              poster={gallery[0].poster}
              ariaLabel={`3D model: ${item.name}. Drag to orbit.`}
              autoRotate
              autoRotateSpeed={0.6}
              distance={1.1}
              className="gallery-viewer"
              onReady={(v) => {
                viewerRef.current = v;
              }}
            />
          </div>
          <div className="gallery-viewer-meta">
            <div>
              <h3>{item.name}</h3>
              <p>{item.subtitle}</p>
            </div>
            <div className="gallery-meta-right">
              <span className="chip">GLB {bytes(item.glbBytes)}</span>
              {arOk && (
                <a className="ar-link" rel="ar" href={item.usdz} aria-label={`View ${item.name} in AR`}>
                  <img src={AR_BADGE} alt="View in AR" width={150} height={44} />
                </a>
              )}
            </div>
          </div>
        </div>

        <ul className="gallery-cards">
          {gallery.map((g, i) => (
            <li key={g.id}>
              <SpotlightCard
                className={`gallery-card ${i === sel ? "is-selected" : ""}`}
                // SpotlightCard writes this literal into --spotlight-color in JS,
                // so it cannot be a CSS var. Mirrors tokens.css --spotlight:
                // dark = blue-on-navy glow, light = accent-blue glow.
                spotlightColor={theme === "dark" ? "rgba(120, 160, 255, 0.16)" : "rgba(0, 102, 204, 0.1)"}
              >
                <button
                  type="button"
                  className="gallery-card-inner"
                  onClick={() => setSel(i)}
                  aria-pressed={i === sel}
                >
                  <span className="gallery-card-thumb">
                    <img src={g.poster} alt="" aria-hidden="true" loading="lazy" draggable={false} />
                  </span>
                  <span className="gallery-card-text">
                    <span className="gallery-card-name">{g.name}</span>
                    <span className="gallery-card-sub">{g.subtitle}</span>
                  </span>
                  {i === sel && <span className="gallery-card-live">Viewing</span>}
                </button>
              </SpotlightCard>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
