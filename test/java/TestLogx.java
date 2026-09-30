// Tests for java/Logx.java. Build and run from the project root:
//   javac -d /tmp/logx-java java/Logx.java test/java/TestLogx.java
//   java -cp /tmp/logx-java TestLogx

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class TestLogx {

    // [HH:MM:SS.mmm][LEVEL] file:line -> message
    private static final Pattern RECORD = Pattern.compile(
        "^\\[\\d{2}:\\d{2}:\\d{2}\\.\\d{3}\\]\\[(\\w+ ?)\\] ([^/\\\\:]+):(\\d+) -> (.*)$");

    private static final List<String> failures = new ArrayList<>();

    static void check(boolean cond, String what) {
        if (cond) {
            System.out.println("PASS: " + what);
        } else {
            System.out.println("FAIL: " + what);
            failures.add(what);
        }
    }

    /** Runs the body with output going to a temp file, returns the lines written. */
    interface Body {
        void run() throws Exception;
    }

    static List<String> capture(Body body) throws Exception {
        Path tmp = Files.createTempFile("logx_java_", ".log");
        check(Logx.setLogFile(tmp.toString()), "setLogFile succeeds");
        try {
            body.run();
        } finally {
            Logx.setLogFile(null);
        }
        List<String> lines = Files.readAllLines(tmp);
        Files.delete(tmp);
        return lines;
    }

    static void testFormatAndArgs() throws Exception {
        List<String> lines = capture(() -> {
            Logx.trace("trace msg");
            Logx.info("port %d", 8080);
            Logx.warn("memory at %.1f%%", 74.2);
            Logx.error("lost: %s", "ECONNRESET");
            Logx.info("literal 100% done");
            Logx.info("bad format %d", "not a number");
        });

        check(lines.size() == 6, "wrote one line per call");
        if (lines.size() < 6) {
            return;
        }

        String[][] want = {
            {"TRACE", "trace msg"},
            {"INFO ", "port 8080"},
            {"WARN ", "memory at 74.2%"},
            {"ERROR", "lost: ECONNRESET"},
            {"INFO ", "literal 100% done"},
        };

        for (int i = 0; i < want.length; i++) {
            Matcher m = RECORD.matcher(lines.get(i));
            if (!m.matches()) {
                check(false, "line " + i + " matches the documented format: " + lines.get(i));
                continue;
            }
            check(m.group(1).equals(want[i][0]), "line " + i + " level is " + want[i][0]);
            check(m.group(4).equals(want[i][1]), "line " + i + " message is " + want[i][1]);
            check(m.group(2).equals("TestLogx.java"), "line " + i + " reports the calling file");
        }

        check(lines.get(5).contains("bad format"),
              "a format mismatch logs instead of throwing");
        check(!lines.get(0).contains("\033["), "no color escapes in a file");
    }

    static void testCallerThroughAWrapper() throws Exception {
        List<String> lines = capture(() -> helper("wrapped"));
        Matcher m = RECORD.matcher(lines.get(0));
        check(m.matches() && m.group(2).equals("TestLogx.java"),
              "a wrapper still reports the original file");
    }

    // Wrapping Logx.info must not shift the reported location onto Logx.java.
    static void helper(String message) {
        Logx.info(message);
    }

    static void testLevelFilter() throws Exception {
        List<String> lines = capture(() -> {
            Logx.setLevel(Logx.WARN);
            Logx.trace("hidden");
            Logx.info("hidden");
            Logx.warn("shown");
            Logx.error("shown");
            Logx.setLevel(Logx.OFF);
            Logx.error("silenced by OFF");
            Logx.setLevel(Logx.TRACE);
        });
        check(lines.size() == 2, "only WARN and above passed the filter");
        check(Logx.getLevel() == Logx.TRACE, "getLevel reflects setLevel");
    }

    static void testEnabled() {
        Logx.setLevel(Logx.WARN);
        check(!Logx.isEnabled(Logx.INFO), "isEnabled is false below the threshold");
        check(Logx.isEnabled(Logx.ERROR), "isEnabled is true at or above it");
        Logx.setLevel(Logx.OFF);
        check(!Logx.isEnabled(Logx.FATAL), "isEnabled is false for everything at OFF");
        Logx.setLevel(Logx.TRACE);
    }

    static void testStreams() {
        PrintStream realOut = System.out;
        PrintStream realErr = System.err;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ByteArrayOutputStream err = new ByteArrayOutputStream();
        System.setOut(new PrintStream(out, true));
        System.setErr(new PrintStream(err, true));
        try {
            Logx.info("to stdout");
            Logx.error("to stderr");
        } finally {
            System.setOut(realOut);
            System.setErr(realErr);
        }
        check(out.toString().contains("to stdout"), "INFO goes to stdout");
        check(!err.toString().contains("to stdout"), "INFO stays off stderr");
        check(err.toString().contains("to stderr"), "ERROR goes to stderr");
        check(!out.toString().contains("to stderr"), "ERROR stays off stdout");
    }

    static void testParseLevel() {
        check(Logx.parseLevel("warn", Logx.TRACE) == Logx.WARN, "level names are case-insensitive");
        check(Logx.parseLevel("WARNING", Logx.TRACE) == Logx.WARN, "WARNING is an alias for WARN");
        check(Logx.parseLevel("3", Logx.TRACE) == Logx.ERROR, "numeric levels work");
        check(Logx.parseLevel("  silent ", Logx.TRACE) == Logx.OFF, "values are trimmed");
        check(Logx.parseLevel("junk", Logx.INFO) == Logx.INFO, "unknown falls back");
        check(Logx.parseLevel(null, Logx.WARN) == Logx.WARN, "null falls back");
    }

    static void testBadPath() {
        check(!Logx.setLogFile("/nonexistent-dir-xyz/app.log"),
              "setLogFile reports an unwritable path");
    }

    public static void main(String[] args) throws Exception {
        testFormatAndArgs();
        testCallerThroughAWrapper();
        testLevelFilter();
        testEnabled();
        testStreams();
        testParseLevel();
        testBadPath();

        System.out.println(failures.isEmpty() ? "all Java tests passed" : "Java tests FAILED");
        System.exit(failures.isEmpty() ? 0 : 1);
    }
}
