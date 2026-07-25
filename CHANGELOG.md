# Changelog

## [1.0.1] - 2026-07-25

- `--redact` now catches prefixed and suffixed secret variables (`MYSQL_PASSWORD`, `PASSWORD_FILE`, `APP__DB_PASSWORD`) — the previous word-boundary pattern only matched a bare `password=`. Keyword set extended with `PWD`, `PASSPHRASE`, `CREDENTIAL(S)`, `DSN` and `PRIVATE_KEY`; quoted values are masked whole. The variable name and its original separator stay in clear so the report keeps its meaning, and policy keys (`password_required=yes`, `PasswordAuthentication no`, `PWD`/`OLDPWD`) are left readable.

## [1.0.0] - 2026-07-17

- Initial Crystal port: SSH audit collector with YAML config, preset inheritance and JSON output.
- Check metadata (`category`, `severity`, `expected`) carried into the JSON output to steer LLM-driven analysis; ssherlock computes no pass/fail.
- `skill` subcommand: print the baked `ssherlock-audit` analysis skill, or install it into a Claude Code skills directory (`--global`, `--force`).
