'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

function findTypeScript() {
  const candidates = [process.env.TYPESCRIPT_PATH];
  try { candidates.push(require.resolve('typescript')); } catch {}
  for (const home of [process.env.DEVECO_STUDIO_HOME, process.env.DEVECO_HOME,
    path.join(process.env.ProgramFiles || 'C:/Program Files', 'Huawei/DevEco Studio'),
    'D:/tools/DevEco Studio', '/Applications/DevEco-Studio.app/Contents'].filter(Boolean)) {
    for (const relative of [
      'tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js',
      'tools/hvigor/node_modules/typescript/lib/typescript.js',
      'tools/hvigor/hvigor-ohos-plugin/node_modules/typescript/lib/typescript.js',
      'plugins/codelinter/node_modules/typescript/lib/typescript.js',
      'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js',
    ]) candidates.push(path.join(home, relative));
  }
  for (const sdk of [process.env.OHOS_SDK_HOME, process.env.HARMONYOS_SDK_HOME].filter(Boolean)) {
    for (const relative of ['ets', 'openharmony/ets', 'default/openharmony/ets']) {
      candidates.push(path.join(sdk, relative, 'build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
    }
  }
  for (const candidate of candidates.filter(Boolean)) {
    if (fs.existsSync(candidate)) {
      const compiler = require(candidate);
      if (typeof compiler.transpileModule === 'function') return compiler;
    }
  }
  throw new Error('Set TYPESCRIPT_PATH to an existing local TypeScript compiler.');
}
const ts = findTypeScript();
function execute(source, bindings = {}) {
  const result = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
    reportDiagnostics: true,
  });
  const errors = (result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error);
  assert.equal(errors.length, 0, errors.map(d => ts.flattenDiagnosticMessageText(d.messageText, '\n')).join('\n'));
  const module = { exports: {} };
  vm.runInNewContext(result.outputText, { module, exports: module.exports, ...bindings }, { timeout: 5000 });
  return module.exports;
}
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}
function fixture(initial = {}, hooks = {}) {
  const data = new Map(Object.entries(initial));
  const pref = {
    async get(key, fallback) { return data.has(key) ? data.get(key) : fallback; },
    async put(key, value) { if (hooks.put) await hooks.put(key, value); data.set(key, value); },
    async flush() { if (hooks.flush) await hooks.flush(); },
  };
  const { StatsStore, Stats } = execute(read('model/StatsStore.ets'), {
    require(id) {
      assert.equal(id, '@kit.ArkData');
      return { preferences: { async getPreferences(ctx, name) { assert.equal(name, 'guess_stats'); return pref; } } };
    },
  });
  return { store: StatsStore, Stats, data };
}
function values(stats) { return { played: stats.played, wins: stats.wins, best: stats.best }; }
function page(file, methods, bindings = {}) {
  const source = read(file);
  const bodies = methods.map(name => {
    const start = source.indexOf(`  ${name}(`);
    assert.ok(start >= 0, name);
    const end = source.indexOf('\n  }', start);
    assert.ok(end > start, name);
    return source.slice(start, end + 4);
  });
  return new (execute(`export class Page {\n${bodies.join('\n')}\n}`, bindings).Page)();
}

test('each difficulty counts completed results and keeps only successful minimum opportunities', async () => {
  const { store } = fixture();
  for (const digits of [3, 4, 5]) assert.deepEqual(values(await store.load({}, digits)), { played: 0, wins: 0, best: 0 });
  await store.recordResult({}, 3, false, 6);
  assert.deepEqual(values(await store.load({}, 3)), { played: 1, wins: 0, best: 0 });
  await store.recordResult({}, 3, true, 5);
  await store.recordResult({}, 3, true, 3);
  await store.recordResult({}, 3, true, 4);
  await store.recordResult({}, 4, true, 6);
  await store.recordResult({}, 5, false, 10);
  assert.deepEqual(values(await store.load({}, 3)), { played: 4, wins: 3, best: 3 });
  assert.deepEqual(values(await store.load({}, 4)), { played: 1, wins: 1, best: 6 });
  assert.deepEqual(values(await store.load({}, 5)), { played: 1, wins: 0, best: 0 });
});

