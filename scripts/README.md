# Scripts

**Owner:** Developer experience

**Purpose:** Portable, non-interactive automation behind documented repository commands. Scripts must default to fixture or temporary data roots, never personal production state.

Current scripts own:

- toolchain version checks
- workspace bootstrap
- dashboard development server launch
- config and simulation fixture validation
- dedicated development database reset
- preview-only simulation artifact generation
- development event log tailing
- repository test entry point

All script writes stay under `.local/development/` unless an explicit repository-local override is provided.
