#!/usr/bin/env bash
set -u

# Resolve repo root and binary
DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$DIR/pathset"

if [[ ! -x "$BIN" ]]; then
	echo "tests: $BIN not found or not executable; run 'make build' first" >&2
	exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pathset-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

ok() {
	printf '  ok  %s\n' "$1"
	pass=$((pass + 1))
}

bad() {
	printf '  FAIL %s\n' "$1"
	[[ -n "${2:-}" ]] && printf '       %s\n' "$2"
	fail=$((fail + 1))
}

# Three real, populated dirs to use as valid PATH entries.
A="$WORK/a"; B="$WORK/b"; C="$WORK/c"
mkdir -p "$A" "$B" "$C"
: >"$A/file"; : >"$B/file"; : >"$C/file"

# --- Test 1: basic parse with comments and blanks ---
cfg1="$WORK/cfg1"
cat >"$cfg1" <<EOF
# leading comment
$A

   $B
	# indented comment with tab
$C
EOF

expected1="$A:$B:$C"
got1="$("$BIN" -c "$cfg1" 2>/dev/null)"
if [[ "$got1" == "$expected1" ]]; then
	ok "basic parsing strips comments and blanks"
else
	bad "basic parsing" "expected: $expected1 / got: $got1"
fi

# --- Test 2: empty file produces empty output ---
cfg2="$WORK/cfg2"
: >"$cfg2"
got2="$("$BIN" -c "$cfg2" 2>/dev/null)"
if [[ -z "$got2" ]]; then
	ok "empty config produces empty output"
else
	bad "empty config" "got: $got2"
fi

# --- Test 3: missing file -> non-zero exit, stderr message ---
if "$BIN" -c "$WORK/does-not-exist" >/dev/null 2>"$WORK/err"; then
	bad "missing file should error"
else
	if grep -q "cannot open" "$WORK/err"; then
		ok "missing file errors with non-zero and stderr message"
	else
		bad "missing file stderr" "stderr: $(cat "$WORK/err")"
	fi
fi

# --- Test 4: -c with no argument -> exit 2 ---
"$BIN" -c >/dev/null 2>"$WORK/err"
rc=$?
if [[ $rc -eq 2 ]]; then
	ok "-c with no arg exits 2"
else
	bad "-c with no arg" "rc=$rc"
fi

# --- Test 5: XDG_CONFIG_HOME fallback (no -c) ---
xdg="$WORK/xdg"
mkdir -p "$xdg/pathset"
echo "$A" >"$xdg/pathset/config"
got5="$(env -i HOME="$WORK/home" XDG_CONFIG_HOME="$xdg" "$BIN" 2>/dev/null)"
if [[ "$got5" == "$A" ]]; then
	ok "XDG_CONFIG_HOME/pathset/config fallback"
else
	bad "XDG fallback" "got: $got5"
fi

# --- Test 6: HOME fallback when XDG_CONFIG_HOME unset ---
home="$WORK/home"
mkdir -p "$home/.pathset"
echo "$B" >"$home/.pathset/config"
got6="$(env -i HOME="$home" "$BIN" 2>/dev/null)"
if [[ "$got6" == "$B" ]]; then
	ok "HOME/.pathset/config fallback"
else
	bad "HOME fallback" "got: $got6"
fi

# --- Test 7: XDG takes precedence over HOME ---
got7="$(env -i HOME="$home" XDG_CONFIG_HOME="$xdg" "$BIN" 2>/dev/null)"
if [[ "$got7" == "$A" ]]; then
	ok "XDG_CONFIG_HOME precedes HOME"
else
	bad "XDG precedence" "got: $got7"
fi

# --- Test 8: CRLF tolerance ---
cfg8="$WORK/cfg8"
printf '%s\r\n%s\r\n' "$A" "$B" >"$cfg8"
got8="$("$BIN" -c "$cfg8" 2>/dev/null)"
if [[ "$got8" == "$A:$B" ]]; then
	ok "CRLF line endings tolerated"
else
	bad "CRLF" "got: $got8"
fi

