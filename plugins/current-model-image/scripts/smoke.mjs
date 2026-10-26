import { resolve, join } from 'node:path';
import { inspectPng } from '../src/png.mjs';
import { readFile } from 'node:fs/promises';
import { startClient } from '../tests/mcp-client.mjs';

const model = process.env.CURRENT_IMAGE_SMOKE_MODEL;
const live = process.argv.includes('--live');
if (live && !model) throw new Error('真实测试必须显式设置 CURRENT_IMAGE_SMOKE_MODEL 为当前会话模型。');
const client = startClient();
try {
  const initialize = await client.initialize();
  const list = await client.request('tools/list');
  if (list.tools.length !== 2) throw new Error('Expected two MCP tools');
  console.log(JSON.stringify({ stage: 'protocol', server: initialize.serverInfo, tools: list.tools.map(tool => tool.name) }));
  if (live) {
    const connection = await client.request('tools/call', { name: 'check_connection', arguments: { model } }, 45000);
    if (connection.isError) throw new Error(connection.content[0].text);
    console.log(JSON.stringify({ stage: 'connection', result: JSON.parse(connection.content[0].text) }));
    const output = resolve(process.env.CURRENT_IMAGE_SMOKE_OUTPUT || join('generated-images', `smoke-${Date.now()}.png`));
    const result = await client.request('tools/call', {
      name: 'generate_image',
      arguments: {
        model,
        prompt: 'Create a simple flat vector app icon on a deep navy background, a single mint green checkmark inside a warm gold rounded square. No words, no letters, no numbers. Large centered symbol, generous padding.',
        output_path: output,
        width: 1024,
        height: 1024,
      },
    }, 300000);
    if (result.isError) throw new Error(result.content[0].text);
    const metadata = JSON.parse(result.content[0].text);
    const bytes = await readFile(metadata.path);
    const png = inspectPng(bytes);
    if (png.width !== 1024 || png.height !== 1024 || metadata.reused) throw new Error('Live test must create a new exact 1024×1024 PNG');
    console.log(JSON.stringify({ stage: 'generated', result: metadata, png: { width: png.width, height: png.height } }));
    const reused = await client.request('tools/call', {
      name: 'generate_image',
      arguments: { model, prompt: 'Same output path must be reused without another billable request.', output_path: output, width: 1024, height: 1024 },
    });
    if (reused.isError || JSON.parse(reused.content[0].text).reused !== true) throw new Error('Existing output was not reused');
    console.log(JSON.stringify({ stage: 'reuse', reused: true }));
  }
  if (client.stderr().trim()) throw new Error('Unexpected MCP stderr output');
} finally {
  client.close();
}
