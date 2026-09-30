/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

//! logx -- single-file logger built on nothing but `std`.
//!
//! Two ways to use it, and the macros are written so both work:
//!
//! Dropped into your project as one file:
//!
//! ```ignore
//! #[macro_use]
//! mod logx;
//! use logx::*;            // brings the helpers the macros expand to into scope
//!
//! fn main() {
//!     logx_info!("listening on port {}", 8080);
//! }
//! ```
//!
//! Or as a dependency:
//!
//! ```ignore
//! use logx::*;
//!
//! logx_info!("listening on port {}", 8080);
//! ```
//!
//! The macros expand to unqualified calls on purpose. A `$crate::` path would
//! work for a dependency but break the dropped-in-module form, and `use logx::*`
//! satisfies both.
//!
//! # Environment
//!
//! | Variable     | Meaning                                                  |
//! |--------------|----------------------------------------------------------|
//! | `LOG_LEVEL`  | `TRACE`..`FATAL`, or `OFF` (also `0`..`5`)                |
//! | `LOG_COLOR`  | `1`/`true`/`yes`/`on` forces, `0`/`false`/`no`/`off` off  |
//! | `NO_COLOR`   | set to anything to disable color                         |
//! | `LOG_FILE`   | path to append to instead of the terminal                 |
//! | `LOG_STREAM` | `split` (default), `stdout`, `stderr`                     |
//!
//! Timestamps are UTC: `std` has no time-zone database. Set `LOG_TZ_OFFSET` to
//! a fixed offset (`+05:30`, `-0800`, or a number of minutes) for local time.

// Dropped in as `mod logx;`, anything the program does not call would otherwise
// be reported as dead code, and a crate built with `-D warnings` would fail.
#![allow(dead_code)]

use std::env;
use std::fs::{File, OpenOptions};
use std::io::{self, IsTerminal, Write};
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

/// A logging threshold. Higher is more severe.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum LogxLevel {
    Trace = 0,
    Info = 1,
    Warn = 2,
    Error = 3,
    Fatal = 4,
    /// Silences everything.
    Off = 5,
}

impl LogxLevel {
    fn name(self) -> &'static str {
        match self {
            LogxLevel::Trace => "TRACE",
            LogxLevel::Info => "INFO ",
            LogxLevel::Warn => "WARN ",
            LogxLevel::Error => "ERROR",
            LogxLevel::Fatal => "FATAL",
            LogxLevel::Off => "OFF  ",
        }
    }

    fn color(self) -> &'static str {
        match self {
            LogxLevel::Trace => "\x1b[36m",
            LogxLevel::Info => "\x1b[32m",
            LogxLevel::Warn => "\x1b[33m",
            LogxLevel::Error => "\x1b[31m",
            LogxLevel::Fatal => "\x1b[35m",
            LogxLevel::Off => "\x1b[0m",
        }
    }

    fn from_u8(value: u8) -> LogxLevel {
        match value {
            0 => LogxLevel::Trace,
            1 => LogxLevel::Info,
            2 => LogxLevel::Warn,
            3 => LogxLevel::Error,
            4 => LogxLevel::Fatal,
            _ => LogxLevel::Off,
        }
    }

    /// Parses a level name, case-insensitively. `0`..`5` work too.
    pub fn parse(text: &str, fallback: LogxLevel) -> LogxLevel {
        match text.trim().to_ascii_uppercase().as_str() {
            "TRACE" | "DEBUG" | "ALL" | "0" => LogxLevel::Trace,
            "INFO" | "1" => LogxLevel::Info,
            "WARN" | "WARNING" | "2" => LogxLevel::Warn,
            "ERROR" | "ERR" | "3" => LogxLevel::Error,
            "FATAL" | "CRITICAL" | "4" => LogxLevel::Fatal,
            "OFF" | "NONE" | "SILENT" | "5" => LogxLevel::Off,
            _ => fallback,
        }
    }
}

const RESET: &str = "\x1b[0m";

