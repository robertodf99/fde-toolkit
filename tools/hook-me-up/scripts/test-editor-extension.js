// Tests editor-extension/extension.js with Node, without VS Code: a stand-in for the
// `vscode` module (terminals with process ids) and request files in a private temporary
// folder. Run by `make editor-extension-check` (locally and in CI), which needs node.
'use strict';

const assert = require('assert');
const childProcess = require('child_process');
const fs = require('fs');
const Module = require('module');
const os = require('os');
const path = require('path');

const shown = [];
function terminal(name, processId) {
  return { name, processId, show: (preserveFocus) => shown.push({ name, preserveFocus }) };
}
let terminals = [];
const vscode = {
  window: {
    get terminals() {
      return terminals;
    },
    onDidChangeWindowState: () => ({ dispose() {} }),
  },
};
const load = Module._load;
Module._load = function (request, ...rest) {
  return request === 'vscode' ? vscode : load.call(this, request, ...rest);
};
const extension = require(path.join(__dirname, '..', 'editor-extension', 'extension.js'));

const NAME = 'editor-focus-request.json';
const nonce = (n) => n.toString(16).padStart(32, '0');
const request = (fields = {}) => ({ created: Date.now(), nonce: nonce(1), pids: [4242, 4100], version: 1, ...fields });
const now = Date.now();

let failures = 0;
async function test(name, body) {
  shown.length = 0;
  try {
    await body();
    console.log(`PASS  ${name}`);
  } catch (error) {
    failures += 1;
    console.log(`FAIL  ${name}\n      ${error.message}`);
  }
}

