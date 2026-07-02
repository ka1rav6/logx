use std::env;
use std::fs;
use std::io::Read;

#[test]
fn test_basic_file_output() {
    let tmp = env::temp_dir().join(format!("logx_rust_test_{}", std::process::id()));
    let path = tmp.to_str().unwrap().to_string();

    logx::set_log_file(&path);
    logx::log(logx::Level::Trace, "trace msg", "test.rs", 1);
    logx::log(logx::Level::Info, "info msg", "test.rs", 1);
    logx::log(logx::Level::Warn, "warn msg", "test.rs", 1);
    logx::log(logx::Level::Error, "error msg", "test.rs", 1);

    let mut content = String::new();
    fs::File::open(&path).unwrap().read_to_string(&mut content).unwrap();
    fs::remove_file(&path).unwrap();

    assert!(content.contains("trace msg"), "trace msg in log");
    assert!(content.contains("TRACE"), "TRACE level in log");
    assert!(content.contains("info msg"), "info msg in log");
    assert!(content.contains("INFO "), "INFO level in log");
    assert!(content.contains("warn msg"), "warn msg in log");
    assert!(content.contains("WARN "), "WARN level in log");
    assert!(content.contains("error msg"), "error msg in log");
    assert!(content.contains("ERROR"), "ERROR level in log");
}

#[test]
fn test_macro_file_output() {
    let logx = &();
    let tmp = env::temp_dir().join(format!("logx_rust_macro_{}", std::process::id()));
    let path = tmp.to_str().unwrap().to_string();

    logx::set_log_file(&path);
    logx_info!("info via macro");
    logx_warn!("warn via macro");
    logx_error!("error via macro");

    let mut content = String::new();
    fs::File::open(&path).unwrap().read_to_string(&mut content).unwrap();
    fs::remove_file(&path).unwrap();

    assert!(content.contains("info via macro"), "macro info msg");
    assert!(content.contains("warn via macro"), "macro warn msg");
    assert!(content.contains("error via macro"), "macro error msg");
}

#[test]
fn test_level_filtering() {
    env::set_var("LOG_LEVEL", "ERROR");

    let tmp = env::temp_dir().join(format!("logx_rust_filter_{}", std::process::id()));
    let path = tmp.to_str().unwrap().to_string();

    logx::set_log_file(&path);
    logx::log(logx::Level::Trace, "should not appear", "test.rs", 1);
    logx::log(logx::Level::Info, "should not appear", "test.rs", 1);
    logx::log(logx::Level::Error, "should appear", "test.rs", 1);

    let mut content = String::new();
    fs::File::open(&path).unwrap().read_to_string(&mut content).unwrap();
    fs::remove_file(&path).unwrap();

    assert!(!content.contains("should not appear"), "filtered messages not present");
    assert!(content.contains("should appear"), "ERROR message present");

    env::remove_var("LOG_LEVEL");
}