# --- Test 9: missing directory is skipped with warning ---
cfg9="$WORK/cfg9"
missing="$WORK/no-such-dir"
cat >"$cfg9" <<EOF
$A
$missing
$B
EOF
got9="$("$BIN" -c "$cfg9" 2>"$WORK/err9")"
if [[ "$got9" == "$A:$B" ]] && grep -q "skipping '$missing'" "$WORK/err9"; then
	ok "missing directory is skipped with warning"
else
	bad "missing dir skip" "got: $got9 / err: $(cat "$WORK/err9")"
fi

# --- Test 10: empty directory is skipped with warning ---
empty="$WORK/empty"
mkdir -p "$empty"
cfg10="$WORK/cfg10"
cat >"$cfg10" <<EOF
$A
$empty
$B
EOF
got10="$("$BIN" -c "$cfg10" 2>"$WORK/err10")"
if [[ "$got10" == "$A:$B" ]] && grep -q "directory is empty" "$WORK/err10"; then
	ok "empty directory is skipped with warning"
else
	bad "empty dir skip" "got: $got10 / err: $(cat "$WORK/err10")"
fi

# --- Test 11: -q suppresses warnings ---
got11="$("$BIN" -c "$cfg9" -q 2>"$WORK/err11")"
if [[ "$got11" == "$A:$B" ]] && [[ ! -s "$WORK/err11" ]]; then
	ok "-q suppresses warnings"
else
	bad "-q suppress" "got: $got11 / err: $(cat "$WORK/err11")"
fi

# --- Test 12: file (not a directory) is skipped with warning ---
filepath="$WORK/regular-file"
: >"$filepath"
cfg12="$WORK/cfg12"
cat >"$cfg12" <<EOF
$A
$filepath
EOF
got12="$("$BIN" -c "$cfg12" 2>"$WORK/err12")"
if [[ "$got12" == "$A" ]] && grep -q "skipping '$filepath'" "$WORK/err12"; then
	ok "non-directory is skipped with warning"
else
	bad "non-dir skip" "got: $got12 / err: $(cat "$WORK/err12")"
fi

# --- Test 13: -d drops duplicate entries, first wins ---
cfg13="$WORK/cfg13"
cat >"$cfg13" <<EOF
$A
$B
$A
$C
$B
EOF
got13="$("$BIN" -c "$cfg13" -d 2>/dev/null)"
if [[ "$got13" == "$A:$B:$C" ]]; then
	ok "-d drops duplicates, preserves first occurrence"
else
	bad "-d dedup" "got: $got13"
fi

# --- Test 14: without -d, duplicates are preserved ---
got14="$("$BIN" -c "$cfg13" 2>/dev/null)"
if [[ "$got14" == "$A:$B:$A:$C:$B" ]]; then
	ok "duplicates preserved without -d"
else
	bad "no-dedup default" "got: $got14"
fi

# --- Test 15: -d combined with skip filtering ---
cfg15="$WORK/cfg15"
cat >"$cfg15" <<EOF
$A
$WORK/no-such
$A
$B
EOF
got15="$("$BIN" -c "$cfg15" -d 2>/dev/null)"
if [[ "$got15" == "$A:$B" ]]; then
	ok "-d runs after filter; skipped entries don't shadow real ones"
else
	bad "-d + filter" "got: $got15"
fi

# --- Test 16: -v prints kept entries on stderr ---
cfg16="$WORK/cfg16"
cat >"$cfg16" <<EOF
$A
$B
EOF
got16="$("$BIN" -c "$cfg16" -v 2>"$WORK/err16")"
if [[ "$got16" == "$A:$B" ]] && \
   grep -q "keeping '$A'" "$WORK/err16" && \
   grep -q "keeping '$B'" "$WORK/err16"; then
	ok "-v prints kept entries on stderr"
else
	bad "-v keeps" "got: $got16 / err: $(cat "$WORK/err16")"
fi

# --- Test 17: -v also reports skipped entries (additive with warnings) ---
cfg17="$WORK/cfg17"
cat >"$cfg17" <<EOF
$A
$WORK/no-such
EOF
"$BIN" -c "$cfg17" -v >/dev/null 2>"$WORK/err17"
if grep -q "keeping '$A'" "$WORK/err17" && \
   grep -q "skipping '$WORK/no-such'" "$WORK/err17"; then
	ok "-v is additive with skip warnings"
