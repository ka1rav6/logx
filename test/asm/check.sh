#!/bin/sh
# Runs test/asm/test_logx.asm and checks its output, since assembly has no
# assertion library to lean on. Invoked by `make test-asm`.
#
#   sh test/asm/check.sh

set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=${TMPDIR:-/tmp}/logx-asm-check.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

failures=0

check() {
    if [ "$1" = "0" ]; then
        echo "PASS: $2"
    else
        echo "FAIL: $2"
        failures=$((failures + 1))
    fi
}

# Asserts that `haystack` contains `needle`.
has() {
    case "$1" in
        *"$2"*) return 0 ;;
        *) return 1 ;;
    esac
}

nasm -felf64 "$ROOT/test/asm/test_logx.asm" -I "$ROOT/asm/" -o "$TMP/t.o" || exit 1
ld "$TMP/t.o" -o "$TMP/t" || exit 1

# ---- default run -----------------------------------------------------------
out=$("$TMP/t" 2>"$TMP/err")
rc=$?
err=$(cat "$TMP/err")
check "$rc" "exits 0 (no register was clobbered)"

has "$out" "registers preserved" && check 0 "every register survives a log call" \
    || check 1 "every register survives a log call"

# [HH:MM:SS.mmm][LEVEL] file:line -> message
if echo "$out" | head -1 | grep -qE '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}\]\[TRACE\] test_logx\.asm:[0-9]+ -> trace msg$'; then
    check 0 "first line matches the documented format"
else
    check 1 "first line matches the documented format (got: $(echo "$out" | head -1))"
fi

has "$out" "[INFO ] test_logx.asm:" && check 0 "INFO label is padded to 5" \
    || check 1 "INFO label is padded to 5"
has "$out" "[WARN ] test_logx.asm:" && check 0 "WARN label is padded to 5" \
    || check 1 "WARN label is padded to 5"
has "$out" "a reusable string" && check 0 "log_str labels work" \
    || check 1 "log_str labels work"
has "$out" "built at runtime" && check 0 "log_msg logs a runtime string" \
    || check 1 "log_msg logs a runtime string"

# ERROR belongs on stderr, and must not appear on stdout.
has "$err" "[ERROR]" && check 0 "ERROR goes to stderr" || check 1 "ERROR goes to stderr"
has "$out" "[ERROR]" && check 1 "ERROR stays off stdout" || check 0 "ERROR stays off stdout"

# ---- level filtering -------------------------------------------------------
filtered=$(LOG_LEVEL=WARN "$TMP/t" 2>&1)
has "$filtered" "trace msg" && check 1 "LOG_LEVEL=WARN drops TRACE" \
    || check 0 "LOG_LEVEL=WARN drops TRACE"
has "$filtered" "memory is high" && check 0 "LOG_LEVEL=WARN keeps WARN" \
    || check 1 "LOG_LEVEL=WARN keeps WARN"

lower=$(LOG_LEVEL=warn "$TMP/t" 2>&1)
has "$lower" "trace msg" && check 1 "LOG_LEVEL is case-insensitive" \
    || check 0 "LOG_LEVEL is case-insensitive"

numeric=$(LOG_LEVEL=3 "$TMP/t" 2>&1)
has "$numeric" "memory is high" && check 1 "LOG_LEVEL=3 means ERROR" \
    || check 0 "LOG_LEVEL=3 means ERROR"

silent=$(LOG_LEVEL=OFF "$TMP/t" 2>&1)
[ -z "$silent" ] && check 0 "LOG_LEVEL=OFF silences everything" \
    || check 1 "LOG_LEVEL=OFF silences everything"

# ---- color -----------------------------------------------------------------
colored=$(LOG_COLOR=1 "$TMP/t" 2>&1)
has "$colored" "$(printf '\033')" && check 0 "LOG_COLOR=1 emits ANSI escapes" \
    || check 1 "LOG_COLOR=1 emits ANSI escapes"

