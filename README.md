# pathset

A tiny C utility that turns a human-readable list of directories into a
`:`-joined string suitable for `PATH`, `MANPATH`, `INFOPATH`, or zsh's
`fpath`. Keep each one in its own config file instead of letting fragments
pile up across rc files.

## Why

On macOS, `/etc/profile` (and its zsh equivalent `/etc/zprofile`) runs
`/usr/libexec/path_helper` **before** `~/.zshenv` and `~/.zprofile`.
`path_helper` reads `/etc/paths` and `/etc/paths.d/*` and **rewrites
`PATH` from scratch** — putting Apple's system entries first and any
tooling you care about (Homebrew, Cargo, language version managers)
after them. Half the entries it pins in front are also empty or
near-empty (e.g. several `/var/run/.../codex.system/...` dirs and
`/Library/Apple/usr/bin`).

It's worse for non-shell contexts. The macOS Shortcuts app's "Run Shell
Script" action only loads `~/.zshenv` (no profile, no rc) — and since
`path_helper` already ran via the system profile, the `PATH` Shortcuts
sees is whatever `path_helper` produced unless you overwrite it in
`~/.zshenv`.

`pathset` fixes both: declare the order you want once in
`~/.config/pathset/path`, set `PATH="$(pathset -q -d)"` in `~/.zshenv`,
and that's the order you actually get — in shells *and* in Shortcuts.
Empty / non-existent dirs are dropped so the final value stays clean.

The same machinery works for the other shell path-like variables — point
`pathset` at `~/.config/pathset/man`, `info`, or `fpath` with `-k KIND`
to manage `MANPATH`, `INFOPATH`, or zsh's `fpath` the same way.

## Quickstart

```sh
# 1. Build and install
make && sudo make install

# 2. Write a config — copy the example and edit
mkdir -p ~/.config/pathset
cp examples/path.example ~/.config/pathset/path
$EDITOR ~/.config/pathset/path

# 3. Add to ~/.zshrc (or ~/.bashrc / ~/.profile)
export PATH="$(pathset -q -d)"
```

That's it. New shells will pick up the managed PATH. Edit
`~/.config/pathset/path` whenever you want to add or remove an entry;
the next shell startup applies the change.

To also manage `MANPATH`, `INFOPATH`, or zsh `fpath`, drop config files
at `~/.config/pathset/man`, `~/.config/pathset/info`, or
`~/.config/pathset/fpath` and select the kind with `-k`:

```sh
export MANPATH="$(pathset -k man -q -d)"
export INFOPATH="$(pathset -k info -q -d)"
fpath=( ${(s.:.)$(pathset -k fpath -q -d)} $fpath )   # zsh array
```

## Installation

### Homebrew

A Homebrew formula is in [`Formula/pathset.rb`](Formula/pathset.rb). Once
published to a tap (instructions inside the formula):

```sh
brew install grazij/pathset/pathset
```

### From source

Build and install (defaults to `/usr/local/bin`):

```sh
make
sudo make install
```

Custom prefix:

```sh
make install PREFIX="$HOME/.local"
```

Uninstall (mirrors the prefix you installed with):

```sh
sudo make uninstall
# or, for a custom prefix:
make uninstall PREFIX="$HOME/.local"
```

By default `make` produces a native single-arch binary. Pass
`make universal` (or `make release-universal` for an optimized build) to
produce a macOS fat binary containing both `arm64` and `x86_64` slices —
useful when packaging a prebuilt release artifact. Verify with:

```sh
lipo -info pathset
```

## Migrating from earlier pathset versions

Before multi-kind support, the canonical config filename was
`~/.config/pathset/config`. The new layout uses one file per kind under
`~/.config/pathset/`. Existing users should rename their config:

```sh
mv ~/.config/pathset/config ~/.config/pathset/path
# also: mv ~/.pathset/config ~/.pathset/path  (if you use the legacy location)
```

The bare-file fallback (`~/.pathset` with no extension) is no longer
recognized — move it to `~/.config/pathset/path` if you were using it.

## Migrating from your current PATH

If you already have a `PATH` you're happy with and just want to take it
under management, seed your config from the live value:

```sh
mkdir -p ~/.config/pathset
echo "$PATH" | tr ':' '\n' > ~/.config/pathset/path
```

Then open `~/.config/pathset/path` in your editor and clean it up:

1. **Add comments** with `#` to group related entries (e.g. `# homebrew`,
   `# language toolchains`, `# system`). Future-you will thank you.
