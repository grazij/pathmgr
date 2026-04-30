# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `-k KIND` flag selects which config to read. Valid kinds: `path`
  (default), `man`, `info`, `fpath`. The output format is unchanged
  (still a `:`-joined string) — the kind only chooses which file is
  read, so users can compose the result into `PATH`, `MANPATH`,
  `INFOPATH`, or zsh's `fpath` array.
- New starter examples: `examples/man.example` and
  `examples/fpath.example`.

### Changed (breaking)

- The canonical config filename is now `<kind>` (e.g. `path`, `man`)
  instead of `config`. Lookup paths become:
  1. `-c CONFIG`
  2. `$XDG_CONFIG_HOME/pathset/<kind>`
  3. `$HOME/.config/pathset/<kind>` (canonical)
  4. `$HOME/.pathset/<kind>`

  Existing users must rename their config:
  `mv ~/.config/pathset/config ~/.config/pathset/path`.
- The `$HOME/.pathset` single-file fallback is removed — it doesn't
  fit the multi-kind layout. Move to `~/.config/pathset/path` if you
  were using it.
- Invalid `-k` values (anything outside `{path, man, info, fpath}`)
  exit `2`. When both `-c` and `-k` are given, `-c` wins and `-k` is
  silently ignored (kind only affects the default lookup).
- Renamed `examples/config.example` → `examples/path.example`.

## 0.2.0

### Changed (breaking)

- Renamed the project from `pathmgr` to `pathset`. The binary, source
  file (`pathset.c`), man page (`pathset.1`), and Homebrew formula are
  all renamed in lockstep.
- Config lookup paths are renamed accordingly. New locations (first
  match wins):
  1. `-c CONFIG`
  2. `$XDG_CONFIG_HOME/pathset/config`
  3. `$HOME/.config/pathset/config` (canonical)
  4. `$HOME/.pathset/config`
  5. `$HOME/.pathset`
- No fallback to old `pathmgr` paths is provided. Users on 0.1.0 must
  move their config: `mv ~/.config/pathmgr ~/.config/pathset` (or the
  equivalent for whichever location they used).
- The `-V` output now prints `pathset X.Y.Z` instead of `pathmgr X.Y.Z`.
- The default `make` / `make build` / `make release` build is now a
  **native single-arch** binary (was: macOS universal). Source-based
  installers like Homebrew compile on the user's host and don't benefit
  from a fat binary. Pass `make universal` or `make release-universal`
  to opt in to a fat binary for prebuilt-distribution artifacts.
- The GitHub repository was renamed from `grazij/pathmgr` to
  `grazij/pathset`. GitHub redirects from the old name continue to work
  for clones, but published Homebrew formula URLs now point at the new
  repo.

### Added

- `make universal` and `make release-universal` targets — explicit
  opt-in fat (`-arch arm64 -arch x86_64`) builds on macOS.
- `make release` and `make release-universal` now also run `make test`
  and `make man`, then print `./pathset -V` and a tag-and-push reminder.
  The full release artifact is verified before you tag.
- `make formula VERSION=X.Y.Z` — fetches the tagged tarball from
  GitHub, computes its SHA256, rewrites `Formula/pathset.rb` (`url` and
  `sha256` lines), commits + pushes to this repo, then mirrors the
  formula to `$TAP_DIR` (default `../homebrew-tap`) and commits +
  pushes there. Override `TAP_DIR`, `GITHUB_USER`, `GITHUB_REPO` if
  your layout differs.
- `make formula-verify` — first-time / sanity-check `brew tap` +
  `install` + `pathset -V` + `uninstall` round-trip against the
  published tap.

### Documentation

- README now explains *why* `pathset` exists: macOS `/etc/zprofile`
  runs `/usr/libexec/path_helper` before `~/.zshenv`, which rewrites
  `PATH` from `/etc/paths` and `/etc/paths.d/*` and pins Apple's
  (often empty) directories first. The Shortcuts app's "Run Shell
  Script" only loads `~/.zshenv`, so without an override it inherits
  whatever `path_helper` produced.
- The recommended shell-rc invocation is now `pathset -q -d` (was
  `pathset -q`). Deduplication is appropriate for the PATH-setting use
  case and avoids accidental duplicates when composing with `$PATH`.
  Updated in README, examples/config.example, `-h` help text, and the
  regenerated man page.

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
