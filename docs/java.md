# LogX for Java

Single-file logger for Java 8 and later. One class, no dependencies, no
configuration file.

- [Requirements](#requirements)
- [Install](#install)
- [Using packages](#using-packages)
- [Quick start](#quick-start)
- [API reference](#api-reference)
- [Recipes](#recipes)
- [logx or the standard logging APIs?](#logx-or-the-standard-logging-apis)
- [Gotchas](#gotchas)
- [Troubleshooting](#troubleshooting)

## Requirements

| | |
|---|---|
| Java | 8 or later (tested on 8 and 21) |
| Platforms | Everywhere the JVM runs |
| Dependencies | None |

## Install

Copy `java/Logx.java` into your source tree and compile it with the rest of
your code.

```bash
javac Logx.java Main.java && java Main
```

**The file must stay named `Logx.java`.** `javac` requires the file name to
match the public class, so a renamed copy fails with:

```
error: class Logx is public, should be declared in a file named Logx.java
```

There is no Maven or Gradle artifact. It is one source file — add it to your
source set and it is compiled like anything else:

```gradle
// Gradle, if you keep it outside the main source tree
sourceSets.main.java.srcDirs += ['third_party/logx']
```

```xml
<!-- Maven -->
<plugin>
  <groupId>org.codehaus.mojo</groupId>
  <artifactId>build-helper-maven-plugin</artifactId>
  <executions>
    <execution>
      <goals><goal>add-source</goal></goals>
      <configuration>
        <sources><source>third_party/logx</source></sources>
      </configuration>
    </execution>
  </executions>
</plugin>
```

## Using packages

`Logx.java` declares no package, so out of the box it lands in the default
package. That works for scripts and small programs, but **code inside a package
cannot see a default-package class** — there is no import syntax for it.

If your project uses packages, add your own package line as the very first line
of the file and move it into the matching directory:

```java
package com.example.util;      // <- add this as line 1

import java.io.FileWriter;
// ... the rest of the file unchanged
```

```
src/main/java/com/example/util/Logx.java
```

```java
import com.example.util.Logx;

Logx.info("listening on port %d", 8080);
```

That one line is the only edit the file ever needs.

## Quick start

```java
public class Main {
    public static void main(String[] args) {
        Logx.trace("starting up");
        Logx.info("listening on port %d", 8080);
        Logx.warn("memory at %.1f%%", 74.2);
        Logx.error("connection lost: %s", "ECONNRESET");
    }
}
```

```
[14:23:01.042][TRACE] Main.java:3 -> starting up
[14:23:01.042][INFO ] Main.java:4 -> listening on port 8080
[14:23:01.043][WARN ] Main.java:5 -> memory at 74.2%
[14:23:01.043][ERROR] Main.java:6 -> connection lost: ECONNRESET
```

No logger to construct, no `getLogger(getClass())`, no properties file.

## API reference

All members are `static`; the class is `final` with a private constructor.

### Log methods

```java
public static void trace(String msg, Object... args)
public static void info (String msg, Object... args)
public static void warn (String msg, Object... args)
public static void error(String msg, Object... args)
public static void fatal(String msg, Object... args)   // logs, then System.exit(1)

public static void log(int level, String msg, Object... args)
```

### Levels

```java
public static final int TRACE = 0;
public static final int INFO  = 1;
public static final int WARN  = 2;
public static final int ERROR = 3;
public static final int FATAL = 4;
public static final int OFF   = 5;   // a threshold only; silences everything
```

Plain `int` constants rather than an `enum`, so the file stays compatible all
the way back to Java 8 with no boxing in the hot path.

### Configuration

```java
public static void    setLevel(int level)
public static int     getLevel()
public static void    setColor(boolean enabled)
public static boolean isEnabled(int level)
public static boolean setLogFile(String path)      // false if it cannot open
public static void    flush()
public static int     parseLevel(String text, int fallback)
```

```java
Logx.setLevel(Logx.WARN);
Logx.setLevel(Logx.OFF);                 // silent

if (Logx.isEnabled(Logx.TRACE)) {
    Logx.trace("state: %s", expensiveDump());
}
```

`parseLevel` is public so you can take a level from your own configuration:

```java
Logx.setLevel(Logx.parseLevel(config.get("log.level"), Logx.INFO));
```

It is case-insensitive, trims whitespace, accepts `0`–`5` and the usual
aliases, and returns `fallback` for anything it does not recognise — including
`null`.

### Formatting

Arguments go through `String.format`, and **only when there are arguments**, so
a literal `%` in a bare message needs no escaping:

```java
Logx.info("listening on port %d", 8080);     // listening on port 8080
Logx.warn("memory at %.1f%%", 74.2);         // memory at 74.2%
Logx.info("100% done");                      // 100% done
```

A malformed format logs the pieces rather than throwing. A broken log statement
should not take down the request that hit it:

```java
Logx.info("bad format %d", "not a number");
// -> bad format %d [not a number]
```

### File output

```java
if (!Logx.setLogFile("/tmp/app.log")) {
    Logx.warn("could not open the log file, staying on the terminal");
}

Logx.setLogFile(null);        // back to the terminal
```

Appended, never truncated, and it returns `false` rather than throwing
`IOException` — a logging call site should not need a `try` block.

## Recipes

### A per-class prefix

```java
public final class Db {
    private static void logf(int level, String msg, Object... args) {
        Logx.log(level, "[db] " + msg, args);
    }

    public static void connect() {
        logf(Logx.INFO, "connected in %dms", 12);
    }
}
```

The reported line is the one inside `logf`, not `connect` — see
[Gotchas](#gotchas).

### Logging an exception with its stack trace

```java
try {
    risky();
} catch (Exception e) {
    StringWriter sw = new StringWriter();
    e.printStackTrace(new PrintWriter(sw));
    Logx.error("risky() failed:%n%s", sw);
}
```

For just the message:

```java
} catch (Exception e) {
    Logx.error("risky() failed: %s: %s", e.getClass().getSimpleName(), e.getMessage());
}
```

### A servlet filter

```java
public class LoggingFilter implements Filter {
    @Override
    public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
            throws IOException, ServletException {
        long start = System.currentTimeMillis();
        chain.doFilter(req, res);

        HttpServletRequest http = (HttpServletRequest) req;
        int status = ((HttpServletResponse) res).getStatus();
        Logx.log(status >= 500 ? Logx.ERROR : Logx.INFO,
                 "%s %s -> %d (%dms)",
                 http.getMethod(), http.getRequestURI(), status,
                 System.currentTimeMillis() - start);
    }
}
```

### Quieting it inside tests

```java
@BeforeEach
void quietLogs() {
    Logx.setLevel(Logx.OFF);
}
```

Or set `LOG_LEVEL=OFF` in your test task's environment. Note that
`System.getenv` cannot be changed from inside the JVM, so `setLevel` is the only
way to change it at runtime.

### Capturing output in a test

`Logx` resolves `System.out` and `System.err` on every call, so
`System.setOut` works:

```java
PrintStream real = System.out;
ByteArrayOutputStream captured = new ByteArrayOutputStream();
System.setOut(new PrintStream(captured, true));
try {
    Logx.info("hello");
} finally {
    System.setOut(real);
}
assertTrue(captured.toString().contains("hello"));
```

Or point it at a temp file with `setLogFile`, which is what the test suite does.

## logx or the standard logging APIs?

SLF4J with Logback, or `java.util.logging`, is the right answer when you need
appenders, per-package levels, rotation, MDC, or structured output — or when a
framework already configures logging for you and you should not fight it.

`Logx` is the right answer for a program where adding a logging facade, a
binding, and an XML configuration file to get a timestamped line is the wrong
trade. One file, no `logback.xml`, file and line on by default.

They coexist fine — `Logx` touches nothing in `java.util.logging`.

## Gotchas

**The file must be named `Logx.java`.** See [Install](#install).

**A helper of yours reports its own line, not its caller's.** The reported
location is the first stack frame outside the `Logx` class, which is your
helper. Java has no depth or skip parameter here; Python has `depth=` and Go
has `skip`. If you need the call site, pass it in the message.

**`fatal()` calls `System.exit(1)`.** Shutdown hooks run; `finally` blocks
after the call do not. It exits even when the level filter hid the message.

**Default package by default.** See [Using packages](#using-packages).

**`setLogFile` returns `false`, it does not throw.** Check the return value if
you care.

**Arguments are not lazy.** `info("x %s", f())` always calls `f()`. Guard with
`isEnabled`.

**Levels come from the environment at class-initialisation time.** The static
initialiser reads `LOG_LEVEL` the first time `Logx` is touched. Java cannot
mutate its own environment, so `setLevel` is the only runtime control.

**TTY detection uses `Console.isTerminal()` where available.** On Java 22+,
`System.console()` returns a console even when output is redirected, so the
reflective `isTerminal()` call is what keeps auto-detection honest. On Java 8
through 21 it falls back to `System.console() != null`.

## Troubleshooting

**`class Logx is public, should be declared in a file named Logx.java`** — the
file was renamed. Name it `Logx.java`.

**`cannot find symbol: class Logx`** from inside a package — a default-package
class is invisible to packaged code. Add a `package` line to `Logx.java`. See
[Using packages](#using-packages).

**`error: unreported exception IOException`** — you are on an old copy whose
`setLogFile` threw. Current versions return `boolean`.

**Every line reports the same helper method** — expected; see
[Gotchas](#gotchas).

**No color in a terminal** — with the default `split` stream, color needs the
console to be a real terminal. Running under Gradle, Maven, or an IDE's captured
console turns it off. Force it with `LOG_COLOR=1` or `Logx.setColor(true)`.

**Lines say `<unknown>:0`** — compiled without debug info. Keep `javac`'s
default, or pass `-g:lines`.

**No logs under Gradle** — Gradle swallows test output. Add:

```gradle
test { testLogging { showStandardStreams = true } }
```

## See also

- [Output format, levels and environment](format.md) — shared across all languages
- [`java/Logx.java`](../java/Logx.java) — the source
- [`test/java/TestLogx.java`](../test/java/TestLogx.java) — worked examples
