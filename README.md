# ssherlock

[![CI](https://github.com/jbox-web/ssherlock/actions/workflows/ci.yml/badge.svg)](https://github.com/jbox-web/ssherlock/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Crystal](https://img.shields.io/badge/Crystal-1.20-black?logo=crystal)](https://crystal-lang.org)

> Point it at your fleet. It logs in read-only over SSH, gathers the evidence,
> and hands you one JSON file per host — shaped for an LLM to reason over.

**ssherlock is the fieldwork of an AI-assisted infra audit.** It plays the
detective: it visits every host and collects the clues, read-only, never a
mutation. Your LLM is Watson — it reads the collected JSON and writes up the
case. ssherlock never calls a model itself; it produces deterministic output
*made to be reasoned over*, and the companion
[`ssherlock-audit` skill](#the-analysis-half) turns a raw collection into a
structured audit report.

A single self-contained binary — no agent to deploy, nothing to install on the
targets. ssherlock connects over SSH (agent / `ssh_config` / `known_hosts`
aware), runs **preset-based command catalogues** tuned per platform (Linux,
Proxmox, VMware ESXi), and writes structured JSON you can diff, grep, or feed to
the analysis half.

Everything it runs is read-only inventory and posture collection — `lscpu`,
`ss -tlnp`, `pveversion`, `esxcli …` — never a mutation.

## Highlights

- **One static binary.** Presets are baked in; drop it on a jump host and go.
- **Platform presets out of the box** — `linux`, `linux-full`, `proxmox`, `vmware`.
- **RuboCop-style check management** — disable, retune or add checks per preset
  straight from your fleet file, without ever touching the presets.
- **Fleet-parallel** with bounded concurrency and per-host / per-command timeouts.
- **Bastion / jump-host** relay, `ssh -G` config resolution, optional
  `known_hosts` verification.
- **Secret redaction** (`--redact`) masks PEM keys, `password=…` pairs and
  bearer tokens before anything hits disk.

## Usage

    ssherlock run                      # collect the whole fleet from ./ssherlock.yml
    ssherlock run -c infra.yml         # use a different config file
    ssherlock run web01 db01           # only these machines (by label or host)
    ssherlock run --redact             # mask secrets in the output
    ssherlock presets                  # list the baked presets
    ssherlock presets linux            # dump a resolved preset as YAML
    ssherlock skill                    # print the bundled ssherlock-audit skill
    ssherlock skill install            # install it into ./.claude/skills
    ssherlock licenses                 # print bundled third-party licenses

The config defaults to `ssherlock.yml` in the working directory; point elsewhere
with `--config`/`-c`. Positional arguments are **targets** — each matched against
a server's `label` or `host` — so you can audit a single machine without editing
the fleet file; an unknown target is an error. Output lands in `output_dir`
(default `audit_<date>/`): `<label>.json` per host plus an aggregated `all.json`.

## The analysis half

The binary stops at the JSON. Turning a collection into findings — hardware
obsolescence, capacity headroom, security posture, config drift across the
fleet — is the analyst's job, and that analyst is an LLM.

The companion **`ssherlock-audit`** skill drives it. It rides **inside the
binary** — `ssherlock skill install` writes it into `./.claude/skills/` where
Claude Code finds it (`--global` targets `~/.claude/skills/`, `--force` to
overwrite). Point it at a run's `output_dir` and it reads every `<label>.json`,
correlates across hosts, and writes a structured `AUDIT_REPORT.md`.

    ssherlock skill install            # 0. materialise the skill (once)
    ssherlock run                      # 1. collect — the fieldwork
    /ssherlock-audit audit_2026-07-19  # 2. deduce  — the writeup

Its method is the non-negotiable part: every figure is proved from a check's
actual output, never from the model's memory; every recommendation carries its
trade-off; gaps are flagged, not invented. ssherlock keeps the collection
deterministic so the reasoning on top stands on solid ground.

The binary only carries and installs the skill — it never runs it, an LLM does.
And that skill is just one way to drive the analysis: `all.json` is plain
structured data; pipe it into whatever assistant you like.

## The fleet file

```yaml
output_dir: audit_2026-07-17
concurrency: 6             # parallel hosts, clamped to 1..32

# Applied to every server, then overridden per entry.
defaults:
  inherit: linux           # which preset a host runs
  ssh:
    user: root
    key: ~/.ssh/id_rsa
    config: true           # honour ~/.ssh/config via `ssh -G` (default true)
    verify_host_key: never # or `known_hosts`
    timeout: 10            # connect timeout, seconds
  cmd_timeout: 20          # per-command timeout, seconds
  sudo: false

servers:
  - { host: web01, label: web01 }
  - { host: pve01, label: pve01, inherit: proxmox }
  - { host: esx01, label: esx01, inherit: vmware, ssh: { user: admin } }
  - { host: db01,  label: db01,  inherit: linux-full, sudo: true, ssh: { bastion: jump@edge } }
```

Each server needs a `host` and a unique `label`; everything else falls back to
`defaults`. `inherit` picks the preset the host runs.

## Checks, RuboCop-style

Think of it the way RuboCop thinks about cops. The **presets** shipped in the
binary are the default rule packs; your fleet file's `overrides:` block is your
`.rubocop.yml` — it layers on top of a preset, keyed by preset name, to disable,
retune or add individual checks. The presets themselves stay untouched.

A preset is a two-level catalogue — `section → check` — where each check is a
`description` plus a `command`:

```yaml
checks:
  cpu:
    lscpu:
      description: CPU topology and instruction-set flags.
      command: lscpu
```

### Check metadata

Each check carries declarative metadata that rides into the JSON output to steer
the analysis:

- `category` — grouping axis, one of `inventory`, `capacity`, `security`,
  `lifecycle`, `availability`, `observability`. Set on every baked check,
  optional on your own (an unknown value is rejected).
- `severity` — `low` / `medium` / `high`, on *control* checks only: how bad a
  bad result is.
- `expected` — free text describing a good result, on control checks.

ssherlock never evaluates `expected` or computes a pass/fail — the analyst (an
LLM) does the judgement. Fields serialise in a fixed order (`category, severity,
expected, description, output`); absent ones are omitted.

```yaml
security:
  sudo_nopasswd:
    category: security
    severity: high
    expected: No NOPASSWD grants unless explicitly justified.
    description: Searches sudoers for NOPASSWD grants.
    command: grep -rhE 'NOPASSWD' /etc/sudoers /etc/sudoers.d/ || echo none
```

### Disable a check

Set it to `null` (`~`) to knock it out — the analogue of `Cop: { Enabled: false }`:

```yaml
overrides:
  linux:
    services:
      packages: ~        # drop the linux/services.packages check
```

### Retune a check

Redeclare it — your keys deep-merge over the preset's, so you can swap the
command or reword the description while keeping everything else:

```yaml
overrides:
  linux:
    storage:
      df:
        command: df -hT -x tmpfs -x devtmpfs -x overlay
```

### Add your own check

Declare a check the preset doesn't have; missing sections and checks are created
on the fly. A `command` is required, `description` is optional:

```yaml
overrides:
  linux:
    cpu:
      logical_count:                 # new check in an existing section
        description: All-logical-CPU count.
        command: nproc --all
    custom:                          # brand-new section
      reboot_pending:
        description: Kernel reboot flag.
        command: '[ -f /var/run/reboot-required ] && echo yes || echo no'
```

Overrides are scoped to the preset name, so `overrides: { proxmox: { … } }`
only touches hosts that `inherit: proxmox`.

### Preset inheritance

Presets can inherit from one another with a top-level `inherit:` — that's how
`linux-full` extends `linux` with SSH-hardening, firewall, update and log
checks. Child checks deep-merge over the parent, and a `null` child knocks a
parent check out. Same merge rules as your overrides, one level up.

### Defining your own preset

A preset is a full named catalogue (`options` + `checks`) you can `inherit:` and
select per host — the level above a per-check `override`. You can define one
without rebuilding, in either of two places, and ssherlock resolves a preset name
through this chain, first source wins:

**inline `presets:` > external directory > baked catalogue.**

Inline, straight in the fleet file — handy for a small derived preset:

```yaml
presets:
  webnode:
    inherit: linux          # extend a baked (or dir, or inline) preset
    options: { wrap: true }
    checks:
      web:
        nginx_version:
          description: Installed nginx build.
          command: nginx -v 2>&1

servers:
  - { host: web01, label: web01, inherit: webnode }
```

Or in an external directory of `<name>.yml` files, pointed at by the `presets_dir:`
key or the `--presets-dir DIR` flag (the flag wins over the key). A relative path
resolves against the **config file's** directory; an absolute path is used as-is:

```yaml
presets_dir: ./presets     # ./presets/freebsd.yml → inherit: freebsd
```

    ssherlock run -c infra.yml --presets-dir /etc/ssherlock/presets

A preset that **shadows an existing name** (inline or dir preset named like a baked
one) replaces it — but it must not `inherit:` that same name, or the resolver
rejects the self-cycle. To extend a baked preset, inherit it under a *new* name.

The baked catalogue itself lives in `config/presets/*.yml` and is embedded at
build time; changing the shipped defaults still means a rebuild, but everyday
customisation belongs in your `overrides`, inline `presets:` or a `presets_dir`.

## Known limitations

- **Host key verification defaults to off.** Hosts connect publickey-only with
  `verify_host_key: never` unless you opt a host into `known_hosts` — convenient
  for a trusted fleet, unsafe on untrusted networks. With `known_hosts`,
  ssherlock fails fast when `~/.ssh/known_hosts` is missing rather than letting
  every host fail auth one by one.
- **A frozen command leaves a background fiber until the host disconnects.**
  Each check is guarded by a caller-side timeout (`cmd_timeout + 5s`), but
  Crystal cannot cancel a fiber blocked on a frozen SSH read; the fiber parks
  until the host's session closes at the end of its checks. The `ssh2.cr`
  session releases its lock while waiting, so the remaining checks on that host
  still run — but one hung read costs a parked fiber and an open channel for
  the rest of that host's collection. Server-side `timeout` wrapping
  (`wrap: true`) is the primary guard; `wrap: false` presets (ESXi) rely on the
  caller-side guard alone.
