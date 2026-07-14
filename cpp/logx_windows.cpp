#include <io.h>

bool Logx::colored() {
    static bool c = []{
        const char* env = std::getenv("LOG_COLOR");
        if (env) return std::string(env) == "1" || std::string(env) == "yes";
        return _isatty(_fileno(stdout)) && _isatty(_fileno(stderr));
    }();
    return c;
}

std::string Logx::LogStream::timestamp() {
    using namespace std::chrono;
    auto now = system_clock::now();
    auto ms = duration_cast<milliseconds>(now.time_since_epoch()) % 1000;
    auto t = system_clock::to_time_t(now);
    std::tm tm;
    localtime_s(&tm, &t);
    std::ostringstream ss;
    ss << std::put_time(&tm, "%H:%M:%S") << '.' << std::setfill('0') << std::setw(3) << ms.count();
    return ss.str();
}
