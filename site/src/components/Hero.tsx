import { useEffect, useRef } from "react";
import ModelViewer from "./ModelViewer";
import CopyButton from "./CopyButton";
import { HERO_MODEL } from "../lib/runData";
import type { ModelViewer as Viewer } from "../lib/modelViewer";
import { useReducedMotion } from "../lib/useReducedMotion";

const BREW = "brew install --cask nhannht/tap/maquette";
const GITHUB = "https://github.com/nhannht/maquette";

function lerp(a: number, b: number, t: number) {
  return a + (b - a) * t;
}
function clamp01(x: number) {
  return x < 0 ? 0 : x > 1 ? 1 : x;
}

export default function Hero() {
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const viewerRef = useRef<Viewer | null>(null);
  const copyARef = useRef<HTMLDivElement | null>(null);
  const copyBRef = useRef<HTMLDivElement | null>(null);
  const reduced = useReducedMotion();

  useEffect(() => {
    if (reduced) return;
    let raf = 0;
    let idleTimer = 0;
    let ticking = false;

    const apply = () => {
      ticking = false;
      const wrap = wrapRef.current;
      if (!wrap) return;
      const rect = wrap.getBoundingClientRect();
      const total = rect.height - window.innerHeight;
      const p = clamp01(total > 0 ? -rect.top / total : 0);

      const v = viewerRef.current;
      if (v) {
        v.setView({
          azimuth: lerp(28, -20, p),
          polar: lerp(63, 52, p),
          distance: lerp(1.1, 0.82, p),
        });
        // Resume gentle idle rotation only when parked near the top.
        window.clearTimeout(idleTimer);
        idleTimer = window.setTimeout(() => {
          if (p < 0.04) v.setAutoRotate(true);
        }, 900);
      }

      // Pinned copy crossfade.
      const a = copyARef.current;
      const b = copyBRef.current;
      if (a) {
        const av = 1 - clamp01((p - 0.26) / 0.2);
        a.style.opacity = String(av);
        a.style.transform = `translateY(${lerp(0, -26, clamp01((p - 0.26) / 0.2))}px)`;
        a.style.pointerEvents = av < 0.5 ? "none" : "auto";
      }
      if (b) {
        const bv = clamp01((p - 0.52) / 0.22);
        b.style.opacity = String(bv);
        b.style.transform = `translateY(${lerp(26, 0, bv)}px)`;
        b.style.pointerEvents = bv > 0.5 ? "auto" : "none";
      }
    };

    const onScroll = () => {
      if (!ticking) {
        ticking = true;
        raf = requestAnimationFrame(apply);
      }
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    apply();
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
      cancelAnimationFrame(raf);
      window.clearTimeout(idleTimer);
    };
  }, [reduced]);

  return (
    <header className="hero" id="top" ref={wrapRef}>
      <div className="hero-stage">
        <div className="hero-viewer-wrap">
          <ModelViewer
            src={HERO_MODEL}
            ariaLabel="A 3D model of an open MacBook Air, sculpted by Maquette. Drag to orbit it."
            eager
            autoRotate
            autoRotateSpeed={0.6}
            distance={1.1}
            className="hero-viewer"
            hint
          />
        </div>

        <div className="hero-copy" ref={copyARef}>
          <p className="eyebrow">macOS - Apple Silicon - bring your own key</p>
          <h1>
            Drop a photo,
            <br />
            get a sculpted 3D&nbsp;model.
          </h1>
          <p className="lede">
            A coder model writes procedural geometry from your photo. A vision model judges
            it against the photo and says what to fix. The loop refines until it looks right,
            and the best cycle wins.
          </p>
          <div className="hero-cta">
            <div className="brew-line">
              <code>{BREW}</code>
              <CopyButton text={BREW} label="Copy" className="on-code" />
            </div>
            <a className="btn btn-ghost" href={GITHUB} target="_blank" rel="noreferrer noopener">
              View on GitHub
            </a>
          </div>
          <p className="hero-scrollhint" aria-hidden="true">
            Scroll to orbit - drag the model any time
          </p>
        </div>

        <div className="hero-copy hero-copy-b" ref={copyBRef} aria-hidden={reduced ? undefined : true}>
          <h2 className="hero-b-head">Not a picture of a model.</h2>
          <p className="lede">
            This is a real GLB you can orbit right now, export to Blender, Unity, or the web,
            and drop into AR Quick Look on your iPhone. Out come <code>model.glb</code> and{" "}
            <code>model.usdz</code>, every cycle.
          </p>
          <div className="hero-cta">
            <a className="btn btn-primary" href="#sculpt">
              Watch it sculpt itself
            </a>
            <a className="btn btn-ghost" href="#gallery">
              See the gallery
            </a>
          </div>
        </div>
      </div>
    </header>
  );
}
