# Changelog

## [1.0.2] - 2026-11-18

### Fixed

- The embedded notices of libssh2, libyaml, PCRE2, zlib and musl carry their
  authors' copyright lines instead of a license template with blanks, and the
  libgcc notice names GPL-3.0-or-later
- The macOS binaries link OpenSSL and libssh2 statically and only load the
  libraries macOS ships: they no longer need Homebrew's `libssh2` and
  `openssl` installed at the same path to start

### Changed

- Releases are built and published by crystalreleaser
  (`.crystalreleaser.yml`, `.github/workflows/release.yml`); the assets keep
  their names, `ssherlock-<os>-<arch>` and its `.sha256`
- The macOS releases no longer ship a `.dwarf` debug file and its `.sha256`
  next to the binary

## [1.0.1] - 2026-07-25

- `--redact` now catches prefixed and suffixed secret variables (`MYSQL_PASSWORD`, `PASSWORD_FILE`, `APP__DB_PASSWORD`) — the previous word-boundary pattern only matched a bare `password=`. Keyword set extended with `PWD`, `PASSPHRASE`, `CREDENTIAL(S)`, `DSN` and `PRIVATE_KEY`; quoted values are masked whole. The variable name and its original separator stay in clear so the report keeps its meaning, and policy keys (`password_required=yes`, `PasswordAuthentication no`, `PWD`/`OLDPWD`) are left readable.

## [1.0.0] - 2026-07-17

- Initial Crystal port: SSH audit collector with YAML config, preset inheritance and JSON output.
- Check metadata (`category`, `severity`, `expected`) carried into the JSON output to steer LLM-driven analysis; ssherlock computes no pass/fail.
- `skill` subcommand: print the baked `ssherlock-audit` analysis skill, or install it into a Claude Code skills directory (`--global`, `--force`).
