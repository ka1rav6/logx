/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

package buggedd

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

type Level int

const (
	TRACE Level = 0
	INFO  Level = 1
	WARN  Level = 2
	ERROR Level = 3
	FATAL Level = 4
)

var names = [...]string{"TRACE", "INFO ", "WARN ", "ERROR", "FATAL"}
var colors = [...]string{"\033[36m", "\033[32m", "\033[33m", "\033[31m", "\033[35m"}
const reset = "\033[0m"

var (
	mu       sync.Mutex
	minLevel Level
	useColor bool
	logFile  *os.File
	once     sync.Once
)

func init() {
	once.Do(func() {
		switch strings.ToUpper(os.Getenv("LOG_LEVEL")) {
		case "TRACE":
			minLevel = TRACE
		case "INFO":
			minLevel = INFO
		case "WARN":
			minLevel = WARN
		case "ERROR":
			minLevel = ERROR
		case "FATAL":
			minLevel = FATAL
		default:
			minLevel = TRACE
		}

		col := os.Getenv("LOG_COLOR")
		if col != "" {
			useColor = col == "1" || col == "yes"
		} else {
			useColor = isTerminal(os.Stdout) && isTerminal(os.Stderr)
		}
	})
}

func isTerminal(f *os.File) bool {
	fi, err := f.Stat()
	if err != nil {
		return false
	}
	return (fi.Mode() & os.ModeCharDevice) != 0
}

func SetLogFile(path string) error {
	mu.Lock()
	defer mu.Unlock()
	if logFile != nil {
		logFile.Close()
	}
	if path == "" {
		logFile = nil
		return nil
	}
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	logFile = f
	return nil
}

func timestamp() string {
	now := time.Now()
	return fmt.Sprintf("%s.%03d", now.Format("15:04:05"), now.Nanosecond()/1e6)
}

func log(level Level, msg string, skip int) {
	if level < minLevel {
		return
	}

	_, file, line, ok := runtime.Caller(skip)
	if !ok {
		file = "<unknown>"
		line = 0
	}
	file = filepath.Base(file)

	ts := timestamp()
	label := fmt.Sprintf("[%s][%s] %s:%d -> %s", ts, names[level], file, line, msg)

	mu.Lock()
	defer mu.Unlock()

	if logFile != nil {
		fmt.Fprintln(logFile, label)
	} else {
		out := os.Stdout
		if level >= ERROR {
			out = os.Stderr
		}
		if useColor {
			fmt.Fprintf(out, "%s%s%s\n", colors[level], label, reset)
		} else {
			fmt.Fprintln(out, label)
		}
	}

	if level == FATAL {
		os.Exit(1)
	}
}

func Trace(msg string) { log(TRACE, msg, 2) }
func Info(msg string)  { log(INFO, msg, 2) }
func Warn(msg string)  { log(WARN, msg, 2) }
func Error(msg string) { log(ERROR, msg, 2) }
func Fatal(msg string) { log(FATAL, msg, 2) }
