/*
 * Offline regression tests: node --test /absolute/path/to/tests/history-review.test.cjs
 * Uses the installed TypeScript scanner/compiler, as tutorial-voice.test.cjs does.
 * No packages, devices, GUI, network, real timers, or build output are required.
 * Real non-UI ETS methods and lifecycle callbacks run in VM; only engine, native
 * UIContext/scroller and clocks are mocked. DSL wiring has separate source contracts;
 * these tests do not claim to render ArkUI or verify device scroll clamping/layout.
 */
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const root = path.resolve(__dirname, '..');
const etsDir = path.join(root, 'entry/src/main/ets');
const gameSource = fs.readFileSync(path.join(etsDir, 'views/GamePage.ets'), 'utf8');
const historySource = fs.readFileSync(path.join(etsDir, 'common/GuessHistory.ets'), 'utf8');
const tutorialSource = fs.readFileSync(path.join(etsDir, 'views/TutorialPage.ets'), 'utf8');

function findTypeScript() {
  const candidates = [];
  if (process.env.TYPESCRIPT_PATH) candidates.push(process.env.TYPESCRIPT_PATH);
  try { candidates.push(require.resolve('typescript')); } catch { /* Offline only. */ }
  const homes = [
    process.env.DEVECO_STUDIO_HOME,
    process.env.DEVECO_HOME,
    path.join(process.env.ProgramFiles || 'C:/Program Files', 'Huawei/DevEco Studio'),
    'D:/tools/DevEco Studio',
    '/Applications/DevEco-Studio.app/Contents',
  ].filter(Boolean);
  for (const home of homes) {
    for (const relative of [
      'tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js',
      'tools/hvigor/node_modules/typescript/lib/typescript.js',
      'tools/hvigor/hvigor-ohos-plugin/node_modules/typescript/lib/typescript.js',
      'plugins/codelinter/node_modules/typescript/lib/typescript.js',
      'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js',
    ]) candidates.push(path.join(home, relative));
  }
  for (const sdk of [process.env.OHOS_SDK_HOME, process.env.HARMONYOS_SDK_HOME].filter(Boolean)) {
    for (const relative of [
      'ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js',
      'openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js',
      'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js',
    ]) candidates.push(path.join(sdk, relative));
  }
  for (const candidate of candidates) {
    if (!fs.existsSync(candidate)) continue;
    const compiler = require(candidate);
    if (typeof compiler.transpileModule === 'function') return { compiler, location: candidate };
  }
  throw new Error('No installed TypeScript found. Set TYPESCRIPT_PATH to an existing local compiler; do not install packages.');
}

const { compiler: ts, location: compilerLocation } = findTypeScript();

// Scanner balancing ignores braces inside comments/strings. Never parse/rewrite
// declarative ArkUI as TypeScript; only selected ordinary methods are compiled.
function block(source, pattern) {
  const match = pattern.exec(source);
  assert.ok(match, `Missing source contract: ${pattern}`);
  const start = match.index + match[0].lastIndexOf('{');
  const scanner = ts.createScanner(ts.ScriptTarget.Latest, true, ts.LanguageVariant.Standard, source.slice(start));
  let depth = 0;
  for (let token = scanner.scan(); token !== ts.SyntaxKind.EndOfFileToken; token = scanner.scan()) {
    if (token === ts.SyntaxKind.OpenBraceToken) depth++;
    if (token === ts.SyntaxKind.CloseBraceToken && --depth === 0) {
      return { header: source.slice(match.index, start), body: source.slice(start, start + scanner.getTextPos()) };
    }
  }
  throw new Error(`Unclosed block: ${pattern}`);
}

function method(source, name) {
  const selected = block(source, new RegExp(`\\n\\s*(?:private\\s+)?${name}\\([^\\n]*\\)[^\\n{]*\\{`));
  return selected.header + selected.body;
}

function callback(source, event) {
  return block(source, new RegExp(`\\.${event}\\s*\\(\\s*\\([^\\n]*\\)\\s*=>\\s*\\{`)).body;
}

function compile(source, filename) {
  const parsed = ts.createSourceFile(filename, source, ts.ScriptTarget.Latest, true);
  assert.equal(parsed.parseDiagnostics.length, 0,
    parsed.parseDiagnostics.map(d => ts.flattenDiagnosticMessageText(d.messageText, '\n')).join('\n'));
  const result = ts.transpileModule(source, {
    fileName: filename,
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
    reportDiagnostics: true,
  });
  const errors = (result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error);
  assert.equal(errors.length, 0, errors.map(d => ts.flattenDiagnosticMessageText(d.messageText, '\n')).join('\n'));
  return result.outputText;
}

