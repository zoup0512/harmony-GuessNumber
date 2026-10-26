import { constants } from 'node:fs';
import { mkdir, realpath, lstat, open, link, unlink } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { inspectPng, resizePng } from './png.mjs';

const MAX_BODY = 64 * 1024 * 1024;
const MAX_CONFIG = 4 * 1024 * 1024;
const QUALITIES = new Set(['auto', 'low', 'medium', 'high']);

export class SafeImageError extends Error {
  constructor(message) { super(message); this.name = 'SafeImageError'; }
}
function fail(message) { throw new SafeImageError(message); }
function publicError(error) {
  if (error instanceof SafeImageError) throw error;
  fail('Image operation failed locally; no automatic retry was performed. Internal error details are withheld.');
}
function aborted(signal) { if (signal?.aborted) fail('Operation cancelled; no automatic retry was performed.'); }
function label(value, secret = '') {
  let text = typeof value === 'string' ? value : '';
  if (secret) text = text.split(secret).join('[redacted]');
  return text.replace(/[^a-zA-Z0-9._:/ @+\-]/g, '_').slice(0, 128);
}
function modelValue(model) {
  if (typeof model !== 'string' || !model.trim() || model !== model.trim() ||
      model.length > 256 || /[\x00-\x20\x7f]/.test(model)) {
    fail('model is required and must be a nonempty model identifier.');
  }
  return model;
}
function sizeValue(value, name) {
  if (!Number.isInteger(value) || value < 256 || value > 2048) fail(`${name} must be an integer from 256 to 2048.`);
  return value;
}
function validateArgs(args) {
  if (!args || typeof args !== 'object') fail('Image arguments are required.');
  const model = modelValue(args.model);
  if (typeof args.prompt !== 'string' || !args.prompt.trim() || Buffer.byteLength(args.prompt, 'utf8') > 256 * 1024 || args.prompt.includes('\0')) {
    fail('prompt must be nonempty text, without NUL, and at most 256 KiB.');
  }
  if (typeof args.output_path !== 'string' || !path.isAbsolute(args.output_path) ||
      /[\x00-\x1f]/.test(args.output_path) || path.extname(args.output_path).toLowerCase() !== '.png' ||
      (process.platform === 'win32' && /[:<>"|?*]/.test(args.output_path.slice(2)))) {
    fail('output_path must be an absolute local .png file path.');
  }
  if (process.platform === 'win32' && (!/^[a-zA-Z]:[\\/]/.test(args.output_path) ||
      args.output_path.split(/[\\/]/).slice(1).some(part => /[. ]$/.test(part) || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(part)))) {
    fail('output_path must not use device, network, or ambiguous Windows paths.');
  }
  const width = sizeValue(args.width ?? 1024, 'width'), height = sizeValue(args.height ?? 1024, 'height');
  const quality = args.quality ?? 'auto';
  if (!QUALITIES.has(quality)) fail('quality must be auto, low, medium, or high.');
  return { prompt: args.prompt, model, output_path: path.resolve(args.output_path), width, height, quality };
}

async function boundedFile(file, limit, description) {
  let handle;
  try {
    const entry = await lstat(file);
    if (!entry.isFile() || entry.isSymbolicLink() || entry.size > limit) fail(`${description} must be a regular file within the size limit.`);
    handle = await open(file, constants.O_RDONLY | (constants.O_NOFOLLOW || 0));
    const stat = await handle.stat();
    if (!stat.isFile() || stat.size > limit) fail(`${description} exceeds the size limit.`);
    const buffer = Buffer.allocUnsafe(stat.size + 1);
    let total = 0;
    while (total < buffer.length) {
      const { bytesRead } = await handle.read(buffer, total, buffer.length - total, null);
      if (!bytesRead) break;
      total += bytesRead;
    }
    if (total > stat.size) fail(`${description} changed during reading.`);
    return buffer.subarray(0, total);
  } finally { if (handle) await handle.close(); }
}

async function configuration(model, env, homeDir) {
  const keyOverride = env.CURRENT_IMAGE_API_KEY, urlOverride = env.CURRENT_IMAGE_BASE_URL;
  if ((keyOverride !== undefined) !== (urlOverride !== undefined)) {
    fail('CURRENT_IMAGE_API_KEY and CURRENT_IMAGE_BASE_URL must be supplied together.');
  }
  let rule, settings;
  if (keyOverride !== undefined) {
    rule = { providerName: env.CURRENT_IMAGE_PROVIDER_NAME || env.CURRENT_IMAGE_PROVIDER_ID || 'Environment override' };
    settings = {};
  } else {
  const configPath = env.ZCODE_PERSONAL_PROVIDER_CONFIG_FILE || path.join(homeDir, '.zcode', 'v2', 'provider_config.json');
  let config;
  try { config = JSON.parse((await boundedFile(configPath, MAX_CONFIG, 'Provider configuration')).toString('utf8')); }
  catch { fail('Cannot read personal provider configuration (expected valid JSON, maximum 4 MiB).'); }
  const rules = config?.config?.providerConfigRules?.providerRules;
  if (!Array.isArray(rules)) fail('Personal provider configuration has no providerRules array.');
  const id = env.CURRENT_IMAGE_PROVIDER_ID;
  const name = env.CURRENT_IMAGE_PROVIDER_NAME || 'NS-GPT';
  const matches = rules.filter(rule => rule && (id ? rule.providerId === id : rule.providerName === name));
  if (matches.length !== 1) fail('Selected image provider is missing or ambiguous; set CURRENT_IMAGE_PROVIDER_ID or CURRENT_IMAGE_PROVIDER_NAME.');
  rule = matches[0]; settings = rule.config;
  if (rule.enabled === false || settings?.enabled === false) fail('Selected image provider is disabled.');
  if (settings?.api?.type !== 'openai-responses') fail('Selected provider must use api.type=openai-responses; no provider fallback is allowed.');
  if (settings.personalModelIds !== undefined && (!Array.isArray(settings.personalModelIds) || !settings.personalModelIds.includes(model))) {
    fail('Requested model is not in the selected provider personalModelIds.');
  }
  }
  const apiKey = keyOverride !== undefined ? keyOverride : settings.access?.apiKey;
  const rawUrl = urlOverride !== undefined ? urlOverride : settings.api.baseUrl;
  if (typeof apiKey !== 'string' || !apiKey.trim() || /[\r\n\x00]/.test(apiKey)) fail('Selected provider has no valid API key.');
  let url;
  try { url = new URL(rawUrl); } catch { fail('Selected provider has an invalid base URL.'); }
  if (!(url.protocol === 'https:' || (url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname))) || url.username || url.password || url.search || url.hash ||
      /\/(responses|models)\/?$/i.test(url.pathname) || url.pathname.includes('%')) {
    fail('base URL must be an HTTP(S) API root without credentials, query, fragment, or /responses or /models suffix.');
  }
  url.pathname = url.pathname.replace(/\/+$/, '');
  const baseUrl = url.href.replace(/\/+$/, '');
  // Never publish URL userinfo, query strings, or a credential-bearing endpoint.
  if (baseUrl.includes(apiKey)) fail('API key must not appear in the base URL.');
  return { apiKey, baseUrl, provider: label(rule.providerName || rule.providerId, apiKey), model };
}

function requestId(response, secret) {
  for (const key of ['x-request-id', 'request-id', 'x-correlation-id']) {
    const value = response.headers?.get?.(key);
    if (value) return label(value, secret);
  }
  return undefined;
}

async function bodyChunks(response, consume, signal) {
  const declared = response.headers?.get?.('content-length');
  if (declared && /^\d+$/.test(declared) && Number(declared) > MAX_BODY) {
    try { await response.body?.cancel(); } catch { /* No response content is surfaced. */ }
    fail('API response exceeds the 64 MiB limit.');
  }
  if (!response.body || typeof response.body.getReader !== 'function') fail('API response has no readable body.');
  const reader = response.body.getReader();
  let total = 0, complete = false;
  const cancel = () => { reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', cancel, { once: true });
  try {
    while (true) {
      aborted(signal);
      const { value, done } = await reader.read();
      aborted(signal);
      if (done) { complete = true; break; }
      total += value.byteLength;
      if (total > MAX_BODY) fail('API response exceeds the 64 MiB limit.');
      consume(value);
    }
  } finally {
    signal.removeEventListener('abort', cancel);
    if (!complete) { try { await reader.cancel(); } catch { /* Preserve the safe primary error. */ } }
    reader.releaseLock();
  }
}

function imageState(secret) {
  const state = { image: null, responseId: undefined, status: undefined, terminal: false };
  const takeItem = item => {
    if (!item || item.type !== 'image_generation_call') return;
    if (item.status && !['completed', 'in_progress', 'generating'].includes(item.status)) return;
    const value = typeof item.result === 'string' ? item.result : typeof item.base64 === 'string' ? item.base64 : null;
    if (value && state.image === null) state.image = value;
  };
  const takeResponse = (response, terminal) => {
    if (!response || typeof response !== 'object') return;
    if (response.id) state.responseId = label(response.id, secret);
    if (response.status) state.status = label(response.status, secret);
    if (terminal) state.terminal = true;
    if (Array.isArray(response.output)) response.output.forEach(takeItem);
  };
  return { state, takeResponse, event(event, eventName) {
    const type = event?.type || eventName;
    if (type === 'response.output_item.done') takeItem(event.item);
    if (type === 'response.completed' || type === 'response.done') takeResponse(event.response, true);
    else if (type === 'response.failed' || type === 'response.incomplete' || type === 'response.cancelled') {
      takeResponse(event.response, true);
      state.status = type.slice('response.'.length);
    } else if (type === 'error') fail('Image API reported a stream error; do not blindly retry a potentially billed request.');
    else if (event?.response) takeResponse(event.response, false);
  } };
}

async function readJson(response, signal) {
  const chunks = [];
  await bodyChunks(response, chunk => chunks.push(Buffer.from(chunk)), signal);
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { fail('API returned invalid JSON; response content is not included.'); }
}

async function readImage(response, signal, secret) {
  const collector = imageState(secret);
  if ((response.headers?.get?.('content-type') || '').toLowerCase().includes('text/event-stream')) {
    const decoder = new TextDecoder();
    let pending = '', data = [], eventName = '', skipLF = false;
    const dispatch = () => {
      if (!data.length) { eventName = ''; return; }
      const text = data.join('\n'); data = [];
      if (text.trim() !== '[DONE]') {
        let event;
        try { event = JSON.parse(text); } catch { fail('Image API returned an invalid SSE JSON event.'); }
        collector.event(event, eventName);
      }
      eventName = '';
    };
    const line = text => {
      if (!text) { dispatch(); return; }
      if (text[0] === ':') return;
      const split = text.indexOf(':');
      const field = split < 0 ? text : text.slice(0, split);
      let value = split < 0 ? '' : text.slice(split + 1);
      if (value[0] === ' ') value = value.slice(1);
      if (field === 'data') data.push(value);
      else if (field === 'event') eventName = value;
    };
    const feed = text => {
      let start = 0;
      if (skipLF) { if (text[0] === '\n') start = 1; skipLF = false; }
      let from = start;
      for (let i = start; i < text.length; i++) {
        if (text[i] !== '\r' && text[i] !== '\n') continue;
        line(pending + text.slice(from, i)); pending = '';
        if (text[i] === '\r') {
          if (text[i + 1] === '\n') i++;
          else if (i === text.length - 1) skipLF = true;
        }
        from = i + 1;
      }
      pending += text.slice(from);
    };
    await bodyChunks(response, bytes => feed(decoder.decode(bytes, { stream: true })), signal);
    feed(decoder.decode());
    if (pending) line(pending);
    dispatch();
  } else {
    collector.takeResponse(await readJson(response, signal), true);
  }
  const state = collector.state;
  const detail = `status=${state.status || 'unknown'}${state.responseId ? `, response_id=${state.responseId}` : ''}`;
  if (['queued', 'pending', 'in_progress', 'background'].includes(state.status) && (state.terminal || !state.image)) {
    fail(`Image response is pending (${detail}); no polling or additional request was made. Check the provider before retrying.`);
  }
  if (['failed', 'incomplete', 'cancelled'].includes(state.status)) fail(`Image generation did not complete (${detail}); do not blindly retry.`);
  if (!state.image) fail(`Response contains no completed PNG image (${detail}); do not blindly retry a potentially billed request.`);
  const base64 = state.image;
  const unpadded = base64.replace(/={1,2}$/, '');
  if (!base64.length || base64.length % 4 !== 0 || /[^A-Za-z0-9+/]/.test(unpadded)) {
    fail('Image result must be inline base64 PNG; URLs and other formats are not supported.');
  }
  const image = Buffer.from(base64, 'base64');
  if (image.length > MAX_BODY || image.toString('base64') !== base64) fail('Image result has invalid base64 encoding or exceeds the size limit.');
  return { image, responseId: state.responseId };
}

async function request(config, suffix, { fetchImpl, signal, body, timeout, consume }) {
  if (typeof fetchImpl !== 'function') fail('A fetch implementation is required (Node >=20).');
  const controller = new AbortController();
  let timedOut = false;
  const cancel = () => controller.abort();
  signal?.addEventListener('abort', cancel, { once: true });
  const timer = setTimeout(() => { timedOut = true; controller.abort(); }, timeout);
  timer.unref?.();
  try {
    aborted(signal);
    let response;
    try {
      response = await fetchImpl(config.baseUrl + suffix, {
        method: body ? 'POST' : 'GET',
        headers: { Authorization: `Bearer ${config.apiKey}`, Accept: body ? 'application/json, text/event-stream' : 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}) },
        ...(body ? { body: JSON.stringify(body) } : {}), signal: controller.signal,
        redirect: 'error',
      });
    } catch {
      if (controller.signal.aborted) throw new Error('aborted');
      fail(`API transport failed at ${suffix}; no automatic retry was performed.`);
    }
    if (!response.ok) {
      const id = requestId(response, config.apiKey);
      try { await response.body?.cancel(); } catch { /* HTTP bodies can contain secrets or base64. */ }
      fail(`HTTP ${Number.isInteger(response.status) ? response.status : 'error'} at ${suffix}${id ? ` (request_id=${id})` : ''}; no automatic retry was performed.`);
    }
    const result = await consume(response, controller.signal);
    aborted(controller.signal);
    return result;
  } catch (error) {
    if (timedOut) fail(`API request timed out after ${timeout / 1000}s at ${suffix}; no retry was made. The request may already have been billed.`);
    if (signal?.aborted) fail('Operation cancelled; no automatic retry was performed. The request may already have been billed.');
    // Only our own errors may cross the public boundary.
    if (error instanceof SafeImageError) throw error;
    fail(`Cannot read API response at ${suffix}; no automatic retry was performed.`);
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', cancel);
  }
}

