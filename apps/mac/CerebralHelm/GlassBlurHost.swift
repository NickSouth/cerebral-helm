import AppKit

/// One piece of glass, as the web layer reported it: viewport coordinates in CSS px (y-down from
/// the top-left) plus the corner radius the CSS draws.
struct GlassRect: Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat

    /// Decode one entry of the `glassControl` message. Returns nil for anything malformed rather
    /// than substituting zeros — a bogus rect would park a blurred rectangle at the window origin.
    init?(_ raw: [String: Any]) {
        guard
            let x = raw["x"] as? Double, let y = raw["y"] as? Double,
            let width = raw["width"] as? Double, let height = raw["height"] as? Double,
            width > 0, height > 0
        else { return nil }
        self.x = CGFloat(x)
        self.y = CGFloat(y)
        self.width = CGFloat(width)
        self.height = CGFloat(height)
        self.radius = CGFloat(raw["radius"] as? Double ?? 0)
    }
}

/// Puts a real desktop blur behind each pane and box of a glass surface — and behind nothing else.
///
/// **Why this is shaped rather than window-wide.** An `NSVisualEffectView` blurs its whole frame,
/// so the obvious implementation — one view filling the window — blurs every empty gap too. On a
/// full-height sidebar or a tall window manager that is an enormous slab of treatment for a handful
/// of controls, which is exactly how it looked and exactly what the owner rejected. The blur has to
/// follow the glass, and only the web layer knows where the glass is; `useGlassGeometry` measures
/// and posts, and this renders one effect view per rect.
///
/// The web view sits on top as the last subview and is transparent, so these show through wherever
/// the surface does not paint. The web layer's own fill stays the tint; this only supplies blur.
///
/// Views are **pooled**, not rebuilt. Scrolling a list republishes geometry many times a second,
/// and allocating a fresh `NSVisualEffectView` per frame would churn hard for a result that is
/// almost always the same set of boxes in slightly different places.
final class GlassBlurHost: NSView {
    /// Chosen by eye against the real dashboard, from a board of all fourteen non-deprecated
    /// materials (owner, 2026-08-07). macOS exposes no blur radius — only this fixed menu — so the
    /// name is the whole API and it is not obvious from reading it: `.underWindowBackground`, which
    /// sounds neutral, is one of the *heaviest* and read as a grey slab. `.hudWindow` is dark and
    /// genuinely see-through, which is what a surface floating over the user's work wants.
    private static let material: NSVisualEffectView.Material = .hudWindow

    private var pool: [NSVisualEffectView] = []
    private var current: [GlassRect] = []

    /// The web content, kept as the topmost subview so the glass always renders behind it.
    private weak var contentView: NSView?

    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        contentView = content
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Re-place the blur to match the surface's current glass.
    func update(rects: [GlassRect]) {
        guard rects != current else { return }
        current = rects
        layoutGlass()
    }

    override func layout() {
        super.layout()
        // The window resized, so every reported rect maps to a different place. The web layer will
        // republish too, but doing it here as well means the blur never lags a resize by a frame.
        layoutGlass()
    }

    private func layoutGlass() {
        while pool.count < current.count {
            let effect = NSVisualEffectView()
            effect.material = Self.material
            // `.behindWindow` is the one that blurs the DESKTOP. `.withinWindow` would blur this
            // window's own content, which is transparent — i.e. nothing.
            effect.blendingMode = .behindWindow
            // These windows are frequently looked at while not key (they float over other apps), so
            // the material must not drain when focus moves.
            effect.state = .active
            // Every CerebralHelm palette is dark; semantic materials otherwise follow the *system*
            // appearance and a light-mode Mac would put a bright frost under a dark surface.
            effect.appearance = NSAppearance(named: .darkAqua)
            effect.wantsLayer = true
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            // Below the web content, always.
            addSubview(effect, positioned: .below, relativeTo: contentView)
            pool.append(effect)
        }

        let height = bounds.height
        for (index, effect) in pool.enumerated() {
            guard index < current.count else {
                effect.isHidden = true
                continue
            }
            let rect = current[index]
            effect.isHidden = false
            // Web coordinates run y-down from the top of the viewport; AppKit runs y-up from the
            // bottom of this view. The web view fills this host exactly, so one flip converts.
            effect.frame = NSRect(
                x: rect.x,
                y: height - rect.y - rect.height,
                width: rect.width,
                height: rect.height
            )
            effect.layer?.cornerRadius = rect.radius
        }
    }
}