2. **Replace hardcoded home paths** like `/Users/me/...` with `~/...` or
   `$HOME/...` so the config is portable across machines.
3. **Drop dead entries** — `pathset` will skip non-existent and empty
   directories with warnings, but it's cleaner to remove the noise from
   the config itself. Run `pathset -v` to see which entries are surviving.
4. **Resolve duplicates** — pass `-d` once to confirm what would be
   removed (`pathset -d -v`), then either edit the duplicates out of the
   config or leave `-d` in your shell rc.

Replace your existing `PATH=...` line in `~/.zshrc` (or wherever you set
it) with:

```sh
export PATH="$(pathset -q -d)"
```

Open a new shell and verify:

```sh
echo $PATH | tr ':' '\n'
```

Existing tools that *append* to PATH (Homebrew, rbenv, asdf, etc.) can
either be removed from your rc (if their bin dir is now in the config) or
left as-is — they'll prepend/append to the managed PATH and continue to
work.

## Configuration

`pathset` reads a plain-text file with one directory per line. Lines whose
first non-whitespace character is `#` are treated as comments. Blank lines are
ignored.

Starter configs live in [`examples/`](examples/):

- [`path.example`](examples/path.example) — copy to `~/.config/pathset/path`
- [`man.example`](examples/man.example) — copy to `~/.config/pathset/man`
- [`fpath.example`](examples/fpath.example) — copy to `~/.config/pathset/fpath`

Excerpt from `path.example`:

```
~/bin
~/.local/bin
/opt/homebrew/bin
/opt/homebrew/sbin
$HOME/.cargo/bin
/usr/local/bin
/usr/bin
/bin
```

The output for that file is a bare colon-joined string:

```
/Users/me/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/bin:/sbin:/usr/bin:/usr/sbin
```

The output is data, not a shell command — compose it into any variable
with `$(...)`.

### Optional entries

Prefix any entry with `?` to mark it as optional. Optional entries that fail
to expand (unset var, unknown user) or aren't valid directories are silently
skipped without affecting the exit code:

```
?/opt/homebrew/bin       # silently skipped on Intel macOS / Linux
?$RBENV_ROOT/bin         # silently skipped if rbenv isn't installed
?~/work/scratch/bin      # silently skipped on personal machines
/usr/local/bin           # required: warns + exit 3 if missing
/usr/bin
/bin
```

This is the right tool when one config file is shared across heterogeneous
machines (work laptop, home laptop, server). Without `?`, every shell startup
on a host that's missing one of those dirs produces a warning and exits 3 —
useful as a *signal* in CI, but noisy at login time.

Verbose mode (`-v`) still reports optional skips, prefixed with
`skipping optional '<path>': <reason>`, so they're easy to audit when you go
looking.

### Variable and tilde expansion

Path entries are expanded by `pathset` before being emitted, so the value
that ends up in `PATH` is fully resolved. Supported forms:

| Syntax | Meaning |
| --- | --- |
| `~/foo` | `$HOME/foo` |
| `~user/foo` | `<user's home>/foo` (looked up via `getpwnam(3)`) |
| `~` alone | `$HOME` |
| `$VAR/foo` | environment variable `VAR` |
| `${VAR}/foo` | braced form, useful when followed by a name char |

Example config:

```
~/bin
$HOME/.local/bin
~root/scripts
${XDG_DATA_HOME}/cargo/bin
```

**Failure handling.** If `$VAR` is unset, the user is unknown, or `$HOME` is
unset for a `~/` entry, the entry is **skipped with a warning** (suppressed
by `-q`). Failed expansions never produce a half-resolved path in the output.

**Not supported** (these limitations are intentional; document the workaround
if you hit one):

- Tilde **not at position 0** of an entry (e.g. `/opt/~/foo`) — treated
  literally. Tilde only expands at the start.
- `${VAR:-default}` and other parameter-expansion forms — only `$VAR` and
  `${VAR}` are recognized.
- Escapes (`\$`, `\~`) — there's no escape mechanism. To use a literal
  `$NAME` in a path, set an env var to the value you need and reference
  that, or put the literal path in the config.
- Numeric or special variables (`$1`, `$$`, `$?`) — only names matching
  `[A-Za-z_][A-Za-z0-9_]*` are recognized; anything else is left literal.
- Empty (set to `""`) variables expand to the empty string. The resulting
  path will usually fail the directory-exists check and get skipped.

### Kinds and config lookup order

`pathset` supports four config kinds, selected with `-k KIND`:

