---
name: Skill Builder
description: Author and edit iClaw skills directly via the fs.* bridge. Includes scaffolding, validation, and reference examples.
iclaw:
  version: "1.0"
  tags: [meta, authoring, scaffolding]
---
# Skill Builder

Use this skill when the user asks you to create, modify, or fork an iClaw
skill. iClaw skills are directories under `/skills/<slug>/` that you author
through the `fs.*` bridge — there are no `create_skill`/`edit_skill` LLM tools.
The canonical structure is documented in `references/example-tooled.md`.

## Authoring flow (the happy path)

1. **Pick a slug.** Lowercase, hyphenated, unique. Check existing slugs with
   `fs.list('skills')` and `list_skills`. Slugs are stable identifiers —
   renaming a slug breaks any agent that has the skill installed.
2. **Scaffold** — fastest path:
   `skill_skill_builder_scaffold(slug, name, description)` writes a minimal
   valid `SKILL.md` plus an empty `tools/` and `scripts/` directory in one
   shot.
3. **Add a tool** — write `tools/<tool>.js` with a top-level `const META`
   declaration. See `references/example-tooled.md` for the canonical shape.
4. **Add a script** (optional) — write `scripts/<script>.js`. The first-line
   comment is the description. Scripts run via `run_snippet skill:<name>:<script>`.
5. **Validate** — `validate_skill(slug)` runs the same Swift-side parser the
   auto-reload path uses. Fix every error before installing; warnings are
   advisory.
6. **Install** — `install_skill(name=<frontmatter name>)`. iClaw materializes
   a `Skill` row from the on-disk package and binds it to the current agent.
   Custom tools immediately become available as `skill_<slug>_<tool>`.

## Editing an existing skill

1. **Read first** — `fs.readFile('skills/<slug>/SKILL.md')` to avoid
   destructively rewriting unrelated content.
2. **Write** — `fs.writeFile('skills/<slug>/...')`. Auto-reload runs against
   the modified package on success; if the rewrite breaks parsing, the last
   good version of the skill keeps running until you fix the package.
3. **Re-validate** — `validate_skill(slug)` after every batch of edits.
4. **No re-install needed** — the cached Skill row updates automatically. Only
   slug renames require uninstall + reinstall.

## Forking a built-in

Built-in skills (under slugs in `BuiltInSkills.shippedSlugs`) are read-only.
Fork before editing:

    fs.cp('skills/deep-research', 'skills/my-research', { recursive: true });

The copy lives in `<Documents>/Skills/` and is fully writable. Edit, validate,
and `install_skill` as usual.

## Permission notes

Writes under `/skills/<slug>/` require the `fs_skill_write` per-agent
permission in addition to whatever permission the action itself needs (e.g.
`files.writeFile`). Agents without `fs_skill_write` can still read packages
and use installed skills — they just can't author or modify them.

## See also

- `references/example-simple.md` — a prose-only skill with no tools or scripts.
- `references/example-tooled.md` — a skill with one tool and one script.
