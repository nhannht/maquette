const GITHUB = "https://github.com/nhannht/maquette";
const LICENSE = "https://github.com/nhannht/maquette/blob/master/LICENSE";

export default function Footer() {
  return (
    <footer className="footer">
      <div className="footer-inner">
        <div className="footer-brand">
          <svg viewBox="0 0 64 64" width="24" height="24" aria-hidden="true" className="nav-mark">
            <path d="M32 8 L54 20 L54 44 L32 56 L10 44 L10 20 Z" fill="none" stroke="currentColor" strokeWidth="3.4" strokeLinejoin="round" />
            <path d="M32 8 L32 32 M10 20 L32 32 L54 20" fill="none" stroke="currentColor" strokeWidth="3.4" strokeLinejoin="round" />
          </svg>
          <span>Maquette</span>
        </div>

        <nav className="footer-links" aria-label="Footer">
          <a href="#sculpt">Watch it sculpt</a>
          <a href="#how">How it works</a>
          <a href="#gallery">Gallery</a>
          <a href="#install">Install</a>
          <a href={GITHUB} target="_blank" rel="noreferrer noopener">
            GitHub
          </a>
          <a href={LICENSE} target="_blank" rel="noreferrer noopener">
            MIT license
          </a>
        </nav>

        <p className="footer-meta">
          Built by <a href="https://github.com/nhannht" target="_blank" rel="noreferrer noopener">nhannht</a>.
          The judged-loop idea builds on{" "}
          <a href="https://github.com/hoainho/img2threejs" target="_blank" rel="noreferrer noopener">
            img2threejs
          </a>{" "}
          (MIT). Models on this page are real Maquette exports.
        </p>
      </div>
    </footer>
  );
}
