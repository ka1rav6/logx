# LogX test runner.
#
#   make test        run every language whose toolchain is installed
#   make test-c      run one language (test-c, test-cpp, test-python, test-js,
#                    test-ts, test-go, test-rust, test-java, test-zig, test-asm)
#   make check-all   build the C and C++ headers in every supported mode
#   make clean       remove build output
#
# A language whose compiler is missing is reported as skipped, not as a failure,
# so this is usable without installing all ten toolchains.

BUILD := build

CC      ?= cc
CXX     ?= c++
PYTHON  ?= python3
NODE    ?= node
NPX     ?= npx
GO      ?= go
CARGO   ?= cargo
JAVAC   ?= javac
JAVA    ?= java
ZIG     ?= zig
NASM    ?= nasm
LD      ?= ld

CFLAGS   ?= -std=c99 -Wall -Wextra -pedantic
CXXFLAGS ?= -std=c++11 -Wall -Wextra -pedantic

LANGUAGES := c cpp python js ts go rust java zig asm

.PHONY: test $(addprefix test-,$(LANGUAGES)) check-all clean help

help:
	@echo "make test        run every language whose toolchain is installed"
	@echo "make test-LANG   run one of: $(LANGUAGES)"
	@echo "make check-all   build the C and C++ headers in every supported mode"
	@echo "make clean       remove build output"

# Runs each language in turn and reports a summary at the end rather than
# stopping at the first failure.
test:
	@fail=""; skip=""; pass=""; \
	for lang in $(LANGUAGES); do \
	  printf '\n=== %s ===\n' "$$lang"; \
	  out=$$($(MAKE) --no-print-directory test-$$lang 2>&1); \
	  status=$$?; \
	  echo "$$out"; \
	  case "$$out" in \
	    *"SKIP:"*) skip="$$skip $$lang" ;; \
	    *) if [ $$status -eq 0 ]; then pass="$$pass $$lang"; else fail="$$fail $$lang"; fi ;; \
	  esac; \
	done; \
	printf '\n======================================\n'; \
	printf 'passed: %s\n' "$${pass:- none}"; \
	[ -n "$$skip" ] && printf 'skipped (no toolchain):%s\n' "$$skip"; \
	if [ -n "$$fail" ]; then printf 'FAILED:%s\n' "$$fail"; exit 1; fi; \
	printf 'all available languages passed\n'

$(BUILD):
	@mkdir -p $(BUILD)

test-c: | $(BUILD)
	@command -v $(CC) >/dev/null 2>&1 || { echo "SKIP: $(CC) not found"; exit 0; }
	$(CC) $(CFLAGS) -I c test/c/test_logx.c -o $(BUILD)/test_logx_c
	@$(BUILD)/test_logx_c

test-cpp: | $(BUILD)
	@command -v $(CXX) >/dev/null 2>&1 || { echo "SKIP: $(CXX) not found"; exit 0; }
	$(CXX) $(CXXFLAGS) -I cpp test/cpp/test_logx.cpp -o $(BUILD)/test_logx_cpp
	@$(BUILD)/test_logx_cpp

test-python:
	@command -v $(PYTHON) >/dev/null 2>&1 || { echo "SKIP: $(PYTHON) not found"; exit 0; }
	@$(PYTHON) test/python/test_logx.py

test-js:
	@command -v $(NODE) >/dev/null 2>&1 || { echo "SKIP: $(NODE) not found"; exit 0; }
	@$(NODE) test/js/test.js

test-ts:
	@command -v $(NPX) >/dev/null 2>&1 || { echo "SKIP: $(NPX) not found"; exit 0; }
	@$(NPX) --yes tsx test/ts/test.mts

test-go:
	@command -v $(GO) >/dev/null 2>&1 || { echo "SKIP: $(GO) not found"; exit 0; }
	@cd go && $(GO) vet ./... && $(GO) test ./...

test-rust:
	@command -v $(CARGO) >/dev/null 2>&1 || { echo "SKIP: $(CARGO) not found"; exit 0; }
	@$(CARGO) test --manifest-path rust/Cargo.toml

test-java: | $(BUILD)
	@command -v $(JAVAC) >/dev/null 2>&1 || { echo "SKIP: $(JAVAC) not found"; exit 0; }
	$(JAVAC) -Xlint:all -d $(BUILD)/java java/Logx.java test/java/TestLogx.java
	@$(JAVA) -cp $(BUILD)/java TestLogx

