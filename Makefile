BINARY = pathmgr
VERSION ?= 0.1.0
PREFIX ?= /usr/local
CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -Wpedantic -std=c99
CFLAGS += -DPATHMGR_VERSION=\"$(VERSION)\"
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
	ARCH_FLAGS = -arch arm64 -arch x86_64
	CFLAGS += -mmacosx-version-min=11.0
else
	ARCH_FLAGS =
endif

.PHONY: all build test clean install run lint release man

all: build

build: $(BINARY)

$(BINARY): pathmgr.c
	$(CC) $(CFLAGS) $(ARCH_FLAGS) -o $@ $<

release: CFLAGS += -O3 -DNDEBUG
release: clean build

test: build
	./tests/run.sh

clean:
	rm -f $(BINARY)

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 0755 $(BINARY) $(DESTDIR)$(PREFIX)/bin/$(BINARY)
	@if [ -f $(BINARY).1 ]; then \
		install -d $(DESTDIR)$(PREFIX)/share/man/man1; \
		install -m 0644 $(BINARY).1 $(DESTDIR)$(PREFIX)/share/man/man1/$(BINARY).1; \
	fi

# Regenerate the man page from the binary's --help / --version output.
# Requires `help2man` (brew install help2man / apt install help2man).
# Run before tagging a release; the generated page is committed so users
# without help2man can still `make install`.
man: build
	help2man --help-option=-h --version-option=-V --no-info \
		--name="manage your shell PATH from a config file" \
		./$(BINARY) -o $(BINARY).1

run: build
	-./$(BINARY) -c examples/config.example

lint:
	$(CC) $(CFLAGS) -fsyntax-only pathmgr.c
