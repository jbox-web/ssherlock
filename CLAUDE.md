# CLAUDE.md

Guidance for Claude Code working in this repository. English is the deliverable
language (code, comments, commits, docs, this file).

## What this is

ssherlock is a single self-contained Crystal binary that SSHes into a fleet
**read-only**, runs preset-based command catalogues per platform (Linux,
Proxmox, VMware ESXi), and writes one structured JSON envelope per host. It is
the *fieldwork* half of an AI-assisted infra audit; the *analysis* half is the
baked `ssherlock-audit` skill (`skills/`), which an LLM runs over the JSON.

## Commands

Everything goes through `mise dev:*` — the build/spec/docs tasks depend on
`dev:licenses`, which assembles `licenses/` **before** compilation because that
folder is baked into the binary (an absent/empty baked folder fails the build).

```sh
mise dev:deps          # shards install (also builds bin/ameba)
mise dev:build         # compile the dev binary
mise dev:format-check  # crystal tool format --check
mise dev:ameba         # static analysis (bin/ameba)
mise dev:spec          # unit specs
mise dev:spec-mt       # same, -Dpreview_mt — fiber-safety gate
mise dev:check         # format-check + ameba + spec + spec-mt in one shot
```

Run `mise dev:check` before declaring work done. Direct `crystal spec` works too
(the `licenses/` and `skills/` folders already exist in-tree), but prefer the
mise tasks so the baked folders stay assembled.

## Architecture

Data flow: `Config` loads a fleet file into `Server` structs (each carrying a
`Preset`-resolved check catalogue) → `Runner` drives collection across a bounded
fiber pool → `Collector` opens one SSH scope per host and runs each check via
`CheckRunner` → `Executor` (real `SshExecutor`, or a fake in specs) → results
serialise into a `Collector::Envelope` written as `<label>.json` plus an
aggregated `all.json`.

- **`Preset`** resolves an `inherit:` chain via `Ssherlock.deep_merge` (child
  overrides parent; a `null` child knocks a check out). Resolution order for a
  preset name: inline `presets:` > `presets_dir` > baked catalogue.
- **`Merge`** — `deep_merge` is the one merge rule used everywhere (preset
  inheritance *and* user `overrides:`); a `null` override removes a key.
- **`Authenticator`** — agent first, key file fallback, like a real ssh client.
- **`SshConfigResolver`** — honours `~/.ssh/config` via `ssh -G`.
- **`HostKeyPolicy`** — strict: only a `known_hosts` MATCH is accepted, applied
  only when `verify_host_key: known_hosts` (default is `never`).
- **Baked folders** (`BakedPresets`, `Licenses`, `BakedSkills`) — embedded at
  compile time from `config/presets/`, `licenses/`, `skills/`. Exposed by the
  `presets`, `licenses`, `skill` subcommands.

## Invariants — non-negotiable

- **Read-only on targets.** Every check command is non-mutating. The "never a
  mutation" promise is about the SSH *targets*, not the local FS (`run` writes
  its output dir; `skill install` writes `.claude/skills/`).
- **No secret reaches disk.** `--redact` masks PEM keys, `password=…` pairs and
  bearer tokens (`Redactor`) before serialisation. If a new check can expose a
  credential, extend `Redactor` and its spec first (TDD), then verify no
  plaintext leaked into the output.
- **Shipped defaults live in baked folders.** Changing a baked preset, a license
  or the skill means a rebuild — everyday customisation belongs in the fleet
  file (`overrides:`, inline `presets:`, `presets_dir`), not in the binary.
- **The spec-mt gate is real.** Specs must be fiber-safe: no process-global
  state (`Dir.cd`, `ENV`, CWD-relative writes) in a spec, or `dev:spec-mt`
  races. Write to explicit temp dirs, not the CWD or `$HOME`.

## Output JSON schema

`all.json` is an array of envelopes; `<label>.json` is one envelope:

```
{ label, host, error, collected_at, data: { <section>: { <check>: CheckResult } } }
```

`CheckResult` serialises in a **fixed field order** with nil metadata omitted:
`category, severity, expected, description, output`. `output` is always a string
(possibly empty); `error` non-null means that host's collection failed. ssherlock
computes no pass/fail — `expected`/`severity` are metadata for the LLM analyst to
judge against. Keep this schema and the `ssherlock-audit` skill's description of
it in sync.

## Gotchas

- **Baked files have a shared read position.** Read baked content through
  `BakedFileSystem.get(path).gets_to_end`, not by re-reading a handle from
  `.files` — a consumed `files` handle yields empty on the next read.
- **`ssh2` is pinned to a feature branch** (`n-rodriguez/ssh2.cr`,
  `feature/known-hosts-helper`) for the known-hosts helper.
- **A frozen SSH read parks a fiber** until the host disconnects; the
  caller-side guard is `cmd_timeout + 5s`, and server-side `timeout` wrapping
  (`wrap: true`) is the primary guard. `wrap: false` presets (ESXi) rely on the
  caller-side guard alone. See README *Known limitations*.

## Conventions

- **TDD** for unit-testable code (Spectator): failing spec first, then minimal
  code. Infra/config/glue is out of scope.
- **Prove before claiming done** — run the command, show the output; never
  declare a change working from assumption.
- **Strict scope** — change only what is asked; flag adjacent issues, do not fix
  them silently. Every file ends with a trailing newline.
- **Commit messages** — English, imperative title (≤ ~70 chars), one body bullet
  per file/group. Commit/push only on an explicit trigger.
