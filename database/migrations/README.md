# Migrations

**Owner:** Storage

**Purpose:** Forward, versioned operational database migrations. Migration files arrive with the storage implementation and must be covered by empty-state and upgrade fixtures.

The `.sql` files here are human-readable **mirrors**. The canonical source the
migrator applies and checksums is `SchemaMigrations` in the `CerebralStorage`
package (embedded in Swift so a OneDrive-dehydrated `.sql` placeholder can never
blank the schema at runtime). `Tests/StorageTests` asserts each mirror stays
identical to its embedded source. Canonical `.sql` resources are revisited once
resource bundling is validated on the macOS toolchain (ADR-005).

- `0001_initial.sql` — initial operational schema (`FR-OBS-01`): commands, command
  events, tool calls, confirmations, note metadata, mode sessions, settings
  metadata, and updates, plus the `schema_migrations` registry, foreign keys, and
  indexes.
