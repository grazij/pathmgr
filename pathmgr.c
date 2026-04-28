#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <pwd.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *PROG = "pathmgr";

#ifndef PATHMGR_VERSION
#define PATHMGR_VERSION "unknown"
#endif

static void die(int code, const char *fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	fprintf(stderr, "%s: ", PROG);
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	va_end(ap);
	exit(code);
}

static void usage(FILE *out) {
	fprintf(out,
		"Usage: %s [-c CONFIG] [-d] [-q] [-v] [-V] [-h]\n"
		"\n"
		"Reads a list of directories from a config file and prints a ':'-joined\n"
		"path string to stdout. Compose into any variable with $(...):\n"
		"  export PATH=\"$(%s -q)\"\n"
		"  export PATH=\"$(%s -q):$PATH\"      # prepend\n"
		"\n"
		"Options:\n"
		"  -c CONFIG  read config from CONFIG (overrides default lookup)\n"
		"  -d         drop duplicate entries (first occurrence wins)\n"
		"  -q         suppress skip warnings on stderr\n"
		"  -v         print kept entries and expansions on stderr (-q wins)\n"
		"  -V         print version and exit\n"
		"  -h         show this help and exit\n"
		"\n"
		"Config file syntax:\n"
		"  - one directory per line, in priority order\n"
		"  - lines whose first non-whitespace character is '#' are comments\n"
		"    (full-line only; '#' mid-path is data, not a comment)\n"
		"  - blank lines are ignored; CRLF line endings are tolerated\n"
		"  - entries that don't exist or are empty directories are skipped\n"
		"  - prefix an entry with '?' to mark it optional (silent skip,\n"
		"    no exit-code effect): e.g. `?/opt/homebrew/bin`\n"
		"\n"
		"Expansion (applied per entry, before the directory check):\n"
		"  ~/foo        $HOME/foo            (only at start of entry)\n"
		"  ~user/foo    that user's home + /foo (via getpwnam)\n"
		"  $VAR/foo     $VAR/foo             (no expansion if unset -> skip)\n"
		"  ${VAR}/foo   braced form, useful next to a name char\n"
		"  Not supported: mid-string '~', ${VAR:-default}, '\\$' escapes.\n"
		"\n"
		"Config lookup (first match wins):\n"
		"  1. -c CONFIG (no fallback if missing — fatal error)\n"
		"  2. $XDG_CONFIG_HOME/pathmgr/config (only if XDG_CONFIG_HOME is set)\n"
		"  3. $HOME/.config/pathmgr/config    (XDG default — canonical)\n"
		"  4. $HOME/.pathmgr/config           (legacy home location)\n"
		"  5. $HOME/.pathmgr                  (single-file fallback)\n"
		"\n"
		"Shell setup (add to your shell rc):\n"
		"  zsh / bash:  export PATH=\"$(%s -q)\"\n"
		"  fish:        set -gx PATH (%s -q | string split :)\n"
		"\n"
		"Exit codes:\n"
		"  0  every config entry was emitted\n"
		"  1  fatal error (missing config, I/O error, out of memory)\n"
		"  2  bad command-line argument\n"
		"  3  one or more entries were skipped (expand or filter failure;\n"
		"     '?optional' skips and dedup drops do NOT contribute)\n",
		PROG, PROG, PROG, PROG, PROG);
}

static char *xstrdup(const char *s) {
	size_t n = strlen(s) + 1;
	char *p = malloc(n);
	if (!p) die(1, "out of memory");
	memcpy(p, s, n);
	return p;
}

static char *join2(const char *a, const char *b) {
	size_t la = strlen(a), lb = strlen(b);
	char *p = malloc(la + lb + 1);
	if (!p) die(1, "out of memory");
	memcpy(p, a, la);
	memcpy(p + la, b, lb + 1);
	return p;
}

/*
 * Lookup order (first match wins):
 *   1. -c CONFIG                          (no fallback if missing)
 *   2. $XDG_CONFIG_HOME/pathmgr/config    (only if XDG_CONFIG_HOME is set)
 *   3. $HOME/.config/pathmgr/config       (XDG spec default — canonical)
 *   4. $HOME/.pathmgr/config              (legacy home location)
 *   5. $HOME/.pathmgr                     (single-file fallback)
 *
 * Steps 3-5 use access(F_OK) to decide which exists. If none do, step 3's
 * canonical path is returned so the "cannot open" error names the location
 * the README recommends.
 */