const created = [];
function folder(mode = 0o700) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hmu-extension-'));
  fs.chmodSync(dir, mode);
  created.push(dir);
  return dir;
}
process.on('exit', () => {
  for (const dir of created) {
    fs.rmSync(`${dir}-link`, { force: true });
    fs.chmodSync(dir, 0o700);
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
/** Writes the request as the agent does: a temporary file renamed over the request. */
function write(dir, value) {
  const text = typeof value === 'string' ? value : JSON.stringify(value);
  const temporary = path.join(dir, `.${NAME}.${process.hrtime.bigint()}.tmp`);
  fs.writeFileSync(temporary, text, { mode: 0o600 });
  fs.renameSync(temporary, path.join(dir, NAME));
}
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

(async () => {
  const { parseRequest, readRequest, showTerminal, RequestWatcher } = extension;
  const text = (fields) => JSON.stringify(request(fields));

  await test('a request as the agent writes it is accepted', () => {
    const value = request();
    assert.deepStrictEqual(parseRequest(JSON.stringify(value), now), {
      created: value.created,
      nonce: value.nonce,
      pids: [4242, 4100],
    });
    assert.ok(parseRequest(text({ pids: Array.from({ length: 16 }, (_, i) => i + 1) }), now));
    assert.ok(parseRequest(text({ pids: [0x7fffffff] }), now));
  });

  const refused = {
    'not JSON': '{"created":',
    'an array': '[]',
    null: 'null',
    'a number': '42',
    'another version': text({ version: 2 }),
    'version as text': text({ version: '1' }),
    'an extra key': JSON.stringify({ ...request(), path: '/Users/dev' }),
    'a missing key': JSON.stringify({ created: now, nonce: nonce(1), pids: [1] }),
    'a __proto__ key': text().replace('{', '{"__proto__":{},'),
    'a short nonce': text({ nonce: 'abc' }),
    'an uppercase nonce': text({ nonce: nonce(1).toUpperCase().replace(/0/g, 'A') }),
    'a nonce with other characters': text({ nonce: `${'0'.repeat(31)}g` }),
    'an old request (over 5 s)': text({ created: now - 5001 }),
    'a request from the future': text({ created: now + 1001 }),
    'created as text': text({ created: String(now) }),
    'created not an integer': text({ created: now + 0.5 }),
    'no pids': text({ pids: [] }),
    'seventeen pids': text({ pids: Array.from({ length: 17 }, (_, i) => i + 1) }),
    'pid zero': text({ pids: [0] }),
    'a negative pid': text({ pids: [-1] }),
    'a pid that is not an integer': text({ pids: [1.5] }),
    'a pid as text': text({ pids: ['4242'] }),
    'a pid too large': text({ pids: [0x80000000] }),
    'pids not a list': text({ pids: 4242 }),
  };
  for (const [name, value] of Object.entries(refused)) {
    await test(`refused: ${name}`, () => assert.strictEqual(parseRequest(value, now), null));
  }

  await test('a request file of this user in a private folder is read', () => {
    const dir = folder();
    write(dir, request());
    assert.deepStrictEqual(readRequest(dir, Date.now()).pids, [4242, 4100]);
  });

  await test('a folder others can reach is refused', () => {
    for (const mode of [0o755, 0o750, 0o701]) {
      const dir = folder();
      write(dir, request());
      fs.chmodSync(dir, mode);
      assert.strictEqual(readRequest(dir, Date.now()), null, mode.toString(8));
    }
  });

  await test('a symlinked folder is refused', () => {
    const dir = folder();
    write(dir, request());
    const link = `${dir}-link`;
    fs.symlinkSync(dir, link);
    assert.strictEqual(readRequest(link, Date.now()), null);
  });

  await test('a symlink at the request is refused', () => {
    const dir = folder();
    const elsewhere = path.join(dir, 'elsewhere.json');
    fs.writeFileSync(elsewhere, JSON.stringify(request()), { mode: 0o600 });
    fs.symlinkSync(elsewhere, path.join(dir, NAME));
    assert.strictEqual(readRequest(dir, Date.now()), null);
  });

  await test('a request over 4 KiB is refused', () => {
    const dir = folder();
    write(dir, JSON.stringify(request()) + ' '.repeat(4096));
    assert.strictEqual(readRequest(dir, Date.now()), null);
  });

  await test('a FIFO at the request is refused without blocking', () => {
    const dir = folder();
    childProcess.execFileSync('/usr/bin/mkfifo', [path.join(dir, NAME)]);
    assert.strictEqual(readRequest(dir, Date.now()), null);
  });

  await test('a folder or request that is missing gives nothing', () => {
    assert.strictEqual(readRequest(path.join(folder(), 'gone'), Date.now()), null);
    assert.strictEqual(readRequest(folder(), Date.now()), null);
  });

  await test('the terminal of the nearest pid is shown, taking focus', async () => {
    terminals = [terminal('git', Promise.resolve(300)), terminal('shell', Promise.resolve(4100))];
    assert.strictEqual(await showTerminal([4242, 4100, 300], terminals), true);
    assert.deepStrictEqual(shown, [{ name: 'shell', preserveFocus: false }]);
  });

  await test('a window without the session\'s terminal does nothing', async () => {
    terminals = [terminal('other', Promise.resolve(999)), terminal('none', Promise.resolve(undefined))];
    assert.strictEqual(await showTerminal([4242, 4100], terminals), false);
    assert.deepStrictEqual(shown, []);
  });

  await test('a terminal that never says its process id, or fails to, is skipped', async () => {
    terminals = [
      terminal('stuck', new Promise(() => {})),
      terminal('broken', Promise.reject(new Error('gone'))),
      terminal('shell', Promise.resolve(4100)),
    ];
    const started = Date.now();
    assert.strictEqual(await showTerminal([4242, 4100], terminals), true);
    assert.deepStrictEqual(shown.map((s) => s.name), ['shell']);
    assert.ok(Date.now() - started < 3000);
  });

  await test('the watcher shows the terminal once per request, and never for an old one', async () => {
    const dir = folder();
    terminals = [terminal('git', Promise.resolve(300)), terminal('shell', Promise.resolve(4100))];
    const watcher = new RequestWatcher(dir, () => terminals);
    watcher.start();
    try {
      write(dir, request({ nonce: nonce(7) }));
      await wait(400);
      assert.deepStrictEqual(shown.map((s) => s.name), ['shell']);
      write(dir, request({ nonce: nonce(7) })); // the same request again (a focus event, say)
      await wait(400);
      watcher.schedule();
      await wait(200);
      assert.deepStrictEqual(shown.map((s) => s.name), ['shell']);
      write(dir, request({ nonce: nonce(8), created: Date.now() - 6000 }));
      await wait(400);
      assert.deepStrictEqual(shown.map((s) => s.name), ['shell']);
      write(dir, request({ nonce: nonce(9), pids: [300] }));
      await wait(400);
      assert.deepStrictEqual(shown.map((s) => s.name), ['shell', 'git']);
      assert.ok(fs.existsSync(path.join(dir, NAME)), 'the request is left in place');
    } finally {
      watcher.dispose();
    }
  });

  await test('a request already there when the window starts is acted on', async () => {
    const dir = folder();
    terminals = [terminal('shell', Promise.resolve(4100))];
    write(dir, request({ nonce: nonce(11) }));
    const watcher = new RequestWatcher(dir, () => terminals);
    watcher.start();
    try {
      await wait(300);
      assert.deepStrictEqual(shown.map((s) => s.name), ['shell']);
    } finally {
      watcher.dispose();
    }
  });

  await test('a folder created after the window starts is watched once it exists', async () => {
    const parent = folder();
    const dir = path.join(parent, 'hook-me-up');
    terminals = [terminal('shell', Promise.resolve(4100))];
    const watcher = new RequestWatcher(dir, () => terminals);
    watcher.start();
    try {
      fs.mkdirSync(dir, { mode: 0o700 });
      write(dir, request({ nonce: nonce(12) }));
      watcher.schedule(); // what a focus change does
      await wait(300);
      assert.deepStrictEqual(shown.map((s) => s.name), ['shell']);
    } finally {
      watcher.dispose();
    }
  });

  if (failures > 0) {
    console.log(`test-editor-extension: ${failures} failed`);
    process.exit(1);
  }
  console.log('test-editor-extension: all checks passed');
})();
