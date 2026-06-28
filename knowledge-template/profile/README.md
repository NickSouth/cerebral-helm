# profile

The durable **"who I am"** layer: stable personal facts that are not a project, an
area of responsibility, or transient capture — name, age, education, relationships,
health, working preferences. This is the core context Heimlich draws on to be
personal, kept as plain Markdown like everything else.

Distinct from the other folders:

- not `projects/` — it has no goal or end state;
- not `areas/` — it is identity, not an ongoing responsibility (though an area like
  "school" or "family" may reference it);
- not `reference/` — it is about *you*, not external material.

**Sensitivity.** Profile notes are personal by nature: default them to at least
`sensitivity: sensitive` and `cloudPolicy: deny`, so identity facts are never sent
to a cloud provider without an explicit, per-note choice. Split anything especially
private (health, finances) into its own note so it can carry its own policy.

[`about-me.md`](about-me.md) is a starter template — personalize or replace it.
Seeding never overwrites an existing profile note.

> Scope note: a *structured* user model (typed fields the system reasons over, the
> North Star "memory system") is future work. Today the profile is durable notes;
> this folder gives that information a first-class home.
