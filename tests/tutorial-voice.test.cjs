/*
 * Device-free regression tests; run from the repository root:
 *   node --test tests/tutorial-voice.test.cjs
 * No npm install, device, GUI, network, or generated build files are needed.
 * Uses an already installed TypeScript compiler (DevEco/SDK locations included).
 * For other installations set TYPESCRIPT_PATH to typescript.js or its package dir:
 *   PowerShell: $env:TYPESCRIPT_PATH='C:\path\to\typescript\lib\typescript.js'
 * Real .ets modules are transpiled in memory and executed in node:vm. Only native
 * kits, AVPlayer/ResourceManager, and the loading clock are mocked. This verifies
 * lifecycle/contracts and WAV structure, not audible speech or device behavior.
 */
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const root = path.resolve(__dirname, '..');
const modelDir = path.join(root, 'entry/src/main/ets/model');
const audioDir = path.join(root, 'entry/src/main/resources/rawfile/tutorial/zh-CN');

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
const compiled = new Map();
function loadModel(name, kits = {}, timers = {}) {
  const filename = path.join(modelDir, name + '.ets');
  if (!compiled.has(filename)) {
    const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      fileName: filename.replace(/\.ets$/, '.ts'),
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
      reportDiagnostics: true,
    });
    const errors = (result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error);
    assert.equal(errors.length, 0, errors.map(d => ts.flattenDiagnosticMessageText(d.messageText, '\n')).join('\n'));
    compiled.set(filename, result.outputText);
  }
  const module = { exports: {} };
  const sandbox = {
    module,
    exports: module.exports,
    require(id) {
      assert.ok(Object.hasOwn(kits, id), `Unexpected native/dependency import: ${id}`);
      return kits[id];
    },
    console,
    setTimeout: timers.setTimeout || (() => { throw new Error('Unexpected real timer'); }),
    clearTimeout: timers.clearTimeout || (() => {}),
  };
  vm.runInNewContext(compiled.get(filename), sandbox, { filename, timeout: 5000 });
  return module.exports;
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

// Drain bounded microtask turns; never read or await the implementation's private queue.
async function flush() {
  for (let i = 0; i < 100; i++) await Promise.resolve();
}

class Clock {
  now = 0;
  next = 1;
  timers = new Map();
  setTimeout = (callback, delay) => {
    const id = this.next++;
    this.timers.set(id, { at: this.now + Number(delay), callback });
    return id;
  };
  clearTimeout = id => { this.timers.delete(id); };
  advance(ms) {
    const target = this.now + ms;
    for (;;) {
      const next = [...this.timers.entries()]
        .filter(([, timer]) => timer.at <= target)
        .sort((a, b) => a[1].at - b[1].at)[0];
      if (!next) break;
      this.now = next[1].at;
      this.timers.delete(next[0]);
      next[1].callback();
    }
    this.now = target;
  }
}

const audio = {
  StreamUsage: { STREAM_USAGE_GAME: 5 },
  InterruptHint: { INTERRUPT_HINT_PAUSE: 2, INTERRUPT_HINT_RESUME: 1, INTERRUPT_HINT_STOP: 3 },
  AudioStreamDeviceChangeReason: { REASON_OLD_DEVICE_UNAVAILABLE: 2, REASON_NEW_DEVICE_AVAILABLE: 1 },
};

