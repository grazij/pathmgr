# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 — initial release

`pathmgr` is a single-file C99 utility (no dependencies beyond libc) that
reads a list of directories from a config file and prints a `:`-joined
path string to stdout. Intended use:

```sh
export PATH="$(pathmgr -q)"
```

### Behavior

- **Config lookup order** (first match wins): `-c CONFIG` →
  `$XDG_CONFIG_HOME/pathmgr/config` (if set) →
  `$HOME/.config/pathmgr/config` (XDG default — canonical) →
  `$HOME/.pathmgr/config` (legacy) → `$HOME/.pathmgr` (single-file).
- **Comments and blanks:** lines whose first non-whitespace character is
  `#` are full-line comments. Blank lines are ignored. CRLF tolerated.
- **Expansion** (per entry, before the directory check): `~/foo`,
  `~user/foo` (via `getpwnam(3)`), `$VAR/foo`, `${VAR}/foo`. Mid-string
  `~`, `${VAR:-default}`, and `\$`-style escapes are intentionally not
  supported.
- **Filtering:** entries that don't exist or are empty directories are
  skipped with a stderr warning. Suppress warnings with `-q`.
- **Optional entries:** prefix a line with `?` (e.g. `?/opt/homebrew/bin`)
  to mark it optional. Optional entries that fail to expand or aren't
  valid directories are silently skipped without affecting the exit code.
- **Output:** bare `:`-joined string, one line. Compose with `$(...)` —
  there is no `PATH=` wrapping.
- **Universal binary on macOS** (`-arch arm64 -arch x86_64`,
  `-mmacosx-version-min=11.0`).

### Flags

| Flag | Purpose |
| --- | --- |
| `-c CONFIG` | Read config from `CONFIG` (overrides default lookup) |
| `-d` | Drop duplicate entries (first occurrence wins) |
| `-q` | Suppress skip warnings on stderr |
| `-v` | Print kept entries, expansions, and dropped duplicates on stderr (`-q` wins if both are given) |
| `-V` | Print version (`pathmgr X.Y.Z`) and exit |
| `-h` | Show help and exit |

Argument parsing uses POSIX `getopt(3)`; short-option bundling (`-dq`)
works. Long options (`--help`, `--version`) are not supported.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Every config entry was emitted |
| `1` | Fatal error (missing config, I/O error, out of memory) |
| `2` | Bad command-line argument |
| `3` | One or more entries were skipped during expansion or filtering. `?optional` skips and dedup drops do **not** contribute. |

### Distribution

- `Formula/pathmgr.rb` — Homebrew formula (placeholders for tarball URL
  and SHA256; fill in once a release is tagged).
- `examples/config.example` — portable starter config.
- `pathmgr.1` — man page generated from `-h`/`-V` output via
  `help2man`. Regenerate with `make man`. `make install` copies it to
  `$(PREFIX)/share/man/man1/`.
