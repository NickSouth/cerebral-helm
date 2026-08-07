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

    /// Make `window` transparent and host `content` over a vibrancy layer.
    ///
    /// `content` becomes the window's content, pinned to all four edges of the effect view; the
    /// effect view becomes the window's `contentView`. The clip is applied once, on the effect
    /// view, so web content cannot square off the corners the window rounds.
    static func apply(
        to window: NSWindow,
        hosting content: NSView,
        material: NSVisualEffectView.Material = .hudWindow,
        cornerRadius: CGFloat = standardCornerRadius
    ) {
        window.isOpaque = false
        window.backgroundColor = .clear

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
        vibrancy.layer?.cornerRadius = cornerRadius
        vibrancy.layer?.cornerCurve = .continuous
        vibrancy.layer?.masksToBounds = true

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
}
