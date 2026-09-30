/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

/*
 * Logx -- single-file logger for Java 8 and later.
 *
 *   Logx.info("listening on port %d", 8080);
 *   Logx.warn("memory at %.1f%%", 74.2);
 *   Logx.error("connection lost");
 *
 * Arguments go through String.format, and only when there are some, so
 * info("100% done") does not need escaping.
 *
 * The file must stay named Logx.java -- javac requires the file name to match
 * the public class. If your project uses packages, add your own package line as
 * the very first line of this file and move it into the matching directory:
 *
 *   package com.example.util;
 *
 * Environment
 *   LOG_LEVEL   TRACE | INFO | WARN | ERROR | FATAL | OFF   (or 0..5)
 *   LOG_COLOR   1/true/yes/on forces, 0/false/no/off disables, unset = auto
 *   NO_COLOR    set to anything to disable color (https://no-color.org)
 *   LOG_FILE    path to append to instead of writing to the terminal
 *   LOG_STREAM  split (default) | stdout | stderr
 */

import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintStream;
import java.io.PrintWriter;
import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Locale;

public final class Logx {

    public static final int TRACE = 0;
    public static final int INFO = 1;
    public static final int WARN = 2;
    public static final int ERROR = 3;
    public static final int FATAL = 4;
    public static final int OFF = 5;

    /** Padded to a fixed width so columns line up in the output. */
    private static final String[] NAMES = {"TRACE", "INFO ", "WARN ", "ERROR", "FATAL"};
    private static final String[] COLORS = {
        "\033[36m", "\033[32m", "\033[33m", "\033[31m", "\033[35m"
    };
    private static final String RESET = "\033[0m";

    private static final int SINK_SPLIT = 0;
    private static final int SINK_STDOUT = 1;
    private static final int SINK_STDERR = 2;

    private static final Object LOCK = new Object();
    private static final String SELF = Logx.class.getName();

    private static int minLevel;
    private static boolean useColor;
    private static int sink;
    private static PrintWriter fileWriter;

    static {
        minLevel = parseLevel(System.getenv("LOG_LEVEL"), TRACE);

        String stream = trimLower(System.getenv("LOG_STREAM"));
        if ("stdout".equals(stream)) {
            sink = SINK_STDOUT;
        } else if ("stderr".equals(stream)) {
            sink = SINK_STDERR;
        } else {
            sink = SINK_SPLIT;
        }

        Boolean forced = parseBool(System.getenv("LOG_COLOR"));
        if (forced != null) {
            useColor = forced;
        } else if (System.getenv("NO_COLOR") != null) {
            useColor = false;
        } else {
            useColor = isTerminal();
        }

        String path = System.getenv("LOG_FILE");
        if (path != null && !path.isEmpty()) {
            // An unwritable LOG_FILE leaves logging on the terminal rather than
            // failing during class initialisation.
            setLogFile(path);
        }
    }

    private Logx() {
    }

    // ----------------------------------------------------------------- config

    /** Parses a level name, case-insensitively. 0..5 work too. */
    public static int parseLevel(String text, int fallback) {
        if (text == null) {
            return fallback;
        }
        String key = text.trim().toUpperCase(Locale.ROOT);
        if (key.equals("TRACE") || key.equals("DEBUG") || key.equals("ALL") || key.equals("0")) return TRACE;
        if (key.equals("INFO") || key.equals("1")) return INFO;
        if (key.equals("WARN") || key.equals("WARNING") || key.equals("2")) return WARN;
        if (key.equals("ERROR") || key.equals("ERR") || key.equals("3")) return ERROR;
        if (key.equals("FATAL") || key.equals("CRITICAL") || key.equals("4")) return FATAL;
        if (key.equals("OFF") || key.equals("NONE") || key.equals("SILENT") || key.equals("5")) return OFF;
        return fallback;
    }

    /** Raises or lowers the threshold at runtime. */
    public static void setLevel(int level) {
        synchronized (LOCK) {
            minLevel = level;
        }
    }

    public static int getLevel() {
        synchronized (LOCK) {
            return minLevel;
        }
    }

    /** Turns ANSI coloring on or off, overriding the auto-detection. */
    public static void setColor(boolean enabled) {
        synchronized (LOCK) {
            useColor = enabled;
        }
    }

    /** Whether a message at {@code level} would be emitted. */
    public static boolean isEnabled(int level) {
        synchronized (LOCK) {
            return minLevel < OFF && level >= minLevel;
        }
    }