function execute(code, globals = {}) {
  const module = { exports: {} };
  vm.runInNewContext(code, { module, ...globals }, { filename: 'history-review-extracted.ts', timeout: 5000 });
  return module.exports;
}

const layoutClass = block(gameSource, /class HistoryLayoutCallback extends FrameCallback\s*\{/);
const gameMethods = [
  'openHistory', 'closeHistory', 'restoreHistoryOffset', 'returnToLatest',
  'onKey', 'scheduleAutoSubmit', 'clearAutoSubmit', 'submit', 'startGame',
  'stopTimer', 'timeText', 'onForegroundChanged', 'aboutToDisappear',
];
const constants = gameSource.slice(gameSource.indexOf('const KEY_DELETE:'), gameSource.indexOf('@Component'));
const gameCode = compile(`
${constants}
${layoutClass.header}${layoutClass.body}
class ExtractedGame {
${gameMethods.map(name => method(gameSource, name)).join('\n')}
}
module.exports = ExtractedGame;
`, 'game-methods.ts');
const gameCallbacks = Object.fromEntries(['onShown', 'onHidden', 'onBackPressed'].map(event => [
  event, compile(`module.exports = function() ${callback(gameSource, event)};`, `${event}.ts`),
]));
const historyBuilder = block(gameSource, /\n\s*History\(\)\s*\{/).body;
const didScrollCode = compile(`module.exports = function() ${callback(historyBuilder, 'onDidScroll')};`, 'did-scroll.ts');
const rowAreaCode = compile(`module.exports = function(oldArea: Area, area: Area) ${callback(historyBuilder, 'onAreaChange')};`, 'row-area.ts');
const tutorialCode = compile(`class ExtractedTutorial {
${['onPracticeKey', 'clearAutoSubmit', 'updateCoach'].map(name => method(tutorialSource, name)).join('\n')}
}
module.exports = ExtractedTutorial;`, 'tutorial-methods.ts');

class Clock {
  now = 0;
  next = 0; // Exercise valid timer id 0, not only positive ids.
  timers = new Map();
  scheduledTimeouts = 0;
  setTimeout = (callback, delay) => {
    this.scheduledTimeouts++;
    return this.add(callback, delay, 0);
  };
  setInterval = (callback, delay) => this.add(callback, delay, Number(delay));
  clearTimeout = id => { this.timers.delete(id); };
  clearInterval = id => { this.timers.delete(id); };
  add(callback, delay, interval) {
    const id = this.next++;
    this.timers.set(id, { at: this.now + Number(delay), callback, interval });
    return id;
  }
  advance(ms) {
    const target = this.now + ms;
    let steps = 0;
    for (;;) {
      const next = [...this.timers.entries()]
        .filter(([, timer]) => timer.at <= target)
        .sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
      if (!next) break;
      assert.ok(++steps < 10000, 'Virtual clock must not loop indefinitely');
      const [id, timer] = next;
      this.now = timer.at;
      if (timer.interval) timer.at += timer.interval;
      else this.timers.delete(id);
      timer.callback();
    }
    this.now = target;
  }
  get timeouts() { return [...this.timers.values()].filter(timer => !timer.interval); }
}

function engineMock() {
  return {
    remaining: 8, starts: [], guesses: [], feedback: { a: 0, b: 0 },
    start(digits, attempts) { this.starts.push([digits, attempts]); this.remaining = attempts; this.guesses = []; },
    judge(guess) {
      this.guesses.push(guess);
      this.remaining--;
      return { index: this.guesses.length, guess, ...this.feedback };
    },
    attemptsLeft() { return this.remaining; },
  };
}

function harness() {
  const clock = new Clock();
  const frames = [];
  const scrolls = [];
  const engine = engineMock();
  const context = { postFrameCallback(frame) { frames.push(frame); } };
  const scroller = {
    offset: 0,
    currentOffset() { return { xOffset: 0, yOffset: this.offset }; },
    scrollTo(options) { scrolls.push({ ...options }); this.offset = options.yOffset; },
    scrollEdge(edge) { assert.equal(edge, 'top'); scrolls.push('top'); this.offset = 0; },
  };
  const globals = {
    FrameCallback: class {}, Edge: { Top: 'top' },
    DIFFICULTIES: [{ digits: 3, attempts: 6 }, { digits: 4, attempts: 8 }, { digits: 5, attempts: 10 }],
    AiAdvice: class {},
    setTimeout: clock.setTimeout, clearTimeout: clock.clearTimeout,
    setInterval: clock.setInterval, clearInterval: clock.clearInterval,
  };
  const Game = execute(gameCode, globals);
  const page = Object.assign(new Game(), {
    engine, digits: 4, current: '', records: [], attemptsLeft: 8, maxAttempts: 8,
    finished: false, win: false, seconds: 0, hintText: '', hintUsed: false,
    statsSaved: false, showAi: false, aiUsesLeft: 2,
    reviewing: false, historyAtTop: true, historyRowHeight: 48,
    inputHistoryOffset: 0, pendingHistoryOffset: -1, historyScroller: scroller,
    active: true, pageVisible: true, appForeground: true, timerId: -1, autoSubmitId: -1,
    getUIContext() { return context; },
    // The persistence/result path is outside this change; record the terminal call.
    endings: [], endGame(win) { this.endings.push(win); this.finished = true; this.stopTimer(); },
    pathStack: { pops: 0, pop() { this.pops++; } },
  });
  const events = Object.fromEntries(Object.entries(gameCallbacks).map(([name, code]) => [name, execute(code, globals)]));
  return {
    page, clock, frames, scrolls, scroller, engine,
    event(name) { return events[name].call(page); },
    didScroll() { execute(didScrollCode).call(page); },
    rowHeight(height) { execute(rowAreaCode).call(page, {}, { height }); },
    flushLayout() {
      for (const frame of frames.splice(0)) { frame.onFrame(); frame.onIdle(); }
    },
  };
}

function enter(page, text = '1234') { for (const key of text) page.onKey(key); }
function roundSnapshot(page) {
  return {
    current: page.current, records: page.records, attempts: page.attemptsLeft,
    seconds: page.seconds, timerId: page.timerId, finished: page.finished, win: page.win,
  };
}

// Behavior tests below execute extracted implementation, never a reimplementation.
test('installed offline compiler parses and transpiles the real selected ETS methods', () => {
  assert.equal(typeof ts.createScanner, 'function');
  console.log(`Offline TypeScript ${ts.version}: ${compilerLocation}`);
  assert.equal(typeof harness().page.restoreHistoryOffset, 'function');
});

for (const missingOffset of [undefined, null]) {
  for (const mode of ['manual', 'auto']) {
    test(`first ${mode} submit tolerates currentOffset returning ${missingOffset}`, () => {
      const h = harness();
      h.scroller.currentOffset = () => missingOffset;
      enter(h.page);
      if (mode === 'manual') h.page.onKey('OK');
      else h.clock.advance(280);
      assert.deepEqual(h.engine.guesses, ['1234']);
      assert.equal(h.page.records.length, 1);
      assert.equal(h.page.current, '');
      assert.equal(h.page.attemptsLeft, 7);
      assert.equal(h.page.pendingHistoryOffset, 0);
      h.flushLayout();
      assert.deepEqual(h.scrolls, [{ xOffset: 0, yOffset: 0 }]);
      assert.equal(h.page.historyAtTop, true);
      h.clock.advance(280);
      assert.equal(h.engine.guesses.length, 1);
    });
  }

  test(`review and scroll state tolerate currentOffset returning ${missingOffset}`, () => {
    const h = harness();
    h.page.records = [{ index: 1, guess: '5678', a: 0, b: 0 }];
    h.scroller.currentOffset = () => missingOffset;
    h.page.openHistory();
    assert.equal(h.page.reviewing, true);
    assert.equal(h.page.inputHistoryOffset, 0);
    h.page.closeHistory();
    h.flushLayout();
    assert.deepEqual(h.scrolls, [{ xOffset: 0, yOffset: 0 }]);
    h.page.historyAtTop = false;
    h.didScroll();
    assert.equal(h.page.historyAtTop, true);
  });
}

for (const draft of ['12', '1234']) {
  test(`review preserves ${draft.length === 4 ? 'full' : 'partial'} draft, records, attempts and running clock`, () => {
    const h = harness();
    h.page.startGame(4);
    h.clock.advance(12000);
    h.page.records = [{ index: 1, guess: '5678', a: 0, b: 0 }];
    h.scroller.offset = 73.5;
    enter(h.page, draft);
    const before = roundSnapshot(h.page);
    h.page.openHistory();
    assert.equal(h.page.reviewing, true);
    assert.equal(h.page.inputHistoryOffset, 73.5);
    assert.equal(h.page.autoSubmitId, -1);
    assert.equal(h.clock.timeouts.length, 0, 'Review cancels the queued full-draft submission');
    assert.deepEqual(roundSnapshot(h.page), before);
    h.clock.advance(2000);
    assert.equal(h.page.seconds, before.seconds + 2, 'Review must not stop or restart the game clock');
    assert.equal(h.page.timerId, before.timerId);
    assert.equal(h.engine.guesses.length, 0);
    assert.equal(h.page.attemptsLeft, before.attempts);
    assert.equal(h.page.current, draft);
    assert.equal(h.page.records, before.records);
    assert.equal(h.page.timeText(), '00:14');
  });
}

test('return from review restores the input offset after layout and never re-arms full-draft auto-submit', () => {
  const h = harness();
  h.scroller.offset = 96.5;
  enter(h.page);
  h.page.openHistory();
  h.scroller.offset = 400;
  const scheduled = h.clock.scheduledTimeouts;
  h.page.closeHistory();
  assert.equal(h.page.reviewing, false);
  assert.equal(h.page.current, '1234');
  assert.equal(h.page.pendingHistoryOffset, 96.5);
  assert.equal(h.scroller.offset, 400, 'Restore must wait for the changed layout');
  assert.equal(h.frames.length, 1);
  h.frames[0].onFrame();
  assert.equal(h.scroller.offset, 400, 'The frame callback must wait until idle');
  h.flushLayout();
  assert.deepEqual(h.scrolls, [{ xOffset: 0, yOffset: 96.5 }]);
  assert.equal(h.page.pendingHistoryOffset, -1);
  assert.equal(h.page.historyAtTop, false);
  h.clock.advance(5000);
  assert.equal(h.clock.scheduledTimeouts, scheduled);
  assert.equal(h.clock.timeouts.length, 0);
  assert.equal(h.engine.guesses.length, 0);
  assert.equal(h.page.attemptsLeft, 8);
  h.page.onKey('OK');
  assert.deepEqual(h.engine.guesses, ['1234'], 'The preserved draft remains manually submittable');
  assert.equal(h.page.attemptsLeft, 7);
});

for (const key of ['DEL', 'OK', '5']) {
  test(`review ignores key ${key} and direct submit without consuming an attempt`, () => {
    const h = harness();
    enter(h.page);
    h.page.openHistory();
    const before = roundSnapshot(h.page);
    h.page.onKey(key);
    h.page.submit();
    h.clock.advance(1000);
    assert.deepEqual(roundSnapshot(h.page), before);
    assert.deepEqual(h.engine.guesses, []);
    assert.equal(h.clock.timeouts.length, 0);
  });
}

test('finished-round review preserves result and returning does not restart clock or submit', () => {
  const h = harness();
  Object.assign(h.page, { finished: true, win: true, seconds: 42, current: '1234', attemptsLeft: 2 });
  const before = roundSnapshot(h.page);
  h.page.openHistory();
  h.page.onKey('DEL');
  h.page.closeHistory();
  h.flushLayout();
  h.clock.advance(5000);
  assert.deepEqual(roundSnapshot(h.page), before);
  assert.equal(h.clock.timers.size, 0);
  assert.equal(h.engine.guesses.length, 0);
});

for (const [offset, expectedTop] of [[-12, true], [0, true], [1, true], [1.01, false], [143.25, false]]) {
  test(`restoreHistoryOffset clamps ${offset} and sets the top threshold after layout`, () => {
    const h = harness();
    h.page.historyAtTop = !expectedTop;
    h.page.restoreHistoryOffset(offset);
    assert.equal(h.page.pendingHistoryOffset, Math.max(0, offset));
    assert.equal(h.scrolls.length, 0);
    h.flushLayout();
    assert.deepEqual(h.scrolls, [{ xOffset: 0, yOffset: Math.max(0, offset) }]);
    assert.equal(h.page.historyAtTop, expectedTop);
    assert.equal(h.page.pendingHistoryOffset, -1);
  });
}

test('returnToLatest cancels a pending restore so an idle callback cannot jump back', () => {
  const h = harness();
  h.scroller.offset = 200;
  h.page.restoreHistoryOffset(300);
  h.page.returnToLatest();
  assert.equal(h.page.pendingHistoryOffset, -1);
  assert.equal(h.page.historyAtTop, true);
  h.flushLayout();
  assert.deepEqual(h.scrolls, ['top']);
  assert.equal(h.scroller.offset, 0);
});

test('queued offset restoration does nothing after the page disappears', () => {
  const h = harness();
  h.page.restoreHistoryOffset(120);
  h.page.aboutToDisappear();
  h.flushLayout();
  assert.equal(h.page.active, false);
  assert.equal(h.page.pageVisible, false);
  assert.deepEqual(h.scrolls, []);
});

test('multiple queued restores settle at the newest target only once', () => {
  const h = harness();
  h.page.restoreHistoryOffset(120);
  h.page.restoreHistoryOffset(240);
  h.flushLayout();
  assert.deepEqual(h.scrolls, [{ xOffset: 0, yOffset: 240 }]);
});

for (const [offset, rowHeight, expected] of [[0, 48, 0], [1, 48, 0], [1.01, 48, 49.01], [110.5, 72, 182.5]]) {
  test(`submit at offset ${offset} follows latest or compensates one measured ${rowHeight}-vp row`, () => {
    const h = harness();
    const old = [{ index: 8, guess: '5678', a: 0, b: 2 }, { index: 7, guess: '9012', a: 1, b: 0 }];
    h.page.records = old;
    h.engine.guesses = Array(8).fill('5678');
    h.scroller.offset = offset;
    h.rowHeight(String(rowHeight));
    h.rowHeight('0'); // A transient zero-size measurement must not erase the last row height.
    h.page.historyAtTop = offset <= 1;
    enter(h.page);
    h.page.onKey('OK');
    assert.equal(h.page.autoSubmitId, -1);
    assert.equal(h.clock.timeouts.length, 0);
    assert.equal(h.page.records.length, 3);
    assert.notEqual(h.page.records, old);
    assert.equal(h.page.records[0].guess, '1234');
    assert.equal(h.page.records[0].index, 9);
    assert.equal(h.page.records[1], old[0]);
    assert.equal(h.page.records[2], old[1]);
    assert.equal(old.length, 2, 'Do not mutate/truncate previous history');
    assert.equal(h.page.current, '');
    assert.equal(h.page.attemptsLeft, 7);
    assert.equal(h.page.pendingHistoryOffset, expected);
    assert.equal(h.scrolls.length, 0);
    h.flushLayout();
    assert.deepEqual(h.scrolls, [{ xOffset: 0, yOffset: expected }]);
    assert.equal(h.page.historyAtTop, expected <= 1);
    h.clock.advance(1000);
    assert.equal(h.engine.guesses.length, 9, 'Manual submission must cancel its delayed duplicate');
  });
}

test('real scroll callback ignores intermediate layout positions and tracks settled scrolling', () => {
  const h = harness();
  h.page.restoreHistoryOffset(100);
  h.scroller.offset = 20;
  h.didScroll();
  assert.equal(h.page.historyAtTop, true);
  h.flushLayout();
  assert.equal(h.page.historyAtTop, false);
  h.scroller.offset = 1;
  h.didScroll();
  assert.equal(h.page.historyAtTop, true);
  h.scroller.offset = 1.01;
  h.didScroll();
  assert.equal(h.page.historyAtTop, false);
});

test('onKey accepts unique digits including leading zero and auto-submits exactly at 280 ms', () => {
  const h = harness();
  enter(h.page, '00123');
  assert.equal(h.page.current, '0123');
  assert.equal(h.clock.timeouts.length, 1);
  h.page.onKey('4');
  assert.equal(h.page.current, '0123');
  h.clock.advance(279);
  assert.deepEqual(h.engine.guesses, []);
  h.clock.advance(1);
  assert.deepEqual(h.engine.guesses, ['0123']);
  assert.equal(h.page.autoSubmitId, -1);
  assert.equal(h.page.current, '');
  assert.equal(h.page.attemptsLeft, 7);
  h.clock.advance(1000);
  assert.equal(h.engine.guesses.length, 1);
});

test('delete cancels the pending full draft; refilling explicitly starts a new delay', () => {
  const h = harness();
  enter(h.page);
  h.clock.advance(100);
  h.page.onKey('DEL');
  assert.equal(h.page.current, '123');
  assert.equal(h.page.autoSubmitId, -1);
  h.clock.advance(1000);
  assert.equal(h.engine.guesses.length, 0);
  h.page.onKey('5');
  h.clock.advance(280);
  assert.deepEqual(h.engine.guesses, ['1235']);
});

test('rescheduling replaces, rather than duplicates, the pending timeout; clearing id 0 is idempotent', () => {
  const h = harness();
  h.page.current = '1234';
  h.page.scheduleAutoSubmit();
  assert.equal(h.page.autoSubmitId, 0);
  h.page.clearAutoSubmit();
  h.page.clearAutoSubmit();
  h.clock.advance(1000);
  assert.equal(h.engine.guesses.length, 0);
  h.page.scheduleAutoSubmit();
  h.clock.advance(100);
  h.page.scheduleAutoSubmit();
  assert.equal(h.clock.timeouts.length, 1);
  h.clock.advance(180);
  assert.equal(h.engine.guesses.length, 0);
  h.clock.advance(100);
  assert.deepEqual(h.engine.guesses, ['1234']);
});

for (const [state, value] of [['reviewing', true], ['pageVisible', false], ['appForeground', false], ['finished', true], ['current', '123']]) {
  test(`delayed callback rechecks ${state} even without a cancellation lifecycle notification`, () => {
    const h = harness();
    enter(h.page);
    h.page[state] = value;
    h.clock.advance(280);
    assert.deepEqual(h.engine.guesses, []);
    assert.equal(h.page.attemptsLeft, 8);
    assert.equal(h.page.autoSubmitId, -1);
    assert.equal(h.clock.timeouts.length, 0);
  });
}

for (const action of ['background', 'hidden', 'disappear']) {
  test(`${action} cancels the delay and returning does not automatically submit the retained draft`, () => {
    const h = harness();
    enter(h.page);
    if (action === 'background') {
      h.page.appForeground = false;
      h.page.onForegroundChanged();
    } else if (action === 'hidden') h.event('onHidden');
    else h.page.aboutToDisappear();
    assert.equal(h.page.autoSubmitId, -1);
    assert.equal(h.clock.timeouts.length, 0);
    assert.equal(h.page.current, '1234');
    assert.equal(h.page.attemptsLeft, 8);
    h.clock.advance(1000);
    h.page.appForeground = true;
    h.page.onForegroundChanged();
    h.page.active = true;
    h.event('onShown');
    assert.equal(h.page.pageVisible, true);
    h.clock.advance(1000);
    assert.deepEqual(h.engine.guesses, []);
    assert.equal(h.clock.timeouts.length, 0);
  });
}

for (const invalid of ['incomplete', 'finished']) {
  test(`direct submit rejects ${invalid} input and clears any pending timeout`, () => {
    const h = harness();
    enter(h.page);
    if (invalid === 'incomplete') h.page.current = '123';
    else h.page.finished = true;
    const before = roundSnapshot(h.page);
    h.page.submit();
    assert.deepEqual(roundSnapshot(h.page), before);
    assert.equal(h.page.autoSubmitId, -1);
    h.clock.advance(1000);
    assert.deepEqual(h.engine.guesses, []);
  });
}

for (const [feedback, remaining, result] of [[{ a: 4, b: 0 }, 8, true], [{ a: 0, b: 0 }, 1, false]]) {
  test(`terminal submission (${result ? 'win' : 'last attempt'}) retains the final history and closes the round`, () => {
    const h = harness();
    h.engine.feedback = feedback;
    h.engine.remaining = remaining;
    enter(h.page);
    h.clock.advance(280);
    assert.deepEqual(h.page.endings, [result]);
    assert.equal(h.page.records.length, 1);
    assert.equal(h.page.records[0].a, feedback.a);
    h.flushLayout();
    assert.equal(h.page.historyAtTop, true);
    h.page.onKey('1');
    assert.equal(h.page.current, '');
  });
}

for (const [requested, digits, attempts] of [[3, 3, 6], [4, 4, 8], [5, 5, 10], [99, 4, 8]]) {
  test(`startGame(${requested}) resets review, draft, history, pending callbacks and the round timer`, () => {
    const h = harness();
    h.page.startGame(4);
    const oldTimer = h.page.timerId;
    h.clock.advance(2000);
    enter(h.page);
    h.page.restoreHistoryOffset(240);
    Object.assign(h.page, {
      reviewing: true, historyAtTop: false, inputHistoryOffset: 160,
      records: [{ index: 1, guess: '5678', a: 0, b: 0 }], finished: true, win: true,
      hintText: 'old hint', hintUsed: true, statsSaved: true, showAi: true, aiUsesLeft: 0,
    });
    h.page.startGame(requested);
    assert.deepEqual(h.engine.starts.at(-1), [digits, attempts]);
    assert.equal(h.page.digits, digits);
    assert.equal(h.page.maxAttempts, attempts);
    assert.equal(h.page.attemptsLeft, attempts);
    assert.equal(h.page.reviewing, false);
    assert.equal(h.page.historyAtTop, true);
    assert.equal(h.page.inputHistoryOffset, 0);
    assert.equal(h.page.pendingHistoryOffset, -1);
    assert.equal(h.page.current, '');
    assert.equal(h.page.records.length, 0);
    assert.equal(h.page.seconds, 0);
    assert.equal(h.page.finished, false);
    assert.equal(h.page.win, false);
    assert.equal(h.page.hintText, '');
    for (const name of ['hintUsed', 'statsSaved', 'showAi']) assert.equal(h.page[name], false, name);
    assert.equal(h.page.aiUsesLeft, 2);
    assert.equal(h.page.autoSubmitId, -1);
    assert.ok(!h.clock.timers.has(oldTimer));
    assert.equal(h.clock.timers.size, 1, 'Exactly the new interval survives');
    h.flushLayout();
    assert.deepEqual(h.scrolls, [], 'Old idle callbacks must not restore a previous round offset');
    h.clock.advance(1000);
    assert.equal(h.page.seconds, 1);
    assert.deepEqual(h.engine.guesses, []);
  });
}

test('hardware back returns from review without navigation or restarting auto-submit', () => {
  const h = harness();
  h.page.startGame(4);
  enter(h.page);
  const timer = h.page.timerId;
  h.page.openHistory();
  assert.equal(h.event('onBackPressed'), true);
  assert.equal(h.page.reviewing, false);
  assert.equal(h.page.current, '1234');
  assert.equal(h.page.pathStack.pops, 0);
  assert.equal(h.page.timerId, timer);
  h.flushLayout();
  h.clock.advance(1000);
  assert.equal(h.engine.guesses.length, 0);
  assert.equal(h.event('onBackPressed'), true);
  assert.equal(h.page.pathStack.pops, 1);
  assert.equal(h.page.timerId, -1);
});

test('tutorial real practice submissions retain all five records, including zero feedback, newest first', () => {
  const clock = new Clock();
  const engine = engineMock();
  const Tutorial = execute(tutorialCode, {
    KEY_DELETE: 'DEL', KEY_SUBMIT: 'OK',
    setTimeout: clock.setTimeout, clearTimeout: clock.clearTimeout,
    practiceClip: (a, b) => ({ id: `practice_${a}_${b}` }),
  });
  const selected = [];
  const page = Object.assign(new Tutorial(), {
    engine, pCurrent: '', pRecords: [], pWon: false, step: 3, practiceSummary: false,
    active: true, visible: true, appForeground: true, autoSubmitTimer: -1,
    selectClip(clip) { selected.push(clip.id); },
  });
  const guesses = ['012', '345', '678', '901', '234'];
  for (const guess of guesses) {
    for (const key of guess) page.onPracticeKey(key);
    clock.advance(280);
  }
  assert.deepEqual(engine.guesses, guesses);
  assert.deepEqual(Array.from(page.pRecords, rec => rec.guess), guesses.slice().reverse());
  assert.equal(page.pRecords.length, 5);
  assert.ok(page.pRecords.every(rec => rec.a === 0 && rec.b === 0));
  assert.match(page.coach, /正位 0，错位 0/);
  assert.deepEqual(selected, Array(5).fill('practice_0_0'));
  assert.equal(clock.timers.size, 0);
});

// Accessibility text is an ordinary TS expression, extracted unchanged from the
// DSL call and evaluated with real record data (including zeros and leading zero).
function callArgument(source, name) {
  const match = new RegExp(`\\.${name}\\s*\\(`).exec(source);
  assert.ok(match, `Missing .${name} call`);
  const start = match.index + match[0].lastIndexOf('(');
  const scanner = ts.createScanner(ts.ScriptTarget.Latest, true, ts.LanguageVariant.Standard, source.slice(start));
  let depth = 0;
  for (let token = scanner.scan(); token !== ts.SyntaxKind.EndOfFileToken; token = scanner.scan()) {
    if (token === ts.SyntaxKind.OpenParenToken) depth++;
    if (token === ts.SyntaxKind.CloseParenToken && --depth === 0) {
      return source.slice(start + 1, start + scanner.getTokenPos());
    }
  }
  throw new Error(`Unclosed call: ${name}`);
}
const recordSource = historySource.slice(historySource.indexOf('export struct HistoryRecord'));
const accessibilityCode = compile(`module.exports = function() { return (${callArgument(recordSource, 'accessibilityText')}); };`, 'record-accessibility.ts');
const stackedCode = compile(`class ExtractedRecord { ${method(recordSource, 'stacked')} }
module.exports = ExtractedRecord;`, 'record-stacked.ts');
for (const [digits, width, fontScale, expected] of [
  [3, 284, 1, false], [4, 284, 1, false], [5, 284, 1, true],
  [5, 287, 1, true], [5, 288, 1, false], [5, 400, 1, false],
  [4, 284, 1.5, true], [5, 400, 2, true], [5, 440, 2, false],
]) {
  test(`history stacked layout: ${digits} digits, width ${width}, font scale ${fontScale}`, () => {
    const Record = execute(stackedCode);
    const row = Object.assign(new Record(), {
      record: { guess: '01234'.slice(0, digits) }, availableWidth: width,
      getUIContext() { return { fp2px: value => value * 2 * fontScale, vp2px: value => value * 2 }; },
    });
    assert.equal(row.stacked(), expected);
  });
}
for (const [a, b] of [[0, 0], [0, 2], [1, 0]]) {
  for (const latest of [false, true]) {
    test(`history accessibility announces guess digits and both counts ${a}/${b}, latest=${latest}`, () => {
      const text = execute(accessibilityCode).call({ record: { index: 5, guess: '0123', a, b }, latest });
      assert.equal(text, `第 5 次，猜测 0 1 2 3，正位 ${a} 个，错位 ${b} 个${latest ? '，最新记录' : ''}`);
    });
  }
}

test('DSL wiring contract: review entry/exit, keyboard replacement, result visibility and latest action', () => {
  const heading = block(gameSource, /\n\s*HistoryHeading\(\)\s*\{/).body;
  const controls = block(gameSource, /\n\s*ReviewControls\(\)\s*\{/).body;
  const header = block(gameSource, /\n\s*Header\(\)\s*\{/).body;
  const footer = block(gameSource, /\n\s*HistoryFooter\(\)\s*\{/).body;
  const result = block(gameSource, /\n\s*ResultOverlay\(\)\s*\{/).body;
  const build = block(gameSource, /\n\s*build\(\)\s*\{/).body;
  assert.match(heading, /if \(this\.reviewing\)\s*\{\s*this\.closeHistory\(\);\s*\} else \{\s*this\.openHistory\(\);/);
  assert.match(header, /if \(this\.reviewing\)\s*\{\s*this\.closeHistory\(\);\s*\} else/);
  assert.match(controls, /\.onClick\(\(\) => this\.closeHistory\(\)\)/);
  assert.match(result, /\.onClick\(\(\) => this\.openHistory\(\)\)/);
  assert.match(footer, /if \(!this\.historyAtTop\)/);
  assert.match(footer, /\.onClick\(\(\) => this\.returnToLatest\(\)\)/);
  assert.match(build, /if \(this\.reviewing\)\s*\{\s*this\.ReviewControls\(\)\s*\} else \{/);
  assert.match(build, /if \(this\.finished && !this\.reviewing\)\s*\{\s*this\.ResultOverlay\(\)/);
});

test('DSL list contract: game and tutorial scroll through all records with shared rows and stable keys', () => {
  const practice = block(tutorialSource, /\n\s*Step3Practice\(\)\s*\{/).body;
  assert.doesNotMatch(tutorialSource, /\.slice\(\s*0\s*,\s*3\s*\)/, 'Practice history must not truncate to three rows');
  for (const [source, records, scroller] of [
    [historyBuilder, 'records', 'historyScroller'],
    [practice, 'pRecords', 'practiceHistoryScroller'],
  ]) {
    assert.match(source, new RegExp(`List\\(\\{ scroller: this\\.${scroller} \\}\\)\\s*\\{\\s*ForEach\\(this\\.${records}\\s*,`));
    assert.match(source, new RegExp(`ListItem\\(\\)\\s*\\{\\s*HistoryRecord\\(\\{ record: rec, latest: rec\\.index === this\\.${records}\\[0\\]\\.index \\}\\)`),
      'Latest must depend on the first record identity, not the stale ForEach callback index');
    assert.match(source, /HistoryColumns\(\)/);
    assert.match(source, /\(rec: GuessRecord\) => rec\.index\.toString\(\)/);
    assert.match(source, /\.scrollBar\(BarState\.Auto\)/);
  }
  assert.match(practice, /\.nestedScroll\(\{ scrollForward: NestedScrollMode\.SELF_FIRST, scrollBackward: NestedScrollMode\.SELF_FIRST \}\)/);
});

test('DSL feedback contract: both layouts render zero counts unconditionally and expose a grouped spoken row', () => {
  const count = block(recordSource, /\n\s*Count\([^\n]*\)\s*\{/).body;
  const build = block(recordSource, /\n\s*build\(\)\s*\{/).body;
  assert.match(count, /^\{\s*Text\(count\.toString\(\)\)/);
  assert.doesNotMatch(count, /\bif\s*\(|\.filter\(/, 'Zero must be rendered, not hidden by a truthiness guard');
  for (const layout of [/if \(!this\.stacked\(\)\)\s*\{/, /if \(this\.stacked\(\)\)\s*\{/]) {
    const body = block(build, layout).body;
    assert.match(body, /this\.Count\(this\.record\.a, true\)/);
    assert.match(body, /this\.Count\(this\.record\.b, false\)/);
    assert.doesNotMatch(body, /if\s*\([^)]*this\.record\.[ab]|\.filter\(/);
  }
  assert.match(build, /\.accessibilityGroup\(true\)/);
  assert.match(historySource, /\.accessibilityText\('次数、猜测数字、正位数量、错位数量；最新在上'\)/);
});