function harness(options = {}) {
  const clock = new Clock();
  const events = [];
  const states = [];
  const players = [];
  const open = new Map();
  const descriptors = new Map();
  let nextFd = 100;
  let getCount = 0;
  const resources = {
    async getRawFd(rawPath) {
      const call = getCount++;
      events.push({ kind: 'getRawFd', path: rawPath, call });
      if (options.getGate && call === 0) await options.getGate.promise;
      if (options.getError && call === 0) throw new Error('getRawFd failed');
      assert.ok(!open.has(rawPath), `Opened ${rawPath} again before closing its previous descriptor`);
      const fd = { fd: nextFd++, offset: 17, length: 4096 };
      open.set(rawPath, fd);
      descriptors.set(fd.fd, rawPath);
      events.push({ kind: 'opened', path: rawPath, fd: fd.fd });
      return fd;
    },
    async closeRawFd(rawPath) {
      assert.ok(open.has(rawPath), `Duplicate close or unopened path: ${rawPath}`);
      const fd = open.get(rawPath);
      events.push({ kind: 'closeRawFd', path: rawPath, fd: fd.fd });
      open.delete(rawPath);
    },
  };
  class Player {
    state = 'idle';
    listeners = new Map();
    calls = { prepare: 0, play: 0, pause: 0, release: 0 };
    source = undefined;
    audioRendererInfo = undefined;
    constructor(index) { this.index = index; }
    on(name, callback) {
      const callbacks = this.listeners.get(name) || [];
      callbacks.push(callback);
      this.listeners.set(name, callbacks);
    }
    off(name) { this.listeners.delete(name); }
    emit(name, value) {
      for (const callback of this.listeners.get(name) || []) callback(value);
    }
    stateChange(state) {
      this.state = state;
      events.push({ kind: 'state', player: this.index, state });
      this.emit('stateChange', state);
    }
    set fdSrc(source) {
      assert.equal(this.state, 'idle', 'fdSrc must be assigned in idle state');
      assert.ok(descriptors.has(source.fd), 'fdSrc must reference an acquired resource');
      const live = open.get(descriptors.get(source.fd));
      assert.equal(live?.fd, source.fd, 'fdSrc must not reference a closed descriptor');
      this.source = source;
      events.push({ kind: 'fdSrc', player: this.index, fd: source.fd });
      if (options.autoInitialize !== false) this.stateChange('initialized');
    }
    get fdSrc() { return this.source; }
    async prepare() {
      assert.equal(this.state, 'initialized', 'prepare must follow initialized');
      this.calls.prepare++;
      events.push({ kind: 'prepare', player: this.index });
      if (options.prepareGate && this.index === 0) await options.prepareGate.promise;
      if (options.prepareError && this.index === 0) throw new Error('prepare failed');
      this.stateChange('prepared');
    }
    async play() {
      assert.ok(['prepared', 'paused'].includes(this.state), `play called from ${this.state}`);
      assert.equal(open.get(descriptors.get(this.source.fd))?.fd, this.source.fd, 'play must keep its resource open');
      this.calls.play++;
      events.push({ kind: 'play', player: this.index, fd: this.source.fd });
      const playGate = options.playGates?.[this.index] || (this.index === 0 ? options.playGate : undefined);
      if (playGate && this.calls.play === (options.playGateCall || 1)) {
        await playGate.promise;
        events.push({ kind: 'playSettled', player: this.index });
      }
      if (options.playError && this.index === 0) throw new Error('play failed');
      // Native state callbacks can arrive after release; intentionally deliver
      // that late event rather than letting the mock hide a generation bug.
      this.stateChange('playing');
    }
    async pause() {
      assert.equal(this.state, 'playing');
      this.calls.pause++;
      events.push({ kind: 'pause', player: this.index });
      this.stateChange('paused');
    }
    async release() {
      this.calls.release++;
      assert.equal(this.calls.release, 1, 'AVPlayer released more than once');
      events.push({ kind: 'release', player: this.index });
      if (options.releaseGate && this.index === 0) await options.releaseGate.promise;
      this.stateChange('released');
      events.push({ kind: 'released', player: this.index });
    }
  }
  const kits = {
    '@kit.MediaKit': { media: { async createAVPlayer() {
      events.push({ kind: 'createAVPlayer' });
      if (options.createGate && players.length === 0) await options.createGate.promise;
      if (options.createError) throw new Error('createAVPlayer failed');
      const player = new Player(players.length);
      players.push(player);
      return player;
    } } },
    '@kit.AudioKit': { audio },
    '@kit.LocalizationKit': { resourceManager: {} },
  };
  const { TutorialVoicePlayer } = loadModel('TutorialVoicePlayer', kits, clock);
  const voice = new TutorialVoicePlayer(resources, state => states.push(state));
  return { voice, players, resources, clock, events, states, open };
}

function latest(h) { return h.states.at(-1); }
function assertClean(h) {
  assert.equal(h.open.size, 0, 'All rawfile descriptors must be closed');
  assert.equal(h.clock.timers.size, 0, 'No loading watchdog may remain');
  for (const player of h.players) {
    assert.equal(player.calls.release, 1, 'Every created player must be released once');
    if (player.source) {
      const released = h.events.findIndex(e => e.kind === 'released' && e.player === player.index);
      const closed = h.events.findIndex(e => e.kind === 'closeRawFd' && e.fd === player.source.fd);
      assert.ok(released >= 0 && closed > released, 'Release player before closing its rawfile');
    }
  }
}
async function dispose(h) {
  h.voice.dispose();
  await flush();
  assertClean(h);
}

const narration = loadModel('TutorialNarration');
const { GameEngine } = loadModel('GameEngine');