# logx.zig targets Zig 0.14-0.16; a 0.17 compiler stops at the version guard
# in the file rather than miscompiling, so report that as a skip.
test-zig:
	@command -v $(ZIG) >/dev/null 2>&1 || { echo "SKIP: $(ZIG) not found"; exit 0; }
	@$(ZIG) fmt --check zig/logx.zig zig/test_logx.zig
	@if $(ZIG) test zig/test_logx.zig 2>&1 | grep -q "targets Zig 0.14-0.16"; then \
	  echo "SKIP: this Zig has the reworked std.Io API (0.17+); logx.zig targets 0.14-0.16"; \
	else \
	  $(ZIG) test zig/test_logx.zig; \
	fi

test-asm:
	@command -v $(NASM) >/dev/null 2>&1 || { echo "SKIP: nasm not found"; exit 0; }
	@command -v $(LD) >/dev/null 2>&1 || { echo "SKIP: ld not found"; exit 0; }
	@case "$$(uname -s)-$$(uname -m)" in \
	  Linux-x86_64) sh test/asm/check.sh ;; \
	  *) echo "SKIP: logx.asm is x86-64 Linux only" ;; \
	esac

# The C and C++ headers have several build modes each; this makes sure none of
# them has rotted. Warnings are errors here on purpose.
check-all: | $(BUILD)
	@set -e; \
	printf '#include "logx.h"\nvoid other(void);\nint main(void){LOGX_INFO("x %%d",1);other();return 0;}\n' > $(BUILD)/a.c; \
	printf '#include "logx.h"\nvoid other(void){LOGX_WARN("y");}\n' > $(BUILD)/b.c; \
	printf '#define LOGX_IMPLEMENTATION\n#include "logx.h"\n' > $(BUILD)/impl.c; \
	printf '#include "logx.h"\nvoid other();\nint main(){LOGX_INFO<<"x";LOGX_WARNF("y %%d",1);other();}\n' > $(BUILD)/a.cpp; \
	printf '#include "logx.h"\nvoid other(){LOGX_WARN<<"y";}\n' > $(BUILD)/b.cpp; \
	for std in c99 c11 c17; do \
	  echo "C  $$std"; \
	  $(CC) -std=$$std -Wall -Wextra -pedantic -Werror -I c $(BUILD)/a.c $(BUILD)/b.c -o $(BUILD)/m; \
	done; \
	echo "C  LOGX_SHARED"; \
	$(CC) $(CFLAGS) -Werror -DLOGX_SHARED -I c $(BUILD)/a.c $(BUILD)/b.c $(BUILD)/impl.c -o $(BUILD)/m; \
	echo "C  LOGX_NO_THREADS"; \
	$(CC) $(CFLAGS) -Werror -DLOGX_NO_THREADS -I c $(BUILD)/a.c $(BUILD)/b.c -o $(BUILD)/m; \
	echo "C  LOGX_COMPILE_LEVEL=LX_WARN"; \
	$(CC) $(CFLAGS) -Werror -DLOGX_COMPILE_LEVEL=LX_WARN -I c $(BUILD)/a.c $(BUILD)/b.c -o $(BUILD)/m; \
	echo "C  compiled as C++"; \
	$(CXX) -std=c++17 -Wall -Wextra -Werror -x c++ -I c $(BUILD)/a.c $(BUILD)/b.c -o $(BUILD)/m; \
	for std in c++11 c++14 c++17 c++20; do \
	  echo "C++ $$std"; \
	  $(CXX) -std=$$std -Wall -Wextra -pedantic -Werror -I cpp $(BUILD)/a.cpp $(BUILD)/b.cpp -o $(BUILD)/mx; \
	done; \
	echo "C++ LOGX_COMPILE_LEVEL"; \
	$(CXX) $(CXXFLAGS) -Werror "-DLOGX_COMPILE_LEVEL=::logx::Level::Warn" -I cpp $(BUILD)/a.cpp $(BUILD)/b.cpp -o $(BUILD)/mx; \
	echo "all header build modes OK"

clean:
	rm -rf $(BUILD)
	rm -rf rust/target
	rm -rf .zig-cache zig-out
	rm -f ts/*.tsbuildinfo
