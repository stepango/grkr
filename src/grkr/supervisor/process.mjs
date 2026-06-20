/**
 * FFI for process management in supervisor (detached bg workers, pid checks, sleep)
 * Matches design in supervisor-design-final.md
 * macOS / Node compatible
 */

import { spawn, execFileSync } from 'child_process';

export function spawn_detached(cmd, args, opts = {}) {
  const argsArray = args && typeof args.toArray === 'function' ? args.toArray() : (Array.isArray(args) ? args : []);
  const fullOpts = {
    detached: true,
    stdio: 'ignore',
    cwd: process.env.GRKR_ROOT || process.cwd(),
    ...opts,
  };
  try {
    const child = spawn(cmd, argsArray, fullOpts);
    if (child && child.unref) {
      child.unref();
    }
    return child && child.pid ? child.pid : 0;
  } catch (e) {
    return 0;
  }
}

export function is_alive(pid) {
  if (typeof pid !== 'number' || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (_) {
    return false;
  }
}

export function kill(pid, signal = 'SIGTERM') {
  if (typeof pid !== 'number' || pid <= 0) return false;
  try {
    process.kill(pid, signal);
    return true;
  } catch (_) {
    return false;
  }
}

export function sleep_seconds(secs) {
  const s = typeof secs === 'number' ? secs : parseInt(secs, 10) || 0;
  if (s <= 0) return;
  try {
    execFileSync('sleep', [s.toString()], { stdio: 'ignore' });
  } catch (_) {
    // ignore
  }
}

export function utc_timestamp() {
  return new Date().toISOString();
}

export function unix_seconds() {
  return Math.floor(Date.now() / 1000);
}

/** Parse UTC ISO-8601 (e.g. 2026-05-17T12:00:00.000Z) to Unix seconds; -1 if invalid. */
export function parse_utc_iso_to_unix(iso) {
  if (typeof iso !== 'string' || iso.trim() === '') return -1;
  const ms = Date.parse(iso);
  if (Number.isNaN(ms)) return -1;
  return Math.floor(ms / 1000);
}
