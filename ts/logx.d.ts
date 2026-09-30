export declare const TRACE = 0;
export declare const INFO = 1;
export declare const WARN = 2;
export declare const ERROR = 3;
export declare const FATAL = 4;
export declare const OFF = 5;
export type Level = 0 | 1 | 2 | 3 | 4 | 5;
export type LevelName = 'TRACE' | 'DEBUG' | 'ALL' | 'INFO' | 'WARN' | 'WARNING' | 'ERROR' | 'ERR' | 'FATAL' | 'CRITICAL' | 'OFF' | 'NONE' | 'SILENT';
/** Append log output to `path`, or pass null to go back to the terminal. */
export declare function setLogFile(path: string | null): void;
/** Raise or lower the threshold. Accepts a constant or a name. */
export declare function setLevel(level: Level | LevelName): void;
export declare function getLevel(): Level;
export declare function setColor(enabled: boolean): void;
export declare function flush(): void;
export declare function log(level: Level, ...args: unknown[]): void;
export declare function trace(...args: unknown[]): void;
export declare function info(...args: unknown[]): void;
export declare function warn(...args: unknown[]): void;
export declare function error(...args: unknown[]): void;
/** Log at FATAL, then exit with status 1. */
export declare function fatal(...args: unknown[]): void;
