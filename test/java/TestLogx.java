import java.io.*;
import java.nio.file.*;

// Compile from project root:
//   javac -d /tmp java/logx.java test/java/TestLogx.java && java -cp /tmp TestLogx

public class TestLogx {
    private static int passed = 0;
    private static int failed = 0;

    static void check(boolean cond, String msg) {
        if (cond) {
            System.out.println("PASS: " + msg);
            passed++;
        } else {
            System.err.println("FAIL: " + msg);
            failed++;
        }
    }

    public static void main(String[] args) throws Exception {
        testBasicOutput();
        testFileLogging();

        System.out.println("\n" + passed + " passed, " + failed + " failed");
        System.exit(failed > 0 ? 1 : 0);
    }

    static void testBasicOutput() throws Exception {
        // Capture stdout
        PrintStream oldOut = System.out;
        ByteArrayOutputStream outBytes = new ByteArrayOutputStream();
        System.setOut(new PrintStream(outBytes, true));

        PrintStream oldErr = System.err;
        ByteArrayOutputStream errBytes = new ByteArrayOutputStream();
        System.setErr(new PrintStream(errBytes, true));

        Logx.trace("trace msg");
        Logx.info("info msg");
        Logx.warn("warn msg");
        Logx.error("error msg");

        System.setOut(oldOut);
        System.setErr(oldErr);

        String out = outBytes.toString();
        String err = errBytes.toString();

        check(out.contains("TRACE") && out.contains("trace msg"), "TRACE output");
        check(out.contains("INFO ") && out.contains("info msg"), "INFO output");
        check(out.contains("WARN ") && out.contains("warn msg"), "WARN output");
        check(err.contains("ERROR") && err.contains("error msg"), "ERROR output");
    }

    static void testFileLogging() throws Exception {
        Path tmp = Files.createTempFile("logx_java_", ".log");
        String path = tmp.toString();

        Logx.setLogFile(path);
        Logx.info("file test");
        Logx.setLogFile(null);

        String content = Files.readString(tmp);
        Files.delete(tmp);

        check(content.contains("file test"), "file log message");
        check(content.contains("INFO "), "file log level");
    }
}
