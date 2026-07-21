import { useEffect, useRef, useState } from "react";
import { ModelViewer as Viewer } from "../lib/modelViewer";
import { useReducedMotion } from "../lib/useReducedMotion";

interface Props {
  src: string;
  poster?: string;
  ariaLabel: string;
  eager?: boolean;
  autoRotate?: boolean;
  autoRotateSpeed?: number;
  distance?: number;
  hint?: boolean;
  className?: string;
  onReady?: (viewer: Viewer) => void;
}

export default function ModelViewer({
  src,
  poster,
  ariaLabel,
  eager = false,
  autoRotate = true,
  autoRotateSpeed,
  distance,
  hint = true,
  className,
  onReady,
}: Props) {
  const hostRef = useRef<HTMLDivElement | null>(null);
  const viewerRef = useRef<Viewer | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [active, setActive] = useState(eager);
  const reduced = useReducedMotion();

  // Lazy: only spin up WebGL when near the viewport (below-fold models).
  useEffect(() => {
    if (active) return;
    const host = hostRef.current;
    if (!host) return;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) {
          setActive(true);
          io.disconnect();
        }
      },
      { rootMargin: "400px 0px" },
    );
    io.observe(host);
    return () => io.disconnect();
  }, [active]);

  useEffect(() => {
    if (!active) return;
    const host = hostRef.current;
    if (!host) return;
    const viewer = new Viewer(host, {
      autoRotate,
      autoRotateSpeed,
      distance,
      reducedMotion: reduced,
      onLoad: () => setLoaded(true),
    });
    viewerRef.current = viewer;
    viewer.load(src).then(() => {
      onReady?.(viewer);
    });
    return () => {
      viewer.dispose();
      viewerRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active]);

  return (
    <div className={`viewer ${className ?? ""}`} role="img" aria-label={ariaLabel}>
      <div className="viewer-host" ref={hostRef} />
      {poster && (
        <img
          className={`viewer-poster ${loaded ? "is-hidden" : ""}`}
          src={poster}
          alt=""
          aria-hidden="true"
          draggable={false}
        />
      )}
      {!poster && !loaded && <div className="viewer-skeleton" aria-hidden="true" />}
      {hint && (
        <span className={`viewer-hint ${loaded ? "" : "is-hidden"}`} aria-hidden="true">
          Drag to rotate
        </span>
      )}
    </div>
  );
}
