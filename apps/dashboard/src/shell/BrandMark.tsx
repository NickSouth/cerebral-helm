/**
 * The CerebralHelm product brand (NIC-118 visual identity): the helm-wheel mark — a streamlined
 * ship's wheel whose top two handles are Heimlich's goat horns, with a brain at the hub — and the
 * CerebralHelm wordmark (Orbitron 500, traced to outline paths at build time so there is no font
 * dependency; regenerate via the fontTools pipeline if the wording ever changes).
 *
 * All color enters through the `brand-*` classes in shell.css, which resolve the data-mode accent
 * tokens — so the brand re-tints with the active mode and never hardcodes a palette here
 * (constitution §2: no raw hex in components; mode color only via data-mode).
 */

/** The helm-wheel mark (top-right corner). Sized by `.brand-mark` in shell.css (rem, so it
 *  scales with the viewport-height root font-size like every other glyph). */
export function BrandMark() {
  return (
    <svg className="brand-mark" viewBox="-110 -142 220 252" aria-hidden="true" focusable="false">
      {/* Wheel frame: rim + inner ring + spokes + five handle pegs (accent secondary). */}
      <g className="brand-mark__frame" fill="none" strokeWidth={7} strokeLinecap="round">
        <circle r={76} />
        <circle r={64} strokeWidth={2} opacity={0.45} />
        <g strokeWidth={3.5} opacity={0.75}>
          <line x1={22.2} y1={-28.4} x2={37.6} y2={-48.1} />
          <line x1={-22.2} y1={-28.4} x2={-37.6} y2={-48.1} />
          <line x1={36} y1={0} x2={61} y2={0} />
          <line x1={-36} y1={0} x2={-61} y2={0} />
          <line x1={25.5} y1={25.5} x2={43.1} y2={43.1} />
          <line x1={-25.5} y1={25.5} x2={-43.1} y2={43.1} />
          <line x1={0} y1={36} x2={0} y2={61} />
        </g>
        <line x1={79.5} y1={0} x2={97} y2={0} />
        <line x1={-79.5} y1={0} x2={-97} y2={0} />
        <line x1={56.2} y1={56.2} x2={68.6} y2={68.6} />
        <line x1={-56.2} y1={56.2} x2={-68.6} y2={68.6} />
        <line x1={0} y1={79.5} x2={0} y2={97} />
      </g>
      {/* Peg tip dots + the goat-horn top handles (accent primary — the Heimlich reference). */}
      <g className="brand-mark__accent">
        <circle cx={101} cy={0} r={4.5} />
        <circle cx={-101} cy={0} r={4.5} />
        <circle cx={71.4} cy={71.4} r={4.5} />
        <circle cx={-71.4} cy={71.4} r={4.5} />
        <circle cx={0} cy={101} r={4.5} />
        <path
          id="brand-mark-horn"
          d="M40 -64 C 48 -95, 58 -118, 86 -136 C 72 -120, 64 -98, 54 -54 Z"
        />
        <use href="#brand-mark-horn" transform="scale(-1,1)" />
      </g>
      {/* Hub (dark ground so the brain reads over the spokes) + the line-art brain. */}
      <circle className="brand-mark__hub" r={34} strokeWidth={4} />
      <g
        className="brand-mark__brain"
        fill="none"
        strokeWidth={3.5}
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <g id="brand-mark-brain-half">
          <path d="M0 -23 C -8 -26 -16 -22 -18 -15 C -26 -13 -28 -4 -24 2 C -27 8 -23 16 -15 17 C -12 22 -5 23 0 20" />
          <path d="M-15 -12 C -9 -11 -7 -6 -10 -2" />
          <path d="M-17 4 C -11 3 -8 8 -10 12" />
        </g>
        <use href="#brand-mark-brain-half" transform="scale(-1,1)" />
        <path d="M0 -23 C 3 -15 -2 -6 1 3 C 2 9 0 14 0 20" />
      </g>
    </svg>
  );
}

/** The CerebralHelm wordmark — one camelCase word; "Cerebral" takes the mode's primary accent,
 *  "Helm" the secondary. Glyph outlines and kerned advances come straight from Orbitron 500
 *  (font units, 1000/em; the flip transform converts the font's y-up space to SVG's y-down). */
