import { createMockCerebralBridge, loadBootstrapState } from "../bridge/mockCerebralBridge";
import { confirmationBridgeEvent, lifecycleBridgeEvents } from "../bridge/eventFixtures";
import { getDashboardFixture } from "../fixtures/canonicalFixtures";
import type { BridgeEvent } from "../bridge/cerebralBridge";
import { createBridgeStore, reduceDashboardState } from "./bridgeStore";

const IRRELEVANT_EVENT: BridgeEvent = {
  eventId: "brevt_irrelevant1",
  type: "config.changed",
  schemaVersion: "1.0.0",
  timestamp: "2026-06-23T16:00:00.000Z",
  payload: {}
};

function lifecycleEvent(currentStatus: string): BridgeEvent {
  return {
    eventId: `brevt_${currentStatus}`,
    type: "command.lifecycle.transition",
    schemaVersion: "1.0.0",
    timestamp: "2026-06-23T16:00:00.000Z",
    payload: { currentStatus }
  };
}

describe("reduceDashboardState", () => {
  // Reverses an earlier assertion on purpose (NIC-171). This test used to prove that the command
  // lifecycle mapped onto Heimlich's state — running → "acting", succeeded → "success" ("Done"),
  // failed → "error". That was wrong twice: the terminal states had nothing to return them to
  // rest, so the indicator stuck on "Done" until a mode switch happened to swap the bootstrap
  // `heimlich`; and animating a lifecycle implies an assistant runtime that does not exist yet.
  // The indicator is now locked to its bootstrap resting state, so the lifecycle must NOT move it.
  it("never drives Heimlich state from the command lifecycle (NIC-171)", () => {
    const base = loadBootstrapState();
    expect(base.heimlich.state).toBe("idle");
    for (const status of [
      "received",
      "planned",
      "requires_confirmation",
      "running",
      "succeeded",
      "failed",
      "cancelled"
    ]) {
      expect(reduceDashboardState(base, lifecycleEvent(status)).heimlich.state).toBe("idle");
    }
  });

  it("cannot be left stuck on a terminal state by a completed command (NIC-171)", () => {
    // The reported bug: run one command, and the indicator reads "Done" forever.
    const base = loadBootstrapState();
    const afterRun = ["received", "running", "succeeded"].reduce(
      (state, status) => reduceDashboardState(state, lifecycleEvent(status)),
      base
    );
    expect(afterRun.heimlich.state).toBe("idle");
    // No command touched anything else either — the whole reduction is a no-op by reference.
    expect(afterRun).toBe(base);
  });

  it("returns the same reference when nothing changes (no needless re-render)", () => {
    const base = loadBootstrapState();
    expect(reduceDashboardState(base, IRRELEVANT_EVENT)).toBe(base);
    // An unknown lifecycle status also leaves state untouched.
    expect(reduceDashboardState(base, lifecycleEvent("idle"))).toBe(base);
    // ...as does a lifecycle status with no workflow run to clear.
    expect(reduceDashboardState(base, lifecycleEvent("running"))).toBe(base);
    expect(reduceDashboardState(base, lifecycleEvent("succeeded"))).toBe(base);
  });

  it("folds live weather into liveWeather that survives a mode switch (NIC-169)", () => {
    const base = loadBootstrapState();
    const live = {
      state: "ready",
      label: "68°F · Sunny",
      temperatureF: 68,
      condition: "Sunny"
    } as const;
    const weatherEvent: BridgeEvent = {
      eventId: "brevt_weather0001",
      type: "weather.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-24T16:00:00.000Z",
      payload: { weather: live }
    };

    const withWeather = reduceDashboardState(base, weatherEvent);
    expect(withWeather.liveWeather).toEqual(live);
    // An identical re-emit is a no-op (no needless re-render).
    expect(reduceDashboardState(withWeather, weatherEvent)).toBe(withWeather);

    // A mode switch swaps the mode-scoped bootstrap `weather`, but the runtime-only
    // `liveWeather` lives outside the snapshot, so it survives with no flash (NIC-136).
    const switched = reduceDashboardState(withWeather, {
      eventId: "brevt_weathercfg001",
      type: "config.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-24T16:00:01.000Z",
      payload: { snapshot: getDashboardFixture("mode.developer.ready") }
    });
    expect(switched.mode).toBe("Developer");
    expect(switched.weather?.temperatureF).toBe(66); // the developer bootstrap value
    expect(switched.liveWeather).toEqual(live); // live value preserved across the switch
  });

  it("ignores a malformed weather.changed payload (no fabricated update)", () => {
    const base = loadBootstrapState();
    const malformed: BridgeEvent = {
      eventId: "brevt_weatherbad01",
      type: "weather.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-24T16:00:00.000Z",
      payload: { weather: { label: "no state field" } }
    };
    expect(reduceDashboardState(base, malformed)).toBe(base);
    expect(reduceDashboardState(base, { ...malformed, payload: {} })).toBe(base);
  });

  it("folds live news into a per-profile liveNews map that survives a mode switch (NIC-127)", () => {
    const base = loadBootstrapState();
    const region = {
      state: "ready",
      headlines: [
        { id: "n1", title: "Markets steady as earnings open", source: "Reuters" },
        { id: "n2", title: "Central bank holds rates", source: "Bloomberg" },
        { id: "n3", title: "Cloud provider unveils AI tooling", source: "The Verge" }
      ]
    } as const;
    const newsEvent: BridgeEvent = {
      eventId: "brevt_news00000001",
      type: "news.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-27T16:00:00.000Z",
      payload: { profile: "broad", news: region }
    };

    const withNews = reduceDashboardState(base, newsEvent);
    expect(withNews.liveNews?.broad).toEqual(region);
    // An identical re-emit for the same profile is a no-op (no needless re-render).
    expect(reduceDashboardState(withNews, newsEvent)).toBe(withNews);

    // A second profile lands alongside the first — the map is keyed, not replaced.
    const engineering = { ...region, headlines: [region.headlines[0]] } as const;
    const withBoth = reduceDashboardState(withNews, {
      ...newsEvent,
      eventId: "brevt_news00000002",
      payload: { profile: "engineering", news: engineering }
    });
    expect(withBoth.liveNews?.broad).toEqual(region);
    expect(withBoth.liveNews?.engineering).toEqual(engineering);

    // A mode switch swaps the mode-scoped bootstrap `news`, but the runtime-only `liveNews` lives
    // outside the snapshot, so it survives with no flash (NIC-136).
    const switched = reduceDashboardState(withBoth, {
      eventId: "brevt_newscfg00001",
      type: "config.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-27T16:00:01.000Z",
      payload: { snapshot: getDashboardFixture("mode.developer.ready") }
    });
    expect(switched.mode).toBe("Developer");
    expect(switched.liveNews?.broad).toEqual(region);
    expect(switched.liveNews?.engineering).toEqual(engineering);
  });

  it("ignores a malformed news.changed payload (no fabricated update)", () => {
    const base = loadBootstrapState();
    const region = { state: "ready", headlines: [] } as const;
    // Missing profile, missing region, and a region without a `state` string are all ignored.
    expect(
      reduceDashboardState(base, {
        eventId: "brevt_newsbad00001",
        type: "news.changed",
        schemaVersion: "1.0.0",
        timestamp: "2026-07-27T16:00:00.000Z",
        payload: { news: region }
      })
    ).toBe(base);
    expect(
      reduceDashboardState(base, {
        eventId: "brevt_newsbad00002",
        type: "news.changed",
        schemaVersion: "1.0.0",
        timestamp: "2026-07-27T16:00:00.000Z",
        payload: { profile: "broad", news: { headlines: [] } }
      })
    ).toBe(base);
    expect(
      reduceDashboardState(base, {
        eventId: "brevt_newsbad00003",
        type: "news.changed",
        schemaVersion: "1.0.0",
        timestamp: "2026-07-27T16:00:00.000Z",
        payload: {}
      })
    ).toBe(base);
  });

  it("folds live schedule into a per-profile liveSchedule map that survives a mode switch (NIC-126)", () => {
    const base = loadBootstrapState();
    const region = {
      state: "ready",
      items: [
        { id: "s1", title: "Quarterly planning review", start: "2026-07-27T14:00:00Z", kind: "today" },
        { id: "s2", title: "1:1 with design lead", start: "2026-07-27T16:30:00Z", kind: "today" },
        { id: "s3", title: "Release retrospective", start: "2026-07-27T23:00:00Z", kind: "tonight" }
      ]
    } as const;
    const scheduleEvent: BridgeEvent = {
      eventId: "brevt_sched00000001",
      type: "schedule.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-27T16:00:00.000Z",
      payload: { profile: "all", schedule: region }
    };

    const withSchedule = reduceDashboardState(base, scheduleEvent);
    expect(withSchedule.liveSchedule?.all).toEqual(region);
    // An identical re-emit for the same profile is a no-op (no needless re-render).
    expect(reduceDashboardState(withSchedule, scheduleEvent)).toBe(withSchedule);

    // A second profile lands alongside the first — the map is keyed, not replaced.
    const engineering = { ...region, items: [region.items[0]] } as const;
    const withBoth = reduceDashboardState(withSchedule, {
      ...scheduleEvent,
      eventId: "brevt_sched00000002",
      payload: { profile: "engineering", schedule: engineering }
    });
    expect(withBoth.liveSchedule?.all).toEqual(region);
    expect(withBoth.liveSchedule?.engineering).toEqual(engineering);

    // A mode switch swaps the mode-scoped bootstrap `schedule`, but the runtime-only `liveSchedule`
    // lives outside the snapshot, so it survives with no flash (NIC-136).
    const switched = reduceDashboardState(withBoth, {
      eventId: "brevt_schedcfg0001",
      type: "config.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-27T16:00:01.000Z",
      payload: { snapshot: getDashboardFixture("mode.developer.ready") }
    });
    expect(switched.mode).toBe("Developer");
    expect(switched.liveSchedule?.all).toEqual(region);
    expect(switched.liveSchedule?.engineering).toEqual(engineering);
  });

  it("ignores a malformed schedule.changed payload (no fabricated update)", () => {
    const base = loadBootstrapState();
    const region = { state: "ready", items: [] } as const;
    // Missing profile, missing region, and a region without a `state` string are all ignored.
    expect(
      reduceDashboardState(base, {
        eventId: "brevt_schedbad0001",
        type: "schedule.changed",
        schemaVersion: "1.0.0",
        timestamp: "2026-07-27T16:00:00.000Z",
        payload: { schedule: region }
      })
    ).toBe(base);
    expect(
      reduceDashboardState(base, {
        eventId: "brevt_schedbad0002",
        type: "schedule.changed",
        schemaVersion: "1.0.0",
        timestamp: "2026-07-27T16:00:00.000Z",
        payload: { profile: "all", schedule: { items: [] } }
      })
    ).toBe(base);
    expect(
      reduceDashboardState(base, {
        eventId: "brevt_schedbad0003",
        type: "schedule.changed",
        schemaVersion: "1.0.0",
        timestamp: "2026-07-27T16:00:00.000Z",
        payload: {}
      })
    ).toBe(base);
  });

  it("folds mode.windowcollapse.changed into a per-mode collapse map (NIC-143)", () => {
    const base = loadBootstrapState();
    const collapse = (modeId: string, collapsed: boolean): BridgeEvent => ({
      eventId: `brevt_collapse_${modeId}_${collapsed}`,
      type: "mode.windowcollapse.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-15T16:00:00.000Z",
      payload: { modeId, collapsed }
    });

    const collapsed = reduceDashboardState(base, collapse("executive", true));
    expect(collapsed.windowCollapse?.executive).toBe(true);
    // Other modes are untouched (sparse map).
    expect(collapsed.windowCollapse?.developer).toBeUndefined();

    // A second mode's state is merged, not replaced.
    const both = reduceDashboardState(collapsed, collapse("developer", true));
    expect(both.windowCollapse).toEqual({ executive: true, developer: true });

    // Expanding flips the entry back.
    const expanded = reduceDashboardState(both, collapse("executive", false));
    expect(expanded.windowCollapse).toEqual({ executive: false, developer: true });

    // A redundant event (same value) returns the same reference — no re-render.
    expect(reduceDashboardState(expanded, collapse("developer", true))).toBe(expanded);
    // A malformed payload is ignored.
    expect(
      reduceDashboardState(base, {
        ...collapse("executive", true),
        payload: { modeId: "executive" }
      })
    ).toBe(base);
  });

  it("folds a quick-apps rewrite into the matching mode (NIC-149)", () => {
    const base = loadBootstrapState();
    const target = base.modes.find((mode) => mode.quickApps.length > 0) ?? base.modes[0];
    const event: BridgeEvent = {
      eventId: "brevt_quickapps0001",
      type: "mode.quickapps.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-08T16:00:00.000Z",
      payload: { modeId: target.id, quickApps: ["vscode", "terminal"] }
    };

    const next = reduceDashboardState(base, event);
    expect(next.modes.find((mode) => mode.id === target.id)?.quickApps).toEqual([
      "vscode",
      "terminal"
    ]);
    // Only the named mode changes; every other mode keeps its reference.
    for (const mode of next.modes) {
      if (mode.id !== target.id) {
        expect(mode).toBe(base.modes.find((other) => other.id === mode.id));
      }
    }

    // Redundant and malformed rewrites return the same reference (no re-render).
    expect(reduceDashboardState(next, { ...event, eventId: "brevt_quickapps0002" })).toBe(next);
    expect(
      reduceDashboardState(next, {
        ...event,
        eventId: "brevt_quickapps0003",
        payload: { modeId: "no-such-mode", quickApps: ["vscode"] }
      })
    ).toBe(next);
    expect(
      reduceDashboardState(next, {
        ...event,
        eventId: "brevt_quickapps0004",
        payload: { quickApps: ["vscode"] }
      })
    ).toBe(next);
  });

  it("folds a display topology snapshot into state (NIC-87)", () => {
    const base = loadBootstrapState();
    const event: BridgeEvent = {
      eventId: "brevt_displays0001",
      type: "display.topology.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-06T16:00:00.000Z",
      payload: {
        displays: [
          {
            id: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
            name: "Built-in Display",
            frame: { x: 0, y: 0, width: 1512, height: 982 },
            primary: true,
            stableIdentity: true
          },
          {
            id: "cgid-724554883",
            name: "External Display",
            frame: { x: 1512, y: -200, width: 2560, height: 1440 },
            primary: false,
            stableIdentity: false
          }
        ],
        primaryDisplayId: "37D8832A-2D66-02CA-B9F7-8F30A301B230"
      }
    };

    const next = reduceDashboardState(base, event);
    expect(next.displayTopology?.displays).toHaveLength(2);
    expect(next.displayTopology?.primaryDisplayId).toBe("37D8832A-2D66-02CA-B9F7-8F30A301B230");
    expect(next.displayTopology?.displays[1]?.stableIdentity).toBe(false);

    // A later snapshot replaces the whole topology — never merges deltas.
    const disconnect = reduceDashboardState(next, {
      ...event,
      eventId: "brevt_displays0002",
      payload: { displays: [(event.payload.displays as unknown[])[0]] }
    });
    expect(disconnect.displayTopology?.displays).toHaveLength(1);
    expect(disconnect.displayTopology?.primaryDisplayId ?? null).toBeNull();

    // A malformed payload never fabricates a topology.
    expect(reduceDashboardState(base, { ...event, payload: {} })).toBe(base);
  });

  it("folds a layout session in and back out on close (NIC-142)", () => {
    const base = loadBootstrapState();
    const open: BridgeEvent = {
      eventId: "brevt_layoutopen01",
      type: "layout.session.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-14T16:00:00.000Z",
      payload: {
        session: {
          modeId: "developer",
          windows: [{ ref: "claude-desktop", kind: "app", label: "Claude" }],
          quickToggle: {
            activeRef: "vscode",
            targets: [{ ref: "vscode", kind: "app", label: "Visual Studio Code" }]
          }
        }
      }
    };
    const opened = reduceDashboardState(base, open);
    expect(opened.layoutSession?.modeId).toBe("developer");
    expect(opened.layoutSession?.quickToggle?.activeRef).toBe("vscode");

    // A null session ends layout mode.
    const closed = reduceDashboardState(opened, {
      ...open,
      eventId: "brevt_layoutclose1",
      payload: { session: null }
    });
    expect(closed.layoutSession).toBeNull();
    // Closing again is a no-op (same reference — no needless re-render).
    expect(reduceDashboardState(closed, { ...open, payload: { session: null } })).toBe(closed);
  });

  it("folds workflow action progress in and clears it on the terminal lifecycle status (NIC-85)", () => {
    const base = loadBootstrapState();
    const progress: BridgeEvent = {
      eventId: "brevt_wfprogress01",
      type: "workflow.action.progress",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: {
        commandId: "cmd_000000000000000000000001",
        workflowId: "open-developer-layout",
        actionId: "open-editor",
        kind: "app.open",
        status: "running",
        index: 2,
        total: 5
      }
    };

    const running = reduceDashboardState(base, progress);
    expect(running.activeWorkflowRun?.workflowId).toBe("open-developer-layout");
    expect(running.activeWorkflowRun?.status).toBe("running");
    expect(running.activeWorkflowRun?.index).toBe(2);
    expect(running.activeWorkflowRun?.total).toBe(5);

    // The command's terminal lifecycle status ends the live run.
    const done = reduceDashboardState(running, lifecycleEvent("succeeded"));
    expect(done.activeWorkflowRun ?? null).toBeNull();
    // ...and does so WITHOUT touching Heimlich. Quick-action progress and assistant state ride the
    // same event; locking the indicator (NIC-171) must not take the run clearing down with it.
    expect(done.heimlich.state).toBe("idle");

    // A non-terminal status leaves the run alone.
    expect(reduceDashboardState(running, lifecycleEvent("running"))).toBe(running);

    // A malformed payload never fabricates a run.
    const malformed = reduceDashboardState(base, { ...progress, payload: { status: "running" } });
    expect(malformed).toBe(base);
  });

  it("degrades system health when metrics become unavailable", () => {
    const base = loadBootstrapState();
    const event: BridgeEvent = {
      eventId: "brevt_cap0001",
      type: "bridge.capability.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: { capability: { id: "system.metrics", available: false } }
    };
    expect(reduceDashboardState(base, event).regions.systemHealth.state).toBe("stale");
  });

  it("folds every capability change into the availability map (FR-SHL-06)", () => {
    const base = loadBootstrapState();
    const capabilityEvent = (id: string, available: boolean): BridgeEvent => ({
      eventId: `brevt_cap_${id}`,
      type: "bridge.capability.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: { capability: { id, available, degradedReason: available ? null : "Denied." } }
    });

    const granted = reduceDashboardState(base, capabilityEvent("native.app.open", true));
    expect(granted.capabilities?.["native.app.open"]?.available).toBe(true);

    // A later revocation flips the same entry and keeps others.
    const revoked = reduceDashboardState(granted, capabilityEvent("native.app.open", false));
    expect(revoked.capabilities?.["native.app.open"]?.available).toBe(false);
    expect(revoked.capabilities?.["native.app.open"]?.degradedReason).toBe("Denied.");

    // A malformed payload never fabricates an entry.
    expect(
      reduceDashboardState(base, {
        ...capabilityEvent("x", true),
        payload: { capability: { id: "x" } }
      })
    ).toBe(base);
  });

  it("folds a confirmation disclosure in on confirmation.changed and back out on null", () => {
    const base = loadBootstrapState();
    expect(base.activeConfirmation ?? null).toBeNull();

    const withConfirmation = reduceDashboardState(base, confirmationBridgeEvent);
    expect(withConfirmation.activeConfirmation?.id).toBe("conf_000000000000000000000001");

    const cleared = reduceDashboardState(withConfirmation, {
      eventId: "brevt_confcleared99",
      type: "confirmation.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:45.000Z",
      payload: { confirmation: null }
    });
    expect(cleared.activeConfirmation ?? null).toBeNull();
    // Clearing an already-absent confirmation is a no-op (same reference, no re-render).
    expect(
      reduceDashboardState(cleared, { ...confirmationBridgeEvent, payload: { confirmation: null } })
    ).toBe(cleared);
  });

  it("folds a live system_metrics snapshot into the system-health region (NIC-81b)", () => {
    const base = loadBootstrapState();
    const event: BridgeEvent = {
      eventId: "brevt_metrics01",
      type: "system.status.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: {
        category: "system_metrics",
        cpu: { availability: "available", value: 23.5, unit: "percent", sampledAt: "2026-06-23T16:00:00.000Z" },
        memory: { availability: "available", value: 61.2, unit: "percent", sampledAt: "2026-06-23T16:00:00.000Z" },
        network: {
          availability: "available",
          linkMbps: 866,
          unit: "mbps",
          sampledAt: "2026-06-23T16:00:00.000Z"
        },
        battery: {
          availability: "available",
          value: 76,
          charging: true,
          pluggedIn: true,
          unit: "percent",
          sampledAt: "2026-06-23T16:00:00.000Z"
        },
        display: { availability: "available", value: 2, unit: null, sampledAt: "2026-06-23T16:00:00.000Z" }
      }
    };

    const health = reduceDashboardState(base, event).regions.systemHealth;
    expect(health.state).toBe("ready");
    expect(health.cpuPercent).toBe(23.5);
    expect(health.memoryPercent).toBe(61.2);
    expect(health.network?.linkMbps).toBe(866);
    expect(health.battery.percent).toBe(76);
    expect(health.battery.state).toBe("ready");
    expect(health.battery.charging).toBe(true);
    expect(health.battery.pluggedIn).toBe(true);
  });

  it("maps per-channel degradation honestly: no battery is unavailable, warming rates are empty", () => {
    const base = loadBootstrapState();
    const event: BridgeEvent = {
      eventId: "brevt_metrics02",
      type: "system.status.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: {
        category: "system_metrics",
        // First tick on a desktop Mac: rate metrics still warming, no battery.
        cpu: { availability: "loading", value: null, unit: "percent", sampledAt: "2026-06-23T16:00:00.000Z" },
        memory: { availability: "available", value: 40, unit: "percent", sampledAt: "2026-06-23T16:00:00.000Z" },
        network: { availability: "loading", linkMbps: null, unit: "mbps", sampledAt: null },
        battery: { availability: "unavailable", value: null, unit: "percent", sampledAt: null },
        display: { availability: "available", value: 1, unit: null, sampledAt: "2026-06-23T16:00:00.000Z" }
      }
    };

    const health = reduceDashboardState(base, event).regions.systemHealth;
    expect(health.state).toBe("ready");
    expect(health.cpuPercent).toBeUndefined();
    expect(health.memoryPercent).toBe(40);
    expect(health.network?.state).toBe("empty");
    expect(health.battery.state).toBe("unavailable");
    expect(health.battery.percent).toBeUndefined();
  });

  it("keeps Wi-Fi power when the link-rate metric is unavailable (NIC-156)", () => {
    // On Ethernet, or Wi-Fi on but unassociated: there is no link rate to report,
    // but the radio is genuinely on. Gating the power field on the channel's state
    // would make the bar indicator claim Wi-Fi is off.
    const base = loadBootstrapState();
    const event: BridgeEvent = {
      eventId: "brevt_metrics03",
      type: "system.status.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: {
        category: "system_metrics",
        cpu: { availability: "available", value: 10, unit: "percent", sampledAt: null },
        memory: { availability: "available", value: 40, unit: "percent", sampledAt: null },
        network: {
          availability: "unavailable",
          linkMbps: null,
          wifiPower: "on",
          signalRssi: -61,
          unit: "mbps",
          sampledAt: null
        },
        battery: { availability: "unavailable", value: null, unit: "percent", sampledAt: null },
        display: { availability: "available", value: 1, unit: null, sampledAt: null }
      }
    };

    const health = reduceDashboardState(base, event).regions.systemHealth;
    expect(health.network?.state).toBe("unavailable");
    expect(health.network?.linkMbps).toBeUndefined();
    expect(health.network?.wifiPower).toBe("on");
    expect(health.network?.signalRssi).toBe(-61);
  });

  it("drops an unrecognized Wi-Fi power value rather than passing it through", () => {
    const base = loadBootstrapState();
    const event: BridgeEvent = {
      eventId: "brevt_metrics04",
      type: "system.status.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: {
        category: "system_metrics",
        cpu: { availability: "available", value: 10, unit: "percent", sampledAt: null },
        memory: { availability: "available", value: 40, unit: "percent", sampledAt: null },
        network: { availability: "available", linkMbps: 100, wifiPower: "sideways", unit: "mbps", sampledAt: null },
        battery: { availability: "unavailable", value: null, unit: "percent", sampledAt: null },
        display: { availability: "available", value: 1, unit: null, sampledAt: null }
      }
    };

    const health = reduceDashboardState(base, event).regions.systemHealth;
    expect(health.network?.wifiPower).toBeUndefined();
  });

  it("still folds bridge_failure status changes into read-only recovery (NIC-64)", () => {
    const base = loadBootstrapState();
    const event: BridgeEvent = {
      eventId: "brevt_failure01",
      type: "system.status.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: {
        category: "bridge_failure",
        state: { status: "read_only", message: "Bridge is in read-only recovery." }
      }
    };
    expect(reduceDashboardState(base, event).recovery?.startupMode).toBe("recovery");
  });

  it("applies a mode-switch snapshot on config.changed, preserving the eager bundle", () => {
    const base = loadBootstrapState(); // Executive default
    const snapshot = getDashboardFixture("mode.school.ready");
    const event: BridgeEvent = {
      eventId: "brevt_config1",
      type: "config.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: { snapshot }
    };

    const next = reduceDashboardState(base, event);

    expect(next.mode).toBe("School");
    // The preloaded modes/agents bundle is preserved by reference; only the per-state slice swaps.
    expect(next.modes).toBe(base.modes);
    expect(next.agents).toBe(base.agents);
  });

  it("preserves the runtime-owned System Health region across a mode switch (NIC-136)", () => {
    const base = loadBootstrapState(); // Executive, live metrics from the fixture stream
    const liveHealth = base.regions.systemHealth;
    expect(liveHealth.state).toBe("ready");

    // The native mode-switch snapshot ships regions in their honest pre-adapter state
    // (System Health unavailable); only the live stream repopulates them. Folding that in
    // wholesale is exactly what caused the unavailable flash.
    const schoolSnapshot = getDashboardFixture("mode.school.ready");
    const event: BridgeEvent = {
      eventId: "brevt_config_health",
      type: "config.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-06-23T16:00:00.000Z",
      payload: {
        snapshot: {
          ...schoolSnapshot,
          regions: {
            ...schoolSnapshot.regions,
            systemHealth: {
              state: "unavailable",
              battery: { state: "unavailable", label: "Battery" }
            }
          }
        }
      }
    };

    const next = reduceDashboardState(base, event);

    expect(next.mode).toBe("School"); // the mode-scoped slice still swaps
    // …but the live System Health region is carried over unchanged — no flash.
    expect(next.regions.systemHealth).toBe(liveHealth);
    expect(next.regions.systemHealth.state).toBe("ready");
    // A mode-scoped region (news) does take the snapshot's value.
    expect(next.regions.news).toBe(schoolSnapshot.regions.news);
  });

  it("folds a widget.data.changed stream into liveWidgets keyed by widget id (NIC-131)", () => {
    const base = loadBootstrapState();
    const widget = {
      widgetId: "repositories",
      state: "ready",
      headline: "1 repository",
      data: { items: [{ id: "cerebral-helm", name: "cerebral-helm", branch: "dev", path: "/p/cerebral-helm" }] }
    };
    const event: BridgeEvent = {
      eventId: "brevt_widget0001",
      type: "widget.data.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-19T16:00:00.000Z",
      payload: { widgetId: "repositories", widget }
    };

    const next = reduceDashboardState(base, event);
    expect(next.liveWidgets?.repositories).toBe(widget);

    // A malformed payload — missing widget, or an envelope whose own id disagrees with the
    // event key — is ignored (same reference, no fabricated update).
    expect(reduceDashboardState(base, { ...event, payload: { widgetId: "repositories" } })).toBe(base);
    expect(
      reduceDashboardState(base, {
        ...event,
        payload: { widgetId: "repositories", widget: { ...widget, widgetId: "projects" } }
      })
    ).toBe(base);
  });

  it("carries liveWidgets across a config.changed mode switch (NIC-131 blueprint)", () => {
    const base = loadBootstrapState(); // Executive
    const widget = { widgetId: "repositories", state: "ready", data: { items: [] } };
    const withLive = reduceDashboardState(base, {
      eventId: "brevt_widget0002",
      type: "widget.data.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-19T16:00:00.000Z",
      payload: { widgetId: "repositories", widget }
    });
    expect(withLive.liveWidgets?.repositories).toBe(widget);

    const snapshot = getDashboardFixture("mode.school.ready");
    const switched = reduceDashboardState(withLive, {
      eventId: "brevt_config_widget",
      type: "config.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-07-19T16:00:00.000Z",
      payload: { snapshot }
    });

    // The mode-scoped slice swaps, but live widget data (outside `regions`) is untouched.
    expect(switched.mode).toBe("School");
    expect(switched.liveWidgets?.repositories).toBe(widget);
  });
});