static char *resolve_config_path(const char *override) {
	if (override) return xstrdup(override);

	const char *xdg = getenv("XDG_CONFIG_HOME");
	if (xdg && *xdg) return join2(xdg, "/pathmgr/config");

	const char *home = getenv("HOME");
	if (home && *home) {
		char *xdg_default = join2(home, "/.config/pathmgr/config");
		if (access(xdg_default, F_OK) == 0) return xdg_default;
		char *legacy_dir = join2(home, "/.pathmgr/config");
		if (access(legacy_dir, F_OK) == 0) {
			free(xdg_default);
			return legacy_dir;
		}
		char *single = join2(home, "/.pathmgr");
		if (access(single, F_OK) == 0) {
			free(xdg_default);
			free(legacy_dir);
			return single;
		}
		free(legacy_dir);
		free(single);
		return xdg_default;
	}

	die(1, "no -c given and neither XDG_CONFIG_HOME nor HOME is set");
	return NULL;
}

static void trim(char **start, size_t *len) {
	char *s = *start;
	size_t n = *len;
	while (n > 0 && isspace((unsigned char)s[0])) { s++; n--; }
	while (n > 0 && isspace((unsigned char)s[n - 1])) n--;
	*start = s;
	*len = n;
}

/*
 * One config entry. `optional` is set when the line was prefixed with `?` —
 * such entries are silently skipped on expand/filter failure (no warning,
 * no exit-code-3 contribution). Useful for configs shared across machines
 * where some paths are expected to be absent.
 */
typedef struct {
	char *path;
	int optional;
} Entry;

typedef struct {
	Entry *items;
	size_t n;
	size_t cap;
} Vec;

static void vec_push(Vec *v, char *s, int optional) {
	if (v->n == v->cap) {
		size_t nc = v->cap ? v->cap * 2 : 16;
		Entry *np = realloc(v->items, nc * sizeof(Entry));
		if (!np) die(1, "out of memory");
		v->items = np;
		v->cap = nc;
	}
	v->items[v->n].path = s;
	v->items[v->n].optional = optional;
	v->n++;
}

/*
 * Returns 1 if `dir` is a directory containing at least one entry other than
 * "." and "..", 0 if it's an existing-but-empty directory, and -1 on any
 * stat/open failure (with errno set). Used to filter out non-existent and
 * empty directories from the emitted PATH.
 */
static int dir_has_entries(const char *dir) {
	struct stat st;
	if (stat(dir, &st) != 0) return -1;
	if (!S_ISDIR(st.st_mode)) {
		errno = ENOTDIR;
		return -1;
	}
	DIR *d = opendir(dir);
	if (!d) return -1;
	int found = 0;
	struct dirent *e;
	errno = 0;
	while ((e = readdir(d)) != NULL) {
		if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
		found = 1;
		break;
	}
	int read_err = errno;
	closedir(d);
	if (!found && read_err != 0) {
		errno = read_err;
		return -1;
	}
	return found;
}

static void read_paths(const char *path, Vec *out) {
	FILE *f = fopen(path, "r");
	if (!f) die(1, "cannot open '%s': %s", path, strerror(errno));

	char *line = NULL;
	size_t cap = 0;
	ssize_t got;
	while ((got = getline(&line, &cap, f)) != -1) {
		char *s = line;
		size_t n = (size_t)got;
		trim(&s, &n);
		if (n == 0 || s[0] == '#') continue;

		/* Leading `?` marks the entry as optional. Strip it; whitespace
		 * between `?` and the path is allowed. */
		int optional = 0;
		if (s[0] == '?') {
			optional = 1;
			s++; n--;
			while (n > 0 && isspace((unsigned char)s[0])) { s++; n--; }
			if (n == 0) continue;  /* "?" with no path is ignored */
		}

		char *entry = malloc(n + 1);
		if (!entry) die(1, "out of memory");
		memcpy(entry, s, n);
		entry[n] = '\0';
		vec_push(out, entry, optional);
	}
	free(line);
	if (ferror(f)) die(1, "read error on '%s': %s", path, strerror(errno));
	if (fclose(f) != 0) die(1, "close error on '%s': %s", path, strerror(errno));
}

