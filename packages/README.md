# Portable packages

**Owner:** Portable core

**Purpose:** Hold deterministic Swift domain logic and language-neutral versioned contracts. These packages must compile and test outside macOS and must never import AppKit.

Tools and knowledge may depend on core; core may depend on shared. Contracts remain language-neutral and do not depend on Swift modules. Exact long-term package boundaries remain subject to the required ADR; this initial graph only enforces the ownership already stated by the MVP PRD.
