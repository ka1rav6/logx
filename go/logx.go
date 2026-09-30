/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

// Package logx is a single-file logger with no dependencies outside the
// standard library.
//
//	logx.Info("listening on port %d", 8080)
//	logx.Warn("memory at %.1f%%", 74.2)
//	logx.Error("connection lost")
//
// Messages are formatted with fmt.Sprintf when arguments are supplied, and
// passed through untouched when they are not, so Info("100% done") is safe.
//
// Environment:
//
//	LOG_LEVEL   TRACE | INFO | WARN | ERROR | FATAL | OFF   (or 0..5)
//	LOG_COLOR   1/true/yes/on forces, 0/false/no/off disables, unset = auto
//	NO_COLOR    set to anything to disable color (https://no-color.org)
//	LOG_FILE    path to append to instead of writing to the terminal
//	LOG_STREAM  split (default) | stdout | stderr
package logx

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"
)

// Level is a logging threshold. Higher values are more severe.
type Level int

// Logging levels, in increasing severity. Off silences everything.
const (
	TRACE Level = 0
	INFO  Level = 1
	WARN  Level = 2
	ERROR Level = 3
	FATAL Level = 4
	OFF   Level = 5
)

func (l Level) String() string {
	switch l {
	case TRACE:
		return "TRACE"
	case INFO:
		return "INFO"
	case WARN:
		return "WARN"
	case ERROR:
		return "ERROR"
	case FATAL:
		return "FATAL"
	case OFF:
		return "OFF"
	}
	return "UNKNOWN"
}

// Padded to a fixed width so columns line up in the output.
var names = [...]string{"TRACE", "INFO ", "WARN ", "ERROR", "FATAL"}
var colors = [...]string{"\033[36m", "\033[32m", "\033[33m", "\033[31m", "\033[35m"}

const reset = "\033[0m"

type sinkMode int

const (
	sinkSplit sinkMode = iota
	sinkStdout
	sinkStderr
)

var (
	mu       sync.Mutex
	minLevel Level
	useColor bool
	sink     sinkMode
	logFile  *os.File
)

func init() {
	minLevel = ParseLevel(os.Getenv("LOG_LEVEL"), TRACE)

	switch strings.ToLower(strings.TrimSpace(os.Getenv("LOG_STREAM"))) {
	case "stdout":
		sink = sinkStdout
	case "stderr":
		sink = sinkStderr
	default:
		sink = sinkSplit
	}

	if forced, ok := parseBool(os.Getenv("LOG_COLOR")); ok {
		useColor = forced
	} else if os.Getenv("NO_COLOR") != "" {
		useColor = false
	} else {
		switch sink {
		case sinkStdout:
			useColor = isTerminal(os.Stdout)
		case sinkStderr:
			useColor = isTerminal(os.Stderr)
		default:
			useColor = isTerminal(os.Stdout) && isTerminal(os.Stderr)
		}
	}

	if path := os.Getenv("LOG_FILE"); path != "" {
		// An unwritable LOG_FILE should not stop the program from starting;
		// logging simply stays on the terminal.
		_ = SetLogFile(path)
	}
}

// ParseLevel turns a level name into a Level, returning fallback for anything
// it does not recognise. Names are case-insensitive and 0..5 also work.
func ParseLevel(s string, fallback Level) Level {
	switch strings.ToUpper(strings.TrimSpace(s)) {
	case "TRACE", "DEBUG", "ALL", "0":
		return TRACE
	case "INFO", "1":
		return INFO
	case "WARN", "WARNING", "2":
		return WARN
	case "ERROR", "ERR", "3":
		return ERROR
	case "FATAL", "CRITICAL", "4":
		return FATAL
	case "OFF", "NONE", "SILENT", "5":
		return OFF
	}
	return fallback
}

func parseBool(s string) (value bool, ok bool) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "1", "true", "yes", "on":
		return true, true
	case "0", "false", "no", "off":
		return false, true
	}
	return false, false
}

func isTerminal(f *os.File) bool {
	fi, err := f.Stat()
	if err != nil {
		return false
	}
	return fi.Mode()&os.ModeCharDevice != 0
}

// SetLevel raises or lowers the threshold at runtime.
func SetLevel(level Level) {
	mu.Lock()
	defer mu.Unlock()
	minLevel = level
}

// GetLevel reports the current threshold.
func GetLevel() Level {
	mu.Lock()
	defer mu.Unlock()
	return minLevel
}

// SetColor turns ANSI coloring on or off, overriding the auto-detection.
func SetColor(enabled bool) {
	mu.Lock()
	defer mu.Unlock()
	useColor = enabled
}

// SetLogFile appends log output to path. Pass "" to go back to the terminal.
func SetLogFile(path string) error {
	var f *os.File
	if path != "" {
		opened, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
		if err != nil {
			return err
		}
		f = opened
	}

	mu.Lock()
	old := logFile
	logFile = f
	mu.Unlock()

	if old != nil {
		return old.Close()
	}
	return nil
}

// Enabled reports whether a message at level would be emitted. Use it to skip
// building an expensive message.
func Enabled(level Level) bool {
	mu.Lock()
	defer mu.Unlock()
	return minLevel < OFF && level >= minLevel
}

func timestamp() string {
	now := time.Now()
	return fmt.Sprintf("%02d:%02d:%02d.%03d",
		now.Hour(), now.Minute(), now.Second(), now.Nanosecond()/int(time.Millisecond))
}

// Log writes one record. skip is how many stack frames to climb to find the
// caller to report: 0 means Log's own caller. Use it when wrapping these
// functions in a helper of your own.
func Log(level Level, skip int, msg string, args ...any) {
	if !Enabled(level) {
		if level == FATAL {
			os.Exit(1)
		}
		return
	}

	if len(args) > 0 {
		msg = fmt.Sprintf(msg, args...)
	}

	file, line := "<unknown>", 0
	if _, f, l, ok := runtime.Caller(skip + 1); ok {
		file, line = filepath.Base(f), l
	}

	text := fmt.Sprintf("[%s][%s] %s:%d -> %s", timestamp(), names[level], file, line, msg)

	mu.Lock()
	if logFile != nil {
		fmt.Fprintln(logFile, text)
	} else {
		var out io.Writer
		switch {
		case sink == sinkStdout:
			out = os.Stdout
		case sink == sinkStderr:
			out = os.Stderr
		case level >= ERROR:
			out = os.Stderr
		default:
			out = os.Stdout
		}
		if useColor {
			fmt.Fprintf(out, "%s%s%s\n", colors[level], text, reset)
		} else {
			fmt.Fprintln(out, text)
		}
	}
	mu.Unlock()

	if level == FATAL {
		os.Exit(1)
	}
}

// Trace logs at TRACE.
func Trace(msg string, args ...any) { Log(TRACE, 1, msg, args...) }

// Info logs at INFO.
func Info(msg string, args ...any) { Log(INFO, 1, msg, args...) }

// Warn logs at WARN.
func Warn(msg string, args ...any) { Log(WARN, 1, msg, args...) }

// Error logs at ERROR.
func Error(msg string, args ...any) { Log(ERROR, 1, msg, args...) }

// Fatal logs at FATAL, then exits with status 1.
func Fatal(msg string, args ...any) { Log(FATAL, 1, msg, args...) }
