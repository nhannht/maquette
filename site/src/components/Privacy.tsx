interface Item {
  title: string;
  body: React.ReactNode;
  icon: React.ReactNode;
}

const items: Item[] = [
  {
    title: "Keys live in the Keychain",
    body: "Your API key goes into the macOS Keychain - never a config file, never UserDefaults, never a log.",
    icon: (
      <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
        <rect x="5" y="10" width="14" height="10" rx="2.4" fill="none" stroke="currentColor" strokeWidth="1.7" />
        <path d="M8 10V7.5a4 4 0 018 0V10" fill="none" stroke="currentColor" strokeWidth="1.7" />
        <circle cx="12" cy="15" r="1.5" fill="currentColor" />
      </svg>
    ),
  },
  {
    title: "The renderer is fully offline",
    body: (
      <>
        Three.js r185 is bundled and served over a custom URL scheme. The sculpt page makes{" "}
        <strong>zero network requests</strong> - the only thing your key ever touches is the
        endpoint you chose.
      </>
    ),
    icon: (
      <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
        <circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" strokeWidth="1.6" />
        <path d="M3.5 12h17M12 3.5c2.5 2.3 3.8 5.3 3.8 8.5S14.5 18.2 12 20.5C9.5 18.2 8.2 15.2 8.2 12S9.5 5.8 12 3.5z" fill="none" stroke="currentColor" strokeWidth="1.4" />
        <path d="M18 6l3-3M17 5l2 .3.3 2" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    ),
  },
  {
    title: "Bring your own key",
    body: (
      <>
        Any OpenAI-compatible endpoint: OpenRouter, OpenAI, Anthropic, Moonshot - or a local{" "}
        <strong>Ollama / LM Studio</strong> with no key at all. Two independent slots for the
        coder and the vision judge.
      </>
    ),
    icon: (
      <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
        <path d="M14.5 5.5a4 4 0 105.7 5.7l-2.5 2.5-3.2-3.2z" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
        <path d="M13 11l-7 7-2.5-.5L3 15l7-7" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" />
      </svg>
    ),
  },
  {
    title: "Under ten cents a run",
    body: "The whole validation sweep that shipped this app cost under $0.10. On the earbuds benchmark, one accepted cycle ran about $0.002.",
    icon: (
      <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
        <circle cx="12" cy="12" r="8.5" fill="none" stroke="currentColor" strokeWidth="1.6" />
        <path d="M14.5 9.2c-.5-1-1.5-1.5-2.7-1.5-1.6 0-2.6.9-2.6 2.1 0 2.8 5.6 1.5 5.6 4.4 0 1.3-1.1 2.2-2.9 2.2-1.4 0-2.5-.6-3-1.7M12 6v1.6M12 16.4V18" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      </svg>
    ),
  },
];

export default function Privacy() {
  return (
    <section className="section privacy-section" id="privacy" aria-labelledby="privacy-title">
      <div className="section-head">
        <p className="eyebrow">Privacy &amp; your key</p>
        <h2 id="privacy-title">Your photo and your key stay yours.</h2>
        <p className="section-sub">
          Maquette is a client, not a service. There is no Maquette server, no account, and no
          telemetry - the app talks only to the endpoint you point it at.
        </p>
      </div>

      <div className="privacy-grid">
        {items.map((it) => (
          <article className="paper-card privacy-card" key={it.title}>
            <span className="card-icon">{it.icon}</span>
            <h3>{it.title}</h3>
            <p>{it.body}</p>
          </article>
        ))}
      </div>
    </section>
  );
}