async function existingPng(file, width, height) {
  try { await lstat(file); }
  catch (error) { if (error.code === 'ENOENT') return null; fail('Cannot inspect output_path.'); }
  let buffer, info;
  try { buffer = await boundedFile(file, MAX_BODY, 'Existing PNG'); info = inspectPng(buffer); }
  catch { fail('output_path already exists but is not a usable supported PNG; it was not overwritten.'); }
  if (info.width !== width || info.height !== height) fail('Existing PNG dimensions do not match the requested dimensions; no generation or overwrite was performed.');
  return { info, bytes: buffer.length };
}

function metadata(file, args, config, source, bytes, reused, responseId) {
  return { path: file, width: args.width, height: args.height, source_width: source.width, source_height: source.height,
    model: args.model, provider: config.provider, base_url: config.baseUrl, reused, response_id: responseId ?? null, bytes,
    ...(reused ? { notice: 'Existing valid PNG reused; this does not mean it was generated from this prompt or model.' } : {}) };
}

/** One paid request at most; a per-target exclusive lock is never automatically retried. */
async function generate(args, { fetchImpl = globalThis.fetch, env = process.env, homeDir = homedir(), signal } = {}) {
  const values = validateArgs(args);
  aborted(signal);
  const config = await configuration(values.model, env, homeDir);
  let file;
  try {
    await mkdir(path.dirname(values.output_path), { recursive: true });
    file = path.join(await realpath(path.dirname(values.output_path)), path.basename(values.output_path));
  } catch { fail('Cannot create or resolve the output directory.'); }
  const previous = await existingPng(file, values.width, values.height);
  if (previous) return metadata(file, values, config, previous.info, previous.bytes, true);
  aborted(signal);
  const lockPath = file + '.lock';
  let lock, temporary;
  try { lock = await open(lockPath, 'wx', 0o600); }
  catch (error) {
    if (error.code === 'EEXIST') fail('output_path is locked by another operation. No request was made; inspect a stale lock manually before retrying.');
    fail('Cannot acquire the output_path lock; no request was made.');
  }
  try {
    const found = await existingPng(file, values.width, values.height);
    if (found) return metadata(file, values, config, found.info, found.bytes, true);
    aborted(signal);
    const size = values.width === values.height ? '1024x1024' : values.width > values.height ? '1536x1024' : '1024x1536';
    const result = await request(config, '/responses', {
      fetchImpl, signal, timeout: 240_000,
      body: { model: values.model, input: values.prompt, tools: [{ type: 'image_generation', size, quality: values.quality }],
        tool_choice: { type: 'image_generation' }, store: false },
      consume: (response, requestSignal) => readImage(response, requestSignal, config.apiKey),
    });
    aborted(signal);
    let source, image;
    try { source = inspectPng(result.image); image = resizePng(result.image, values.width, values.height); }
    catch { fail('Image result is not a valid supported 8-bit non-interlaced RGB/RGBA PNG, or exceeds PNG safety limits. No output was written.'); }
    aborted(signal);
    temporary = path.join(path.dirname(file), `.${path.basename(file)}.${randomUUID()}.tmp`);
    let handle;
    try { handle = await open(temporary, 'wx', 0o600); await handle.writeFile(image); await handle.sync(); }
    catch { fail('Cannot write generated PNG to the output directory; no retry was made.'); }
    finally { if (handle) await handle.close(); }
    aborted(signal);
    try { await link(temporary, file); }
    catch (error) {
      if (error.code === 'EEXIST') {
        const winner = await existingPng(file, values.width, values.height);
        if (winner) return metadata(file, values, config, winner.info, winner.bytes, true);
      }
      fail('Cannot atomically publish PNG without overwriting; no existing output was replaced.');
    }
    return metadata(file, values, config, source, image.length, false, result.responseId);
  } finally {
    if (temporary) await unlink(temporary).catch(() => {});
    await lock.close().catch(() => {});
    await unlink(lockPath).catch(() => {});
  }
}

/** Checks configuration and /models only; this never invokes image generation. */
async function check({ model } = {}, { fetchImpl = globalThis.fetch, env = process.env, homeDir = homedir(), signal } = {}) {
  modelValue(model);
  aborted(signal);
  const config = await configuration(model, env, homeDir);
  const listing = await request(config, '/models', { fetchImpl, signal, timeout: 20_000, consume: readJson });
  if (!listing || !Array.isArray(listing.data)) fail('The /models endpoint returned no valid model list.');
  const available = listing.data.some(item => item && item.id === model);
  if (!available) fail('Requested model was not listed by the selected provider /models endpoint; no generation was attempted.');
  return { connected: true, provider: config.provider, base_url: config.baseUrl, model, model_available: true,
    api_type: 'openai-responses', image_generation: 'not_tested',
    notice: 'Model listing does not prove image_generation tool support; no image was generated.' };
}

export async function generateImage(args, opts) {
  try { return await generate(args, opts); }
  catch (error) { publicError(error); }
}

export async function checkConnection(args, opts) {
  try { return await check(args, opts); }
  catch (error) { publicError(error); }
}