// Only inspect selected non-UI method bodies; ordinary TypeScript cannot parse
// ArkUI's declarative build DSL. Token balancing ignores comments/string braces.
const pageSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/views/TutorialPage.ets'), 'utf8');
function pageBlock(pattern) {
  const match = pattern.exec(pageSource);
  assert.ok(match, `Missing TutorialPage lifecycle contract: ${pattern}`);
  const start = match.index + match[0].lastIndexOf('{');
  const scanner = ts.createScanner(ts.ScriptTarget.Latest, true, ts.LanguageVariant.Standard, pageSource.slice(start));
  let depth = 0;
  for (let token = scanner.scan(); token !== ts.SyntaxKind.EndOfFileToken; token = scanner.scan()) {
    if (token === ts.SyntaxKind.OpenBraceToken) depth++;
    if (token === ts.SyntaxKind.CloseBraceToken && --depth === 0) {
      const text = pageSource.slice(start, start + scanner.getTextPos());
      const parsed = ts.createSourceFile('page-contract.ts', `function contract() ${text}`, ts.ScriptTarget.Latest, true);
      assert.equal(parsed.parseDiagnostics.length, 0, 'Selected method must parse without rewriting its implementation');
      return parsed.statements[0].body;
    }
  }
  throw new Error(`Unclosed block: ${pattern}`);
}
function pageMethod(name) {
  return pageBlock(new RegExp(`\\n\\s*(?:private\\s+)?${name}\\([^\\n]*\\)[^\\n{]*\\{`));
}
function walk(node, visit) {
  visit(node);
  ts.forEachChild(node, child => { walk(child, visit); });
}
function propertyNames(node) {
  const names = new Set();
  walk(node, child => {
    if (ts.isPropertyAccessExpression(child)) names.add(child.name.text);
  });
  return names;
}
function calledNames(node) {
  const names = new Set();
  walk(node, child => {
    if (ts.isCallExpression(child) && ts.isPropertyAccessExpression(child.expression)) names.add(child.expression.name.text);
  });
  return names;
}


