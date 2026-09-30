use logx::*;
use std::env;
use std::fs;
use std::process;

// [HH:MM:SS.mmm][LEVEL] file:line -> message
fn parse(line: &str) -> Option<(String, String, u32, String)> {
    let rest = line.strip_prefix('[')?;
    let (stamp, rest) = rest.split_once(']')?;
    let bytes = stamp.as_bytes();
    if stamp.len() != 12 || bytes[2] != b':' || bytes[5] != b':' || bytes[8] != b'.' {
        return None;
    }
    let rest = rest.strip_prefix('[')?;
    let (level, rest) = rest.split_once(']')?;
    let rest = rest.strip_prefix(' ')?;
    let (location, message) = rest.split_once(" -> ")?;
    let (file, line_no) = location.rsplit_once(':')?;
    Some((
        level.to_string(),
        file.to_string(),
        line_no.parse().ok()?,
        message.to_string(),
    ))
}

fn capture(body: impl FnOnce()) -> Vec<String> {
    let path = env::temp_dir().join(format!("logx_rust_{}_{:?}.log", process::id(), std::thread::current().id()));
    let path = path.to_str().unwrap().to_string();
    let _ = fs::remove_file(&path);

    set_log_file(&path).expect("set_log_file");
    body();
    clear_log_file();

    let content = fs::read_to_string(&path).expect("read back the log");
    let _ = fs::remove_file(&path);
    content.lines().map(str::to_string).collect()
}

// These run in one test because the logger state is process-wide and the
// level-filter cases would otherwise race the formatting cases.
#[test]
fn logx_behaves_as_documented() {
    // ---- format and arguments ----
    let lines = capture(|| {
        logx_trace!("trace msg");
        logx_info!("port {}", 8080);
        logx_warn!("memory at {:.1}%", 74.2);
        logx_error!("lost: {}", "ECONNRESET");
    });

    assert_eq!(lines.len(), 4, "one line per call: {:?}", lines);

    let expected = [
        ("TRACE", "trace msg"),
        ("INFO ", "port 8080"),
        ("WARN ", "memory at 74.2%"),
        ("ERROR", "lost: ECONNRESET"),
    ];

    for (i, line) in lines.iter().enumerate() {
        let (level, file, _, message) =
            parse(line).unwrap_or_else(|| panic!("line {} unparsed: {:?}", i, line));
        assert_eq!(level, expected[i].0, "level on line {}", i);
        assert_eq!(message, expected[i].1, "message on line {}", i);
        assert_eq!(file, "integration.rs", "file on line {}", i);
    }

    assert!(!lines[0].contains('\x1b'), "color escapes leaked into a file");

    // ---- level filtering ----
    let lines = capture(|| {
        set_level(LogxLevel::Warn);
        logx_trace!("hidden");
        logx_info!("hidden");
        logx_warn!("shown");
        logx_error!("shown");
        set_level(LogxLevel::Off);
        logx_error!("silenced by Off");
        set_level(LogxLevel::Trace);
    });
    assert_eq!(lines.len(), 2, "only Warn and above passed: {:?}", lines);
    assert_eq!(get_level(), LogxLevel::Trace);

    // ---- enabled() ----
    set_level(LogxLevel::Warn);
    assert!(!enabled(LogxLevel::Info));
    assert!(enabled(LogxLevel::Error));
    set_level(LogxLevel::Off);
    assert!(!enabled(LogxLevel::Fatal));
    set_level(LogxLevel::Trace);

    // ---- level parsing ----
    assert_eq!(LogxLevel::parse("warn", LogxLevel::Trace), LogxLevel::Warn);
    assert_eq!(LogxLevel::parse("WARNING", LogxLevel::Trace), LogxLevel::Warn);
    assert_eq!(LogxLevel::parse("3", LogxLevel::Trace), LogxLevel::Error);
    assert_eq!(LogxLevel::parse("silent", LogxLevel::Trace), LogxLevel::Off);
    assert_eq!(LogxLevel::parse("junk", LogxLevel::Info), LogxLevel::Info);

    // ---- a bad path is reported, not panicked on ----
    assert!(set_log_file("/nonexistent-dir-xyz/app.log").is_err());
}
