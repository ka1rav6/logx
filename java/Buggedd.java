/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

import java.io.*;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;

public class Buggedd {

    public static final int TRACE = 0;
    public static final int INFO  = 1;
    public static final int WARN  = 2;
    public static final int ERROR = 3;
    public static final int FATAL = 4;

    private static final String[] NAMES = {"TRACE", "INFO ", "WARN ", "ERROR", "FATAL"};
    private static final String[] COLORS = {
        "\033[36m", "\033[32m", "\033[33m", "\033[31m", "\033[35m"
    };
    private static final String RESET = "\033[0m";

    private static int minLevel = -1;
    private static boolean useColor;
    private static PrintWriter fileWriter = null;

    static {
        String env = System.getenv("LOG_LEVEL");
        if (env == null) minLevel = TRACE;
        else if (env.equals("TRACE")) minLevel = TRACE;
        else if (env.equals("INFO"))  minLevel = INFO;
        else if (env.equals("WARN"))  minLevel = WARN;
        else if (env.equals("ERROR")) minLevel = ERROR;
        else if (env.equals("FATAL")) minLevel = FATAL;
        else minLevel = TRACE;

        String col = System.getenv("LOG_COLOR");
        if (col != null) {
            useColor = col.equals("1") || col.equals("yes");
        } else {
            useColor = System.console() != null;
        }
    }

    public static synchronized void setLogFile(String path) throws IOException {
        if (fileWriter != null) { fileWriter.close(); fileWriter = null; }
        if (path != null) {
            fileWriter = new PrintWriter(new FileWriter(path, true), true);
        }
    }

    private static String timestamp() {
        LocalTime now = LocalTime.now();
        return now.format(DateTimeFormatter.ofPattern("HH:mm:ss.SSS"));
    }

    public static void trace(String msg) { log(TRACE, msg, 2); }
    public static void info(String msg)  { log(INFO,  msg, 2); }
    public static void warn(String msg)  { log(WARN,  msg, 2); }
    public static void error(String msg) { log(ERROR, msg, 2); }
    public static void fatal(String msg) { log(FATAL, msg, 2); }

    private static synchronized void log(int level, String msg, int depth) {
        if (level < minLevel) return;

        StackTraceElement[] stack = Thread.currentThread().getStackTrace();
        String file = "<unknown>";
        int line = 0;
        if (stack.length > depth) {
            file = stack[depth].getFileName();
            line = stack[depth].getLineNumber();
        }

        String ts = timestamp();
        String label = String.format("[%s][%s] %s:%d -> %s", ts, NAMES[level], file, line, msg);

        if (fileWriter != null) {
            fileWriter.println(label);
            fileWriter.flush();
        } else {
            PrintStream out = (level >= ERROR) ? System.err : System.out;
            if (useColor) {
                out.println(COLORS[level] + label + RESET);
            } else {
                out.println(label);
            }
        }

        if (level == FATAL) System.exit(1);
    }
}
