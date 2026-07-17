# Changelog

## [Unreleased]

- Initial Crystal port: SSH audit collector with YAML config, preset inheritance and JSON output.
- Check metadata (`category`, `severity`, `expected`) carried into the JSON output to steer LLM-driven analysis; ssherlock computes no pass/fail.
- `skill` subcommand: print the baked `ssherlock-audit` analysis skill, or install it into a Claude Code skills directory (`--global`, `--force`).
