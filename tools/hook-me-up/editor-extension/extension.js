// Hook Me Up for VS Code (and VS Code Insiders, Cursor and Windsurf): shows a Claude Code
// session's integrated terminal when its Hook Me Up notification is clicked.
//
// The Hook Me Up agent (a macOS menu-bar app) can't reach into an editor, so on a click it
// writes a small request into its private support folder:
//
//   ~/Library/Application Support/hook-me-up/editor-focus-request.json
//   {"created": <ms since 1970>, "nonce": "<32 hex digits>",
//    "pids": [<the session's processes, nearest first>], "version": 1}
//
// Every editor window runs this extension and watches that file; the window with a terminal
// whose process (its shell, usually) is one of those pids shows it, the earliest pid first.
// The other windows do nothing.
//
// A request counts only when it is exactly what the agent writes: a regular file of this
// user (not a link) in a folder of this user that no one else can reach, at most 4 KiB,
// exactly those four keys, 1 to 16 positive integer pids, a nonce of 32 hex digits not seen
// before, and created less than 5 seconds ago. Anything else is ignored. The extension never
// writes, moves or removes the file, has no dependencies, logs nothing and sends nothing
// anywhere.
'use strict';

const vscode = require('vscode');
const fs = require('fs');
const os = require('os');
const path = require('path');

const REQUEST_NAME = 'editor-focus-request.json';
const MAX_BYTES = 4096;
const MAX_AGE_MS = 5000;
// A request from slightly in the future (another clock reading) still counts.
const MAX_SKEW_MS = 1000;
const MAX_PIDS = 16;
const MAX_PID = 0x7fffffff;
const NONCE = /^[0-9a-f]{32}$/;
const KEYS = ['created', 'nonce', 'pids', 'version'];
const PROCESS_ID_TIMEOUT_MS = 1000;
const DEBOUNCE_MS = 50;
// While the folder can't be watched (it doesn't exist yet), try again this often.
const REWATCH_MS = 30000;

/** The agent's support folder, from the user database (as the agent finds it). */
function supportFolder() {
  let home;
  try {
    home = os.userInfo().homedir;
  } catch {
    home = os.homedir();
  }
  return path.join(home, 'Library', 'Application Support', 'hook-me-up');
}

/** The request in `text` when it is exactly what the agent writes, at time `now`; else null. */
function parseRequest(text, now) {
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    return null;
  }
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  const keys = Object.keys(value).sort();
  if (keys.length !== KEYS.length || keys.some((key, index) => key !== KEYS[index])) return null;
  const { created, nonce, pids, version } = value;
  if (version !== 1) return null;
  if (typeof nonce !== 'string' || !NONCE.test(nonce)) return null;
  if (!Number.isSafeInteger(created) || created <= 0) return null;
  if (created > now + MAX_SKEW_MS || now - created > MAX_AGE_MS) return null;
  if (!Array.isArray(pids) || pids.length < 1 || pids.length > MAX_PIDS) return null;
  if (!pids.every((pid) => Number.isSafeInteger(pid) && pid > 0 && pid <= MAX_PID)) return null;
  return { created, nonce, pids: pids.slice() };
}

/**
 * The request in `folder` at time `now`, or null. The folder must be this user's and closed
 * to everyone else; the file a regular file of this user, opened without following a link
 * (and without blocking), checked again once open, and read only up to the limit.
 */
