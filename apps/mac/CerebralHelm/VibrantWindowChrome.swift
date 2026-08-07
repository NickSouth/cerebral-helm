import AppKit
import WebKit

/// The translucency setup shared by CerebralHelm's three **content** windows — Settings, More Apps
/// and the Window Navigator (2026-08-07).
///
/// Those three are `.titled` windows whose macOS chrome is hidden and whose entire surface is drawn
/// in web content. Until now they had no transparency setup at all, so the web layer's glass had
/// nothing behind it but the window's own opaque background: a translucent slab rendered as a flat
/// grey rectangle sitting inside a solid box. The other window family in the app (mode menu, layout
/// pin, sidebar) is borderless and already transparent; this is the missing half for the family that
/// stays titled.
///
/// Three things have to be true **together**, which is why this is one function rather than a
/// checklist copied into three controllers:
///
/// 1. the **window** stops painting (`isOpaque = false`, clear background), and
/// 2. the **web view** stops painting (`drawsBackground = false`), so anything the web layer leaves
///    transparent is a genuine hole through to the desktop, and
/// 3. an `NSVisualEffectView` sits behind the web view to supply the blur.
///
/// Step 3 is not optional and cannot be done in CSS. Inside a WKWebView, `backdrop-filter` can only
/// sample the page's own backdrop — which, once step 2 lands, is empty. Blurring the *desktop*
/// belongs to the window server, and `NSVisualEffectView` is the only way to ask for it. Web
/// surfaces should therefore supply the tint and drop their own `backdrop-filter` when running
/// standalone; the two would otherwise be paying for a blur that only one of them can deliver.
///
/// `.titled` is kept deliberately rather than switching these to `.borderless` like the other
/// family: Settings resizes, and the titled frame keeps macOS's own resize handling and window
/// behaviours. What `.titled` does *not* survive is a clear background — the frame view stops
/// drawing, and with it the rounded-corner mask — so the radius is applied to the layer here and
/// each caller passes the radius its web surface was designed around.
enum VibrantWindowChrome {
    /// Matches `--ch-radius-lg` (0.75rem ≈ 12px) — the radius the floated variants of these same
    /// surfaces use when they render as in-page overlays.
    static let standardCornerRadius: CGFloat = 12

    /// How far the blur dissolves at each edge, as a fraction of that dimension (0 = a hard edge).
    ///
    /// Some surfaces have no edge of their own — the sidebar dissolves into the desktop on its
    /// right and softens top and bottom, and the window manager now does the same (owner,
    /// 2026-08-07). Their web layers already fade out with a CSS mask, but a rectangular vibrancy
    /// view behind them would put a hard blur edge exactly where the tint has faded to nothing,
    /// which is worse than having no blur at all. The native mask has to agree with the CSS one.
    struct EdgeFade: Equatable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
        var top: CGFloat = 0
        var bottom: CGFloat = 0

        static let none = EdgeFade()

        /// Softened on every side — for a surface that floats free rather than attaching to a
        /// screen edge.
        static func all(_ fraction: CGFloat) -> EdgeFade {
            EdgeFade(leading: fraction, trailing: fraction, top: fraction, bottom: fraction)
        }

