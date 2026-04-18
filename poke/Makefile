# snapback-poke — tiny UDS poker for SnapBack hook scripts.
CC      ?= clang
CFLAGS  ?= -O2 -std=c11 -Wall -Wextra -Wpedantic
BUILD   := build
BIN     := $(BUILD)/snapback-poke

.PHONY: all clean install

all: $(BIN)

$(BIN): snapback-poke.c
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $< -o $@

clean:
	rm -rf $(BUILD)

install: $(BIN)
	install -m 0755 $(BIN) $(DESTDIR)/usr/local/bin/snapback-poke
