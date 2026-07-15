import { useCallback, useEffect, useState } from "react";
import { useBridge } from "../state/BridgeProvider";
import type {
  NavigatorWindow,
  NavigatorWindowGroup,
  WindowInventory
} from "../bridge/cerebralBridge";

/** Fallback app mark when a group carries no icon (mock/preview, or a render miss). */
function WindowMark() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="M3 9h18" />
    </svg>
  );
}

function MinusGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
      <path d="M6 12h12" />
    </svg>
  );
}
function CloseGlyph() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
      <path d="M7 7l10 10M17 7L7 17" />
    </svg>
  );
}

/** One window tile: app icon + window title (+ app name for disambiguation), with
 *  minimize/close controls. Clicking the tile body surfaces the window. */
function WindowCard({
  window: win,
  group,
  onSurface,
  onMinimize,
  onClose
}: {
  window: NavigatorWindow;
  group: NavigatorWindowGroup;
  onSurface: () => void;
  onMinimize: () => void;
  onClose: () => void;
}) {
  const title = win.title.trim() || group.appName;
  return (
    <div className="win-nav__card" data-minimized={win.minimized ? "true" : undefined}>
      <button
        type="button"
        className="win-nav__card-open"
        aria-label={`Surface ${title}`}
        title={`Surface ${title}`}
        onClick={onSurface}
      >
        <span className="win-nav__card-icon" aria-hidden="true">
          {group.appIconPng ? (
            <img src={`data:image/png;base64,${group.appIconPng}`} alt="" />
          ) : (
            <WindowMark />
          )}
        </span>
        <span className="win-nav__card-text">
          <span className="win-nav__card-title">{title}</span>
          <span className="win-nav__card-sub">
            {group.appName}
            {win.minimized ? " · minimized" : ""}
          </span>
        </span>
      </button>
      <span className="win-nav__card-actions">
        <button
          type="button"
          className="win-nav__icon-btn"
          aria-label={`Minimize ${title}`}
          title="Minimize"
          onClick={onMinimize}
        >
          <MinusGlyph />
        </button>
        <button
          type="button"
          className="win-nav__icon-btn win-nav__icon-btn--close"
          aria-label={`Close ${title}`}
          title="Close window"
          onClick={onClose}
        >
          <CloseGlyph />
        </button>
      </span>
    </div>
  );
}

/** One app's windows: a single card, or an expandable stack when the app has more
 *  than one window (collapsed shows the front window with a count; expand reveals all). */
function AppGroup({
  group,
  expanded,
  onToggleExpand,
  onSurface,
  onMinimize,
  onClose
}: {
  group: NavigatorWindowGroup;
  expanded: boolean;
  onToggleExpand: () => void;
  onSurface: (id: string) => void;
  onMinimize: (id: string) => void;
  onClose: (id: string) => void;
}) {
  const multi = group.windows.length > 1;
  const card = (win: NavigatorWindow) => (
    <WindowCard
      key={win.id}
      window={win}
      group={group}
      onSurface={() => onSurface(win.id)}
      onMinimize={() => onMinimize(win.id)}
      onClose={() => onClose(win.id)}
    />
  );

  if (multi && !expanded) {
    const [front] = group.windows;
    return (
      <div className="win-nav__stack">
        <button
          type="button"
          className="win-nav__stack-toggle"
          aria-expanded={false}
          aria-label={`Show all ${group.windows.length} ${group.appName} windows`}
          title={`${group.windows.length} windows — expand`}
          onClick={onToggleExpand}
        >
          {group.windows.length}
        </button>
        {card(front)}
      </div>
    );
  }

  return (
    <div className="win-nav__group">
      {multi ? (
        <button
          type="button"
          className="win-nav__group-header"
          aria-expanded
          onClick={onToggleExpand}
        >
          {group.appName} · {group.windows.length}
        </button>
      ) : null}
      {group.windows.map(card)}
    </div>
  );
}

/**
 * The window navigator (NIC-143): an app-grouped, iPhone-switcher-style list of every
 * open window, with per-window minimize/close and click-to-surface. It layers above open
 * windows — in the native shell as its own floating window (`variant="standalone"`), and
 * in a plain browser as an in-dashboard overlay (`variant="overlay"`). All actions go
 * through the bridge's direct-capability window ops; the list refreshes after each.
 */
export function WindowNavigator({
  variant,
  onClose
}: {
  variant: "standalone" | "overlay";
  onClose: () => void;
}) {
  const bridge = useBridge();
  const [inventory, setInventory] = useState<WindowInventory | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      setInventory(await bridge.listWindows());
    } catch {
      setInventory({ apps: [] });
    }
  }, [bridge]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    function onKey(event: KeyboardEvent): void {
      if (event.key === "Escape") {
        onClose();
      }
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  const surface = async (id: string): Promise<void> => {
    await bridge.surfaceWindow({ windowId: id });
    // Surfacing brings the window forward — dismiss the navigator to reveal it.
    onClose();
  };
  const minimize = async (id: string): Promise<void> => {
    await bridge.minimizeWindow({ windowId: id });
    await refresh();
  };
  const closeWindow = async (id: string): Promise<void> => {
    await bridge.closeWindow({ windowId: id });
    await refresh();
  };

  const apps = inventory?.apps ?? [];
  const total = apps.reduce((sum, group) => sum + group.windows.length, 0);

  const body = (
    <section className="win-nav" role="dialog" aria-modal={variant === "overlay"} aria-label="Open windows">
      <header className="win-nav__header">
        <h2 className="win-nav__title">Windows{total > 0 ? ` · ${total}` : ""}</h2>
        <button type="button" className="win-nav__close" aria-label="Close window navigator" onClick={onClose}>
          <CloseGlyph />
        </button>
      </header>
      <div className="win-nav__scroll">
        {apps.length === 0 ? (
          <p className="win-nav__empty">No open windows to show.</p>
        ) : (
          apps.map((group) => (
            <AppGroup
              key={group.bundleId}
              group={group}
              expanded={expanded === group.bundleId}
              onToggleExpand={() =>
                setExpanded((current) => (current === group.bundleId ? null : group.bundleId))
              }
              onSurface={(id) => void surface(id)}
              onMinimize={(id) => void minimize(id)}
              onClose={(id) => void closeWindow(id)}
            />
          ))
        )}
      </div>
    </section>
  );

  if (variant === "standalone") {
    return body;
  }
  return (
    <>
      <div className="win-nav__scrim" onClick={onClose} aria-hidden="true" />
      {body}
    </>
  );
}
