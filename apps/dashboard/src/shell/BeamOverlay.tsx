/**
 * The ambient-beam reflection layer for one outlined surface (rail panels, the Heimlich stage,
 * the bottom bar, the global launcher). A ring-masked container holding one "light" tile per
 * beam; useAmbientBeam moves the tiles with `transform` writes so all surfaces reflect slices
 * of the same viewport-space beam. Transform-only motion is the point (NIC-122): the previous
 * CSS-var + fixed-attachment `background-position` approach re-rastered every outline on every
 * frame and grew the web process to multiple GB. Decorative only — never intercepts input.
 */
export function BeamOverlay() {
  return (
    <div className="beam-overlay" aria-hidden="true">
      <div className="beam-overlay__light" data-beam="a" />
      <div className="beam-overlay__light" data-beam="b" />
    </div>
  );
}