static void print_path(const Vec *v) {
	for (size_t i = 0; i < v->n; i++) {
		if (i) fputc(':', stdout);
		fputs(v->items[i].path, stdout);
	}
	fputc('\n', stdout);
}

/*
 * Growing byte buffer. Owns its allocation; caller takes the buffer with
 * `b->buf` (transfers ownership) or frees it.
 */
typedef struct {
	char *buf;
	size_t n;
	size_t cap;
} Buf;

static void buf_append(Buf *b, const char *s, size_t len) {
	if (b->n + len + 1 > b->cap) {
		size_t nc = b->cap ? b->cap : 64;
		while (nc < b->n + len + 1) nc *= 2;
		char *np = realloc(b->buf, nc);
		if (!np) die(1, "out of memory");
		b->buf = np;
		b->cap = nc;
	}
	memcpy(b->buf + b->n, s, len);
	b->n += len;
	b->buf[b->n] = '\0';
}

/* Looks up a user's home directory via getpwnam(3). Returns malloc'd home
 * dir on success, NULL on failure (unknown user or no home set). */
static char *lookup_user_home(const char *user) {
	errno = 0;
	struct passwd *pw = getpwnam(user);
	if (!pw || !pw->pw_dir || !*pw->pw_dir) return NULL;
	return xstrdup(pw->pw_dir);
}

/*
 * Expands one config entry. Supports:
 *   - leading `~/...` using $HOME
 *   - leading `~user/...` via dscl/getent
 *   - `$VAR` and `${VAR}` anywhere in the entry
 *
 * Returns malloc'd expanded string on success. On failure returns NULL and
 * writes a short reason to *err (caller must use immediately — backing
 * storage is static and overwritten by subsequent calls).
 *
 * Not supported (intentional, documented in README):
 *   - tilde NOT at position 0 (treated literally)
 *   - `${VAR:-default}` and other parameter expansion forms
 *   - escapes (`\$`, `\~`)
 *   - numeric/special vars (`$1`, `$$`)
 */
static char *expand_entry(const char *in, const char **err) {
	static char errbuf[320];
	Buf b = {0};
	const char *p = in;

	if (*p == '~') {
		const char *u = p + 1;
		const char *slash = strchr(u, '/');
		size_t ulen = slash ? (size_t)(slash - u) : strlen(u);
		char *home = NULL;
		if (ulen == 0) {
			const char *h = getenv("HOME");
			if (!h || !*h) { *err = "HOME is not set"; goto fail; }
			home = xstrdup(h);
		} else {
			if (ulen >= 128) { *err = "username too long"; goto fail; }
			char user[128];
			memcpy(user, u, ulen);
			user[ulen] = '\0';
			home = lookup_user_home(user);
			if (!home) {
				snprintf(errbuf, sizeof errbuf, "unknown user '%s'", user);
				*err = errbuf;
				goto fail;
			}
		}
		buf_append(&b, home, strlen(home));
		free(home);
		p = slash ? slash : u + ulen;
	}

	while (*p) {
		if (*p != '$') {
			buf_append(&b, p, 1);
			p++;
			continue;
		}
		const char *name_start;
		size_t name_len;
		const char *after;
		if (p[1] == '{') {
			name_start = p + 2;
			const char *close = strchr(name_start, '}');
			if (!close) { buf_append(&b, p, 1); p++; continue; }
			name_len = (size_t)(close - name_start);
			after = close + 1;
		} else if (isalpha((unsigned char)p[1]) || p[1] == '_') {
			name_start = p + 1;
			const char *e = name_start;
			while (*e && (isalnum((unsigned char)*e) || *e == '_')) e++;
			name_len = (size_t)(e - name_start);
			after = e;
		} else {
			buf_append(&b, p, 1);
			p++;
			continue;
		}
		if (name_len == 0 || name_len >= 256) {
			*err = "invalid variable name";
			goto fail;
		}
		char name[256];
		memcpy(name, name_start, name_len);
		name[name_len] = '\0';
		const char *val = getenv(name);
		if (!val) {
			snprintf(errbuf, sizeof errbuf, "$%s is not set", name);
			*err = errbuf;
			goto fail;
		}
		buf_append(&b, val, strlen(val));
		p = after;
	}

	if (!b.buf) return xstrdup("");
	return b.buf;

fail:
	free(b.buf);
	return NULL;
}

