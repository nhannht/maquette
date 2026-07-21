import CopyButton from "./CopyButton";
import SpotlightCard from "./reactbits/SpotlightCard/SpotlightCard";
import { useTheme } from "../theme";

const BREW = "brew install --cask nhannht/tap/maquette";
const RELEASES = "https://github.com/nhannht/maquette/releases";
const GITHUB = "https://github.com/nhannht/maquette";

export default function Install() {
  const { theme } = useTheme();
  // Mirrors tokens.css --spotlight; SpotlightCard writes it into a CSS var in
  // JS, so it cannot itself be a CSS var. Dark = blue-on-navy, light = accent.
  const spot: `rgba(${number}, ${number}, ${number}, ${number})` =
    theme === "dark" ? "rgba(120, 160, 255, 0.16)" : "rgba(0, 102, 204, 0.1)";
  return (
    <section className="section install-section" id="install" aria-labelledby="install-title">
      <div className="section-head">
        <p className="eyebrow">Install</p>
        <h2 id="install-title">Signed, notarized, and one command away.</h2>
        <p className="section-sub">
          The app is signed with a Developer ID and notarized by Apple. Apple Silicon, macOS 14
          or later.
        </p>
      </div>

      <div className="install-grid">
        <SpotlightCard className="install-card install-primary" spotlightColor={spot}>
          <h3>Homebrew</h3>
          <p>The fastest way in. One line, and updates come with your next brew upgrade.</p>
          <div className="brew-line brew-line-lg">
            <code>{BREW}</code>
            <CopyButton text={BREW} label="Copy" className="on-code" />
          </div>
        </SpotlightCard>

        <SpotlightCard className="install-card" spotlightColor={spot}>
          <h3>Direct download</h3>
          <p>Prefer a DMG? Grab the notarized build from GitHub Releases.</p>
          <a className="btn btn-primary" href={RELEASES} target="_blank" rel="noreferrer noopener">
            Download the DMG
          </a>
        </SpotlightCard>

        <SpotlightCard className="install-card" spotlightColor={spot}>
          <h3>Build from source</h3>
          <p>
            Clone the repo, run <code>./build.sh</code>, and you have both the app and the
            headless <code>maquette-cli</code>. MIT licensed.
          </p>
          <a className="btn btn-ghost" href={GITHUB} target="_blank" rel="noreferrer noopener">
            Read the source
          </a>
        </SpotlightCard>
      </div>

      <p className="install-note">
        Requirements: Apple Silicon Mac, macOS 14+. Clean, single-object photos on quiet
        backgrounds sculpt best.
      </p>
    </section>
  );
}
