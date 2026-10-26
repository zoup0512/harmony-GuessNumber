import { createInterface } from 'node:readline';
import { generateImage, checkConnection, SafeImageError } from './engine.mjs';

class ArgumentError extends Error {}

const tools = [
  {
    name: 'check_connection',
    description: '检查当前模型生图的本地供应商配置和 /models 连接，不生成图片、不产生生图费用。不自动检测会话模型，必须显式传入当前模型 ID。',
    inputSchema: {
      type: 'object',
      properties: { model: { type: 'string', minLength: 1, description: '当前会话的模型 ID，例如 gpt-6.1-sol；不是 providerId/modelId。' } },
      required: ['model'],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true },
  },
  {
    name: 'generate_image',
    description: '用显式传入的当前模型调用 Responses image_generation，一次请求生成并保存 PNG，按指定尺寸中心裁切及缩放。读取本地已有供应商凭据；不切换模型、不扫描日志、不覆盖已有图片、不自动重试。可能产生供应商生图费用。返回真实文件路径供预览。',
    inputSchema: {
      type: 'object',
      properties: {
        prompt: { type: 'string', minLength: 1, maxLength: 16000, description: '完整图片描述；只发送用户授权的画面内容。' },
        model: { type: 'string', minLength: 1, description: '当前会话的准确模型 ID。' },
        output_path: { type: 'string', minLength: 1, description: '绝对 PNG 文件路径，不覆盖现有文件；新变体用新路径。' },
        width: { type: 'integer', minimum: 256, maximum: 2048, default: 1024 },
        height: { type: 'integer', minimum: 256, maximum: 2048, default: 1024 },
        quality: { type: 'string', enum: ['auto', 'low', 'medium', 'high'], default: 'auto' },
      },
      required: ['prompt', 'model', 'output_path'],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true },
  },
];
const controllers = new Map();
const cancelled = new Set();
const supportedVersions = ['2025-06-18', '2025-03-26', '2024-11-05'];
const MAX_LINE = 128 * 1024;

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}
function response(id, result) {
  if (!cancelled.has(id)) send({ jsonrpc: '2.0', id, result });
}
function fail(id, code, message) {
  send({ jsonrpc: '2.0', id, error: { code, message } });
}
function validateArguments(tool, args) {
  if (!args || typeof args !== 'object' || Array.isArray(args)) throw new ArgumentError('工具参数必须为对象。');
  const schema = tool.inputSchema;
  if (Object.keys(args).some(key => !Object.hasOwn(schema.properties, key))) throw new ArgumentError('工具参数包含未知字段。');
  for (const name of schema.required) if (typeof args[name] !== 'string' || !args[name].trim()) throw new ArgumentError(`缺少有效参数：${name}。`);
  if (args.prompt && args.prompt.length > 16000) throw new ArgumentError('提示词超过 16000 字符。');
  if (args.model.length > 160 || /[\s/\\]/u.test(args.model)) throw new ArgumentError('model 必须是单独的模型 ID，不是 providerId/modelId。');
  for (const name of ['width', 'height']) if (args[name] !== undefined && (!Number.isInteger(args[name]) || args[name] < 256 || args[name] > 2048)) throw new ArgumentError(`${name} 必须为 256–2048 的整数。`);
  if (args.quality !== undefined && !['auto', 'low', 'medium', 'high'].includes(args.quality)) throw new ArgumentError('quality 参数无效。');
}

async function handle(message) {
  const { id, method, params } = message;
  if (method === 'notifications/cancelled') {
    const requestId = params?.requestId;
    const controller = controllers.get(requestId);
    if (controller) {
      cancelled.add(requestId);
      controller.abort();
    }
    return;
  }
  if (id === undefined) return;
  if (message.jsonrpc !== '2.0' || !['string', 'number'].includes(typeof id) || typeof method !== 'string') {
    fail(null, -32600, 'Invalid JSON-RPC request');
    return;
  }
  if (method === 'initialize') {
    response(id, {
      protocolVersion: supportedVersions.includes(params?.protocolVersion) ? params.protocolVersion : supportedVersions[0],
      capabilities: { tools: { listChanged: false } },
      serverInfo: { name: 'current-model-image', version: '0.1.0' },
      instructions: '传入当前会话模型 ID。generate_image 只做一次请求，失败不自动重试；成功后用返回文件路径预览 PNG。',
    });
    return;
  }
  if (method === 'ping') { response(id, {}); return; }
  if (method === 'tools/list') { response(id, { tools }); return; }
  if (method !== 'tools/call') { fail(id, -32601, 'Method not found'); return; }
  const tool = tools.find(item => item.name === params?.name);
  if (!tool) { fail(id, -32602, 'Unknown tool'); return; }
  if (controllers.has(id)) { fail(id, -32600, 'Duplicate active request ID'); return; }
  const controller = new AbortController();
  controllers.set(id, controller);
  try {
    const args = params.arguments;
    validateArguments(tool, args);
    const result = tool.name === 'generate_image'
      ? await generateImage(args, { signal: controller.signal })
      : await checkConnection(args, { signal: controller.signal });
    response(id, { content: [{ type: 'text', text: JSON.stringify(result) }] });
  } catch (error) {
    // Only controlled error types can be shown without leaking provider bodies or credentials.
    const message = controller.signal.aborted
      ? '请求已取消。远端可能已处理并计费，不要自动重试。'
      : error instanceof SafeImageError || error instanceof ArgumentError
        ? error.message
        : '工具调用未完成。发生内部错误，不要自动重试生图。';
    response(id, { isError: true, content: [{ type: 'text', text: message }] });
  } finally {
    controllers.delete(id);
    cancelled.delete(id);
  }
}

const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on('line', line => {
  if (!line.trim()) return;
  if (Buffer.byteLength(line) > MAX_LINE) { fail(null, -32600, 'Request exceeds 128 KiB'); return; }
  let message;
  try { message = JSON.parse(line); } catch { fail(null, -32700, 'Parse error'); return; }
  if (!message || typeof message !== 'object' || Array.isArray(message)) { fail(null, -32600, 'Invalid request'); return; }
  void handle(message).catch(() => fail(message.id ?? null, -32603, 'Internal error'));
});
input.on('close', () => {
  for (const controller of controllers.values()) controller.abort();
});
process.on('SIGTERM', () => { input.close(); process.exitCode = 0; });