export function BrandWordmark() {
  return (
    <svg className="brand-wordmark" viewBox="0 0 7709 771" aria-hidden="true" focusable="false">
      <g transform="translate(0,771) scale(1,-1)">
        <g className="brand-wordmark__primary">
          <path
            transform="translate(0,0)"
            d="M186.2 0Q150.3 0 120.6 17.5Q90.9 34.9 73.5 64.6Q56 94.3 56 130.2V589.8Q56 625.7 73.5 655.4Q90.9 685.1 120.6 702.5Q150.3 720 186.2 720H774V611.6H200.8Q184.8 611.6 174.4 601.4Q164 591.2 164 574.8V145.2Q164 129.2 174.4 118.8Q184.8 108.4 200.8 108.4H774V0Z"
          />
          <path
            transform="translate(818,0)"
            d="M180.8 0Q145.4 0 116 17.8Q86.6 35.6 68.8 65Q51 94.4 51 129.8V450.2Q51 485.6 68.8 515Q86.6 544.4 116 562.2Q145.4 580 180.8 580H510.5Q546.9 580 576.2 562.3Q605.6 544.5 623.3 515Q640.9 485.4 640.9 450.2V235.9H158.9V132.7Q158.9 122.5 166.2 115.2Q173.5 107.9 183.7 107.9H640.9V0H180.8ZM158.9 336.8H532.4V447.3Q532.4 457.5 525.1 464.8Q517.8 472.1 507.6 472.1H183.7Q173.5 472.1 166.2 464.8Q158.9 457.5 158.9 447.3Z"
          />
          <path
            transform="translate(1504,0)"
            d="M52 0V450.2Q52 485.6 69.8 515Q87.6 544.4 117.1 562.2Q146.7 580 182.1 580H505.9V472.1H184.7Q174.5 472.1 167.2 464.8Q159.9 457.5 159.9 447.3V0Z"
          />
          <path
            transform="translate(2025,0)"
            d="M180.8 0Q145.4 0 116 17.8Q86.6 35.6 68.8 65Q51 94.4 51 129.8V450.2Q51 485.6 68.8 515Q86.6 544.4 116 562.2Q145.4 580 180.8 580H510.5Q546.9 580 576.2 562.3Q605.6 544.5 623.3 515Q640.9 485.4 640.9 450.2V235.9H158.9V132.7Q158.9 122.5 166.2 115.2Q173.5 107.9 183.7 107.9H640.9V0H180.8ZM158.9 336.8H532.4V447.3Q532.4 457.5 525.1 464.8Q517.8 472.1 507.6 472.1H183.7Q173.5 472.1 166.2 464.8Q158.9 457.5 158.9 447.3Z"
          />
          <path
            transform="translate(2717,0)"
            d="M54 0V770H161.9V580H514.1Q549.6 580 579.2 562.2Q608.7 544.4 626.3 515Q643.9 485.6 643.9 450.2V129.8Q643.9 94.4 626.3 65Q608.7 35.6 579.2 17.8Q549.6 0 514.1 0ZM187.3 107.9H511.2Q521.4 107.9 528.7 115.2Q536 122.5 536 132.7V447.3Q536 457.5 528.7 464.8Q521.4 472.1 511.2 472.1H187.3Q177.1 472.1 169.5 464.8Q161.9 457.5 161.9 447.3V132.7Q161.9 122.5 169.5 115.2Q177.1 107.9 187.3 107.9Z"
          />
          <path
            transform="translate(3384,0)"
            d="M52 0V450.2Q52 485.6 69.8 515Q87.6 544.4 117.1 562.2Q146.7 580 182.1 580H505.9V472.1H184.7Q174.5 472.1 167.2 464.8Q159.9 457.5 159.9 447.3V0Z"
          />
          <path
            transform="translate(3908,0)"
            d="M181.8 0Q146.3 0 116.7 17.8Q87.2 35.6 69.6 65Q52 94.4 52 129.8V344.1H533.4V447.3Q533.4 457.5 526.1 464.8Q518.8 472.1 508.6 472.1H52V580H511.5Q547.9 580 577.2 562.3Q606.6 544.5 624.3 515Q641.9 485.4 641.9 450.2V0ZM184.7 107.9H533.4V243.2H159.9V132.7Q159.9 122.5 167.2 115.2Q174.5 107.9 184.7 107.9Z"
          />
          <path
            transform="translate(4586,0)"
            d="M181.8 0Q146.4 0 117 17.8Q87.6 35.6 69.8 65Q52 94.4 52 129.8V770.4H160.3V132.7Q160.3 122.5 167.6 115.2Q174.9 107.9 185 107.9H290V0H181.8Z"
          />
        </g>
        <g className="brand-wordmark__secondary">
          <path
            transform="translate(4901,0)"
            d="M57 0V720H165V414.5H685.3V720H793.9V0H685.3V305.5H165V0Z"
          />
          <path
            transform="translate(5752,0)"
            d="M180.8 0Q145.4 0 116 17.8Q86.6 35.6 68.8 65Q51 94.4 51 129.8V450.2Q51 485.6 68.8 515Q86.6 544.4 116 562.2Q145.4 580 180.8 580H510.5Q546.9 580 576.2 562.3Q605.6 544.5 623.3 515Q640.9 485.4 640.9 450.2V235.9H158.9V132.7Q158.9 122.5 166.2 115.2Q173.5 107.9 183.7 107.9H640.9V0H180.8ZM158.9 336.8H532.4V447.3Q532.4 457.5 525.1 464.8Q517.8 472.1 507.6 472.1H183.7Q173.5 472.1 166.2 464.8Q158.9 457.5 158.9 447.3Z"
          />
          <path
            transform="translate(6422,0)"
            d="M181.8 0Q146.4 0 117 17.8Q87.6 35.6 69.8 65Q52 94.4 52 129.8V770.4H160.3V132.7Q160.3 122.5 167.6 115.2Q174.9 107.9 185 107.9H290V0H181.8Z"
          />
          <path
            transform="translate(6731,0)"
            d="M54 0V580H795.2Q831.6 580 861 562.2Q890.4 544.4 907.7 515Q924.9 485.6 924.9 450.2V0H818V447.3Q818 457.5 810.4 464.8Q802.8 472.1 792.6 472.1H569.5Q559.4 472.1 552 464.8Q544.7 457.5 544.7 447.3V0H435.8V447.3Q435.8 457.5 428.5 464.8Q421.2 472.1 411.1 472.1H187.3Q177.1 472.1 169.8 464.8Q162.5 457.5 162.5 447.3V0Z"
          />
        </g>
      </g>
    </svg>
  );
}