test('TutorialPage static contract: playback entry points guard screen reader and foreground', () => {
  for (const name of ['selectClip', 'togglePlayback', 'replayVoice']) {
    const body = pageMethod(name);
    const guardProperties = new Set();
    walk(body, node => {
      if (ts.isIfStatement(node)) {
        for (const property of propertyNames(node.expression)) guardProperties.add(property);
      }
    });
    for (const property of ['screenReader', 'appForeground', 'visible']) {
      assert.ok(guardProperties.has(property), `${name} must guard ${property}`);
    }
  }
  const foreground = pageMethod('onForegroundChanged');
  assert.ok(propertyNames(foreground).has('appForeground'));
  assert.ok(calledNames(foreground).has('stop'));
  const screenReader = pageBlock(/screenReaderChanged\s*:[^\n]*=>\s*\{/);
  assert.ok(calledNames(screenReader).has('stop'), 'Enabling screen reader stops current narration');
});

test('TutorialPage static contract: pending auto-submit is cancelled on exit, navigation and background', () => {
  for (const name of ['aboutToDisappear', 'onForegroundChanged', 'onPrevious', 'onPrimary', 'finish']) {
    assert.ok(calledNames(pageMethod(name)).has('clearAutoSubmit'), `${name} must cancel pending submission`);
  }
  const hidden = pageBlock(/\.onHidden\s*\(\s*\(\s*\)\s*=>\s*\{/);
  assert.ok(calledNames(hidden).has('clearAutoSubmit'));
  assert.ok(calledNames(hidden).has('stop'));
  for (const name of ['aboutToDisappear', 'finish']) {
    assert.ok(calledNames(pageMethod(name)).has('dispose'), `${name} must dispose voice`);
  }
  assert.ok(calledNames(pageMethod('onPracticeKey')).has('clearAutoSubmit'));
});

test('TutorialPage static contract: onPrimary never persists an implicit voice preference', () => {
  const calls = calledNames(pageMethod('onPrimary'));
  assert.ok(!calls.has('chooseVoice'), 'Next must not call chooseVoice(false) and overwrite the saved preference');
  assert.ok(!calls.has('setTutorialVoiceEnabled'), 'Next must not directly persist a voice preference');
});

test('TutorialPage static contract: narration uses public feedback, never the secret answer', () => {
  for (const name of ['selectClip', 'selectStepClip', 'updateCoach']) {
    assert.ok(!propertyNames(pageMethod(name)).has('secret'), `${name} must not access the secret`);
  }
  for (const name of ['TutorialNarration', 'TutorialVoicePlayer']) {
    const source = fs.readFileSync(path.join(modelDir, name + '.ets'), 'utf8');
    const ast = ts.createSourceFile(name + '.ts', source, ts.ScriptTarget.Latest, true);
    assert.ok(!propertyNames(ast).has('secret'), `${name} must not access the secret`);
    const imports = ast.statements.filter(ts.isImportDeclaration).map(node => node.moduleSpecifier.text);
    assert.ok(!imports.some(id => /GameEngine/.test(id)), `${name} must not depend on game secrets`);
  }
});

test('offline compiler loads real ETS modules', () => {
  assert.equal(typeof ts.transpileModule, 'function');
  assert.equal(typeof GameEngine.computeAB, 'function');
  console.log(`Offline TypeScript ${ts.version}: ${compilerLocation}`);
});

test('every subtitle has exactly one nonempty PCM WAV and every WAV has a subtitle', () => {
  const clips = narration.TUTORIAL_CLIPS;
  assert.ok(clips.length > 0);
  assert.equal(new Set(clips.map(c => c.id)).size, clips.length, 'Clip ids must be unique');
  const expected = Array.from(clips, c => c.id + '.wav').sort();
  const actual = fs.readdirSync(audioDir).filter(f => /\.wav$/i.test(f)).sort();
  assert.deepEqual(actual, expected);
  for (const clip of clips) {
    assert.match(clip.id, /^[a-z0-9_]+$/);
    assert.ok(clip.text.trim().length > 0, `${clip.id} lacks subtitles`);
    assert.equal(narration.tutorialClip(clip.id).text, clip.text);
    const wav = fs.readFileSync(path.join(audioDir, clip.id + '.wav'));
    assert.equal(wav.toString('ascii', 0, 4), 'RIFF', clip.id);
    assert.equal(wav.toString('ascii', 8, 12), 'WAVE', clip.id);
    assert.equal(wav.readUInt32LE(4) + 8, wav.length, `${clip.id}: truncated RIFF`);
    let format;
    let data;
    for (let offset = 12; offset + 8 <= wav.length;) {
      const tag = wav.toString('ascii', offset, offset + 4);
      const size = wav.readUInt32LE(offset + 4);
      assert.ok(offset + 8 + size <= wav.length, `${clip.id}: truncated ${tag} chunk`);
      if (tag === 'fmt ') format = wav.subarray(offset + 8, offset + 8 + size);
      if (tag === 'data') data = wav.subarray(offset + 8, offset + 8 + size);
      offset += 8 + size + (size % 2);
    }
    assert.ok(format?.length >= 16 && data?.length > 0, `${clip.id}: missing format/audio`);
    assert.equal(format.readUInt16LE(0), 1, `${clip.id}: expected PCM`);
    const channels = format.readUInt16LE(2);
    const sampleRate = format.readUInt32LE(4);
    const byteRate = format.readUInt32LE(8);
    const blockAlign = format.readUInt16LE(12);
    const bits = format.readUInt16LE(14);
    assert.ok(channels > 0 && sampleRate > 0 && bits > 0);
    assert.equal(blockAlign, channels * bits / 8, clip.id);
    assert.equal(byteRate, sampleRate * blockAlign, clip.id);
    assert.equal(data.length % blockAlign, 0, clip.id);
    assert.ok(data.length / byteRate > 0.1, `${clip.id}: unexpectedly short audio`);
    assert.ok(data.some(byte => byte !== 0), `${clip.id}: all-zero audio`);
  }
});

test('all 518400 three-digit secret/guess pairs select valid feedback, excluding impossible 2A1B', () => {
  const values = [];
  for (let a = 0; a < 10; a++) for (let b = 0; b < 10; b++) for (let c = 0; c < 10; c++) {
    if (a !== b && a !== c && b !== c) values.push(`${a}${b}${c}`);
  }
  assert.equal(values.length, 720);
  const combinations = new Set();
  for (const secret of values) for (const guess of values) {
    const [a, b] = GameEngine.computeAB(secret, guess);
    combinations.add(`${a}_${b}`);
  }
  assert.deepEqual([...combinations].sort(), ['0_0', '0_1', '0_2', '0_3', '1_0', '1_1', '1_2', '2_0', '3_0']);
  for (const pair of combinations) {
    const [a, b] = pair.split('_').map(Number);
    const clip = narration.practiceClip(a, b);
    assert.equal(clip.id, `practice_${pair}`, 'Must not silently fall back to the goal clip');
    assert.ok(clip.text.trim());
    assert.ok(fs.existsSync(path.join(audioDir, clip.id + '.wav')));
  }
  assert.deepEqual(Array.from(GameEngine.computeAB('5234', '5346')), [1, 2]);
});

test('play -> initialized -> prepared -> playing configures renderer and preserves fd metadata', async () => {
  const h = harness();
  h.voice.play('goal');
  assert.equal(latest(h), 'loading');
  await flush();
  assert.deepEqual(h.states, ['loading', 'playing']);
  const p = h.players[0];
  assert.deepEqual(h.events.filter(e => e.kind === 'state').map(e => e.state), ['initialized', 'prepared', 'playing']);
  assert.equal(p.audioRendererInfo.usage, audio.StreamUsage.STREAM_USAGE_GAME);
  assert.equal(p.audioRendererInfo.rendererFlags, 0);
  assert.deepEqual({ ...p.source }, { fd: 100, offset: 17, length: 4096 });
  assert.equal(h.clock.timers.size, 0);
  await dispose(h);
});

test('pause/resume keeps the same player and descriptor; pause is not a restart', async () => {
  const h = harness();
  h.voice.play('demo');
  await flush();
  const p = h.players[0];
  h.voice.pause();
  await flush();
  assert.equal(latest(h), 'paused');
  assert.equal(h.open.size, 1);
  h.clock.advance(30000);
  h.voice.resume();
  await flush();
  assert.equal(latest(h), 'playing');
  assert.equal(h.players.length, 1);
  assert.equal(p.calls.pause, 1);
  assert.equal(p.calls.play, 2);
  assert.equal(h.events.filter(e => e.kind === 'getRawFd').length, 1);
  await dispose(h);
});

test('same-generation repeated resume starts native playback only once while pending', async () => {
  const gate = deferred();
  const h = harness({ playGate: gate, playGateCall: 2 });
  h.voice.play('goal');
  await flush();
  h.voice.pause();
  await flush();
  const p = h.players[0];
  assert.equal(p.state, 'paused');
  h.voice.resume();
  h.voice.resume();
  await flush();
  h.voice.resume();
  await flush();
  assert.equal(p.state, 'paused', 'Native resume is still pending');
  assert.equal(p.calls.play, 2, 'One initial play plus exactly one pending resume');
  gate.resolve();
  await flush();
  assert.equal(latest(h), 'playing');
  h.voice.pause();
  await flush();
  h.voice.resume();
  await flush();
  assert.equal(p.calls.play, 3, 'Settled startup must permit a later explicit resume');
  await dispose(h);
});

test('old-generation play resolve cannot clear the new generation startup guard', async () => {
  const oldGate = deferred();
  const newGate = deferred();
  const h = harness({ playGates: [oldGate, newGate], playGateCall: 2 });
  h.voice.play('goal');
  await flush();
  h.voice.pause();
  await flush();
  h.voice.resume();
  await flush();
  const old = h.players[0];
  assert.equal(old.calls.play, 2);
  assert.equal(old.state, 'paused');

  h.voice.play('demo');
  await flush();
  assert.equal(old.calls.release, 1, 'New generation starts without waiting for old native play');
  const current = h.players[1];
  assert.equal(current.state, 'playing');
  h.voice.pause();
  await flush();
  h.voice.resume();
  await flush();
  assert.equal(current.calls.play, 2);
  assert.equal(current.state, 'paused');
  const states = h.states.slice();

  oldGate.resolve();
  await flush();
  assert.deepEqual(h.states, states, 'Old playing event must remain stale');
  h.voice.resume();
  h.voice.resume();
  await flush();
  assert.equal(current.calls.play, 2, 'Old resolve must not clear the new pending-start guard');
  assert.equal(current.state, 'paused', 'New native resume remains pending');
  newGate.resolve();
  await flush();
  assert.equal(latest(h), 'playing');
  await dispose(h);
});

// Execute only the real, ordinary lifecycle method body, not ArkUI rendering.
// This complements the static contracts without copying page stop logic.
function runPageLifecycle(body, h) {
  const source = 'module.exports = function lifecycle() ' + ts.createPrinter().printNode(
    ts.EmitHint.Unspecified, body, body.getSourceFile());
  const result = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  });
  const module = { exports: {} };
  vm.runInNewContext(result.outputText, { module }, { timeout: 5000 });
  let cancelled = false;
  const page = {
    appForeground: false,
    visible: true,
    voice: h.voice,
    clearAutoSubmit() { cancelled = true; },
  };
  module.exports.call(page);
  assert.ok(cancelled, 'The real lifecycle callback must cancel pending submission');
}

for (const origin of ['prepared', 'resume']) {
  for (const action of ['stop', 'dispose', 'background', 'hidden', 'call-pause', 'call-stop', 'headphone-disconnect']) {
    for (const settlement of ['resolve', 'reject']) {
      test(`pending native play from ${origin}: ${action} releases before late ${settlement}`, async () => {
        const gate = deferred();
        let settled = false;
        gate.promise.then(() => { settled = true; }, () => { settled = true; });
        const h = harness({ playGate: gate, playGateCall: origin === 'resume' ? 2 : 1 });
        h.voice.play('goal');
        await flush();
        const p = h.players[0];
        if (origin === 'resume') {
          assert.equal(latest(h), 'playing');
          h.voice.pause();
          await flush();
          assert.equal(latest(h), 'paused');
          h.voice.resume();
          await flush();
          assert.equal(p.calls.play, 2, 'Resume must have invoked native play');
          assert.equal(p.state, 'paused', 'Native resume has not settled yet');
        } else {
          assert.equal(p.calls.play, 1, 'Prepared must have invoked native play');
          assert.equal(p.state, 'prepared', 'Native initial play has not settled yet');
          assert.equal(latest(h), 'loading');
        }
        assert.equal(settled, false);
        if (action === 'background') runPageLifecycle(pageMethod('onForegroundChanged'), h);
        else if (action === 'hidden') runPageLifecycle(pageBlock(/\.onHidden\s*\(\s*\(\s*\)\s*=>\s*\{/), h);
        else if (action === 'call-pause' || action === 'call-stop') {
          p.emit('audioInterrupt', {
            hintType: action === 'call-pause'
              ? audio.InterruptHint.INTERRUPT_HINT_PAUSE : audio.InterruptHint.INTERRUPT_HINT_STOP,
          });
        } else if (action === 'headphone-disconnect') {
          p.emit('audioOutputDeviceChangeWithInfo', {
            changeReason: audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE,
          });
        } else h.voice[action]();
        await flush();

        // Critical regression assertion: do NOT settle playGate before checking
        // release/close. Awaiting native play in the queue fails right here.
        assert.equal(settled, false, 'Cleanup is tested while native play is still pending');
        assert.equal(p.calls.release, 1, 'Cleanup must not wait for the native play promise');
        assertClean(h);
        assert.equal(latest(h), 'idle');
        const states = h.states.slice();
        const playCalls = p.calls.play;

        // Even a playing event delivered before the promise settles is stale.
        p.emit('stateChange', 'playing');
        if (settlement === 'resolve') gate.resolve();
        else gate.reject(new Error('native play rejected after cancellation'));
        await flush();
        assert.equal(settled, true);
        assert.deepEqual(h.states, states, 'Late playing/rejection must not restore playing or report a new error');
        p.emit('audioInterrupt', { hintType: audio.InterruptHint.INTERRUPT_HINT_RESUME });
        h.voice.resume();
        h.clock.advance(30000);
        await flush();
        assert.deepEqual(h.states, states);
        assert.equal(p.calls.play, playCalls, 'No automatic replay after cancellation');
        assert.equal(h.players.length, 1);
        assertClean(h);
        await dispose(h);
      });
    }
  }
}

test('pending native initial play times out and releases before its promise rejects', async () => {
  const gate = deferred();
  const h = harness({ playGate: gate });
  h.voice.play('goal');
  await flush();
  assert.equal(h.players[0].calls.play, 1);
  h.clock.advance(8000);
  await flush();
  assert.equal(latest(h), 'error');
  assertClean(h);
  const states = h.states.slice();
  gate.reject(new Error('late timeout rejection'));
  await flush();
  assert.deepEqual(h.states, states);
  await dispose(h);
});

test('rapid synchronous replay/switch only starts the final generation', async () => {
  const h = harness();
  h.voice.play('goal');
  h.voice.play('goal');
  h.voice.play('demo');
  await flush();
  assert.equal(h.players.length, 1);
  assert.equal(h.players[0].calls.play, 1);
  assert.deepEqual(h.events.filter(e => e.kind === 'getRawFd').map(e => e.path), ['tutorial/zh-CN/demo.wav']);
  await dispose(h);
});

for (const nextId of ['goal', 'demo']) {
  test(`active replay/switch to ${nextId} waits for old release and closes only the old fd`, async () => {
    const gate = deferred();
    const h = harness({ releaseGate: gate });
    h.voice.play('goal');
    await flush();
    const old = h.players[0];
    h.voice.play(nextId);
    await flush();
    assert.equal(h.players.length, 1, 'Do not create/open replacement before release finishes');
    assert.equal(h.open.size, 1, 'Old fd must remain open while release is pending');
    const snapshot = h.states.slice();
    old.emit('stateChange', 'prepared');
    old.emit('stateChange', 'playing');
    old.emit('stateChange', 'completed');
    old.emit('error', new Error('stale player'));
    await flush();
    assert.deepEqual(h.states, snapshot, 'Stale events must not update current UI state');
    gate.resolve();
    await flush();
    assert.equal(h.players.length, 2);
    assert.equal(old.calls.play, 1);
    assert.equal(h.players[1].calls.play, 1);
    const closed = h.events.findIndex(e => e.kind === 'closeRawFd' && e.fd === 100);
    const opened = h.events.findIndex(e => e.kind === 'opened' && e.fd === 101);
    assert.ok(closed >= 0 && opened > closed, 'Path-based old close must precede new open');
    assert.equal(h.open.get(`tutorial/zh-CN/${nextId}.wav`).fd, 101);
    await dispose(h);
  });
}

for (const action of ['stop', 'dispose']) {
  test(`getRawFd resolving after ${action} is closed without assigning or playing it`, async () => {
    const gate = deferred();
    const h = harness({ getGate: gate });
    h.voice.play('goal');
    await flush();
    assert.equal(h.players.length, 1);
    assert.equal(h.events.filter(e => e.kind === 'getRawFd').length, 1);
    h.voice[action]();
    const states = h.states.slice();
    gate.resolve();
    await flush();
    assert.equal(h.players[0].source, undefined);
    assert.equal(h.players[0].calls.play, 0);
    assert.deepEqual(h.states, states);
    assertClean(h);
    await dispose(h);
  });
}

test('getRawFd resolving after same-path replay cannot close the replacement descriptor', async () => {
  const gate = deferred();
  const h = harness({ getGate: gate });
  h.voice.play('goal');
  await flush();
  h.voice.play('goal');
  await flush();
  assert.equal(h.players.length, 1);
  gate.resolve();
  await flush();
  assert.equal(h.players[0].calls.play, 0);
  assert.equal(h.players[1].calls.play, 1);
  const close = h.events.findIndex(e => e.kind === 'closeRawFd' && e.fd === 100);
  const open = h.events.findIndex(e => e.kind === 'opened' && e.fd === 101);
  assert.ok(close >= 0 && open > close);
  assert.equal(h.open.get('tutorial/zh-CN/goal.wav').fd, 101);
  await dispose(h);
});

for (const action of ['stop', 'dispose', 'switch']) {
  test(`prepare resolving after ${action} never plays the old generation`, async () => {
    const gate = deferred();
    const h = harness({ prepareGate: gate });
    h.voice.play('goal');
    await flush();
    assert.equal(h.players[0].calls.prepare, 1);
    if (action === 'switch') h.voice.play('demo');
    else h.voice[action]();
    gate.resolve();
    await flush();
    assert.equal(h.players[0].calls.play, 0);
    assert.equal(h.players[0].calls.release, 1);
    if (action === 'switch') {
      assert.equal(h.players[1].calls.play, 1);
      assert.equal(latest(h), 'playing');
    } else assertClean(h);
    await dispose(h);
  });
}

test('late createAVPlayer after dispose is released without opening a resource', async () => {
  const gate = deferred();
  const h = harness({ createGate: gate });
  h.voice.play('goal');
  await flush();
  h.voice.dispose();
  gate.resolve();
  await flush();
  assert.equal(h.players.length, 1);
  assert.equal(h.events.filter(e => e.kind === 'getRawFd').length, 0);
  assertClean(h);
});

test('completion releases player and fd; replay after completion starts a fresh player', async () => {
  const h = harness();
  h.voice.play('goal');
  await flush();
  h.players[0].stateChange('completed');
  await flush();
  assert.equal(latest(h), 'completed');
  assertClean(h);
  h.voice.play('goal');
  await flush();
  assert.equal(h.players.length, 2);
  assert.equal(latest(h), 'playing');
  await dispose(h);
});

test('native playback error releases once, ignores late events, and permits explicit retry', async () => {
  const h = harness();
  h.voice.play('goal');
  await flush();
  const old = h.players[0];
  old.emit('error', new Error('native playback failed'));
  await flush();
  assert.equal(latest(h), 'error');
  assertClean(h);
  const count = h.states.length;
  old.emit('error', new Error('duplicate error'));
  old.emit('stateChange', 'playing');
  old.emit('stateChange', 'prepared');
  await flush();
  assert.equal(h.states.length, count);
  h.voice.play('demo');
  await flush();
  assert.equal(latest(h), 'playing');
  await dispose(h);
});

for (const failure of ['createError', 'getError', 'prepareError', 'playError']) {
  test(`${failure} reports fallback state and releases acquired resources`, async () => {
    const h = harness({ [failure]: true });
    h.voice.play('goal');
    await flush();
    assert.equal(latest(h), 'error');
    assert.equal(h.states.filter(s => s === 'error').length, 1);
    assertClean(h);
    await dispose(h);
  });
}

test('loading timeout provides error fallback, releases resources, and ignores late prepared', async () => {
  const h = harness({ autoInitialize: false });
  h.voice.play('goal');
  await flush();
  h.clock.advance(7999);
  await flush();
  assert.equal(latest(h), 'loading');
  h.clock.advance(1);
  await flush();
  assert.equal(latest(h), 'error');
  assertClean(h);
  const states = h.states.slice();
  h.players[0].emit('stateChange', 'initialized');
  h.players[0].emit('stateChange', 'prepared');
  await flush();
  assert.equal(h.players[0].calls.play, 0);
  assert.deepEqual(h.states, states);
});

for (const pending of ['createGate', 'getGate', 'prepareGate']) {
  test(`timeout during pending ${pending} reports fallback immediately and cleans up when it settles`, async () => {
    const gate = deferred();
    const h = harness({ [pending]: gate });
    h.voice.play('goal');
    await flush();
    h.clock.advance(8000);
    assert.equal(latest(h), 'error', 'Fallback must not wait for a native promise');
    gate.resolve();
    await flush();
    assert.equal(h.players[0].calls.play, 0);
    assertClean(h);
    h.voice.play('demo');
    await flush();
    assert.equal(latest(h), 'playing', 'Explicit retry remains available');
    await dispose(h);
  });
}

test('replacing a loading generation cancels its watchdog, not the new watchdog', async () => {
  const h = harness({ autoInitialize: false });
  h.voice.play('goal');
  await flush();
  h.clock.advance(7000);
  h.voice.play('demo');
  await flush();
  h.clock.advance(1000);
  await flush();
  assert.equal(latest(h), 'loading');
  h.players[1].stateChange('initialized');
  await flush();
  assert.equal(latest(h), 'playing');
  h.clock.advance(30000);
  await flush();
  assert.equal(latest(h), 'playing');
  await dispose(h);
});

for (const hint of ['INTERRUPT_HINT_PAUSE', 'INTERRUPT_HINT_STOP']) {
  test(`incoming-call ${hint} releases and never auto-resumes on RESUME`, async () => {
    const h = harness();
    h.voice.play('goal');
    await flush();
    const p = h.players[0];
    p.emit('audioInterrupt', { hintType: audio.InterruptHint[hint] });
    await flush();
    assert.equal(latest(h), 'idle');
    assertClean(h);
    p.emit('audioInterrupt', { hintType: audio.InterruptHint.INTERRUPT_HINT_RESUME });
    h.voice.resume();
    h.clock.advance(30000);
    await flush();
    assert.equal(p.calls.play, 1);
    assert.equal(h.players.length, 1);
    assert.equal(latest(h), 'idle');
    await dispose(h);
  });
}

test('headphone disconnect stops and reconnect never auto-resumes', async () => {
  const h = harness();
  h.voice.play('goal');
  await flush();
  const p = h.players[0];
  p.emit('audioOutputDeviceChangeWithInfo', {
    changeReason: audio.AudioStreamDeviceChangeReason.REASON_OLD_DEVICE_UNAVAILABLE,
  });
  await flush();
  assert.equal(latest(h), 'idle');
  assertClean(h);
  p.emit('audioOutputDeviceChangeWithInfo', {
    changeReason: audio.AudioStreamDeviceChangeReason.REASON_NEW_DEVICE_AVAILABLE,
  });
  h.clock.advance(30000);
  await flush();
  assert.equal(p.calls.play, 1);
  assert.equal(h.players.length, 1);
  assert.equal(latest(h), 'idle');
  await dispose(h);
});

test('pause while loading cancels; repeated stop/dispose and post-dispose calls do not allocate or play', async () => {
  const gate = deferred();
  const h = harness({ getGate: gate });
  h.voice.play('goal');
  await flush();
  h.voice.pause();
  gate.resolve();
  await flush();
  assert.equal(latest(h), 'idle');
  assert.equal(h.players[0].calls.play, 0);
  assertClean(h);
  h.voice.stop();
  h.voice.stop();
  await dispose(h);
  const creates = h.events.filter(e => e.kind === 'createAVPlayer').length;
  h.voice.dispose();
  h.voice.play('demo');
  h.voice.pause();
  h.voice.resume();
  h.voice.stop();
  await flush();
  assert.equal(h.events.filter(e => e.kind === 'createAVPlayer').length, creates);
  assertClean(h);
});