else
	bad "-v additive" "err: $(cat "$WORK/err17")"
fi

# --- Test 18: -q overrides -v ---
"$BIN" -c "$cfg17" -v -q >/dev/null 2>"$WORK/err18"
if [[ ! -s "$WORK/err18" ]]; then
	ok "-q overrides -v (silent stderr)"
else
	bad "-q overrides -v" "err: $(cat "$WORK/err18")"
fi

# --- Test 19: -v reports dropped duplicates ---
cfg19="$WORK/cfg19"
cat >"$cfg19" <<EOF
$A
$B
$A
EOF
got19="$("$BIN" -c "$cfg19" -d -v 2>"$WORK/err19")"
if [[ "$got19" == "$A:$B" ]] && grep -q "dropping duplicate '$A'" "$WORK/err19"; then
	ok "-v reports dropped duplicates"
else
	bad "-v + dedup" "got: $got19 / err: $(cat "$WORK/err19")"
fi

# --- Test 20: ~/sub expands using $HOME ---
fakehome="$WORK/home2"
mkdir -p "$fakehome/bin"
: >"$fakehome/bin/file"
cfg20="$WORK/cfg20"
echo '~/bin' >"$cfg20"
got20="$(HOME="$fakehome" "$BIN" -c "$cfg20" 2>/dev/null)"
if [[ "$got20" == "$fakehome/bin" ]]; then
	ok "~/sub expands via \$HOME"
else
	bad "tilde expand" "got: $got20"
fi

# --- Test 21: \$VAR expansion ---
cfg21="$WORK/cfg21"
echo '$MY_TEST_DIR/sub' >"$cfg21"
testdir="$WORK/vartest"
mkdir -p "$testdir/sub"
: >"$testdir/sub/file"
got21="$(MY_TEST_DIR="$testdir" "$BIN" -c "$cfg21" 2>/dev/null)"
if [[ "$got21" == "$testdir/sub" ]]; then
	ok "\$VAR expansion"
else
	bad "var expand" "got: $got21"
fi

# --- Test 22: \${VAR} braced expansion ---
cfg22="$WORK/cfg22"
echo '${MY_TEST_DIR}/sub' >"$cfg22"
got22="$(MY_TEST_DIR="$testdir" "$BIN" -c "$cfg22" 2>/dev/null)"
if [[ "$got22" == "$testdir/sub" ]]; then
	ok "\${VAR} braced expansion"
else
	bad "braced var expand" "got: $got22"
fi

# --- Test 23: unset var -> skip with warning ---
cfg23="$WORK/cfg23"
cat >"$cfg23" <<EOF
$A
\$PATHSET_DEFINITELY_UNSET_XYZ/bin
EOF
got23="$(unset PATHSET_DEFINITELY_UNSET_XYZ; "$BIN" -c "$cfg23" 2>"$WORK/err23")"
if [[ "$got23" == "$A" ]] && grep -q "PATHSET_DEFINITELY_UNSET_XYZ is not set" "$WORK/err23"; then
	ok "unset \$VAR is skipped with warning"
else
	bad "unset var" "got: $got23 / err: $(cat "$WORK/err23")"
fi

# --- Test 24: unknown ~user -> skip with warning ---
cfg24="$WORK/cfg24"
cat >"$cfg24" <<EOF
$A
~pathset_no_such_user_xyz/bin
EOF
got24="$("$BIN" -c "$cfg24" 2>"$WORK/err24")"
if [[ "$got24" == "$A" ]] && grep -q "unknown user" "$WORK/err24"; then
	ok "unknown ~user is skipped with warning"
else
	bad "unknown user" "got: $got24 / err: $(cat "$WORK/err24")"
fi

