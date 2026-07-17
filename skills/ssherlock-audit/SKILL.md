---
name: ssherlock-audit
description: Analyze a ssherlock collection run and write a structured AUDIT_REPORT.md. Use when the user has a ssherlock output directory (audit_<date>/ with <label>.json per host plus all.json) and wants findings — hardware obsolescence, capacity headroom, security posture, config drift across the fleet — deduced from the collected JSON. Triggers on "/ssherlock-audit", "audit this ssherlock run", "analyze the collected JSON", "write the audit report".
---

# ssherlock-audit

ssherlock does the fieldwork: it visits every host read-only and writes the
collected evidence as JSON. This skill is the analyst half — Watson writing up
the case. It reads a run's output, correlates across the fleet, and produces a
structured `AUDIT_REPORT.md`. It never connects to a host; it only reads JSON
already on disk and writes the report.

## Input — locate the run

The argument is the run's `output_dir` (e.g. `audit_2026-07-19`). If none is
given, list `audit_*/` directories in the working tree and ask which one; never
guess. A valid run contains one `<label>.json` per host plus an aggregated
`all.json`.

Read `all.json` for the fleet view, and the per-host `<label>.json` files when
you need detail — `all.json` holds only the **last batch** launched, so for a
fleet collected in several passes the per-host files are authoritative.

## The JSON you are reading

Each host is one envelope (`all.json` is an array of them):

```json
{
  "label": "web01",
  "host": "web01",
  "error": null,
  "collected_at": "2026-07-19 10:32:01 +02:00",
  "data": {
    "<section>": {
      "<check>": {
        "category": "security",
        "severity": "high",
        "expected": "No NOPASSWD grants unless explicitly justified.",
        "description": "Searches sudoers for NOPASSWD grants.",
        "output": "…"
      }
    }
  }
}
```

- `error` non-null means collection failed for that host — report it as a gap,
  do not analyze absent data as if it were a finding.
- `output` is always a string, the raw command output; it may be **empty**
  (command produced nothing / was unavailable). Empty output is itself a
  signal — note it, never invent what the command "would have" returned.
- The metadata fields ride in from the check definition, in the fixed order
  `category, severity, expected, description, output`; **nil fields are
  omitted**, so a plain inventory check may carry only `description` + `output`:
  - `category` — grouping axis (`inventory`, `capacity`, `security`,
    `lifecycle`, `availability`, `observability`). Use it to structure findings.
  - `severity` — `low` / `medium` / `high`, on *control* checks only: how bad a
    bad result is. Rank findings by it.
  - `expected` — free text describing a good result, on control checks.
    ssherlock computes **no** pass/fail — judge the actual `output` against
    `expected` yourself; that judgement is the whole point of this skill.
- Section and check names come from the preset the host ran; do not assume a
  fixed set — read what is actually present.

## Method — non-negotiable

- **Source is the JSON read this turn, never training memory.** Every figure,
  version, model number and count in the report is quoted from a check's actual
  `output`. If it is not in the collected data, you do not know it — say so.
- **Prove, do not assert.** When you claim a host is over-committed, obsolete, or
  unpatched, cite the section/check and the value that shows it.
- **Never conclude from a single noisy metric.** Cross-check; a value that swings
  run-to-run (build times, cache-warmed timings) is not evidence on its own.
- **Every recommendation carries its trade-off** — the cost, the risk, what it
  loses, the case where it breaks. A recommendation with no downside listed is
  suspect: either a downside was missed or it is not a real choice.
- **Flag gaps, never fill them.** Missing checks, failed hosts, `null` outputs →
  an explicit "to complete" list, not invented numbers.
- **Read-only.** This skill reads collected JSON and writes one report. It does
  not run commands against hosts and does not modify the collected data.

## Analysis dimensions

Adapt to whatever the presets collected; typical axes:

- **Hardware / CPU** — generation, microarchitecture, instruction-set level
  (AVX2 / AVX-512, `x86-64-v2/v3`), core/thread counts, obsolescence vs the
  target workload.
- **Capacity & consolidation** — RAM and vCPU allocated (running guests) vs
  physical, over-commit ratios, HA headroom, what can be evacuated onto what.
- **Security posture** — kernel and platform versions, mitigations enabled,
  SSH hardening, EOL software, version drift between hosts that should match.
- **Storage** — backend, protocol, saturation, single points of failure.
- **Config drift** — services, packages, and settings that diverge across
  hosts meant to be identical.

## Deliverable — AUDIT_REPORT.md

Write `AUDIT_REPORT.md` in the run's directory (or where the user asks). It is
the living deliverable and takes precedence over any prose in the chat. Suggested
structure, pruned to what the data supports:

1. **Overview** — fleet, collection date, what was covered and what failed.
2. **Inventory** — per host (or per site/group when the user anchors a topology):
   hardware, versions, roles, drawn from the checks.
3. **Findings by dimension** — the axes above, each claim proved from a check.
4. **Prioritized recommendations** — each with its trade-off (pour / contre).
5. **To complete** — gaps: failed hosts, `null` outputs, checks not run,
   questions the collection cannot answer.

## Language

Default to the user's language (the audit reports these teams produce are in
French). If the user specifies a language, use it.

## Scope (v1)

One `output_dir` → one report. Multi-site topology reasoning — capacity that is
non-fungible between sites, WAN vs LAN placement, per-site renewal strategy — is
client-specific; this skill supplies the method and the report structure, and
the user anchors the topology. State this when a fleet clearly spans sites the
collected data alone cannot relate.
