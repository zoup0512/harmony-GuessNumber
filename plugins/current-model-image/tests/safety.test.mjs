import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { generateImage, checkConnection } from '../src/engine.mjs';
import { encodePng } from '../src/png.mjs';

const env = { CURRENT_IMAGE_API_KEY: 'test-private-key', CURRENT_IMAGE_BASE_URL: 'http://127.0.0.1:8765/v1', ZCODE_PERSONAL_PROVIDER_CONFIG_FILE: '/nonexistent/provider.json' };
const key = env.CURRENT_IMAGE_API_KEY;
const image = encodePng(2, 2, Buffer.from([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 0]));
const response = () => new Response(JSON.stringify({ status: 'completed', output: [{ type: 'image_generation_call', result: image.toString('base64') }] }), { headers: { 'content-type': 'application/json' } });
async function folder(t) { const dir = await mkdtemp(join(tmpdir(), 'image-safety-')); t.after(() => rm(dir, { force: true, recursive: true })); return dir; }

test('explicit credentials work without any ZCode configuration', async () => {
  const result = await checkConnection({ model: 'explicit-model' }, { env, fetchImpl: async () => new Response(JSON.stringify({ data: [{ id: 'explicit-model' }] })) });
  assert.equal(result.connected, true);
  assert.ok(!JSON.stringify(result).includes(key));
});

test('partial credential override and plaintext remote endpoints fail without sending secrets', async () => {
  let requests = 0;
  const fetchImpl = async () => { requests++; throw new Error('unexpected request'); };
  await assert.rejects(checkConnection({ model: 'test' }, { env: { CURRENT_IMAGE_API_KEY: key }, fetchImpl }));
  await assert.rejects(checkConnection({ model: 'test' }, { env: { ...env, CURRENT_IMAGE_BASE_URL: 'http://example.com/v1' }, fetchImpl }));
  assert.equal(requests, 0);
});

test('concurrent calls for one path make at most one generation request', async t => {
  const dir = await folder(t);
  const args = { model: 'test', prompt: 'check', output_path: join(dir, 'same.png'), width: 256, height: 256 };
  let requests = 0;
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  let entered;
  const started = new Promise(resolve => { entered = resolve; });
  const fetchImpl = async () => { requests++; entered(); await gate; return response(); };
  const first = generateImage(args, { env, fetchImpl });
  await started;
  await assert.rejects(generateImage(args, { env, fetchImpl }), /lock/iu);
  release();
  await first;
  assert.equal(requests, 1);
  assert.deepEqual(await readdir(dir), ['same.png']);
});

test('cancelled calls and oversized responses leave no output or stale locks', async t => {
  const dir = await folder(t);
  const args = { model: 'test', prompt: 'check', output_path: join(dir, 'cancelled.png') };
  const controller = new AbortController(); controller.abort();
  let requests = 0;
  await assert.rejects(generateImage(args, { env, signal: controller.signal, fetchImpl: async () => { requests++; return response(); } }));
  assert.equal(requests, 0);
  await assert.rejects(generateImage(args, { env, fetchImpl: async () => new Response('{}', { headers: { 'content-type': 'application/json', 'content-length': String(65 * 1024 * 1024) } }) }), /64 MiB/iu);
  assert.deepEqual(await readdir(dir), []);
});