test('legacy totals and tutorial preferences are preserved without attributing a difficulty', async () => {
  const old = { played: 20, wins: 15, best: 2, streak: 4, tutorial_done: true, tutorial_voice_enabled: true };
  const { store, data } = fixture(old);
  assert.deepEqual(values(await store.loadLegacy({})), { played: 20, wins: 15, best: 2 });
  for (const digits of [3, 4, 5]) assert.equal((await store.load({}, digits)).played, 0);
  await store.recordResult({}, 4, true, 5);
  for (const [key, value] of Object.entries(old)) assert.equal(data.get(key), value);
  assert.equal(await store.isTutorialDone({}), true);
  assert.equal(await store.isTutorialVoiceEnabled({}), true);
  await store.setTutorialVoiceEnabled({}, false);
  await store.setTutorialDone({});
  assert.equal(await store.isTutorialVoiceEnabled({}), false);
  assert.equal((await store.load({}, 4)).played, 1);
  const restarted = fixture(Object.fromEntries(data));
  assert.deepEqual(values(await restarted.store.load({}, 4)), { played: 1, wins: 1, best: 5 });
});

test('concurrent results do not lose increments and immediate reads await submitted writes', async () => {
  const gate = deferred();
  let first = true;
  const { store } = fixture({}, { async put() { if (first) { first = false; await gate.promise; } } });
  const writes = Array.from({ length: 12 }, (_, i) => store.recordResult({}, 4, i % 2 === 0, 8));
  const latest = store.load({}, 4);
  let loaded = false;
  latest.then(() => { loaded = true; });
  for (let i = 0; i < 20; i++) await Promise.resolve();
  assert.equal(loaded, false);
  gate.resolve();
  await Promise.all(writes);
  assert.deepEqual(values(await latest), { played: 12, wins: 6, best: 8 });
});

test('errors reject the operation without blocking later operations', async () => {
  let fail = true;
  const { store } = fixture({}, { async flush() { if (fail) { fail = false; throw new Error('disk unavailable'); } } });
  await assert.rejects(store.recordResult({}, 4, true, 3), /disk unavailable/);
  await store.recordResult({}, 3, true, 2);
  assert.equal((await store.load({}, 3)).wins, 1);
  await assert.rejects(store.load({}, 6), /Unsupported/);
  await assert.rejects(store.recordResult({}, 2, true, 1), /Unsupported/);
  await assert.rejects(store.recordResult({}, 4, true, 0), /Invalid consumed/);
  await assert.rejects(store.recordResult({}, 4, true, 1.5), /Invalid consumed/);
  assert.equal((await store.load({}, 3)).played, 1);
});

test('malformed saved records report an error instead of overwriting existing data', async () => {
  const raw = JSON.stringify({ played: 2, wins: 3, best: 1 });
  const { store, data } = fixture({ challenge_v2_4: raw });
  await assert.rejects(store.load({}, 4), /Invalid challenge/);
  await assert.rejects(store.recordResult({}, 4, true, 1), /Invalid challenge/);
  assert.equal(data.get('challenge_v2_4'), raw);
  assert.equal((await store.load({}, 3)).played, 0);
});

test('real engine hint and AI consumption is included in best, not just guesses', async () => {
  const { GameEngine } = execute(read('model/GameEngine.ets'));
  const engine = new GameEngine();
  engine.start(4, 8);
  engine.secret = '1234';
  assert.notEqual(engine.useHint([]), '');
  engine.spendAttempt();
  assert.equal(engine.judge('1234').a, 4);
  const { store } = fixture();
  await store.recordResult({}, engine.digits, true, engine.attemptsUsed);
  assert.equal((await store.load({}, 4)).best, 3);
});