        var isNone: Bool { self == .none }
    }

    /// Make `window` transparent and host `content` over a vibrancy layer.
    ///
    /// `content` becomes the window's content, pinned to all four edges of the effect view; the
    /// effect view becomes the window's `contentView`. The clip is applied once, on the effect
    /// view, so web content cannot square off the corners the window rounds.
    static func apply(
        to window: NSWindow,
        hosting content: NSView,
        material: NSVisualEffectView.Material = .hudWindow,
        cornerRadius: CGFloat = standardCornerRadius,
        edgeFade: EdgeFade = .none
    ) {
        window.isOpaque = false
        window.backgroundColor = .clear
        if !edgeFade.isNone {
            // A window shadow traces the window's *rect*, so a surface with no edge of its own
            // would be outlined by a hard rectangle it spent the whole design dissolving away.
            window.hasShadow = false
        }

        let vibrancy = NSVisualEffectView()
        vibrancy.material = material
        // `.behindWindow` is the one that blurs the desktop; `.withinWindow` would only blur this
        // window's own content, which is the job the web layer already does for itself.
        vibrancy.blendingMode = .behindWindow
        // `.followsWindowActiveState` would drain the blur whenever the window is not key. These
        // windows are summoned over other apps and are frequently not key while still being looked
        // at, so the material stays live.
        vibrancy.state = .active
        // Every CerebralHelm palette is dark. Semantic materials follow the *system* appearance, so
        // without this a light-mode Mac would put a bright material under a dark web surface.
        vibrancy.appearance = NSAppearance(named: .darkAqua)
        vibrancy.wantsLayer = true
        // A radius and an edge fade are two answers to the same question; a fade already eats the
        // corners, and clipping it as well would put back the hard boundary it exists to remove.
        vibrancy.layer?.cornerRadius = edgeFade.isNone ? cornerRadius : 0
        vibrancy.layer?.cornerCurve = .continuous
        vibrancy.layer?.masksToBounds = edgeFade.isNone
        vibrancy.maskImage = edgeFadeMask(edgeFade)

        content.translatesAutoresizingMaskIntoConstraints = false
        vibrancy.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor),
            content.topAnchor.constraint(equalTo: vibrancy.topAnchor),
            content.bottomAnchor.constraint(equalTo: vibrancy.bottomAnchor)
        ])

        window.contentView = vibrancy
        // A transparent window's shadow is derived from the alpha of what it draws, and the cached
        // shadow was computed for the opaque rect. Without this the old square shadow outlines the
        // new rounded corners.
        window.invalidateShadow()
    }

    /// Stop a web view painting its own background, so the vibrancy behind it shows through
    /// wherever the surface is transparent. Same technique the palette and mode menu already use.
    static func makeTransparent(_ webView: WKWebView) {
        webView.setValue(false, forKey: "drawsBackground")
    }

    /// Transparency with **no material at all** — the window shows nothing except what the web
    /// layer actually paints.
    ///
    /// For surfaces that are a set of floating boxes rather than a panel: the sidebar and the window
    /// manager (owner, 2026-08-07). An `NSVisualEffectView` blurs and tints the **entire window
    /// rect**, so on a surface that is mostly empty space it produces a large dark slab with a few
    /// controls on it — the opposite of the intent. "Blur behind the boxes only" is not something a
    /// window-level material can express; it would need one effect view per box, positioned from
    /// geometry the web layer reports.
    ///
    /// The boxes therefore carry their own legibility, in CSS, where their geometry already lives.
    @discardableResult
    static func clear(window: NSWindow, hosting content: NSView) -> GlassBlurHost {
        window.isOpaque = false
        window.backgroundColor = .clear
        // Nothing here fills the window rect, so a window shadow would outline a rectangle that
        // does not visually exist.
        window.hasShadow = false
        // The host puts a real desktop blur behind each pane and box the web layer reports, and
        // behind nothing else — the shaped alternative to the window-wide material above.
        let host = GlassBlurHost(content: content)
        window.contentView = host
        window.invalidateShadow()
        return host
    }

    /// An alpha mask that ramps the blur in from each faded edge.
    ///
    /// Drawn once at a small fixed size and stretched: a linear gradient is scale-invariant, so
    /// this stays correct through every window resize without regenerating anything. The two axes
    /// are composited with `.destinationIn`, which multiplies alpha — the same operation as CSS's
    /// `mask-composite: intersect`, and for the same reason: a corner should be the *minimum* of
    /// its two edges, not the sum.
    static func edgeFadeMask(_ fade: EdgeFade) -> NSImage? {
        guard !fade.isNone else { return nil }

        let image = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.setFill()
            rect.fill()
            context.setBlendMode(.destinationIn)
            drawAxisGradient(context, in: rect, horizontal: true, from: fade.leading, to: fade.trailing)
            // `flipped: false`, so y runs up the image: the *start* of the vertical axis is the
            // bottom edge.
            drawAxisGradient(context, in: rect, horizontal: false, from: fade.bottom, to: fade.top)
            return true
        }
        image.resizingMode = .stretch
        return image
    }

    /// One axis of the mask: opaque through the middle, ramping to clear over `from`/`to` of the
    /// length at each end. A zero ramp leaves that end hard.
    private static func drawAxisGradient(
        _ context: CGContext,
        in rect: CGRect,
        horizontal: Bool,
        from start: CGFloat,
        to end: CGFloat
    ) {
        guard start > 0 || end > 0 else { return }
        let clear = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        let solid = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        var locations: [CGFloat] = [0]
        var colors: [CGColor] = [start > 0 ? clear : solid]
        if start > 0 {
            locations.append(min(start, 1)); colors.append(solid)
        }
        if end > 0 {
            locations.append(max(0, 1 - end)); colors.append(solid)
        }
        locations.append(1)
        colors.append(end > 0 ? clear : solid)

        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: locations
            )
        else { return }

        let startPoint = horizontal
            ? CGPoint(x: rect.minX, y: rect.midY)
            : CGPoint(x: rect.midX, y: rect.minY)
        let endPoint = horizontal
            ? CGPoint(x: rect.maxX, y: rect.midY)
            : CGPoint(x: rect.midX, y: rect.maxY)
        context.drawLinearGradient(
            gradient,
            start: startPoint,
            end: endPoint,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
}
