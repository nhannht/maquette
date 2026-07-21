import { useState } from "react";

interface Props {
  text: string;
  label?: string;
  className?: string;
}

export default function CopyButton({ text, label = "Copy", className }: Props) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      // Fallback for permission-restricted contexts.
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      try {
        document.execCommand("copy");
      } catch {
        /* ignore */
      }
      document.body.removeChild(ta);
    }
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1800);
  }

  return (
    <button
      type="button"
      className={`copy-btn ${className ?? ""}`}
      onClick={copy}
      aria-label={copied ? "Copied to clipboard" : `${label}: ${text}`}
    >
      {copied ? (
        <>
          <svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true">
            <path
              d="M4 10.5l4 4 8-9"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
          Copied
        </>
      ) : (
        <>
          <svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true">
            <rect
              x="7"
              y="7"
              width="9"
              height="9"
              rx="2"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
            />
            <path
              d="M4 13V5a1 1 0 011-1h8"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
            />
          </svg>
          {label}
        </>
      )}
    </button>
  );
}
