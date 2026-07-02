package logx

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

func captureOutput(fn func()) (string, string) {
	stdoutR, stdoutW, _ := os.Pipe()
	stderrR, stderrW, _ := os.Pipe()
	oldStdout := os.Stdout
	oldStderr := os.Stderr
	os.Stdout = stdoutW
	os.Stderr = stderrW

	fn()

	stdoutW.Close()
	stderrW.Close()
	os.Stdout = oldStdout
	os.Stderr = oldStderr

	var stdoutBuf, stderrBuf bytes.Buffer
	stdoutBuf.ReadFrom(stdoutR)
	stderrBuf.ReadFrom(stderrR)
	return stdoutBuf.String(), stderrBuf.String()
}

func TestBasicOutput(t *testing.T) {
	stdout, stderr := captureOutput(func() {
		Trace("trace msg")
		Info("info msg")
		Warn("warn msg")
		Error("error msg")
	})

	if !strings.Contains(stdout, "TRACE") || !strings.Contains(stdout, "trace msg") {
		t.Error("TRACE not found in stdout")
	}
	if !strings.Contains(stdout, "INFO ") || !strings.Contains(stdout, "info msg") {
		t.Error("INFO not found in stdout")
	}
	if !strings.Contains(stdout, "WARN ") || !strings.Contains(stdout, "warn msg") {
		t.Error("WARN not found in stdout")
	}
	if !strings.Contains(stderr, "ERROR") || !strings.Contains(stderr, "error msg") {
		t.Error("ERROR not found in stderr")
	}
}

func TestFileLogging(t *testing.T) {
	f, _ := os.CreateTemp("", "logx_test_*.log")
	path := f.Name()
	f.Close()
	defer os.Remove(path)

	SetLogFile(path)
	Info("file test")
	SetLogFile("")

	data, _ := os.ReadFile(path)
	content := string(data)
	if !strings.Contains(content, "file test") {
		t.Error("file log missing message")
	}
	if !strings.Contains(content, "INFO ") {
		t.Error("file log missing level")
	}
}

func TestLevelFiltering(t *testing.T) {
	saved := minLevel
	minLevel = ERROR
	defer func() { minLevel = saved }()

	stdout, stderr := captureOutput(func() {
		Trace("should not appear")
		Info("should not appear")
		Warn("should not appear")
		Error("should appear")
	})

	if stdout != "" {
		t.Error("expected no stdout output with minLevel=ERROR")
	}
	if !strings.Contains(stderr, "should appear") {
		t.Error("ERROR message should appear in stderr")
	}
}