#[derive(Clone, Copy, PartialEq)]
enum Sink {
    Split,
    Stdout,
    Stderr,
}

struct Config {
    color: bool,
    sink: Sink,
    tz_offset_secs: i64,
}

static MIN_LEVEL: AtomicU8 = AtomicU8::new(0);
static COLOR_OVERRIDE: AtomicU8 = AtomicU8::new(2); // 0 off, 1 on, 2 follow config
static LOG_FILE: Mutex<Option<File>> = Mutex::new(None);
static TERMINAL_LOCK: Mutex<()> = Mutex::new(());
static CONFIG: OnceLock<Config> = OnceLock::new();

fn parse_bool(text: &str) -> Option<bool> {
    match text.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
}

/// Accepts `+05:30`, `-0800`, `+2`, or a bare number of minutes.
fn parse_tz_offset(text: &str) -> Option<i64> {
    let text = text.trim();
    if text.is_empty() {
        return None;
    }
    let (sign, rest) = match text.as_bytes()[0] {
        b'+' => (1i64, &text[1..]),
        b'-' => (-1i64, &text[1..]),
        _ => (1i64, text),
    };
    let digits: String = rest.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        return None;
    }
    let (hours, minutes) = if rest.contains(':') || digits.len() == 4 {
        (digits[..digits.len() - 2].parse::<i64>().ok()?, digits[digits.len() - 2..].parse::<i64>().ok()?)
    } else if digits.len() <= 2 {
        (digits.parse::<i64>().ok()?, 0)
    } else {
        // A bare minute count, e.g. LOG_TZ_OFFSET=330.
        return Some(sign * digits.parse::<i64>().ok()? * 60);
    };
    Some(sign * (hours * 3600 + minutes * 60))
}

fn config() -> &'static Config {
    CONFIG.get_or_init(|| {
        MIN_LEVEL.store(
            LogxLevel::parse(&env::var("LOG_LEVEL").unwrap_or_default(), LogxLevel::Trace) as u8,
            Ordering::Relaxed,
        );

        let sink = match env::var("LOG_STREAM").unwrap_or_default().trim().to_ascii_lowercase().as_str() {
            "stdout" => Sink::Stdout,
            "stderr" => Sink::Stderr,
            _ => Sink::Split,
        };

        let color = match env::var("LOG_COLOR").ok().and_then(|v| parse_bool(&v)) {
            Some(forced) => forced,
            None if env::var_os("NO_COLOR").is_some() => false,
            None => match sink {
                Sink::Stdout => io::stdout().is_terminal(),
                Sink::Stderr => io::stderr().is_terminal(),
                Sink::Split => io::stdout().is_terminal() && io::stderr().is_terminal(),
            },
        };

        if let Ok(path) = env::var("LOG_FILE") {
            if !path.is_empty() {
                // An unwritable LOG_FILE just leaves logging on the terminal.
                let _ = set_log_file(&path);
            }
        }

        Config {
            color,
            sink,
            tz_offset_secs: env::var("LOG_TZ_OFFSET")
                .ok()
                .and_then(|v| parse_tz_offset(&v))
                .unwrap_or(0),
        }
    })
}

/// Raises or lowers the threshold at runtime.
pub fn set_level(level: LogxLevel) {
    config();
    MIN_LEVEL.store(level as u8, Ordering::Relaxed);
}

/// The current threshold.
pub fn get_level() -> LogxLevel {
    config();
    LogxLevel::from_u8(MIN_LEVEL.load(Ordering::Relaxed))
}

/// Turns ANSI coloring on or off, overriding the auto-detection.
pub fn set_color(enabled: bool) {
    COLOR_OVERRIDE.store(if enabled { 1 } else { 0 }, Ordering::Relaxed);
}

/// Whether a message at `level` would be emitted.
pub fn enabled(level: LogxLevel) -> bool {
    config();
    let min = MIN_LEVEL.load(Ordering::Relaxed);
    min < LogxLevel::Off as u8 && (level as u8) >= min
}

