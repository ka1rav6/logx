package logx

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// [HH:MM:SS.mmm][LEVEL] file:line -> message
var record = regexp.MustCompile(`^\[\d{2}:\d{2}:\d{2}\.\d{3}\]\[(\w+ ?)\] ([^/\\:]+):(\d+) -> (.*)$`)

// capture runs fn with output going to a temp file and returns the lines.
func capture(t *testing.T, fn func()) []string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "logx.log")
	if err := SetLogFile(path); err != nil {
		t.Fatalf("SetLogFile: %v", err)
	}
	fn()
	if err := SetLogFile(""); err != nil {
		t.Fatalf("SetLogFile(\"\"): %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	return strings.Split(strings.TrimRight(string(data), "\n"), "\n")
}

func TestFormatAndArgs(t *testing.T) {
	lines := capture(t, func() {
		Trace("trace msg")
		Info("port %d", 8080)
		Warn("memory at %.1f%%", 74.2)
		Error("lost: %s", "ECONNRESET")
		Info("literal 100% done")
	})

	if len(lines) != 5 {
		t.Fatalf("got %d lines, want 5: %q", len(lines), lines)
	}

	want := []struct {
		level string
		msg   string
	}{
		{"TRACE", "trace msg"},
		{"INFO ", "port 8080"},
		{"WARN ", "memory at 74.2%"},
		{"ERROR", "lost: ECONNRESET"},
		{"INFO ", "literal 100% done"},
	}

	for i, line := range lines {
		m := record.FindStringSubmatch(line)
		if m == nil {
			t.Errorf("line %d does not match the documented format: %q", i, line)
			continue
		}
		if m[1] != want[i].level {
			t.Errorf("line %d level = %q, want %q", i, m[1], want[i].level)
		}
		if m[4] != want[i].msg {
			t.Errorf("line %d message = %q, want %q", i, m[4], want[i].msg)
		}
		if m[2] != "logx_test.go" {
			t.Errorf("line %d file = %q, want logx_test.go", i, m[2])
		}
	}

	if strings.Contains(lines[0], "\033[") {
		t.Error("color escapes leaked into a file")
	}
}

// Log's skip parameter should let a wrapper report its own caller.
func TestSkipReportsTheWrappersCaller(t *testing.T) {
	helper := func(msg string) { Log(INFO, 1, msg) }

	lines := capture(t, func() { helper("wrapped") })

	m := record.FindStringSubmatch(lines[0])
	if m == nil {
		t.Fatalf("unparsed: %q", lines[0])
	}
	if m[2] != "logx_test.go" {
		t.Errorf("file = %q, want logx_test.go", m[2])
	}
}

func TestLevelFilter(t *testing.T) {
	defer SetLevel(TRACE)

	lines := capture(t, func() {
		SetLevel(WARN)
		Trace("hidden")
		Info("hidden")
		Warn("shown")
		Error("shown")
		SetLevel(OFF)
		Error("silenced by OFF")
		SetLevel(TRACE)
	})

	if len(lines) != 2 {
		t.Errorf("got %d lines, want 2: %q", len(lines), lines)
	}
	if GetLevel() != TRACE {
		t.Errorf("GetLevel() = %v, want TRACE", GetLevel())
	}
}

func TestEnabled(t *testing.T) {
	defer SetLevel(TRACE)

	SetLevel(WARN)
	if Enabled(INFO) {
		t.Error("Enabled(INFO) should be false at WARN")
	}
	if !Enabled(ERROR) {
		t.Error("Enabled(ERROR) should be true at WARN")
	}

	SetLevel(OFF)
	if Enabled(FATAL) {
		t.Error("Enabled should be false for every level at OFF")
	}
}

func TestParseLevel(t *testing.T) {
	cases := map[string]Level{
		"trace": TRACE, "TRACE": TRACE, "debug": TRACE, "0": TRACE,
		"info": INFO, "warning": WARN, "2": WARN,
		"err": ERROR, "3": ERROR,
		"fatal": FATAL, "off": OFF, "silent": OFF, "5": OFF,
		"  warn  ": WARN,
	}
	for input, want := range cases {
		if got := ParseLevel(input, TRACE); got != want {
			t.Errorf("ParseLevel(%q) = %v, want %v", input, got, want)
		}
	}
	if got := ParseLevel("junk", INFO); got != INFO {
		t.Errorf("ParseLevel(%q) = %v, want the fallback INFO", "junk", got)
	}
}

func TestSetLogFileRejectsABadPath(t *testing.T) {
	if err := SetLogFile("/nonexistent-dir-xyz/app.log"); err == nil {
		t.Error("SetLogFile should report an unwritable path")
	}
}

func TestLevelString(t *testing.T) {
	if TRACE.String() != "TRACE" || WARN.String() != "WARN" || OFF.String() != "OFF" {
		t.Error("Level.String is wrong")
	}
}
