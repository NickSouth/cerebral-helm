import React from "react";
import ReactDOM from "react-dom/client";

// The native shell loads the same bundle at `index.html?surface=palette` into the
// floating command-palette panel (NIC-75); everywhere else renders the full dashboard.
// The two surfaces are loaded by *dynamic* import so only the active one's module runs:
// both `AppRoot` and `CommandPaletteApp` create a bridge at module scope (which claims
// the singleton `window.__cerebralReceive`), so importing the inactive surface would
// clobber the active surface's receiver and silently drop its events + responses.
const isPalette =
  typeof window !== "undefined" &&
  new URLSearchParams(window.location.search).get("surface") === "palette";

const root = ReactDOM.createRoot(document.getElementById("root")!);

if (isPalette) {
  void import("./app/CommandPaletteApp").then(({ CommandPaletteApp }) => {
    root.render(
      <React.StrictMode>
        <CommandPaletteApp />
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
