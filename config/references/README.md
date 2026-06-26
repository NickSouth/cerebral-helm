# Reference catalogs

Minimal, distributable catalogs of the named references the direct-command
parser (NIC-24) resolves:

- `apps.json` — application references opened by `app.open` (`open <id>`).
- `urls.json` — allowlisted URL references opened by `url.open` (`open <id>`).
- `hooks.json` — allowlisted hook references run by `hook.run` (`hook <id>`).

Each file is `{ "schemaVersion", "references": [{ "id", "label", "target" }] }`.
`target` is provider-neutral payload data (a bundle id, URL, or hook script
path); the parser only resolves the reference and never executes it.

This catalog is intentionally minimal and not yet wired into the JSON Schema /
codegen pipeline. It is a deliberate placeholder meant to be easy to rewrite
when the full, validated reference model is designed. Mode files
(`config/modes/*.json`) reference these ids through `quickApps`/`quickActions`.
