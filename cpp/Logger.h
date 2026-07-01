/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

#ifndef LOGGER_H
#define LOGGER_H

#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <mutex>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <cstdlib>
#include <cstring>
#include <unistd.h>

enum class LogLevel {
    TRACE = 0,
    INFO  = 1,
    WARN  = 2,
    ERROR = 3,
    FATAL = 4,
};

class Logger {
public:
    static LogLevel& minLevel() {
        static LogLevel level = []{
            const char* env = std::getenv("LOG_LEVEL");
            if (!env) return LogLevel::TRACE;
            std::string s(env);
            if (s == "TRACE") return LogLevel::TRACE;
            if (s == "INFO")  return LogLevel::INFO;
            if (s == "WARN")  return LogLevel::WARN;
            if (s == "ERROR") return LogLevel::ERROR;
            if (s == "FATAL") return LogLevel::FATAL;
            return LogLevel::TRACE;
        }();
        return level;
    }

    static bool colored() {
        static bool c = []{
            const char* env = std::getenv("LOG_COLOR");
            if (env) return std::string(env) == "1" || std::string(env) == "yes";
            return isatty(fileno(stdout)) && isatty(fileno(stderr));
        }();
        return c;
    }

    static void setLogFile(const std::string& path) {
        logStream().open(path, std::ios::app);
    }

    static void setLogFile() {
        logStream().close();
    }

    class LogStream {
    public:
        LogStream(LogLevel level, const char* file, int line)
            : m_level(level) {
            if (level < Logger::minLevel()) return;
            m_active = true;
            stripPath(file);
            m_line = line;
        }

        ~LogStream() {
            if (!m_active) return;
            static std::mutex mtx;
            std::lock_guard<std::mutex> lock(mtx);

            auto& fs = logStream();
            if (fs.is_open()) {
                fs << "[" << timestamp() << "]"
                   << "[" << levelString(m_level) << "]"
                   << " " << m_file << ":" << m_line
                   << " -> " << m_buf.str()
                   << std::endl;
            } else {
                std::ostream& out = (m_level >= LogLevel::ERROR) ? std::cerr : std::cout;
                if (colored()) out << levelColor(m_level);
                out << "[" << timestamp() << "]"
                    << "[" << levelString(m_level) << "]"
                    << " " << m_file << ":" << m_line
                    << " -> " << m_buf.str();
                if (colored()) out << "\033[0m";
                out << std::endl;
            }

            if (m_level == LogLevel::FATAL)
                std::terminate();
        }

        template <typename T>
        LogStream& operator<<(const T& val) {
            if (m_active) m_buf << val;
            return *this;
        }

        LogStream& operator<<(std::ostream& (*manip)(std::ostream&)) {
            if (m_active) m_buf << manip;
            return *this;
        }

    private:
        LogLevel m_level;
        std::ostringstream m_buf;
        const char* m_file = nullptr;
        int m_line = 0;
        bool m_active = false;

        void stripPath(const char* path) {
            const char* slash = strrchr(path, '/');
#ifdef _WIN32
            if (!slash) slash = strrchr(path, '\\');
#endif
            m_file = slash ? slash + 1 : path;
        }

        static const char* levelString(LogLevel l) {
            switch (l) {
                case LogLevel::TRACE: return "TRACE";
                case LogLevel::INFO:  return "INFO ";
                case LogLevel::WARN:  return "WARN ";
                case LogLevel::ERROR: return "ERROR";
                case LogLevel::FATAL: return "FATAL";
            }
            return "?????";
        }

        static const char* levelColor(LogLevel l) {
            switch (l) {
                case LogLevel::TRACE: return "\033[36m";
                case LogLevel::INFO:  return "\033[32m";
                case LogLevel::WARN:  return "\033[33m";
                case LogLevel::ERROR: return "\033[31m";
                case LogLevel::FATAL: return "\033[35m";
            }
            return "\033[0m";
        }

        static std::string timestamp() {
            using namespace std::chrono;
            auto now = system_clock::now();
            auto ms = duration_cast<milliseconds>(now.time_since_epoch()) % 1000;
            auto t = system_clock::to_time_t(now);
            std::tm tm;
            localtime_r(&t, &tm);
            std::ostringstream ss;
            ss << std::put_time(&tm, "%H:%M:%S") << '.' << std::setfill('0') << std::setw(3) << ms.count();
            return ss.str();
        }
    };

    static std::ofstream& logStream() {
        static std::ofstream fs;
        return fs;
    }

private:
    Logger() = delete;
};

#define LOG_TRACE Logger::LogStream(LogLevel::TRACE, __FILE__, __LINE__)
#define LOG_INFO  Logger::LogStream(LogLevel::INFO,  __FILE__, __LINE__)
#define LOG_WARN  Logger::LogStream(LogLevel::WARN,  __FILE__, __LINE__)
#define LOG_ERROR Logger::LogStream(LogLevel::ERROR, __FILE__, __LINE__)
#define LOG_FATAL Logger::LogStream(LogLevel::FATAL, __FILE__, __LINE__)

#endif