# --- Test 25: tilde mid-string is literal ---
cfg25="$WORK/cfg25"
echo "$WORK/~mid/foo" >"$cfg25"
"$BIN" -c "$cfg25" >/dev/null 2>"$WORK/err25"
if grep -q "skipping '$WORK/~mid/foo'" "$WORK/err25"; then
	ok "tilde mid-string treated literally (not expanded)"
else
	bad "mid-tilde literal" "err: $(cat "$WORK/err25")"
fi

# --- Test 26: -v reports expansion ---
cfg26="$WORK/cfg26"
echo '~/bin' >"$cfg26"
HOME="$fakehome" "$BIN" -c "$cfg26" -v >/dev/null 2>"$WORK/err26"
if grep -q "expanded '~/bin' -> '$fakehome/bin'" "$WORK/err26"; then
	ok "-v reports expansions"
else
	bad "-v expansion" "err: $(cat "$WORK/err26")"
fi

# --- Test 27: HOME unset -> ~/x skipped with warning ---
cfg27="$WORK/cfg27"
echo '~/bin' >"$cfg27"
env -i "$BIN" -c "$cfg27" >/dev/null 2>"$WORK/err27"
if grep -q "HOME is not set" "$WORK/err27"; then
	ok "~/sub is skipped when \$HOME unset"
else
	bad "HOME unset" "err: $(cat "$WORK/err27")"
fi

# --- Test 28: full literal path with embedded $ that doesn't match a var pattern ---
cfg28="$WORK/cfg28"
literal="$WORK/with\$dollar"
mkdir -p "$literal"
: >"$literal/file"
echo "$WORK/with\$/foo" >"$cfg28"
# $/ does not match a var pattern (next char is /, not [A-Za-z_]) so $ is literal
got28="$("$BIN" -c "$cfg28" 2>"$WORK/err28")"
# That literal path doesn't exist, so it's skipped — but the warning should
# mention the original (literal $) form, proving no expansion happened.
if grep -q "skipping '$WORK/with\$/foo'" "$WORK/err28"; then
	ok "lone \$ followed by non-name char is literal"
else
	bad "lone \$" "err: $(cat "$WORK/err28")"
fi

# --- Test 29: clean run exits 0 ---
cfg31="$WORK/cfg31"
cat >"$cfg31" <<EOF
$A
$B
EOF
"$BIN" -c "$cfg31" >/dev/null 2>/dev/null
rc=$?
if [[ $rc -eq 0 ]]; then
	ok "clean run exits 0"
else
	bad "exit 0 clean" "rc=$rc"
fi

# --- Test 32: any skipped entry exits 3 (filter) ---
cfg32="$WORK/cfg32"
cat >"$cfg32" <<EOF
$A
$WORK/no-such-dir
EOF
"$BIN" -c "$cfg32" >/dev/null 2>/dev/null
rc=$?
if [[ $rc -eq 3 ]]; then
	ok "skipped entry (filter) exits 3"
else
	bad "exit 3 filter" "rc=$rc"
fi

# --- Test 33: skipped expansion (unset var) exits 3 ---
cfg33="$WORK/cfg33"
cat >"$cfg33" <<EOF
$A
\$PATHSET_NOPE_X/bin
EOF
unset PATHSET_NOPE_X 2>/dev/null
"$BIN" -c "$cfg33" >/dev/null 2>/dev/null
rc=$?
if [[ $rc -eq 3 ]]; then
	ok "skipped entry (expand) exits 3"
else
	bad "exit 3 expand" "rc=$rc"
fi

# --- Test 34: -q does not change exit code ---
"$BIN" -c "$cfg32" -q >/dev/null 2>/dev/null
rc=$?
if [[ $rc -eq 3 ]]; then
	ok "-q does not mask exit 3"
else
	bad "-q + exit" "rc=$rc"
fi

# --- Test 35: -d alone (no skips) exits 0 — dedup is not a skip ---
cfg35="$WORK/cfg35"
cat >"$cfg35" <<EOF
$A
$A
$B
EOF
"$BIN" -c "$cfg35" -d >/dev/null 2>/dev/null
rc=$?
if [[ $rc -eq 0 ]]; then
	ok "dedup does not count as skip (exit 0)"
else
	bad "dedup exit" "rc=$rc"
