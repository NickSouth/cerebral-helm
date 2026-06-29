import { MODE_IDS, modeTokenCssVar, type ModeId } from "./tokens/tokens";
import { Unavailable } from "./components/Unavailable";

const MODE_META: Record<ModeId, { label: string; character: string }> = {
  executive: { label: "Executive", character: "Gold with cyan balance" },
  developer: { label: "Developer", character: "Restrained cool white / cyan" },
  school: { label: "School", character: "Electric blue with warm gold" },
  entertainment: { label: "Entertainment", character: "Emerald with cool cyan" }
};

const STATUS_TOKENS: ReadonlyArray<{ token: string; label: string }> = [
  { token: "--ch-status-success", label: "Success / Ready" },
  { token: "--ch-status-warning", label: "Review" },
  { token: "--ch-status-info", label: "Info / Thinking" },
  { token: "--ch-status-error", label: "Error" },
  { token: "--ch-status-neutral", label: "Idle / Unavailable" }
];

function cssVar(token: string): string {
  return `var(${token})`;
}

export function App() {
  return (
    <main id="main" tabIndex={-1} className="tokens-page">
      <header>
        <p className="eyebrow">CerebralHelm / Design tokens</p>
        <h1>Token reference</h1>
        <p className="lede">
          The foundation surface for the PRE-UI dashboard. Every value here comes from a
          semantic token; mode color is applied only through <code>data-mode</code>. This
          page is the first visual-regression fixture.
        </p>
      </header>

      <section className="token-section" aria-label="Mode palettes">
        <h2>Mode palettes</h2>
        <div className="swatch-grid">
          {MODE_IDS.map((mode) => (
            <article key={mode} className="panel mode-panel" data-mode={mode}>
              <p className="eyebrow">{MODE_META[mode].label}</p>
              <span className="character">{MODE_META[mode].character}</span>
              <div className="swatch-row">
                <span
                  className="swatch"
                  title={`${mode}.primary`}
                  style={{ background: cssVar(modeTokenCssVar(`${mode}.primary`)) }}
                />
                <span
                  className="swatch"
                  title={`${mode}.secondary`}
                  style={{ background: cssVar(modeTokenCssVar(`${mode}.secondary`)) }}
                />
                <span
                  className="swatch"
                  title="glow-soft"
                  style={{ background: "var(--ch-glow-soft)" }}
                />
              </div>
              <span className="type-sm">accent-primary resolves under data-mode</span>
            </article>
          ))}
        </div>
      </section>

      <section className="token-section" aria-label="Status tokens">
        <h2>Status (mode-independent, never color alone)</h2>
        <div className="status-row">
          {STATUS_TOKENS.map(({ token, label }) => (
            <span key={token} className="chip">
              <span className="dot" style={{ background: cssVar(token) }} />
              {label}
            </span>
          ))}
        </div>
      </section>

      <section className="token-section" aria-label="Confirmation surface">
        <h2>Confirmation (neutral system blue)</h2>
        <div className="panel confirm-sample">
          <p className="eyebrow">Confirm gated action</p>
          <p className="type-base">
            Neutral blue regardless of active mode — never inherits the mode accent.
          </p>
        </div>
      </section>

      <section className="token-section" aria-label="Typography scale">
        <h2>Typography</h2>
        <div className="type-sample">
          <span className="type-display">Good morning</span>
          <span className="type-xl">Extra large heading</span>
          <span className="type-lg">Panel value</span>
          <span className="type-base">Body text reads at base size and wraps before shrinking.</span>
          <span className="type-sm">Secondary text</span>
          <span className="eyebrow">Eyebrow label</span>
        </div>
      </section>

      <section className="token-section" aria-label="Focus and unavailable">
        <h2>Focus and honest-unavailable</h2>
        <div className="focus-demo">
          <button type="button">Focusable control (Tab to see focus ring)</button>
        </div>
        <Unavailable />
      </section>
    </main>
  );
}

export default App;
