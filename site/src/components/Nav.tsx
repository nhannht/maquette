import { useEffect, useRef, useState } from "react";
import { useTheme } from "../theme";
import GlassSurface from "./reactbits/GlassSurface/GlassSurface";

const LINKS = [
  { href: "#sculpt", label: "Watch it sculpt" },
  { href: "#how", label: "How it works" },
  { href: "#gallery", label: "Gallery" },
  { href: "#install", label: "Install" },
];

const GITHUB = "https://github.com/nhannht/maquette";

function Mark() {
  return (
    <svg viewBox="0 0 64 64" width="22" height="22" aria-hidden="true" className="nav-mark">
      <path
        d="M32 8 L54 20 L54 44 L32 56 L10 44 L10 20 Z"
        fill="none"
        stroke="currentColor"
        strokeWidth="3.4"
        strokeLinejoin="round"
      />
      <path
        d="M32 8 L32 32 M10 20 L32 32 L54 20"
        fill="none"
        stroke="currentColor"
        strokeWidth="3.4"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export default function Nav() {
  const { theme, toggle } = useTheme();
  const [open, setOpen] = useState(false);
  const navRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    const onClick = (e: MouseEvent) => {
      if (navRef.current && !navRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onClick);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onClick);
    };
  }, [open]);

  return (
    <nav className="nav" ref={navRef} aria-label="Primary">
      {/* GlassSurface is the ONE persistent glass pane (nav pill). Frost/border
          are themed from outside via .nav-glass overrides in app.css, so the
          vendored component stays byte-untouched. */}
      <GlassSurface
        className="nav-glass"
        width="min(980px, 100%)"
        height="auto"
        borderRadius={28}
      >
        <a href="#top" className="nav-brand" aria-label="Maquette, home">
          <Mark />
          <span className="nav-word">Maquette</span>
        </a>

        <ul className="nav-links">
          {LINKS.map((l) => (
            <li key={l.href}>
              <a href={l.href}>{l.label}</a>
            </li>
          ))}
        </ul>

        <div className="nav-actions">
          <a
            className="nav-icon"
            href={GITHUB}
            target="_blank"
            rel="noreferrer noopener"
            aria-label="Maquette on GitHub"
          >
            <svg viewBox="0 0 24 24" width="19" height="19" aria-hidden="true">
              <path
                fill="currentColor"
                d="M12 2C6.48 2 2 6.58 2 12.25c0 4.53 2.87 8.37 6.84 9.73.5.1.68-.22.68-.49 0-.24-.01-.87-.01-1.71-2.78.62-3.37-1.22-3.37-1.22-.46-1.18-1.11-1.5-1.11-1.5-.9-.63.07-.62.07-.62 1 .07 1.53 1.06 1.53 1.06.89 1.56 2.34 1.11 2.91.85.09-.66.35-1.11.63-1.37-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.3.1-2.71 0 0 .84-.28 2.75 1.05a9.3 9.3 0 015 0c1.91-1.33 2.75-1.05 2.75-1.05.55 1.41.2 2.45.1 2.71.64.72 1.03 1.63 1.03 2.75 0 3.93-2.35 4.79-4.58 5.05.36.32.68.94.68 1.9 0 1.37-.01 2.48-.01 2.82 0 .27.18.6.69.49A10.02 10.02 0 0022 12.25C22 6.58 17.52 2 12 2z"
              />
            </svg>
          </a>

          <button
            type="button"
            className="nav-icon theme-toggle"
            onClick={toggle}
            aria-label={theme === "dark" ? "Switch to light theme" : "Switch to dark theme"}
          >
            <span className="theme-knob" data-theme={theme}>
              <svg className="ico-sun" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
                <circle cx="12" cy="12" r="4.2" fill="currentColor" />
                <g stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
                  <path d="M12 2.6v2.6M12 18.8v2.6M2.6 12h2.6M18.8 12h2.6M5.4 5.4l1.8 1.8M16.8 16.8l1.8 1.8M18.6 5.4l-1.8 1.8M7.2 16.8l-1.8 1.8" />
                </g>
              </svg>
              <svg className="ico-moon" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
                <path
                  fill="currentColor"
                  d="M20 14.2A8 8 0 019.8 4 8 8 0 1020 14.2z"
                />
              </svg>
            </span>
          </button>

          <button
            type="button"
            className="nav-icon nav-burger"
            aria-label="Menu"
            aria-expanded={open}
            onClick={() => setOpen((v) => !v)}
          >
            <span className={`burger ${open ? "is-open" : ""}`} aria-hidden="true">
              <i />
              <i />
            </span>
          </button>
        </div>
      </GlassSurface>

      {open && (
        <div className="nav-sheet" role="menu">
          {LINKS.map((l) => (
            <a key={l.href} href={l.href} role="menuitem" onClick={() => setOpen(false)}>
              {l.label}
            </a>
          ))}
          <a
            href={GITHUB}
            role="menuitem"
            target="_blank"
            rel="noreferrer noopener"
            onClick={() => setOpen(false)}
          >
            GitHub
          </a>
        </div>
      )}
    </nav>
  );
}
