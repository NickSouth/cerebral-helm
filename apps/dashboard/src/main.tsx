import React from "react";
import ReactDOM from "react-dom/client";

// The native shell loads the same bundle at `index.html?surface=palette` into the
// floating command-palette panel (NIC-75), at `index.html?surface=settings` into
// the dedicated settings window (backdrop-policy decision, 2026-07-06), and at
// `index.html?surface=moreapps` into the top-most More Apps launcher window
// (NIC-148); everywhere else renders the full dashboard. The surfaces are loaded by *dynamic* import so
// only the active one's module runs: each creates a bridge at module scope (which
// claims the singleton `window.__cerebralReceive`), so importing an inactive
// surface would clobber the active surface's receiver and silently drop its
// events + responses.
const surface =
  typeof window !== "undefined"
    ? new URLSearchParams(window.location.search).get("surface")
    : null;

const root = ReactDOM.createRoot(document.getElementById("root")!);

if (surface === "palette") {
  void import("./app/CommandPaletteApp").then(({ CommandPaletteApp }) => {
    root.render(
      <React.StrictMode>
        <CommandPaletteApp />
      </React.StrictMode>
    );
  });
} else if (surface === "settings") {
  void import("./app/SettingsApp").then(({ SettingsApp }) => {
    root.render(
      <React.StrictMode>
        <SettingsApp />
      </React.StrictMode>
    );
  });
} else if (surface === "companion") {
  void import("./app/CompanionApp").then(({ CompanionApp }) => {
    root.render(
      <React.StrictMode>
        <CompanionApp />
      </React.StrictMode>
    );
  });
} else if (surface === "moreapps") {
  void import("./app/MoreAppsApp").then(({ MoreAppsApp }) => {
    root.render(
      <React.StrictMode>
        <MoreAppsApp />
      </React.StrictMode>
    );
  });
} else {
  void import("./app/AppRoot").then(({ AppRoot }) => {
    root.render(
      <React.StrictMode>
        <AppRoot />
      </React.StrictMode>
    );
  });
}