static void expand_paths(Vec *v, int quiet, int verbose, int *skipped) {
	size_t kept = 0;
	for (size_t i = 0; i < v->n; i++) {
		Entry e = v->items[i];
		const char *err = NULL;
		char *exp = expand_entry(e.path, &err);
		if (!exp) {
			if (e.optional) {
				if (verbose) {
					fprintf(stderr, "%s: skipping optional '%s': %s\n", PROG, e.path, err);
				}
			} else {
				if (!quiet) {
					fprintf(stderr, "%s: skipping '%s': %s\n", PROG, e.path, err);
				}
				(*skipped)++;
			}
			free(e.path);
			continue;
		}
		if (verbose && strcmp(e.path, exp) != 0) {
			fprintf(stderr, "%s: expanded '%s' -> '%s'\n", PROG, e.path, exp);
		}
		free(e.path);
		v->items[kept].path = exp;
		v->items[kept].optional = e.optional;
		kept++;
	}
	v->n = kept;
}

/*
 * In-place dedup: keep the first occurrence of each entry, drop later ones.
 * O(n^2) scan is fine — config files are tiny (typically <50 entries) and
 * avoiding a hash table keeps the dependency surface at libc.
 */
static void dedup_paths(Vec *v, int verbose) {
	size_t kept = 0;
	for (size_t i = 0; i < v->n; i++) {
		Entry e = v->items[i];
		int dup = 0;
		for (size_t j = 0; j < kept; j++) {
			if (strcmp(v->items[j].path, e.path) == 0) { dup = 1; break; }
		}
		if (dup) {
			if (verbose) fprintf(stderr, "%s: dropping duplicate '%s'\n", PROG, e.path);
			free(e.path);
		} else {
			v->items[kept++] = e;
		}
	}
	v->n = kept;
}

static void filter_paths(Vec *v, int quiet, int verbose, int *skipped) {
	size_t kept = 0;
	for (size_t i = 0; i < v->n; i++) {
		Entry e = v->items[i];
		int rc = dir_has_entries(e.path);
		if (rc == 1) {
			if (verbose) fprintf(stderr, "%s: keeping '%s'\n", PROG, e.path);
			v->items[kept++] = e;
			continue;
		}
		const char *reason = (rc == 0) ? "directory is empty" : strerror(errno);
		if (e.optional) {
			if (verbose) {
				fprintf(stderr, "%s: skipping optional '%s': %s\n", PROG, e.path, reason);
			}
			/* Optional skips do not warn (unless verbose) and do not affect exit code. */
		} else {
			if (!quiet) {
				fprintf(stderr, "%s: skipping '%s': %s\n", PROG, e.path, reason);
			}
			(*skipped)++;
		}
		free(e.path);
	}
	v->n = kept;
}

int main(int argc, char **argv) {
	const char *cfg_override = NULL;
	int quiet = 0;
	int dedup = 0;
	int verbose = 0;

	/* Suppress getopt's auto-error so we control the exit code (must be 2)
	 * and the message format. */
	opterr = 0;
	int opt;
	while ((opt = getopt(argc, argv, ":c:dqvVh")) != -1) {
		switch (opt) {
		case 'c': cfg_override = optarg; break;
		case 'd': dedup = 1; break;
		case 'q': quiet = 1; break;
		case 'v': verbose = 1; break;
		case 'V': printf("%s %s\n", PROG, PATHMGR_VERSION); return 0;
		case 'h': usage(stdout); return 0;
		case ':':
			usage(stderr);
			die(2, "-%c requires an argument", optopt);
		case '?':
		default:
			usage(stderr);
			die(2, "unknown argument: -%c", optopt);
		}
	}
	if (optind < argc) {
		usage(stderr);
		die(2, "unexpected argument: %s", argv[optind]);
	}

	/* -q wins if both are given: silence everything on stderr. */
	if (quiet) verbose = 0;

	char *cfg = resolve_config_path(cfg_override);
	Vec v = {0};
	int skipped = 0;
	read_paths(cfg, &v);
	expand_paths(&v, quiet, verbose, &skipped);
	filter_paths(&v, quiet, verbose, &skipped);
	if (dedup) dedup_paths(&v, verbose);
	print_path(&v);

	for (size_t i = 0; i < v.n; i++) free(v.items[i].path);
	free(v.items);
	free(cfg);
	return skipped > 0 ? 3 : 0;
}