describe("createBridgeStore", () => {
  it("seeds from initial state and folds the bridge event stream", () => {
    const bridge = createMockCerebralBridge();
    const store = createBridgeStore(bridge, loadBootstrapState());

    expect(store.getState().heimlich.state).toBe("idle");

    let notifications = 0;
    const unsubscribe = store.subscribe(() => {
      notifications += 1;
    });

    // Weather, not the command lifecycle: since NIC-171 a lifecycle event moves no state on its
    // own, so it can no longer serve as this test's proof that the stream folds and notifies.
    const weatherEvent: BridgeEvent = {
      eventId: "brevt_storeweather01",
      type: "weather.changed",
      schemaVersion: "1.0.0",
      timestamp: "2026-08-05T16:00:00.000Z",
      payload: { weather: { state: "ready", label: "71°F · Clear", temperatureF: 71, condition: "Clear" } }
    };
    bridge.emit(weatherEvent);

    expect(store.getState().liveWeather?.label).toBe("71°F · Clear");
    expect(notifications).toBe(1);

    // A lifecycle event reaches the store but changes nothing, so subscribers stay quiet.
    const runningEvent = lifecycleBridgeEvents.find(
      (event) => (event.payload as { currentStatus: string }).currentStatus === "running"
    )!;
    bridge.emit(runningEvent);
    expect(store.getState().heimlich.state).toBe("idle");
    expect(notifications).toBe(1);

    unsubscribe();
    bridge.emit({ ...weatherEvent, eventId: "brevt_storeweather02" });
    expect(notifications).toBe(1);
  });

  it("does not notify subscribers on an irrelevant event", () => {
    const bridge = createMockCerebralBridge();
    const store = createBridgeStore(bridge, loadBootstrapState());

    let notifications = 0;
    store.subscribe(() => {
      notifications += 1;
    });

    bridge.emit(IRRELEVANT_EVENT);
    expect(notifications).toBe(0);
  });
});
