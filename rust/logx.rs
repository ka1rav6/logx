/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

use std::env;
use std::fs::File;
use std::fs::OpenOptions;
use std::io::{self, Write};
use std::sync::Mutex;
use std::time::SystemTime;

static LOG_FILE: Mutex<Option<File>> = Mutex::new(None);

#[derive(Clone, Copy, Debug)]
pub enum Level {
    Trace,
    Info,
    Warn,
    Error,
    Fatal,
}

const NAMES: [&str; 5] = ["TRACE", "INFO ", "WARN ", "ERROR", "FATAL"];
const COLORS: [&str; 5] = [
    "\x1b[36m", "\x1b[32m", "\x1b[33m", "\x1b[31m", "\x1b[35m",
];
const RESET: &str = "\x1b[0m";

fn level_val(l: Level) -> u8 {
    match l {
        Level::Trace => 0,
        Level::Info => 1,
        Level::Warn => 2,
        Level::Error => 3,
        Level::Fatal => 4,
    }
}

fn min_level() -> u8 {
    match env::var("LOG_LEVEL").unwrap_or_default().as_str() {
        "TRACE" => 0,
        "INFO" => 1,
        "WARN" => 2,
        "ERROR" => 3,
        "FATAL" => 4,
        _ => 0,
    }
}

fn use_color() -> bool {
    let env = env::var("LOG_COLOR").unwrap_or_default();
    if !env.is_empty() {
        return env == "1" || env == "yes";
    }
    // Check if stdout and stderr are TTYs
    unsafe { libc::isatty(1) != 0 && libc::isatty(2) != 0 }
}

fn timestamp() -> String {
    let d = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default();
    let total_secs = d.as_secs();
    let ms = d.subsec_millis();
    let secs = total_secs % 86400;
    let h = secs / 3600;
    let m = (secs % 3600) / 60;
    let s = secs % 60;
    format!("{:02}:{:02}:{:02}.{:03}", h, m, s, ms)
}

pub fn set_log_file(path: &str) {
    let file =
        OpenOptions::new().create(true).append(true).open(path).unwrap();
    *LOG_FILE.lock().unwrap() = Some(file);
}

pub fn log(level: Level, msg: &str, file: &str, line: u32) {
    if level_val(level) < min_level() {
        return;
    }

    let ts = timestamp();
    let label = format!(
        "[{}][{}] {}:{} -> {}",
        ts,
        NAMES[level as usize],
        file,
        line,
        msg
    );

    let mut guard = LOG_FILE.lock().unwrap();
    if let Some(ref mut f) = *guard {
        let _ = writeln!(f, "{}", label);
    } else {
        let use_col = use_color();
        let out: &mut dyn Write = if level_val(level) >= 3 {
            &mut io::stderr()
        } else {
            &mut io::stdout()
        };
        if use_col {
            let _ = write!(out, "{}{}{}\n", COLORS[level as usize], label, RESET);
        } else {
            let _ = writeln!(out, "{}", label);
        }
    }

    if matches!(level, Level::Fatal) {
        std::process::exit(1);
    }
}

#[macro_export]
macro_rules! logx_trace {
    ($($arg:tt)*) => {
        $crate::log($crate::Level::Trace, &format!($($arg)*), file!(), line!());
    };
}
#[macro_export]
macro_rules! logx_info {
    ($($arg:tt)*) => {
        $crate::log($crate::Level::Info, &format!($($arg)*), file!(), line!());
    };
}
#[macro_export]
macro_rules! logx_warn {
    ($($arg:tt)*) => {
        $crate::log($crate::Level::Warn, &format!($($arg)*), file!(), line!());
    };
}
#[macro_export]
macro_rules! logx_error {
    ($($arg:tt)*) => {
        $crate::log($crate::Level::Error, &format!($($arg)*), file!(), line!());
    };
}
#[macro_export]
macro_rules! logx_fatal {
    ($($arg:tt)*) => {
        $crate::log($crate::Level::Fatal, &format!($($arg)*), file!(), line!());
    };
}
