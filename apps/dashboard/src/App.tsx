import { loadBootstrapState } from "./bridge/mockCerebralBridge";
import "./app.css";

const bootstrapState = loadBootstrapState();

export function App() {
  return (
    <main className="shell">
      <section className="hero">
        <p className="eyebrow">Heimlich / Pre-Mac dashboard</p>
        <h1>CerebralHelm is running as a local-first workspace.</h1>
        <p className="summary">{bootstrapState.summary}</p>
      </section>

      <section className="grid" aria-label="Dashboard bootstrap state">
        <article className="card">
          <span className="label">Mode</span>
          <strong>{bootstrapState.mode}</strong>
        </article>
        <article className="card">
          <span className="label">Project</span>
          <strong>{bootstrapState.project}</strong>
        </article>
        <article className="card">
          <span className="label">Agent surface</span>
          <strong>{bootstrapState.activeSurface}</strong>
        </article>
        <article className="card">
          <span className="label">Commands today</span>
          <strong>{bootstrapState.commandsToday}</strong>
        </article>
        <article className="card">
          <span className="label">Pending confirmations</span>
          <strong>{bootstrapState.pendingConfirmations}</strong>
        </article>
      </section>
    </main>
  );
}

export default App;
