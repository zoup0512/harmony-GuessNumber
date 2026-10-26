import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:http';
import { encodePng, inspectPng, resizePng } from '../src/png.mjs';
import { generateImage, checkConnection } from '../src/engine.mjs';
import { startClient } from './mcp-client.mjs';

const fakeKey = 'test-key-must-never-leak';
function png(width = 8, height = 8) {
  const pixels = Buffer.alloc(width * height * 4);
  for (let i = 0; i < pixels.length; i += 4) { pixels[i] = 40; pixels[i + 1] = 200; pixels[i + 2] = 150; pixels[i + 3] = i % 8 ? 255 : 96; }
  return encodePng(width, height, pixels);
}
function imageResponse(bytes = png()) {
  return { id: 'resp_test', status: 'completed', output: [{ id: 'ig_test', type: 'image_generation_call', status: 'completed', result: bytes.toString('base64') }] };
}
function envFor(base = 'http://127.0.0.1:8765/v1') {
  return { CURRENT_IMAGE_API_KEY: fakeKey, CURRENT_IMAGE_BASE_URL: base };
}
async function folder(t) {
  const dir = await mkdtemp(join(tmpdir(), 'current-model-image-test-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  return dir;
}

test('PNG encoder, CRC validation and exact resize', () => {
  const source = png(13, 9);
  assert.equal(inspectPng(source).width, 13);
  const resized = resizePng(source, 512, 256);
  assert.equal(inspectPng(resized).width, 512);
  assert.equal(inspectPng(resized).height, 256);
  const corrupt = Buffer.from(source); corrupt[30] ^= 0xff;
  assert.throws(() => inspectPng(corrupt));
  assert.throws(() => inspectPng(Buffer.from('not a png')));
});

test('engine makes one Responses request, resizes PNG and reuses output', async t => {
  const dir = await folder(t);
  const output = join(dir, 'nested', 'icon.png');
  let requests = 0;
  const fetchImpl = async (url, options) => {
    requests++;
    assert.equal(url, 'http://127.0.0.1:8765/v1/responses');
    const body = JSON.parse(options.body);
    assert.equal(body.model, 'gpt-6.1-sol');
    assert.equal(body.tools[0].type, 'image_generation');
    assert.equal(body.store, false);
    return new Response(JSON.stringify(imageResponse()), { headers: { 'content-type': 'application/json' } });
  };
  const args = { prompt: 'mint checkmark', model: 'gpt-6.1-sol', output_path: output, width: 256, height: 512 };
  const metadata = await generateImage(args, { env: envFor(), fetchImpl });
  assert.equal(metadata.path, output);
  assert.equal(metadata.width, 256);
  assert.equal(metadata.height, 512);
  assert.equal(metadata.source_width, 8);
  assert.equal(inspectPng(await readFile(output)).height, 512);
  const reused = await generateImage(args, { env: envFor(), fetchImpl });
  assert.equal(reused.reused, true);
  assert.equal(requests, 1);
  assert.ok(!JSON.stringify(metadata).includes(fakeKey));
  assert.equal((await readdir(join(dir, 'nested'))).some(name => name.endsWith('.lock')), false);
});

test('bad paths and mismatching existing files fail before a billable request', async t => {
  const dir = await folder(t);
  let requests = 0;
  const options = { env: envFor(), fetchImpl: async () => { requests++; throw new Error('unexpected request'); } };
  const base = { prompt: 'test', model: 'gpt-6.1-sol', width: 256, height: 256 };
  for (const output_path of ['relative.png', join(dir, 'icon.jpg')]) {
    await assert.rejects(generateImage({ ...base, output_path }, options));
  }
  await assert.rejects(generateImage({ ...base, prompt: '', output_path: join(dir, 'empty.png') }, options));
  await assert.rejects(generateImage({ ...base, width: 0, output_path: join(dir, 'bad-size.png') }, options));
  const file = join(dir, 'existing.png'); await writeFile(file, png(12, 12));
  await assert.rejects(generateImage({ ...base, output_path: file }, options));
  assert.equal(requests, 0);
});

test('provider errors are sanitized and never automatically retried', async t => {
  const dir = await folder(t);
  let calls = 0;
  const fetchImpl = async () => { calls++; return new Response(`secret=${fakeKey} raw provider body`, { status: 400 }); };
  await assert.rejects(generateImage({ prompt: 'test', model: 'gpt-6.1-sol', output_path: join(dir, 'failed.png') }, { env: envFor(), fetchImpl }), error => {
    assert.ok(!error.message.includes(fakeKey));
    assert.ok(!error.message.includes('raw provider body'));
    assert.match(error.message, /400/u);
    return true;
  });
  assert.equal(calls, 1);
  assert.equal((await readdir(dir)).some(name => name.endsWith('.lock')), false);
});

test('JSON completion without image is a failure, not a success', async t => {
  const dir = await folder(t);
  await assert.rejects(generateImage({ prompt: 'test', model: 'gpt-6.1-sol', output_path: join(dir, 'no-image.png') }, {
    env: envFor(), fetchImpl: async () => new Response(JSON.stringify({ status: 'completed', output: [] }), { headers: { 'content-type': 'application/json' } }),
  }));
  assert.deepEqual(await readdir(dir), []);
});

test('chunked SSE completion and output_item.done image results work', async t => {
  const dir = await folder(t);
  for (const [index, event] of [
    { type: 'response.completed', response: imageResponse() },
    { type: 'response.output_item.done', item: imageResponse().output[0] },
  ].entries()) {
    const streamText = `event: message\r\ndata: ${JSON.stringify(event)}\r\n\r\ndata: [DONE]\r\n\r\n`;
    const bytes = new TextEncoder().encode(streamText);
    const stream = new ReadableStream({ start(controller) { for (let offset = 0; offset < bytes.length; offset += 31) controller.enqueue(bytes.subarray(offset, offset + 31)); controller.close(); } });
    const result = await generateImage({ prompt: 'test', model: 'gpt-6.1-sol', output_path: join(dir, `sse-${index}.png`), width: 256, height: 256 }, {
      env: envFor(), fetchImpl: async () => new Response(stream, { headers: { 'content-type': 'text/event-stream' } }),
    });
    assert.equal(result.width, 256);
  }
});

test('provider selection, disabled rules and configured model list are respected', async t => {
  const dir = await folder(t);
  const configPath = join(dir, 'provider.json');
  const rule = { providerId: 'local-test', providerName: 'NS-GPT', config: { access: { apiKey: fakeKey }, api: { type: 'openai-responses', baseUrl: 'https://example.invalid/v1' }, personalModelIds: ['gpt-6.1-sol'] } };
  const writeConfig = () => writeFile(configPath, JSON.stringify({ config: { providerConfigRules: { providerRules: [rule] } } }));
  await writeConfig();
  const env = { ZCODE_PERSONAL_PROVIDER_CONFIG_FILE: configPath };
  let calls = 0;
  const fetchImpl = async () => { calls++; return new Response(JSON.stringify({ data: [{ id: 'gpt-6.1-sol' }] }), { headers: { 'content-type': 'application/json' } }); };
  const connection = await checkConnection({ model: 'gpt-6.1-sol' }, { env, fetchImpl });
  assert.equal(connection.model, 'gpt-6.1-sol');
  assert.ok(!JSON.stringify(connection).includes(fakeKey));
  await assert.rejects(checkConnection({ model: 'other-model' }, { env, fetchImpl }));
  rule.enabled = false; await writeConfig();
  await assert.rejects(checkConnection({ model: 'gpt-6.1-sol' }, { env, fetchImpl }));
  assert.equal(calls, 1);
});

test('MCP stdio initialize/list/check/generate/reuse and validation', async t => {
  const dir = await folder(t);
  let generations = 0;
  const server = createServer(async (req, res) => {
    assert.equal(req.headers.authorization, `Bearer ${fakeKey}`);
    res.setHeader('content-type', 'application/json');
    if (req.url === '/v1/models') { res.end(JSON.stringify({ data: [{ id: 'gpt-6.1-sol' }] })); return; }
    if (req.url === '/v1/responses') {
      let raw = ''; for await (const chunk of req) raw += chunk;
      const body = JSON.parse(raw); assert.equal(body.model, 'gpt-6.1-sol'); generations++;
      res.end(JSON.stringify(imageResponse())); return;
    }
    res.statusCode = 404; res.end('{}');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const client = startClient(envFor(`http://127.0.0.1:${server.address().port}/v1`));
  t.after(() => { client.close(); server.closeAllConnections(); server.close(); });
  const info = await client.initialize();
  assert.equal(info.protocolVersion, '2024-11-05');
  assert.equal(info.serverInfo.name, 'current-model-image');
  const list = await client.request('tools/list');
  assert.deepEqual(list.tools.map(tool => tool.name), ['check_connection', 'generate_image']);
  assert.deepEqual(await client.request('ping'), {});
  const connection = await client.request('tools/call', { name: 'check_connection', arguments: { model: 'gpt-6.1-sol' } });
  assert.ok(!connection.isError);
  const args = { prompt: 'checkmark', model: 'gpt-6.1-sol', output_path: join(dir, 'mcp.png'), width: 256, height: 256 };
  const result = await client.request('tools/call', { name: 'generate_image', arguments: args });
  assert.ok(!result.isError, result.content[0].text);
  assert.equal(inspectPng(await readFile(args.output_path)).width, 256);
  const second = await client.request('tools/call', { name: 'generate_image', arguments: args });
  assert.equal(JSON.parse(second.content[0].text).reused, true);
  assert.equal(generations, 1);
  const invalid = await client.request('tools/call', { name: 'generate_image', arguments: { ...args, surprise: true } });
  assert.equal(invalid.isError, true);
  assert.equal(client.stderr(), '');
});