test('homepage ignores stale loads on rapid difficulty switches and masks stale numbers', async () => {
  const loads = [];
  const { Stats } = fixture();
  const homepage = page('pages/Index.ets', ['loadStats', 'statsValue', 'solveRateText'], {
    StatsStore: {
      load(ctx, digits) { const d = deferred(); loads.push({ digits, ...d }); return d.promise; },
      async loadLegacy() { return new Stats(); },
    },
  });
  Object.assign(homepage, { selectedDigits: 4, statsRequest: 0, stats: new Stats(),
    getUIContext: () => ({ getHostContext: () => ({}) }) });
  homepage.loadStats();
  assert.equal(homepage.statsValue(5), '--');
  homepage.selectedDigits = 3;
  homepage.loadStats();
  loads[1].resolve({ played: 3, wins: 2, best: 4 });
  for (let i = 0; i < 10; i++) await Promise.resolve();
  assert.equal(homepage.solveRateText(), '67%');
  loads[0].resolve({ played: 20, wins: 20, best: 1 });
  for (let i = 0; i < 10; i++) await Promise.resolve();
  assert.equal(homepage.stats.played, 3);
  homepage.loadStats();
  loads[2].reject(new Error('read failed'));
  for (let i = 0; i < 10; i++) await Promise.resolve();
  assert.equal(homepage.statsError, true);
  assert.equal(homepage.statsValue(3), '--');
  assert.equal(homepage.solveRateText(), '--');
  homepage.loadStats();
  loads[3].resolve(new Stats());
  for (let i = 0; i < 10; i++) await Promise.resolve();
  assert.equal(homepage.statsError, false);
  assert.equal(homepage.statsValue(0), '0');
  assert.equal(homepage.solveRateText(), '--');
});

test('settlement records engine difficulty and total opportunity cost only once', () => {
  const writes = [];
  const game = page('views/GamePage.ets', ['endGame'], {
    StatsStore: { recordResult(...args) { writes.push(args); return Promise.resolve(); } },
  });
  Object.assign(game, { engine: { digits: 5, attemptsUsed: 7 }, statsSaved: false,
    stopTimer() {}, getUIContext: () => ({ getHostContext: () => ({}) }) });
  game.endGame(true);
  game.engine.attemptsUsed = 0;
  game.endGame(true);
  assert.equal(writes.length, 1);
  assert.deepEqual(writes[0].slice(1), [5, true, 7]);
});

test('leaving before automatic submission cancels the pending guess without recording a result', () => {
  const timers = new Map();
  let next = 1;
  let submitted = false;
  const game = page('views/GamePage.ets', ['scheduleAutoSubmit', 'clearAutoSubmit', 'stopTimer', 'aboutToDisappear'], {
    setTimeout(callback) { const id = next++; timers.set(id, callback); return id; },
    clearTimeout(id) { timers.delete(id); },
    clearInterval() {},
  });
  Object.assign(game, { current: '1234', digits: 4, finished: false, autoSubmitId: -1, timerId: -1,
    submit() { submitted = true; } });
  game.scheduleAutoSubmit();
  assert.equal(timers.size, 1);
  game.aboutToDisappear();
  for (const callback of timers.values()) callback();
  assert.equal(timers.size, 0);
  assert.equal(submitted, false);
});

test('record labels, selected difficulty refresh, legacy note and teaching exclusion stay aligned', () => {
  const home = read('pages/Index.ets');
  for (const text of ['挑战局数', '破解率', '累计破解', '最佳破解', '旧版历史汇总', '不纳入以上分难度统计']) {
    assert.ok(home.includes(text), text);
  }
  assert.doesNotMatch(home, /'对局'|'胜率'|'连胜'|stats\.streak/);
  assert.match(home, /this\.selectedDigits = d\.digits;\s*this\.loadStats\(\)/);
  assert.match(home, /我的记录 · /);
  assert.match(home, /StatsStore\.load\(ctx, digits\)/);
  const tutorial = read('views/TutorialPage.ets');
  assert.doesNotMatch(tutorial, /StatsStore\.recordResult/);
  assert.match(tutorial, /中途退出和教学练习不计/);
  const game = read('views/GamePage.ets');
  assert.match(game, /· 消耗 .* 次机会/);
  assert.doesNotMatch(game, / 次尝试/);
});
