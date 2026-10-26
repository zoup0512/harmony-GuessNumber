import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

export function startClient(env = {}) {
  const child = spawn(process.execPath, [fileURLToPath(new URL('../src/server.mjs', import.meta.url))], {
    env: { ...process.env, ...env }, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true,
  });
  const pending = new Map();
  const lines = createInterface({ input: child.stdout });
  let sequence = 0;
  let stderr = '';
  child.stderr.on('data', chunk => { stderr += chunk; });
  lines.on('line', line => {
    let message;
    try { message = JSON.parse(line); } catch { throw new Error('MCP stdout contains non-JSON output'); }
    const item = pending.get(message.id);
    if (item) {
      pending.delete(message.id);
      clearTimeout(item.timer);
      if (message.error) item.reject(new Error(message.error.message));
      else item.resolve(message.result);
    }
  });
  child.on('exit', () => {
    for (const item of pending.values()) { clearTimeout(item.timer); item.reject(new Error('MCP process exited before response')); }
    pending.clear();
  });
  return {
    child,
    stderr: () => stderr,
    notify(method, params = {}) { child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method, params })}\n`); },
    request(method, params = {}, timeout = 30000) {
      const id = ++sequence;
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { pending.delete(id); reject(new Error('MCP request timed out')); }, timeout);
        pending.set(id, { resolve, reject, timer });
        child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
      });
    },
    async initialize() {
      const info = await this.request('initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'local-smoke', version: '1.0.0' } });
      this.notify('notifications/initialized');
      return info;
    },
    close() { lines.close(); child.stdin.end(); child.kill(); },
  };
}
