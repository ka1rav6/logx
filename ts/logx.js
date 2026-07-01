"use strict";
/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.fatal = exports.error = exports.warn = exports.info = exports.trace = void 0;
exports.setLogFile = setLogFile;
const fs = __importStar(require("node:fs"));
const LEVELS = { TRACE: 0, INFO: 1, WARN: 2, ERROR: 3, FATAL: 4 };
const NAMES = { TRACE: 'TRACE', INFO: 'INFO ', WARN: 'WARN ', ERROR: 'ERROR', FATAL: 'FATAL' };
const COLORS = {
    TRACE: '\x1b[36m', INFO: '\x1b[32m', WARN: '\x1b[33m',
    ERROR: '\x1b[31m', FATAL: '\x1b[35m',
};
const RESET = '\x1b[0m';
const envLevel = (process.env.LOG_LEVEL ?? '').toUpperCase();
const minLevel = LEVELS[envLevel] ?? 0;
const colEnv = process.env.LOG_COLOR ?? '';
const useColor = colEnv ? colEnv === '1' || colEnv === 'yes' : process.stdout.isTTY && process.stderr.isTTY;
let logFile = null;
function setLogFile(filePath) {
    if (logFile)
        logFile.close();
    logFile = filePath ? fs.createWriteStream(filePath, { flags: 'a' }) : null;
}
function timestamp() {
    const now = new Date();
    const hh = String(now.getHours()).padStart(2, '0');
    const mm = String(now.getMinutes()).padStart(2, '0');
    const ss = String(now.getSeconds()).padStart(2, '0');
    const ms = String(now.getMilliseconds()).padStart(3, '0');
    return `${hh}:${mm}:${ss}.${ms}`;
}
function callerInfo(depth) {
    const err = new Error();
    if (!err.stack)
        return ['<unknown>', 0];
    const lines = err.stack.split('\n');
    // depth: 0=this fn, 1=log, 2=trace/info/etc, 3=user
    const target = 3 + depth;
    if (target >= lines.length)
        return ['<unknown>', 0];
    const m = lines[target].match(/(?:\/|)([^/]+?):(\d+):\d+\)?$/);
    return m ? [m[1], parseInt(m[2])] : ['<unknown>', 0];
}
function write(level, msg, skip) {
    if (LEVELS[level] < minLevel)
        return;
    const [file, line] = callerInfo(skip);
    const ts = timestamp();
    const label = `[${ts}][${NAMES[level]}] ${file}:${line} -> ${msg}`;
    if (logFile) {
        logFile.write(label + '\n');
    }
    else {
        const out = LEVELS[level] >= LEVELS.ERROR ? process.stderr : process.stdout;
        if (useColor) {
            out.write(COLORS[level] + label + RESET + '\n');
        }
        else {
            out.write(label + '\n');
        }
    }
    if (level === 'FATAL')
        process.exit(1);
}
const trace = (msg) => write('TRACE', msg, 0);
exports.trace = trace;
const info = (msg) => write('INFO', msg, 0);
exports.info = info;
const warn = (msg) => write('WARN', msg, 0);
exports.warn = warn;
const error = (msg) => write('ERROR', msg, 0);
exports.error = error;
const fatal = (msg) => write('FATAL', msg, 0);
exports.fatal = fatal;