| `-k` value | Reads | Compose into |
| --- | --- | --- |
| `path` (default) | `~/.config/pathset/path` | `PATH` |
| `man` | `~/.config/pathset/man` | `MANPATH` |
| `info` | `~/.config/pathset/info` | `INFOPATH` |
| `fpath` | `~/.config/pathset/fpath` | zsh `fpath` array |

Invalid kind values exit `2`. The output format is the same `:`-joined
string for every kind — what changes is which file is read.

For each kind, `pathset` resolves the config path in this order — **first
match wins** (`<kind>` is the value of `-k`, default `path`):

1. `-c CONFIG` on the command line (no fallback if missing — fatal error;
   when `-c` is given, `-k` is ignored)
2. `$XDG_CONFIG_HOME/pathset/<kind>` (only if `XDG_CONFIG_HOME` is set)
3. `$HOME/.config/pathset/<kind>` (XDG default — **canonical**)
4. `$HOME/.pathset/<kind>` (legacy home location)

Steps 3-4 use `access(F_OK)` to decide which exists. If neither does, the
error message points at the canonical step-3 path.

## Usage

```
pathset [-c CONFIG] [-k KIND] [-d] [-q] [-v] [-V] [-h]
```

Pass `-k KIND` to select which config to read — one of `path` (default),
`man`, `info`, `fpath`. Pass `-V` to print the version and exit.

Directories that don't exist or are empty are skipped, with a warning printed
to stderr. Pass `-q` to suppress those warnings.

Pass `-d` to drop duplicate entries — the first occurrence wins, later
duplicates are removed. Useful when composing PATH from multiple sources or
when migrating a `$PATH` that has accreted repeats over the years.

Pass `-v` to print each kept entry (and dropped duplicate, if `-d` is also
given) on stderr. Useful for debugging why your shell PATH is what it is.
`-q` overrides `-v` if both are given.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Every config entry was emitted. |
| `1` | Fatal error — missing config, I/O error, out of memory. |
| `2` | Bad command-line argument. |
| `3` | One or more entries were skipped during expansion or filtering. The output is still emitted; the non-zero code lets scripts and CI detect rot in the config. |

Note: dropping duplicates with `-d` is not a skip — exit code stays `0`.

Drop into your shell rc (e.g. `~/.zshrc`):

```sh
export PATH="$(pathset -q -d)"
```

Or compose with the existing PATH:

```sh
export PATH="$(pathset -q -d):$PATH"
```

Or pin to a specific config:

```sh
export PATH="$(pathset -c "$HOME/dotfiles/path" -q -d)"
```

### Fish shell

`pathset` emits a colon-joined string, but fish wants `PATH` as a list. Split
on `:` in your `~/.config/fish/config.fish`:

```fish
set -gx PATH (pathset -q -d | string split :)
```

Or to compose with the existing fish path:

```fish
set -gx PATH (pathset -q -d | string split :) $PATH
```

### MANPATH, INFOPATH, fpath

The same machinery manages other shell path-like variables. Drop a config
file at `~/.config/pathset/<kind>` and select the kind with `-k`:

```sh
# zsh / bash
export MANPATH="$(pathset -k man -q -d)"
export INFOPATH="$(pathset -k info -q -d)"

# zsh — fpath is an array, so split the colon-joined output back into elements
fpath=( ${(s.:.)$(pathset -k fpath -q -d)} $fpath )
```

```fish
set -gx MANPATH (pathset -k man -q -d | string split :)
set -gx INFOPATH (pathset -k info -q -d | string split :)
```

The output format and exit-code semantics are identical for every kind —
only the file that's read changes.

## Development

```sh
make build             # compile (native arch)
make lint              # syntax-only check
make test              # run smoke tests in tests/run.sh
make clean             # remove build artifacts
make release           # -O3 build (native arch)
make universal         # macOS fat binary (arm64 + x86_64)
make release-universal # -O3 macOS fat binary
make install           # install to $(PREFIX)/bin (default /usr/local)
make uninstall         # remove the installed binary and man page
```

The implementation is a single C99 source file (`pathset.c`) with no
dependencies beyond libc.

## Changes

See [CHANGELOG.md](CHANGELOG.md) for release notes.

## Limitations

- Comments are full-line only. Inline `# ...` is not stripped (paths may
  legitimately contain `#`).
- Path entries containing literal `"` are not escaped.
- `pathset` does not deduplicate entries by default; pass `-d` to dedup.
- Directories that don't exist or are empty are silently dropped (with a
  stderr warning unless `-q` is given). Permission errors on a path are
  treated the same way.

## License

MIT — see [`LICENSE.md`](LICENSE.md).
