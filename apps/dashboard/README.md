# Dashboard

**Owner:** Dashboard

**Purpose:** Production React and TypeScript presentation hosted by the Pre-Mac development server and, later, WKWebView.

The dashboard may render state and express intent through `CerebralBridge`. It must not import filesystem, process, database, native-platform, model, or provider APIs.

NIC-12 increment 1 establishes the runnable baseline:

- Vite development server
- React + TypeScript entry point
- mock bootstrap state through a local bridge module
- Vitest coverage for the initial render path
