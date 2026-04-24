# Proposal: Align iClaw Skills with the Standard Claude Skill Format

## Context

iClaw's current skill system is a fully working, opinionated design that works well for the app's runtime (Swift host + WKWebView JS sandbox with a native `AppleEcosystemBridge`). However, it diverges substantially from the [standard Claude custom-skill format](https://support.claude.com/en/articles/12512198-how-to-create-custom-skills):

| Axis | Standard Claude skill | Current iClaw skill |
|---|---|---|
| Unit of distribution | Directory + `SKILL.md` (zippable) | SwiftData row with JSON blobs |
| Metadata | YAML frontmatter (`name` ≤64, `description` ≤200, `dependencies`) | Separate DB columns (`name`, `summary`, `tags`, `author`, `version`, `displayName`) |
| Body | Markdown with in-file refs to supporting files | `content: String` column |
| Supporting files | `scripts/*`, `references/*` loaded on demand | Inline JSON arrays: `scripts[]`, `customTools[]`, `configSchema[]` |
| Progressive disclosure | Metadata first → body on activation → resources on demand | Full `content` + all tool schemas injected into every turn's system prompt |
| Executable code | Runs in Claude's code-execution tool (Python / Node.js + `pip`/`npm`) | Runs in WKWebView JS sandbox, no package manager, exposes `fs.*`, `apple.{health,calendar,reminders,contacts,clipboard,notifications,location,maps}.*`, `fetch` |
| Import/export | A zip moves between Claude.ai, Claude Code, and agents | Not portable |

The user's observation is correct: iClaw's runtime is not a standard Node.js or Python — it is a WKWebView sandbox bridged to iOS-native capabilities that **have no equivalent** in either Claude.ai's code-execution tool or plain Node.js. Trying to execute an upstream Claude skill that calls `pandas` or `fs.readFileSync` on an arbitrary path inside iClaw would fail. Wrapping bridge functionality as typed LLM tool calls (what iClaw does today via `skill_<skill>_<tool>`) is strictly more ergonomic for the model than asking it to author JS that calls `apple.health.readSteps(...)` from a free-form implementation string — the type schema and description are parsed by the function-calling path, not by the model reading prose.

**Therefore the tradeoff is not "standard vs. iClaw" but "transport format vs. execution model".** We should adopt the standard for authoring/transport/progressive-disclosure while keeping the function-call wrapper around non-standard bridges.

## Recommendation — Hybrid: Standard authoring, iClaw-native execution

### Summary

1. Make the canonical on-disk representation a **directory with `SKILL.md`** that matches the standard layout.
2. Put iClaw-specific extensions (the function-call tools that wrap the native bridge) under `tools/*.js` and `scripts/*.js` — pure JS files that declare their metadata inline, not YAML-wrapped markdown. Standard readers see a valid skill; iClaw reads the extra payload.
3. **Skill packages live at `<Documents>/Skills/<slug>/`**, not inside a SwiftData blob. The `Skill` row becomes a cache of the parsed directory. Because `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` are already set in Info.plist, this directory is automatically visible in the iOS Files app — users can edit skills with any text editor, version-control with Working Copy, sync via iCloud, etc.
4. **Extend the `fs.*` bridge with a reserved `/skills/` mount**, so agents author and edit skills with ordinary filesystem primitives. `fs.writeFile('/skills/my-skill/SKILL.md', ...)` is how the Agent creates a skill. This replaces the `create_skill` / `edit_skill` / `delete_skill` / `read_skill` function-calls entirely.
5. Implement **progressive disclosure** at prompt-build time: when a skill is installed but not active, only `name` + `description` go into the system prompt. The body is revealed only when the skill is activated (see next point).
6. Add a **`/skill_name` slash-command** as the user-facing activation mechanism, in addition to the LLM's implicit activation-on-tool-call. Typing `/deep_research` in the chat input activates the *Deep Research* skill for the session.
7. Built-in skills migrate to on-disk directories inside the app bundle; `BuiltInSkills.Template` becomes a loader, not a source.
8. **Import / export is UI-only** — handled by the existing `SkillLibraryView` / `SkillDetailView`, not exposed as LLM function-call tools.

### Why this wins the tradeoff

- **Portability**: a user's custom skill becomes a `.zip` that can be inspected, shared, version-controlled, and partially used on Claude.ai (instructional portion — the iClaw-specific tools will just be inert there).
- **Prompt budget**: today every installed skill's full markdown + every custom tool schema is in context every turn. With progressive disclosure that cost collapses to a line per installed skill unless the skill is actively in use.
- **No runtime regression**: execution still happens in WKWebView via `AppleEcosystemBridge`; the bridge API surface does not change; permission enforcement stays dual-layer.
- **Non-standard bridges stay first-class**: `apple.health.*` is still exposed as typed `skill_<skill>_<tool>` function calls — the LLM gets the same high-quality tool-call ergonomics it has today.
- **Standard compatibility is opt-in, not forced**: a skill that only wants to be "prose + methodology" (like the current *Deep Research* body) is just a `SKILL.md` — no iclaw section needed.

### On-disk layout

```
<skill-root>/
├── SKILL.md                 # required, YAML frontmatter + markdown body
├── scripts/                 # optional, run_snippet targets — pure .js
│   ├── extract_links.js
│   └── summarize_text.js
├── tools/                   # optional, function-call tools (iClaw extension) — pure .js
│   └── fetch_and_extract.js
├── references/              # optional, progressive-disclosure resources (markdown, .txt, .json)
│   └── rubric.md
└── assets/                  # optional (images, JSON, etc.)
```

The loader walks `tools/` and `scripts/` directly — there is **no manifest enumeration** of them in `SKILL.md`. The filesystem is the source of truth.

#### Localization — package-local overlays (not `Localizable.strings`)

Today built-ins pull `displayName` / `summary` / `content` / tool + parameter descriptions from `Localizable.strings` via `localizationKey`, and the markdown body lives in `<lang>.lproj/<Skill Name>.md`. This was workable when the skill was a code-as-data struct, but it has two problems in a file-based world: (a) if a skill is exported as a zip, the strings table does **not** travel with it; (b) user-authored skills get no localization story at all, creating a two-tier system.

Solution: keep translations **inside the package**, as locale overlay files:

```
<skill-root>/
├── SKILL.md                    # canonical English — always required
├── SKILL.zh-Hans.md            # overlay: frontmatter + body for zh-Hans
├── SKILL.ja.md
├── SKILL.ko.md
├── tools/
│   ├── fetch_and_extract.js          # code + canonical English META
│   └── fetch_and_extract.zh-Hans.json # overlay: only translated strings
│   (same for .ja.json, .ko.json)
└── scripts/
    ├── extract_links.js        # code; first-line comment is English description
    └── extract_links.zh-Hans.txt     # overlay: single-line localized description
```

Resolution rule: for a given UI locale `L`, the loader selects `SKILL.<L>.md` if present; otherwise tries base-language matches (`zh-Hans` → `zh`); falls back to `SKILL.md`. Overlays are **partial** — they only need to carry the translated fields (`display_name`, `description`, body). Omitted fields inherit from the canonical file.

Tool overlay example `tools/fetch_and_extract.zh-Hans.json`:
```json
{
  "description": "快速抓取网页并提取纯文本。",
  "parameters": {
    "url": { "description": "要抓取的 URL" },
    "max_length": { "description": "返回文本的最大长度（字符数）" }
  }
}
```

What stays **not localized** — for correctness, not laziness:
- `name` in frontmatter: the stable English identifier used by `skill_<slug>_<tool>` tool-name generation, `run_snippet` keys, and cross-agent references. Already a documented invariant in the current code (`Skill.swift:76-80`).
- `tools/<tool>.name`, `scripts/<script>` filenames: the agent-facing tool names must not shift with UI language, or function-call history / transcripts break.
- `iclaw.slash`: slash-command slug is English.
- `iclaw.tags`: already kept English for search stability across locales (current code convention, `BuiltInSkills` line 270).

Migration of built-ins: the current `Localizable.strings` entries (`skill.<key>.display_name`, `skill.<key>.summary`, `skill.<key>.content`, tool/param descriptions) get transplanted into per-locale overlay files inside each `Resources/BuiltInSkills/<slug>/` directory at build time. A one-time script can generate these from the existing `.strings` tables — the mapping is mechanical. Afterwards, the `Localizable.strings` skill entries can be deleted.

User-authored skills can opt into localization by adding overlay files — same mechanism as built-ins, no special privilege. `skill-builder`'s `references/example-tooled.md` demonstrates the overlay pattern.

`SKILL.md`:
```markdown
---
name: Deep Research                              # ≤64 chars, stable English id
description: Multi-source research with ...      # ≤200 chars, used for matching + slash-command hint
# --- iClaw extension (ignored by standard readers) ---
iclaw:
  version: "1.0"
  tags: [research, analysis]
  slash: deep_research                           # optional, overrides the derived `/deep_research`
  config:
    - { key: default_max_length, type: number, default: "5000" }
  display_name_key: skill.deep_research.display_name   # optional Localizable.strings key
---

# Deep Research Skill
When asked to research a topic, follow this methodology ...
```

#### JS-native tool definition (not markdown-wrapped)

Tool implementations are already JavaScript. Wrapping JS in a markdown frontmatter-and-body container added a parser step and obscured that the file is just code. Tools are authored as plain `.js` files with a top-level `META` declaration that the loader reads by regex (and validates by parsing into a small JS object — no full eval needed):

`tools/fetch_and_extract.js`:
```javascript
const META = {
  name: "fetch_and_extract",
  description: "Quick plain-text fetch with HTML stripping.",
  parameters: [
    { name: "url",        type: "string", required: true  },
    { name: "max_length", type: "number", required: false },
  ],
};

// Body runs with `args` and the AppleEcosystemBridge (`fs`, `apple`, `fetch`,
// `console.log`) in scope — same environment as today's implementation strings.
const url = args.url;
const maxLen = args.max_length || 5000;
try {
  const resp = fetch(url);
  if (!resp.ok) {
    console.log(`[Error] HTTP ${resp.status}`);
  } else {
    const text = resp.text
      .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "")
      /* ... */;
    console.log(text.substring(0, maxLen));
  }
} catch (e) {
  console.log(`[Error] ${e.message}`);
}
```

At load time the parser extracts the `META` literal, validates `name`/`description`/`parameters`, and stores the file's **full contents** as the script body — `META` is harmless at runtime (an unused const). This is the whole encoding: no JSDoc, no decorators, no build step.

Scripts (for `run_snippet`, not function-calls) use an even simpler convention: filename is the script name; the first-line comment is the description. No `META` needed.

`scripts/extract_links.js`:
```javascript
// Parse HTML to extract follow-up URLs for deeper investigation.

const html = args.html || '';
const matches = [...html.matchAll(/<a[^>]+href=["']([^"']+)["'][^>]*>([^<]*)<\/a>/gi)];
/* ... */
```

This layout is (a) what the standard expects at the `SKILL.md` level, (b) authorable in any text editor with JS syntax highlighting for the parts that actually are JS, (c) diffable in git, (d) has an unambiguous mapping to the existing `Skill` model, and (e) does not re-wrap code in markdown.

### Slash-command invocation (`/skill_name`)

Today a skill is surfaced to the LLM only through (i) its body in the system prompt and (ii) its `skill_*` function-call tools. The user has no explicit way to say "activate this skill for this turn" — the model has to infer it. Add a direct invocation path:

- Each skill gets a slug derived from its `name` (lowercase, spaces → underscores, punctuation stripped). The `iclaw.slash` frontmatter key overrides the derived slug.
- `ChatViewModel.sendMessage()` (iClaw/ViewModels/ChatViewModel.swift:552) gets a preprocessing step that looks at the message's first token. If it is `/<slug>` and matches an **installed, enabled** skill on the current agent, the preprocessor:
  1. Strips the `/slug` prefix from the user's text.
  2. Marks the skill as **active for this session** (the same activation flag the progressive-disclosure renderer reads).
  3. Attaches a short system note to the outbound request: "User explicitly invoked the `<name>` skill. Follow its methodology." This is enough to get the model to actually use the skill rather than paraphrase around it.
- If the message is only `/<slug>` with no content, treat it as a skill-activation no-op and render a UI hint ("Deep Research skill activated — ask your question.") without sending to the LLM.
- Unknown `/word` is a no-op (no error) so normal text starting with `/` still works — this is a soft-matching feature, not a command parser.
- UI affordance: an autocomplete chip above the chat composer when `/` is the first character, listing installed skills by slug + display name. Existing `AgentSkillsView` already has the enabled-skills list, so the data source is already there.

This matches the ergonomic of the standard Claude skill "the user enables it and then just asks", plus adds an explicit trigger for users who want it. It does **not** replace the implicit activation-on-tool-call path — both coexist.

### Skills as files — `fs` bridge authoring

The `fs.*` bridge currently routes every path through `AgentFileManager.resolvedURL(agentId:path:)` (iClaw/Services/CodeExecution/AppleEcosystemBridge.swift:640), which scopes paths to `<Documents>/AgentFiles/<agentId>/`. Extend this resolver with a reserved top-level mount that has **two backing roots**:

- `/skills/<slug>/...` where `<slug>` is a **user (non-built-in) skill** → resolves to `<Documents>/Skills/<slug>/...` (read-write, visible in Files).
- `/skills/<slug>/...` where `<slug>` is a **built-in skill** → resolves to `Bundle.main.url(forResource: "BuiltInSkills/<slug>", withExtension: nil)` inside the app bundle, and is **rejected at the resolver for any write-mode open / mutation call**.
- Every other path keeps today's behavior (per-agent scope).

Built-ins live in the bundle, not Documents — they are **immutable by construction** (the app bundle is read-only at runtime on iOS) and also not exposed in the Files app, so neither agents nor end-users can clobber them. User skills are in Documents and therefore Files-visible + editable.

The decision "is this slug built-in?" is already known to `SkillService` (the `Skill.isBuiltIn` flag). The resolver consults an in-memory `Set<String>` of built-in slugs populated by `SkillService.ensureBuiltInSkills()`. A write attempt against a built-in slug returns an `[Error] Cannot modify built-in skill '<slug>' (read-only)` without ever touching disk.

If a user wants to customize a built-in, the pattern is **fork-then-edit**: `fs.cp('/skills/deep-research', '/skills/my-deep-research', {recursive: true})` copies from the read-only bundle path into Documents, producing a writable user skill. The resolver allows read from either root; write is constrained by the destination slug's built-in status.

**What this replaces in `SkillTools.swift`:**

| Old LLM tool | Replaced by |
|---|---|
| `create_skill(name, content, scripts, tools)` | `fs.mkdir('/skills/<slug>'); fs.writeFile('/skills/<slug>/SKILL.md', ...); fs.writeFile('/skills/<slug>/tools/foo.js', ...)` |
| `edit_skill(id, content, ...)` | `fs.writeFile('/skills/<slug>/SKILL.md', ...)` etc. |
| `delete_skill(id)` | `fs.delete('/skills/<slug>', {recursive: true})` |
| `read_skill(id)` | `fs.readFile('/skills/<slug>/SKILL.md')` (+ `fs.list('/skills/<slug>/tools/')`) |

**What is kept as a function-call:** `install_skill`, `uninstall_skill`, `list_skills`. These are per-agent binding concerns (which agent has which skill enabled, what the `InstalledSkill.config` values are) — not file concerns. Representing them as files (e.g. a `.installed` marker) would be over-engineering.

**Teaching the authoring workflow — new built-in `skill-builder`.** Removing `create_skill`/`edit_skill` from the tool prompt means agents no longer have inline documentation for how to author a skill. We close the gap with a **built-in skill** that is installable like any other, but whose entire purpose is to teach its own authoring format:

```
Resources/BuiltInSkills/skill-builder/
├── SKILL.md              # methodology: frontmatter shape, JS META convention,
│                         # fs.* workflow against /skills/<slug>/, install_skill flow
├── tools/
│   ├── scaffold.js       # scaffold_skill(slug, name, description) → writes a
│   │                     # valid minimal package at /skills/<slug>/
│   └── validate.js       # validate_skill(slug) → parses the package and reports
│                         # frontmatter / META errors with line numbers
└── references/
    ├── example-simple.md # a prose-only skill example (just SKILL.md)
    └── example-tooled.md # a skill with one tool + one script
```

`scaffold.js` and `validate.js` are **thin wrappers over `fs.*`** — they exist only to keep the happy path safe (no typos in frontmatter, no missing required fields). The agent can still author everything from scratch using raw `fs.writeFile` calls once it has read `SKILL.md`; scaffold is the shortcut.

The skill body instructs the agent concretely:
1. Pick a slug (kebab-case, not in use — the agent can check via `fs.list('/skills')`).
2. Call `skill_skill_builder_scaffold_skill(slug, name, description)` **or** write the files manually with `fs.*`.
3. Add `tools/foo.js` and/or `scripts/bar.js` as needed, following the `const META` convention documented in `references/example-tooled.md`.
4. Call `skill_skill_builder_validate_skill(slug)` to check for parse errors.
5. Call `install_skill name=<name>` to activate it on the current agent.

This turns skill authoring into a **bootstrap-by-reading**: the agent installs `skill-builder`, reads its body on activation, and now knows how to make more skills. The methodology lives in a skill (which is itself a well-formed skill package — the canonical example), not in Swift code. When the format evolves, updating one bundled file updates the instructions every agent sees.

**Auto-reload on write — transactional, last-good semantics.** `AppleEcosystemBridge.dispatch` intercepts any successful write (`writeFile`, `appendFile`, `delete`, `mkdir`, `cp`, `mv`, `fd-close-after-write`) whose resolved URL is under `<Documents>/Skills/<slug>/`. On success it enqueues `SkillService.reload(slug:)`, which:

1. Parses `SKILL.md` + `tools/*.js` + `scripts/*.js` into a **candidate** `ParsedSkillPackage` value type (pure Swift struct, not persisted).
2. If parsing **succeeds**: atomically swap the cached `Skill` row's fields (`scriptsRaw` / `toolsRaw` / `content` / etc.) and re-sync each `InstalledSkill`'s registered `CodeSnippet`s (same logic as `SkillTools.resyncInstalledSnippets`, SkillTools.swift:257-278).
3. If parsing **fails**: **keep the existing cached state in memory** — the last-good version of the skill continues to run. Log the parse error with file + line, and attach a short warning to the write call's `ToolCallResult` that caused the reload: `[Warning] Skill '<slug>' now fails to parse: <error>. Running last-good version. Fix SKILL.md / tools / scripts or call validate_skill("<slug>").`

This guarantees that **an agent can never brick a skill mid-session by saving an invalid edit**. Worst case: the skill stops picking up changes until the agent fixes the error. Existing in-flight tool calls and future tool calls both keep working against the last successfully-parsed version.

If a skill has **never** parsed successfully (e.g. a brand-new package the agent is still writing), reload failure means the skill is simply unavailable — it is surfaced in `list_skills` with an error marker instead of silently disappearing.

With auto-reload, the agent's workflow becomes: *"write files, tools appear on next turn"* — no explicit "reload" step — but with a safety net that broken writes don't propagate.

**Single Swift validator — every consumer wraps it.** Validation lives in one place: `SkillPackage.validate(at: URL) -> ValidationReport` in Swift. This is the canonical, testable implementation. Everywhere else is a thin adapter:

| Consumer | Wrapping |
|---|---|
| `validate_skill(slug)` LLM tool | Formats the `ValidationReport` as JSON for the model |
| `SkillService.reload(slug:)` on `fs.*` auto-reload | On `errors.isEmpty`, swap the in-memory cache; otherwise keep last-good + attach warning |
| `SkillLibraryView` import (zip / directory) | Unzip to a temp dir, run validator, refuse imports with errors, let user confirm warnings, only then copy into `<Documents>/Skills/<slug>/` |
| `SkillService.fetchSkill(...)` / `PromptBuilder.buildInstalledSkillsSection` | Lazy mtime check on every read (see below) — catches edits made via Files app that bypass the `fs` bridge |
| `skill-builder` | Its `SKILL.md` documents `validate_skill` as the canonical check. **No** duplicated JS validator — `tools/validate.js` is dropped from the scaffold; the agent calls the top-level `validate_skill` tool instead. This removes the drift risk entirely. |

This means there is exactly one answer to "is skill X valid?", whether the question comes from the LLM, the importer, the auto-reload path, or a UI display.

**Lazy mtime-based re-validation instead of a periodic scan.** The `fs` bridge write-hook only fires for agent-initiated writes. Users who edit `SKILL.md` in the Files app bypass it. To pick those up without a background sweep:

1. Add a `sourceMtime: Date?` column to the `Skill` model — the mtime at which the current cache was parsed.
2. In each read path (`SkillService.fetchSkill(id:)`, `fetchSkill(name:)`, `fetchAllSkills()`, plus `PromptBuilder.buildInstalledSkillsSection`'s iteration), before returning the cached row, `stat` the skill's root directory (built-in slugs resolve to bundle, user slugs to `<Documents>/Skills/<slug>/`) and compare mtime against `sourceMtime`.
3. If the on-disk mtime is **newer**, call `SkillService.reload(slug:)` inline (same last-good-cache semantics) and return the refreshed row.
4. If the mtime is **same**, return the cache directly — a single `stat` is effectively free.

A directory's mtime on iOS reflects child additions/removals but not edits *inside* children. So the check also looks at `SKILL.md`'s mtime (the only file whose edit would change `content` / frontmatter without changing the directory listing). For full correctness in edge cases (someone editing `tools/foo.js` without touching `SKILL.md`), keep a cheap top-level walk: `max(mtime of SKILL.md, tools/, scripts/)` — still three `stat`s, microsecond-scale.

This replaces a would-be periodic scan with zero background work: validation happens exactly when the data is about to be used, and only re-parses when the on-disk state has actually changed.

### Error vs. warning spectrum

The validator classifies every issue as either `error` (skill cannot be used at all — not exposed as `skill_<slug>_*` tools, last-good cache kept if available) or `warning` (skill loads and runs, but something should be fixed).

**Errors — skill is unavailable:**

- `SKILL.md` missing.
- `SKILL.md` frontmatter block missing or not parseable (bad `---` delimiters / malformed YAML subset).
- `name` field missing, empty, or > 64 chars.
- `description` field missing, empty, or > 200 chars.
- Slug derived from `name` (or overridden by `iclaw.slash`) does not match the directory name.
- Slug collides with a **different** skill already registered (built-in or user).
- Any `tools/*.js` file exists but has no `META` literal, or the `META` literal is not a parseable object.
- `META.name` missing, empty, contains characters that break the `skill_<skill>_<tool>` derived LLM tool name, or is duplicated within the same skill.
- `META.description` missing or empty.
- `META.parameters[].name` or `parameters[].type` missing.
- `parameters[].type` not in {`string`, `number`, `boolean`, `array`, `object`}.
- Any `scripts/*.js` fails `JSContext`'s `checkSyntax` (syntax error).
- A `tools/*.js` file body fails `checkSyntax` too.
- A derived tool name would collide with a core iClaw tool (prevent `skill_foo_read_config` from shadowing the real `read_config`).
- Locale overlay JSON file malformed (unparseable JSON).

**Warnings — skill loads, but something is off:**

- `description` > 150 chars (approaches the 200 limit; matching quality degrades for long descriptions).
- `META.description` < 10 chars (too terse for the model to pick the tool).
- Script has no first-line comment (no description surfaced in the "Available scripts" list).
- Parameter name duplicated within one tool's `META` (validator de-duplicates, keeps the first).
- Locale overlay references a field (e.g. `parameters.foo.description`) that does not exist in the canonical — a likely stale translation.
- `iclaw.tags` contains non-ASCII characters (tags are search keys and are documented to stay English).
- `references/*` files present but not mentioned anywhere in `SKILL.md`'s body (likely orphaned).
- `SKILL.md` body has a markdown link pointing to a relative path that does not exist (`./scripts/missing.js`).
- A `tools/*.js` does not reference `console.log` or return anything — its output will be empty (common authoring mistake).

The report structure is flat and uniform so every consumer (LLM, UI, logs) can render it the same way:

```json
{
  "slug": "my-skill",
  "ok": false,
  "errors": [
    { "file": "SKILL.md",       "line": 2, "code": "missing_field", "message": "Missing required frontmatter field 'description'" },
    { "file": "tools/greet.js", "line": 4, "code": "bad_param_type", "message": "META.parameters[0].type: unknown type 'strng' (did you mean 'string'?)" }
  ],
  "warnings": [
    { "file": "scripts/helper.js", "line": 1, "code": "no_description", "message": "Script has no first-line description comment" }
  ]
}
```

### Validation at import time

Import via `SkillLibraryView`'s "Import Skill…":

1. User picks a `.zip` or directory.
2. iClaw unzips into a **temp directory** (never the live `<Documents>/Skills/` yet).
3. Runs `SkillPackage.validate(at: tempURL)`.
4. **If errors**: refuse the import; show the full report in a dialog. Temp directory is deleted.
5. **If warnings only**: show a "Import with warnings?" confirmation; proceeding copies into `<Documents>/Skills/<slug>/` and registers the `Skill` row.
6. **If clean**: copy into `<Documents>/Skills/<slug>/` silently, toast "Imported '<name>'".

Slug collisions with an existing skill halt import with a choice: "Replace existing" (deletes old, installs new, invalidates the `Skill` row's `InstalledSkill` bindings with a warning) or "Cancel".

Export never fails validation — we're serializing an already-parsed `Skill` — but the exported zip is re-validated as a self-test before the user sees "Export complete" (catches serializer bugs early).

**Permissions.** Two gates stack:
1. **Per-slug read-only**: the resolver rejects any write to a built-in slug — always, for every agent. This is a correctness invariant, not a configurable permission.
2. **Per-agent `fs_skill_write`**: a new blocked-action name controls whether an agent can write to *user* slugs under `/skills/`. Agents that should only *use* skills get this blocked; agents that should author skills don't. Layered on top of today's dual-layer enforcement (JS preamble + native `dispatch`) without changes to the enforcement mechanism itself.

Reads follow today's `fs_read` permission and apply uniformly to both bundle-backed and Documents-backed slugs.

**Secrets.** `InstalledSkill.config` values (per-installation secrets like API keys) stay in SwiftData, not in the on-disk package. The package is portable and shareable; the config is personal. The frontmatter's `iclaw.config` block only declares the *schema* for config, never values.

### Progressive disclosure

Today `PromptBuilder.buildInstalledSkillsSection` (iClaw/Services/Prompt/PromptBuilder.swift:359-395) expands every installed skill's full body, scripts list, and custom tools list into the system prompt. Change this to:

- **Dormant state** (default): one line per installed skill — `- **<name>** (`/<slug>`) — <description>.`
- **Active state**: the skill's full body joins the prompt. A skill becomes active when *any* of these happen in the session:
  1. User types `/<slug>` in the chat composer.
  2. The LLM calls one of the skill's `skill_*` function-call tools.
  3. The LLM calls `run_snippet` with a `skill:<name>:*` identifier.

Custom tool *definitions* (the JSON-schema tool list sent to the LLM) stay fully populated — that is small per-tool and removing them would defeat discovery. What we shrink is the **prose body** in the system prompt.

This keeps today's UX (tools are discoverable, methodology is accessible) while removing the O(n) prompt cost on number of installed skills, and naturally wires the slash-command path into the same disclosure state machine.

### Critical files to change

- **Parser / serializer / validator** — NEW
  - `iClaw/Services/Skill/SkillPackage.swift` — `parse(at:) -> ParsedSkillPackage`, `validate(at:) -> ValidationReport`, `read(at:) -> Skill` (parse + validate, throws on errors), `write(_ skill: Skill, to: URL)`. Responsible for locale resolution: picks the best `SKILL.<L>.md` overlay against `Bundle.preferredLocalizations`, merges with the canonical `SKILL.md`, and applies `tools/<tool>.<L>.json` + `scripts/<script>.<L>.txt` overlays before writing into the cached `Skill` row.
  - `iClaw/Services/Skill/SkillFrontmatter.swift` — minimal `---`-delimited YAML-subset parser for `SKILL.md` (name, description, `iclaw:` block)
  - `iClaw/Services/Skill/SkillJSMetaParser.swift` — regex-extract the `META = { ... }` literal at the top of a `tools/*.js` file, then parse it into a `SkillToolDefinition` (the object literal is a strict subset, so a small recursive-descent reader over the braced range is enough — no JS engine involved). Also runs `JSContext.checkSyntax` on the full file body for the syntax-error validator rule.
  - `iClaw/Services/Skill/ValidationReport.swift` — the `{ errors: [...], warnings: [...] }` value type, shared across all consumers.
- **Model** — LIGHT CHANGES
  - `iClaw/Models/Skill.swift:72-155` — add an optional `sourcePath` column (on-disk package URL) and a `sourceMtime: Date?` column (mtime at which the cache was parsed, for the lazy re-validation check). `scriptsRaw`/`toolsRaw`/`configSchemaRaw` remain as the parsed cache. Add a computed `slashSlug` that prefers `iclaw.slash` from the parsed package, falling back to `name` normalized.
- **Built-in loader** — REFACTOR
  - `iClaw/Services/Skill/BuiltInSkillResources.swift:18-25` — today loads one markdown file per skill. Extend to load a whole directory per skill.
  - `iClaw/Services/Skill/SkillService.swift:256-702` — replace the code-as-data `BuiltInSkills.Template` enum entries with a directory scan of `Bundle.main.url(forResource: "BuiltInSkills", withExtension: nil)`.
  - Move the current Swift-string `scripts: [ScriptTemplate(...)]`, `customTools: [ToolTemplate(...)]` payloads (SkillService.swift:341-702) into real files under `Resources/BuiltInSkills/<skill>/`. Purely mechanical but large.
- **New built-in skill: `skill-builder`** — NEW CONTENT
  - `Resources/BuiltInSkills/skill-builder/SKILL.md` — instructional body covering the directory layout, `SKILL.md` frontmatter, `const META` convention for tools, the `fs.*` + `install_skill` authoring flow, and the recommended pattern "after any edit, call the top-level `validate_skill(slug)` tool".
  - `Resources/BuiltInSkills/skill-builder/tools/scaffold.js` — `scaffold_skill(slug, name, description)` writes a minimal valid package using `fs.mkdir` + `fs.writeFile`, with slug uniqueness / format validation.
  - `Resources/BuiltInSkills/skill-builder/references/example-simple.md`, `example-tooled.md` — canonical examples the agent can read on demand.
  - **No `tools/validate.js`** — validation is the top-level `validate_skill` LLM tool backed by Swift. A JS mirror would drift; the SKILL.md instructs the agent to call the Swift-backed tool directly.
- **Prompt builder** — BEHAVIOR CHANGE
  - `iClaw/Services/Prompt/PromptBuilder.swift:359-395` — switch to dormant/active rendering. Requires a session-scoped "which skills have been activated" set (thread it from the caller; `PromptBuilder` stays stateless per build).
- **Slash-command preprocessor** — NEW
  - `iClaw/ViewModels/ChatViewModel.swift:552` (`sendMessage`) — prepend a small preprocessor that detects `/<slug>` as the leading token, marks the matching skill active in the session state, and strips the prefix (or no-ops the send if the message was slug-only).
  - `iClaw/Views/Chat/ChatView.swift` (around the composer near line 522) — add an autocomplete chip that lists installed-and-enabled skill slugs when the composer's first character is `/`. Reuse the data already surfaced by `AgentSkillsView`.
- **`fs` bridge — `/skills/` mount + auto-reload**
  - `iClaw/Services/Agent/AgentFileManager.swift:13` / `AgentFileManager.resolvedURL(agentId:path:)` — special-case paths whose first component is `skills`. Route to `Bundle.main/BuiltInSkills/<slug>/…` when `<slug>` is a built-in (read-only — reject all write-mode opens at resolve time), otherwise to `<Documents>/Skills/<slug>/…`. Consult a `Set<String>` of built-in slugs maintained by `SkillService`. The existing path-sanitization (no `..`, no null bytes, no backslashes — AgentFileManager.swift:364) keeps covering the `skills` subtree.
  - `iClaw/Services/CodeExecution/AppleEcosystemBridge.swift` — in each write-path dispatcher (`writeFile`, `appendFile`, `delete`, `mkdir`, `cp`, `mv`, plus fd-close for writable modes), after a successful mutation whose resolved URL is under `<Documents>/Skills/<slug>/`, post a `SkillService.reload(slug:)` on the main actor. Write attempts against built-in slugs return the resolver's read-only error without touching disk.
  - Add a `fs_skill_write` action name to the existing blocked-actions set, gating writes to *user* slugs only (built-ins are already read-only). Default policy per agent is chosen in `AgentSkillsView` (or wherever `blockedActions` is configured today).
- **SkillTools simplification** — REMOVE + ADD
  - `iClaw/Services/FunctionCall/SkillTools.swift` — delete `createSkill`, `editSkill`, `deleteSkill`, `readSkill` (agents use `fs.*` on `/skills/` instead). Keep `installSkill`, `uninstallSkill`, `listSkills`. Add `validateSkill(slug)` as a top-level safety primitive (returns the structured error/warning report). Add `reload_skill(slug)` as an **escape hatch** only, in case auto-reload on write misses something; not required for normal flows.
  - `iClaw/Services/FunctionCall/ToolDefinitions.swift` — remove the registrations for the dropped tools, add the `validate_skill` registration.
- **Skill UI (import / export)** — NEW ENTRIES, NO NEW TOOLS
  - `iClaw/Views/Skill/SkillLibraryView.swift` — add "Import Skill…" (unzip to temp → `SkillPackage.validate` → on errors, show a dialog of the report and abort; on warnings, show "Import anyway?"; on success, copy into `<Documents>/Skills/<slug>/` and register), "Export Skill…" (calls `SkillPackage.write`, then re-validates the exported artifact as a self-check), and "Show in Files" that deep-links to `<Documents>/Skills/` via `com.apple.DocumentManagerUI` URL scheme.
  - `iClaw/Views/Skill/SkillDetailView.swift` — a "Reveal package…" action for skills that have a `sourcePath`, so users can locate the on-disk source. Show a per-skill status badge driven by the cached `ValidationReport` (refreshed lazily on view appear via the mtime check): green (ok), amber (warnings), red (errors → last-good cache active).
- **No change**:
  - `JavaScriptExecutor.swift`, `FunctionCallRouter.executeSkillTool` — the JS execution path is already correct.
  - Existing `skill_<skill>_<tool>` generation — unchanged.

### Migration strategy

1. Land the parser (SKILL.md + tools/*.js `META` reader) + new on-disk format behind a feature flag, reading built-ins from a new `Resources/BuiltInSkills/` directory. Ship the directory alongside the existing Swift-string templates (do not remove them yet).
2. When parsing works in practice, flip the flag and delete the `BuiltInSkills.Template` code-as-data payloads. Retain `ensureBuiltInSkills()` — it iterates parsed directories now. User-created skills simultaneously migrate from SwiftData blobs to `<Documents>/Skills/<slug>/` (one-time migration in `ensureBuiltInSkills` or a companion `migrateUserSkillsToFiles`).
3. Wire the `/skills/` mount in `AgentFileManager` + auto-reload in `AppleEcosystemBridge`. Add `fs_skill_write` to the permission vocabulary. Remove the `create/edit/delete/read_skill` LLM tools.
4. Add import / export entries to the Skill UI so users can move packages on and off the device via Files.
5. Add the `/skill_name` preprocessor + composer autocomplete. Low risk — the feature is invisible until the user types `/`.
6. Do progressive disclosure last — it's the biggest behavior delta for existing users. Gate it on a setting (`skill.progressive_disclosure.enabled`), default on, user can turn off if they preferred the old prompt shape.

### Things I considered and rejected

- **Full standard compliance (no iclaw extension)**. Would either (a) drop all function-call tooling and force the LLM to author JS against `apple.*` inside free-form implementations, regressing tool ergonomics badly, or (b) invent a non-standard JSON file anyway. Neither is better than a namespaced frontmatter block.
- **Standard-only import path, keep DB as source of truth**. Superficially cheap. But without migrating built-ins to files, we keep two authoring paths forever and never get portability wins.
- **Run standard Claude skills unmodified** (i.e. execute their Python / shell). Out of scope — iOS sandbox has no Python, no `pip`, no Node. We would be pretending to run a skill while silently ignoring half of it. Instructional parts of standard skills will still work because they are just prose.

## Verification

- **Parser round-trip**: `SkillPackage.write(skill) → SkillPackage.read(path)` produces a `Skill` equal to the original on all fields (add a unit test in `iClawTests/SkillPackageTests.swift`).
- **JS META parser**: unit tests cover `tools/fetch_and_extract.js` with varied whitespace, trailing commas, and nested `parameters` arrays; malformed META returns a parse error with file+line.
- **Built-in parity**: after the built-in refactor, run the app and confirm `listSkills` shows the same set with the same `effectiveDisplayName`, summary, tools, and scripts per locale (en / zh-Hans / ja / ko). Specifically, in zh-Hans, verify *Deep Research*'s display name is "深度研究", its summary and body are localized, and `fetch_and_extract`'s tool description + parameter descriptions are the translated strings — all sourced from `Resources/BuiltInSkills/deep-research/SKILL.zh-Hans.md` and `tools/fetch_and_extract.zh-Hans.json`, with **no remaining `skill.*` keys in `Localizable.strings`**.
- **Locale fallback**: remove the `ja` overlay for one skill, switch the device to Japanese, verify the skill falls back to English cleanly (not to a hardcoded key, not to an empty string).
- **UI import / export round-trip**: from `SkillLibraryView`, export *Deep Research* to a folder, re-import it as a new skill, confirm it renders and its `skill_deep_research_fetch_and_extract` tool runs identically.
- **Slash-command**: type `/deep_research what is RLHF?` in the chat composer. Verify (i) the `/deep_research` prefix is stripped before the message is sent, (ii) the *Deep Research* body is now in the system prompt for this and subsequent turns, (iii) an unknown `/foo` is sent as-is without error, (iv) the autocomplete chip appears on leading `/` and lists installed-and-enabled skills only.
- **Progressive disclosure**: install two non-trivial skills (e.g. *Deep Research* + *Health Plus*), measure system-prompt char count before and after the flag flip. Body sections should disappear from dormant skills. Then call a `skill_health_plus_*` tool and re-measure — *Health Plus* body should reappear, *Deep Research* should remain dormant until `/deep_research` or one of its tools fires.
- **Bridge regression**: run the existing *Deep Research* custom tool `fetch_and_extract` and each *File Ops* tool. Behavior must be identical to today (nothing in the execution path changed).
- **Agent-authored skill (fs)**: from an agent with `fs_skill_write` enabled, `fs.mkdir('/skills/hello-world')` + `fs.writeFile('/skills/hello-world/SKILL.md', '---\\nname: Hello\\ndescription: ...\\n---\\n...')` + `fs.writeFile('/skills/hello-world/tools/greet.js', ...)`. Then on the next turn, `install_skill name="Hello"` and verify `skill_hello_greet` appears as a callable tool. Confirm no `create_skill`/`edit_skill` LLM tool is needed along the way.
- **Skill-builder bootstrap**: install the built-in `skill-builder` on a fresh agent. Ask the agent "create a skill that greets the user by name". Expected: the agent reads `skill-builder`'s body (or calls `scaffold_skill`), writes a valid package under `/skills/<new-slug>/`, calls `validate_skill` successfully, then calls `install_skill`. Verify the resulting `skill_<new>_*` tool is callable and produces the expected output — all without the agent ever seeing `create_skill` in its tool list.
- **Broken-edit resilience (last-good cache)**: install *Deep Research* (or a forked user copy), invoke `fetch_and_extract` once to confirm it runs. Then, from the agent, `fs.writeFile('/skills/<slug>/tools/fetch_and_extract.js', '// broken — no META and syntax error {{{')`. Expect: the write succeeds, the `ToolCallResult` carries a `[Warning] Skill '<slug>' now fails to parse: …` message, and a follow-up call to `skill_<slug>_fetch_and_extract` **still succeeds** against the last-good code. Then `validate_skill("<slug>")` must surface the same error with file + line. Finally, overwrite with a valid version and confirm the skill picks up the fix on the next call (cache re-warms after a successful parse).
- **Validator consistency**: craft one malformed package (missing `description`, bad `META.parameters[].type`, JS syntax error in a script, stale locale overlay). Feed it through each of the four code paths — `validate_skill` LLM tool, `SkillLibraryView` import dialog, `SkillService.reload` after an `fs.writeFile`, and the lazy mtime-triggered re-parse on read — and assert **identical** error/warning lists (same codes, same messages, same files, same lines). Regression test: if any consumer diverges from the others, the single-validator invariant is broken.
- **External edit pickup**: edit `<Documents>/Skills/<slug>/SKILL.md` directly from the iOS Files app (bypassing the `fs` bridge), then open iClaw and observe: the next `list_skills` or `skill_<slug>_*` call produces the updated content without any foreground hook or explicit reload. Confirm the `stat` check is actually firing by logging a "mtime-changed → re-parse" event.
- **Import hardening**: try to import (a) a valid skill, (b) a skill with `name` > 64 chars (error), (c) a skill with a warning-only issue (short `META.description`), (d) a zip whose root is a subfolder (malformed — should reject cleanly), (e) a slug that collides with an existing user skill. Verify each is handled according to the spec.
- **Error spectrum coverage**: unit tests exercise each bullet under "Errors — skill is unavailable" and "Warnings — skill loads, but something is off" individually, asserting the right `code` and `file`/`line` surface in the `ValidationReport`.
- **Files app round-trip**: open the iOS Files app on a simulator, navigate to iClaw's Documents → Skills → Hello, open `SKILL.md` in a text editor, edit the description, save. Re-open iClaw and verify the new description is reflected in `list_skills` (auto-reload via file-system watcher or next-read re-parse — whichever variant is chosen).
- **Permission model**: an agent with `fs_skill_write` blocked cannot write to `/skills/` but *can* still read it and use installed skills. Verify the native-layer rejection (not just the JS preamble) by tampering with the JS layer.
- **Built-in read-only**: from an agent with `fs_skill_write` **enabled**, attempt `fs.writeFile('/skills/deep-research/SKILL.md', 'hijacked')`, `fs.delete('/skills/file-ops', {recursive: true})`, and `fs.mkdir('/skills/deep-research/new-subdir')`. All three must fail with the read-only error, and the on-bundle files must be byte-unchanged. Also verify the fork flow: `fs.cp('/skills/deep-research', '/skills/my-research', {recursive: true})` succeeds and the copy is writable.
- **Secret isolation**: verify `InstalledSkill.config` values never appear anywhere under `<Documents>/Skills/<slug>/` — they remain in SwiftData only.