plain=$(LOG_COLOR=0 "$TMP/t" 2>&1)
has "$plain" "$(printf '\033')" && check 1 "LOG_COLOR=0 suppresses them" \
    || check 0 "LOG_COLOR=0 suppresses them"

# A pipe is not a terminal, so auto-detection must leave color off.
auto=$("$TMP/t" 2>&1)
has "$auto" "$(printf '\033')" && check 1 "no color when output is not a terminal" \
    || check 0 "no color when output is not a terminal"

nocolor=$(NO_COLOR=1 LOG_COLOR= "$TMP/t" 2>&1)
has "$nocolor" "$(printf '\033')" && check 1 "NO_COLOR is honored" \
    || check 0 "NO_COLOR is honored"

# ---- stream routing --------------------------------------------------------
only_err=$(LOG_STREAM=stderr "$TMP/t" 2>/dev/null)
[ -z "$only_err" ] && check 0 "LOG_STREAM=stderr leaves stdout empty" \
    || check 1 "LOG_STREAM=stderr leaves stdout empty"

only_out=$(LOG_STREAM=stdout "$TMP/t" 2>/dev/null)
has "$only_out" "[ERROR]" && check 0 "LOG_STREAM=stdout sends errors to stdout" \
    || check 1 "LOG_STREAM=stdout sends errors to stdout"

# ---- file output -----------------------------------------------------------
cat > "$TMP/f.asm" <<EOF
%define LOG_FILE_PATH "$TMP/app.log"
%include "logx.asm"
section .text
global _start
_start:
    log_init
    log_info("into the file")
    log_error("errors go to the file too")
    call log_close
    log_info("back on the terminal")
    log_exit 0
EOF
nasm -felf64 "$TMP/f.asm" -I "$ROOT/asm/" -o "$TMP/f.o" || exit 1
ld "$TMP/f.o" -o "$TMP/f" || exit 1
terminal=$(LOG_COLOR=1 "$TMP/f" 2>&1)
logged=$(cat "$TMP/app.log")

has "$logged" "into the file" && check 0 "LOG_FILE_PATH writes to the file" \
    || check 1 "LOG_FILE_PATH writes to the file"
has "$logged" "errors go to the file too" \
    && check 0 "errors go to the file rather than stderr" \
    || check 1 "errors go to the file rather than stderr"
has "$logged" "$(printf '\033')" && check 1 "no color escapes in a file" \
    || check 0 "no color escapes in a file"
has "$terminal" "back on the terminal" && check 0 "log_close returns to the terminal" \
    || check 1 "log_close returns to the terminal"

# Appending, not truncating.
"$TMP/f" >/dev/null 2>&1
lines=$(wc -l < "$TMP/app.log")
[ "$lines" -eq 4 ] && check 0 "a second run appends instead of truncating" \
    || check 1 "a second run appends (expected 4 lines, got $lines)"

# ---- fatal -----------------------------------------------------------------
cat > "$TMP/fatal.asm" <<'EOF'
%include "logx.asm"
section .text
global _start
_start:
    log_init
    log_fatal("unrecoverable")
    log_info("UNREACHABLE")
    log_exit 0
EOF
nasm -felf64 "$TMP/fatal.asm" -I "$ROOT/asm/" -o "$TMP/fatal.o" || exit 1
ld "$TMP/fatal.o" -o "$TMP/fatal" || exit 1
fatal_out=$("$TMP/fatal" 2>&1)
fatal_rc=$?
[ "$fatal_rc" -eq 1 ] && check 0 "log_fatal exits with status 1" \
    || check 1 "log_fatal exits with status 1 (got $fatal_rc)"
has "$fatal_out" "[FATAL]" && check 0 "log_fatal writes its record first" \
    || check 1 "log_fatal writes its record first"
has "$fatal_out" "UNREACHABLE" && check 1 "log_fatal stops execution" \
    || check 0 "log_fatal stops execution"

if [ "$failures" -eq 0 ]; then
    echo "all assembly tests passed"
    exit 0
fi
echo "assembly tests FAILED ($failures)"
exit 1