function readRequest(folder, now) {
  const uid = process.getuid();
  const file = path.join(folder, REQUEST_NAME);
  try {
    const folderInfo = fs.lstatSync(folder);
    if (!folderInfo.isDirectory() || folderInfo.uid !== uid || (folderInfo.mode & 0o077) !== 0) return null;
    const fileInfo = fs.lstatSync(file);
    if (!fileInfo.isFile() || fileInfo.uid !== uid || fileInfo.size > MAX_BYTES) return null;
  } catch {
    return null;
  }
  let descriptor;
  try {
    const { O_RDONLY, O_NOFOLLOW, O_NONBLOCK } = fs.constants;
    descriptor = fs.openSync(file, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
  } catch {
    return null;
  }
  try {
    const info = fs.fstatSync(descriptor);
    if (!info.isFile() || info.uid !== uid || info.size > MAX_BYTES) return null;
    const buffer = Buffer.alloc(MAX_BYTES + 1);
    let length = 0;
    for (;;) {
      const count = fs.readSync(descriptor, buffer, length, buffer.length - length, null);
      if (count <= 0) break;
      length += count;
      if (length === buffer.length) break;
    }
    if (length > MAX_BYTES) return null;
    return parseRequest(buffer.toString('utf8', 0, length), now);
  } catch {
    return null;
  } finally {
    fs.closeSync(descriptor);
  }
}

/** The terminal's process id, or undefined when it has none or doesn't say in time. */
async function terminalProcessId(terminal) {
  let timer;
  const late = new Promise((resolve) => {
    timer = setTimeout(() => resolve(undefined), PROCESS_ID_TIMEOUT_MS);
  });
  try {
    const id = Promise.resolve(terminal.processId).catch(() => undefined);
    return await Promise.race([id, late]);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Shows the terminal whose process is the earliest of `pids` (the nearest to the session);
 * true when there is one. A window without such a terminal does nothing.
 */
async function showTerminal(pids, terminals) {
  const list = Array.from(terminals);
  const ids = await Promise.all(list.map(terminalProcessId));
  for (const pid of pids) {
    const index = ids.indexOf(pid);
    if (index !== -1) {
      list[index].show(false);
      return true;
    }
  }
  return false;
}

/** Watches the support folder and acts on each new request once. */
class RequestWatcher {
  constructor(folder, terminals = () => vscode.window.terminals) {
    this.folder = folder;
    this.terminals = terminals;
    this.seen = new Map(); // nonce -> created
    this.watcher = undefined;
    this.timer = undefined;
    this.rewatch = undefined;
    this.disposed = false;
  }

  start() {
    this.watch();
    this.rewatch = setInterval(() => this.watch(), REWATCH_MS);
    this.schedule();
  }

  watch() {
    if (this.disposed || this.watcher) return;
    try {
      this.watcher = fs.watch(this.folder, { persistent: false }, (event, name) => {
        if (!name || String(name) === REQUEST_NAME) this.schedule();
      });
      this.watcher.on('error', () => this.unwatch());
    } catch {
      this.watcher = undefined;
    }
  }

  unwatch() {
    try {
      if (this.watcher) this.watcher.close();
    } catch {
      // Already closed.
    }
    this.watcher = undefined;
  }

  /** Checks the request shortly (several events for one write become one check). */
  schedule() {
    if (this.disposed) return;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = undefined;
      this.check().catch(() => {});
    }, DEBOUNCE_MS);
  }

  async check() {
    if (this.disposed) return false;
    this.watch(); // the folder may be back
    const now = Date.now();
    for (const [nonce, created] of this.seen) {
      // Older requests are refused anyway.
      if (now - created > 2 * (MAX_AGE_MS + MAX_SKEW_MS)) this.seen.delete(nonce);
    }
    const request = readRequest(this.folder, now);
    if (!request || this.seen.has(request.nonce)) return false;
    this.seen.set(request.nonce, request.created);
    return showTerminal(request.pids, this.terminals());
  }

  dispose() {
    this.disposed = true;
    clearTimeout(this.timer);
    clearInterval(this.rewatch);
    this.unwatch();
  }
}

function activate(context) {
  const watcher = new RequestWatcher(supportFolder());
  watcher.start();
  context.subscriptions.push(watcher);
  // A click focuses the session's window: look again then, in case an event was missed.
  context.subscriptions.push(
    vscode.window.onDidChangeWindowState((state) => {
      if (state.focused) watcher.schedule();
    }),
  );
}

function deactivate() {}

module.exports = { activate, deactivate, parseRequest, readRequest, showTerminal, RequestWatcher };
