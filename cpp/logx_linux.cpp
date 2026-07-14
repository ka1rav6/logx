#include <unistd.h>

bool Logx::colored() {
    static bool c = []{
        const char* env = std::getenv("LOG_COLOR");
        if (env) return std::string(env) == "1" || std::string(env) == "yes";
        return isatty(fileno(stdout)) && isatty(fileno(stderr));
    }();
    return c;
}

std::string Logx::LogStream::timestamp() {
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
