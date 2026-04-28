# pathmgr

A tiny C utility that turns a human-readable list of directories into a
`PATH` value. Keep your shell `PATH` managed in one config file instead of
accreting fragments across rc files.

## Quickstart

```sh
# 1. Build and install
make && sudo make install

# 2. Write a config — copy the example and edit
mkdir -p ~/.config/pathmgr
cp examples/config.example ~/.config/pathmgr/config
$EDITOR ~/.config/pathmgr/config

# 3. Add to ~/.zshrc (or ~/.bashrc / ~/.profile)
export PATH="$(pathmgr -q)"
```

That's it. New shells will pick up the managed PATH. Edit
`~/.config/pathmgr/config` whenever you want to add or remove an entry;
the next shell startup applies the change.

## Installation

### Homebrew

A Homebrew formula is in [`Formula/pathmgr.rb`](Formula/pathmgr.rb). Once
published to a tap (instructions inside the formula):

```sh
brew install grazij/pathmgr/pathmgr
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

On macOS, `make` produces a universal (fat) binary containing both `arm64` and
`x86_64` slices. Verify with:

```sh
lipo -info pathmgr
```

## Migrating from your current PATH

If you already have a `PATH` you're happy with and just want to take it
under management, seed your config from the live value:

```sh
mkdir -p ~/.config/pathmgr
echo "$PATH" | tr ':' '\n' > ~/.config/pathmgr/config
```

Then open `~/.config/pathmgr/config` in your editor and clean it up:

1. **Add comments** with `#` to group related entries (e.g. `# homebrew`,
   `# language toolchains`, `# system`). Future-you will thank you.
2. **Replace hardcoded home paths** like `/Users/me/...` with `~/...` or
   `$HOME/...` so the config is portable across machines.
3. **Drop dead entries** — `pathmgr` will skip non-existent and empty
   directories with warnings, but it's cleaner to remove the noise from
   the config itself. Run `pathmgr -v` to see which entries are surviving.
4. **Resolve duplicates** — pass `-d` once to confirm what would be
   removed (`pathmgr -d -v`), then either edit the duplicates out of the
   config or leave `-d` in your shell rc.

Replace your existing `PATH=...` line in `~/.zshrc` (or wherever you set
it) with:

```sh
export PATH="$(pathmgr -q)"
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

`pathmgr` reads a plain-text file with one directory per line. Lines whose
first non-whitespace character is `#` are treated as comments. Blank lines are
ignored.

A starter config is in
[`examples/config.example`](examples/config.example) — copy it to
`~/.config/pathmgr/config` and edit. Excerpt:

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

Path entries are expanded by `pathmgr` before being emitted, so the value
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

### Config lookup order

`pathmgr` resolves the config path in this order — **first match wins**:

1. `-c CONFIG` on the command line (no fallback if missing — fatal error)
2. `$XDG_CONFIG_HOME/pathmgr/config` (only if `XDG_CONFIG_HOME` is set)
3. `$HOME/.config/pathmgr/config` (XDG default — **canonical**)
4. `$HOME/.pathmgr/config` (legacy home location)
5. `$HOME/.pathmgr` (single-file fallback for users who prefer a dotfile)

Steps 3-5 use `access(F_OK)` to decide which exists. If none do, the
error message points at the canonical step-3 path.

## Usage

```
pathmgr [-c CONFIG] [-d] [-q] [-v] [-V] [-h]
```

Pass `-V` to print the version and exit.

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
export PATH="$(pathmgr -q)"
```

Or compose with the existing PATH:

```sh
export PATH="$(pathmgr -q):$PATH"
```

Or pin to a specific config:

```sh
export PATH="$(pathmgr -c "$HOME/dotfiles/path" -q)"
```

### Fish shell

`pathmgr` emits a colon-joined string, but fish wants `PATH` as a list. Split
on `:` in your `~/.config/fish/config.fish`:

```fish
set -gx PATH (pathmgr -q | string split :)
```

Or to compose with the existing fish path:

```fish
set -gx PATH (pathmgr -q | string split :) $PATH
```

## Development

```sh
make build     # compile
make lint      # syntax-only check
make test      # run smoke tests in tests/run.sh
make clean     # remove build artifacts
make release   # -O3 build
make install   # install to $(PREFIX)/bin (default /usr/local)
make uninstall # remove the installed binary and man page
```

The implementation is a single C99 source file (`pathmgr.c`) with no
dependencies beyond libc.

## Changes

See [CHANGELOG.md](CHANGELOG.md) for release notes.

## Limitations

- Comments are full-line only. Inline `# ...` is not stripped (paths may
  legitimately contain `#`).
- Path entries containing literal `"` are not escaped.
- `pathmgr` does not deduplicate entries by default; pass `-d` to dedup.
- Directories that don't exist or are empty are silently dropped (with a
  stderr warning unless `-q` is given). Permission errors on a path are
  treated the same way.

## License

MIT — see [`LICENSE.md`](LICENSE.md).