    /**
     * Appends log output to {@code path}, or pass null to go back to the
     * terminal. Returns false if the file could not be opened, in which case
     * logging stays wherever it already was.
     */
    public static boolean setLogFile(String path) {
        PrintWriter opened = null;
        if (path != null) {
            try {
                opened = new PrintWriter(new FileWriter(path, true), true);
            } catch (IOException e) {
                return false;
            }
        }
        synchronized (LOCK) {
            if (fileWriter != null) {
                fileWriter.close();
            }
            fileWriter = opened;
        }
        return true;
    }

    public static void flush() {
        synchronized (LOCK) {
            if (fileWriter != null) {
                fileWriter.flush();
            } else {
                System.out.flush();
                System.err.flush();
            }
        }
    }

    // ----------------------------------------------------------------- output

    public static void trace(String msg, Object... args) {
        log(TRACE, msg, args);
    }

    public static void info(String msg, Object... args) {
        log(INFO, msg, args);
    }

    public static void warn(String msg, Object... args) {
        log(WARN, msg, args);
    }

    public static void error(String msg, Object... args) {
        log(ERROR, msg, args);
    }

    /** Logs at FATAL, then exits with status 1. */
    public static void fatal(String msg, Object... args) {
        log(FATAL, msg, args);
    }

    /**
     * Logs one record. The reported location is the first frame outside this
     * class, so wrapping these methods in a helper of your own still reports
     * your caller rather than the helper.
     */
    public static void log(int level, String msg, Object... args) {
        if (!isEnabled(level)) {
            if (level == FATAL) {
                System.exit(1);
            }
            return;
        }

        String text = msg == null ? "null" : msg;
        if (args != null && args.length > 0) {
            try {
                text = String.format(text, args);
            } catch (RuntimeException e) {
                // Better to log the pieces than to throw out of a log call.
                text = text + " " + Arrays.toString(args);
            }
        }

        String line = "[" + timestamp() + "][" + NAMES[level] + "] "
            + callerLocation() + " -> " + text;

        synchronized (LOCK) {
            if (fileWriter != null) {
                fileWriter.println(line);
                fileWriter.flush();
            } else {
                PrintStream out;
                if (sink == SINK_STDOUT) {
                    out = System.out;
                } else if (sink == SINK_STDERR) {
                    out = System.err;
                } else {
                    out = level >= ERROR ? System.err : System.out;
                }
                out.println(useColor ? COLORS[level] + line + RESET : line);
                out.flush();
            }
        }

        if (level == FATAL) {
            System.exit(1);
        }
    }

    // ----------------------------------------------------------------- detail

    private static String timestamp() {
        // Calendar rather than java.time, so this file still compiles on Java 8
        // with no extra imports to trim.
        Calendar cal = Calendar.getInstance();
        cal.setTimeInMillis(System.currentTimeMillis());
        return String.format(Locale.ROOT, "%02d:%02d:%02d.%03d",
            cal.get(Calendar.HOUR_OF_DAY),
            cal.get(Calendar.MINUTE),
            cal.get(Calendar.SECOND),
            cal.get(Calendar.MILLISECOND));
    }

    /**
     * The first stack frame that is not ours. Matching on the class name rather
     * than counting frames means a wrapper method does not shift the answer.
     */
    private static String callerLocation() {
        StackTraceElement[] stack = Thread.currentThread().getStackTrace();
        for (int i = 0; i < stack.length; i++) {
            String cls = stack[i].getClassName();
            if (cls.equals(SELF) || cls.equals("java.lang.Thread")) {
                continue;
            }
            String file = stack[i].getFileName();
            return (file != null ? file : cls) + ":" + stack[i].getLineNumber();
        }
        return "<unknown>:0";
    }

    private static String trimLower(String value) {
        return value == null ? null : value.trim().toLowerCase(Locale.ROOT);
    }

    private static Boolean parseBool(String value) {
        String low = trimLower(value);
        if (low == null || low.isEmpty()) {
            return null;
        }
        if (low.equals("1") || low.equals("true") || low.equals("yes") || low.equals("on")) {
            return Boolean.TRUE;
        }
        if (low.equals("0") || low.equals("false") || low.equals("no") || low.equals("off")) {
            return Boolean.FALSE;
        }
        return null;
    }

    /**
     * On Java 22 and later System.console() returns a Console even when output
     * is redirected, so ask Console.isTerminal() when it exists and fall back to
     * the older null check when it does not.
     */
    private static boolean isTerminal() {
        try {
            Object console = System.console();
            if (console == null) {
                return false;
            }
            try {
                Method isTerminal = console.getClass().getMethod("isTerminal");
                Object result = isTerminal.invoke(console);
                return result instanceof Boolean && (Boolean) result;
            } catch (NoSuchMethodException e) {
                return true;
            }
        } catch (Throwable t) {
            return false;
        }
    }
}