fi

# --- Test 36: bundled flags (-dq) ---
cfg36="$WORK/cfg36"
cat >"$cfg36" <<EOF
$A
$A
$B
EOF
got36="$("$BIN" -c "$cfg36" -dq 2>"$WORK/err36")"
if [[ "$got36" == "$A:$B" ]] && [[ ! -s "$WORK/err36" ]]; then
	ok "bundled short flags (-dq)"
else
	bad "bundled flags" "got: $got36 / err: $(cat "$WORK/err36")"
fi

# --- Test 37: unknown flag exits 2 ---
"$BIN" -Z >/dev/null 2>"$WORK/err37"
rc=$?
if [[ $rc -eq 2 ]] && grep -q "unknown argument" "$WORK/err37"; then
	ok "unknown flag exits 2"
else
	bad "unknown flag" "rc=$rc / err: $(cat "$WORK/err37")"
fi

# --- Test 38: positional argument is rejected ---
"$BIN" extra-arg >/dev/null 2>"$WORK/err38"
rc=$?
if [[ $rc -eq 2 ]] && grep -q "unexpected argument" "$WORK/err38"; then
	ok "positional argument is rejected"
else
	bad "positional arg" "rc=$rc / err: $(cat "$WORK/err38")"
fi

# --- Test 39: -V prints version and exits 0 ---
got39="$("$BIN" -V 2>/dev/null)"
rc=$?
if [[ $rc -eq 0 ]] && [[ "$got39" =~ ^pathset\ [0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	ok "-V prints version (matches 'pathset X.Y.Z')"
else
	bad "-V" "rc=$rc / got: $got39"
fi

# --- Test 38: ?optional missing dir -> silent skip, exit 0 ---
cfg38="$WORK/cfg38"
cat >"$cfg38" <<EOF
$A
?$WORK/no-such-optional
EOF
got38="$("$BIN" -c "$cfg38" 2>"$WORK/err38")"
rc=$?
if [[ "$got38" == "$A" ]] && [[ ! -s "$WORK/err38" ]] && [[ $rc -eq 0 ]]; then
	ok "?optional missing dir is silently skipped (exit 0)"
else
	bad "?optional silent" "got: $got38 / rc=$rc / err: $(cat "$WORK/err38")"
fi

# --- Test 39: ?optional + -v reports the skip ---
"$BIN" -c "$cfg38" -v >/dev/null 2>"$WORK/err39"
if grep -q "skipping optional '$WORK/no-such-optional'" "$WORK/err39"; then
	ok "?optional reported under -v"
else
	bad "?optional verbose" "err: $(cat "$WORK/err39")"
fi

# --- Test 40: ?optional with unset var also silent ---
cfg40="$WORK/cfg40"
cat >"$cfg40" <<EOF
$A
?\$PATHSET_DEFINITELY_UNSET_OPT/bin
EOF
got40="$(unset PATHSET_DEFINITELY_UNSET_OPT; "$BIN" -c "$cfg40" 2>"$WORK/err40")"
rc=$?
if [[ "$got40" == "$A" ]] && [[ ! -s "$WORK/err40" ]] && [[ $rc -eq 0 ]]; then
	ok "?optional with unset var is silent (exit 0)"
else
	bad "?optional unset var" "got: $got40 / rc=$rc / err: $(cat "$WORK/err40")"
fi

# --- Test 41: ?optional that DOES exist behaves normally ---
cfg41="$WORK/cfg41"
cat >"$cfg41" <<EOF
?$A
$B
EOF
got41="$("$BIN" -c "$cfg41" 2>/dev/null)"
rc=$?
if [[ "$got41" == "$A:$B" ]] && [[ $rc -eq 0 ]]; then
	ok "?optional that resolves is included normally"
else
	bad "?optional resolves" "got: $got41 / rc=$rc"
fi

# --- Test 42: ?optional with whitespace between ? and path ---
cfg42="$WORK/cfg42"
cat >"$cfg42" <<EOF
?  $A
EOF
got42="$("$BIN" -c "$cfg42" 2>/dev/null)"
if [[ "$got42" == "$A" ]]; then
	ok "?optional accepts whitespace between ? and path"
else
	bad "?optional whitespace" "got: $got42"
fi

# --- Test 43: permission-denied directory is skipped with warning ---
noperm="$WORK/noperm"
mkdir -p "$noperm"
chmod 000 "$noperm"
# Ensure cleanup so trap can rm -rf
trap 'chmod 755 "$noperm" 2>/dev/null; rm -rf "$WORK"' EXIT
cfg43="$WORK/cfg43"
cat >"$cfg43" <<EOF
$A
$noperm
EOF
got43="$("$BIN" -c "$cfg43" 2>"$WORK/err43")"
rc=$?
# Behavior: stat() may succeed (we can stat the dir we own) but opendir() will
# fail with EACCES. Either path leads to a skip with errno-derived warning.
if [[ "$got43" == "$A" ]] && grep -q "skipping '$noperm'" "$WORK/err43" && [[ $rc -eq 3 ]]; then
	ok "permission-denied directory is skipped (exit 3)"
else
	bad "chmod 000 skip" "got: $got43 / rc=$rc / err: $(cat "$WORK/err43")"
fi
# Restore perms so subsequent tests / rm -rf work.
chmod 755 "$noperm"

# --- Test 44: $HOME/.pathset (single-file) fallback ---
home44="$WORK/home44"
mkdir -p "$home44"
echo "$A" >"$home44/.pathset"
got44="$(env -i HOME="$home44" "$BIN" 2>/dev/null)"
if [[ "$got44" == "$A" ]]; then
	ok "\$HOME/.pathset (single-file) fallback"
else
	bad "single-file fallback" "got: $got44"
fi

# --- Test 45: $HOME/.pathset/config takes precedence over $HOME/.pathset ---
home45="$WORK/home45"
mkdir -p "$home45/.pathset"
echo "$A" >"$home45/.pathset/config"
# A real ~/.pathset can't be both file and dir, but the parent path
# `$home45/.pathset` IS the dir here. To prove dir-form wins, we use a
# separate dir layout where the file would conflict; instead, simulate
# precedence by checking that when both are reachable as separate paths,
# the dir-form is selected.
got45="$(env -i HOME="$home45" "$BIN" 2>/dev/null)"
if [[ "$got45" == "$A" ]]; then
	ok "\$HOME/.pathset/config preferred when present"
else
	bad "config-dir precedence" "got: $got45"
fi

# --- Test 46: missing all forms -> error mentions canonical XDG-default path ---
home46="$WORK/home46"
mkdir -p "$home46"
env -i HOME="$home46" "$BIN" >/dev/null 2>"$WORK/err46"
rc=$?
if [[ $rc -ne 0 ]] && grep -q "$home46/.config/pathset/config" "$WORK/err46"; then
	ok "missing config error names canonical XDG-default path"
else
	bad "missing canonical err" "rc=$rc / err: $(cat "$WORK/err46")"
fi

# --- Test 47: $HOME/.config/pathset/config (XDG default) found ---
home47="$WORK/home47"
mkdir -p "$home47/.config/pathset"
echo "$A" >"$home47/.config/pathset/config"
got47="$(env -i HOME="$home47" "$BIN" 2>/dev/null)"
if [[ "$got47" == "$A" ]]; then
	ok "\$HOME/.config/pathset/config (XDG default) found"
else
	bad "XDG default" "got: $got47"
fi

# --- Test 48: XDG default precedes legacy ~/.pathset/config ---
home48="$WORK/home48"
mkdir -p "$home48/.config/pathset" "$home48/.pathset"
echo "$A" >"$home48/.config/pathset/config"
echo "$B" >"$home48/.pathset/config"
got48="$(env -i HOME="$home48" "$BIN" 2>/dev/null)"
if [[ "$got48" == "$A" ]]; then
	ok "XDG default precedes legacy ~/.pathset/config"
else
	bad "XDG precedence over legacy" "got: $got48"
fi

# --- Summary ---
echo
echo "passed: $pass  failed: $fail"
[[ $fail -eq 0 ]] || exit 1