/// Appends log output to `path`.
pub fn set_log_file(path: &str) -> io::Result<()> {
    let file = OpenOptions::new().create(true).append(true).open(path)?;
    let mut guard = LOG_FILE.lock().unwrap_or_else(|e| e.into_inner());
    *guard = Some(file);
    Ok(())
}

/// Sends log output back to the terminal.
pub fn clear_log_file() {
    let mut guard = LOG_FILE.lock().unwrap_or_else(|e| e.into_inner());
    *guard = None;
}

pub fn flush() {
    let mut guard = LOG_FILE.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(file) = guard.as_mut() {
        let _ = file.flush();
    } else {
        let _ = io::stdout().flush();
        let _ = io::stderr().flush();
    }
}

fn timestamp(offset_secs: i64) -> String {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    let millis = now.subsec_millis();
    let shifted = now.as_secs() as i64 + offset_secs;
    let secs_of_day = shifted.rem_euclid(86_400);
    format!(
        "{:02}:{:02}:{:02}.{:03}",
        secs_of_day / 3600,
        (secs_of_day % 3600) / 60,
        secs_of_day % 60,
        millis
    )
}

fn base_name(path: &str) -> &str {
    match path.rfind(['/', '\\']) {
        Some(index) => &path[index + 1..],
        None => path,
    }
}

/// The function the `logx_*!` macros expand to. Call it directly if you would
/// rather not use the macros.
pub fn logx_log(level: LogxLevel, message: &str, file: &str, line: u32) {
    if !enabled(level) {
        if level == LogxLevel::Fatal {
            std::process::exit(1);
        }
        return;
    }

    let cfg = config();
    let text = format!(
        "[{}][{}] {}:{} -> {}",
        timestamp(cfg.tz_offset_secs),
        level.name(),
        base_name(file),
        line,
        message
    );

    let mut guard = LOG_FILE.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(file) = guard.as_mut() {
        let _ = writeln!(file, "{}", text);
        let _ = file.flush();
    } else {
        drop(guard);
        let color = match COLOR_OVERRIDE.load(Ordering::Relaxed) {
            0 => false,
            1 => true,
            _ => cfg.color,
        };
        // One lock for both streams, so concurrent threads cannot interleave
        // a color escape from one record with the text of another.
        let _serialize = TERMINAL_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let to_stderr = match cfg.sink {
            Sink::Stdout => false,
            Sink::Stderr => true,
            Sink::Split => level >= LogxLevel::Error,
        };
        if to_stderr {
            let mut out = io::stderr().lock();
            let _ = if color {
                writeln!(out, "{}{}{}", level.color(), text, RESET)
            } else {
                writeln!(out, "{}", text)
            };
            let _ = out.flush();
        } else {
            let mut out = io::stdout().lock();
            let _ = if color {
                writeln!(out, "{}{}{}", level.color(), text, RESET)
            } else {
                writeln!(out, "{}", text)
            };
            let _ = out.flush();
        }
    }

    if level == LogxLevel::Fatal {
        std::process::exit(1);
    }
}

#[macro_export]
macro_rules! logx_trace {
    ($($arg:tt)*) => { logx_log(LogxLevel::Trace, &format!($($arg)*), file!(), line!()) };
}
#[macro_export]
macro_rules! logx_info {
    ($($arg:tt)*) => { logx_log(LogxLevel::Info, &format!($($arg)*), file!(), line!()) };
}
#[macro_export]
macro_rules! logx_warn {
    ($($arg:tt)*) => { logx_log(LogxLevel::Warn, &format!($($arg)*), file!(), line!()) };
}
#[macro_export]
macro_rules! logx_error {
    ($($arg:tt)*) => { logx_log(LogxLevel::Error, &format!($($arg)*), file!(), line!()) };
}
#[macro_export]
macro_rules! logx_fatal {
    ($($arg:tt)*) => { logx_log(LogxLevel::Fatal, &format!($($arg)*), file!(), line!()) };
}
