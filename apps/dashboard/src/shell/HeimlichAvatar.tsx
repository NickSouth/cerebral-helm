/**
 * Heimlich's identity portrait (NIC-118 visual identity): a geometric cyborg goat head, front
 * view — big swept horns, leaf ears, faceted muzzle, and the signature goatee. The left eye is
 * organic (horizontal goat-bar pupil); the right side carries the cyborg hardware: lens with
 * crosshair ticks, brow plate, a circuit trace down the cheek, and a riveted jaw seam.
 *
 * Color enters only through the `heimlich-avatar__*` classes in shell.css, which resolve the
 * data-mode-repointed --ch-heimlich-* stream palette — organic structure follows the primary,
 * cyborg hardware the secondary — so the portrait re-tints with the active mode (constitution §2).
 */
export function HeimlichAvatar() {
  return (
    <svg
      className="heimlich-avatar"
      viewBox="-104 -176 208 316"
      aria-hidden="true"
      focusable="false"
    >
      {/* Horns (organic fill). */}
      <g className="heimlich-avatar__fill">
        <path
          id="heimlich-avatar-horn"
          d="M16 -86 C 28 -122, 46 -152, 84 -170 C 62 -146, 50 -118, 38 -80 Z"
        />
        <use href="#heimlich-avatar-horn" transform="scale(-1,1)" />
      </g>

      {/* Ears + face outline + facet lines (organic line work). */}
      <g className="heimlich-avatar__line" fill="none" strokeWidth={5} strokeLinejoin="round">
        <path d="M52 -58 L100 -66 L60 -34 Z" />
        <path d="M-52 -58 L-100 -66 L-60 -34 Z" />
        <path d="M-34 -84 L-52 -58 L-44 -6 L-18 84 L-10 108 L10 108 L18 84 L44 -6 L52 -58 L34 -84 Z" />
        <g strokeWidth={2.5} opacity={0.35}>
          <path d="M-52 -58 L0 -42 L52 -58" />
          <path d="M-44 -6 L0 -22 L44 -6" />
          <path d="M-18 84 L0 72 L18 84" />
        </g>
      </g>

      {/* Left eye: organic almond with the horizontal goat-bar pupil. */}
      <path
        className="heimlich-avatar__line"
        d="M-40 -30 Q-28 -39 -16 -30 Q-28 -21 -40 -30 Z"
        fill="none"
        strokeWidth={3}
      />
      <rect className="heimlich-avatar__fill" x={-34} y={-33} width={12} height={6} rx={2} />

      {/* Right eye: cyborg lens + brow plate + cheek circuit trace + jaw seam (secondary). */}
      <g
        className="heimlich-avatar__cyber-line"
        fill="none"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <circle cx={28} cy={-30} r={13} strokeWidth={3.5} />
        <g strokeWidth={2}>
          <line x1={28} y1={-47} x2={28} y2={-41} />
          <line x1={28} y1={-19} x2={28} y2={-13} />
          <line x1={11} y1={-30} x2={17} y2={-30} />
          <line x1={39} y1={-30} x2={45} y2={-30} />
        </g>
        <path d="M14 -50 L44 -50 L48 -44" strokeWidth={3} />
        <path d="M28 -15 L28 8 L42 22 L42 40" strokeWidth={2.5} />
        <path d="M38 0 L16 70" strokeWidth={2} opacity={0.6} />
      </g>
      <g className="heimlich-avatar__cyber-fill">
        <circle cx={28} cy={-30} r={5.5} />
        <circle cx={28} cy={8} r={2.5} />
        <circle cx={42} cy={22} r={2.5} />
        <circle cx={42} cy={40} r={2.5} />
        <g opacity={0.85}>
          <circle cx={34} cy={10} r={2} />
          <circle cx={28} cy={34} r={2} />
          <circle cx={22} cy={58} r={2} />
        </g>
      </g>

      {/* Nostrils + goatee. */}
      <g className="heimlich-avatar__line" strokeWidth={3} strokeLinecap="round">
        <line x1={-8} y1={96} x2={-4} y2={102} />
        <line x1={8} y1={96} x2={4} y2={102} />
      </g>
      <path className="heimlich-avatar__fill" d="M-9 108 L-3 124 L0 136 L3 124 L9 108 Z" />
    </svg>
  );
}
