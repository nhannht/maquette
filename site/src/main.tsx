import { createRoot } from "react-dom/client";
import { ThemeProvider } from "./theme";
import App from "./App";
import "./styles/tokens.css";
import "./styles/app.css";

// StrictMode intentionally omitted: it double-invokes effects in dev, which
// would create and dispose each WebGL viewer twice on mount and risk hitting
// the browser context limit. Viewer cleanup is still handled on real unmount.
createRoot(document.getElementById("root")!).render(
  <ThemeProvider>
    <App />
  </ThemeProvider>,
);
