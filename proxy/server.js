#!/usr/bin/env node
// ============================================================
// TokenWatch 本地代理网关(零依赖,Node 22+)
// 用途:所有非 Claude Code 的 API 调用指向本代理(OpenAI 兼容),
//       转发到 DeepSeek/智谱/MiniMax/聚合平台,并把每个请求的
//       token 用量记录为 JSONL(格式与 TokenWatch 解析器兼容)。
// 启动:node server.js
// 测试:curl -s localhost:8787/health
// ============================================================
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const CONFIG_PATH = path.join(__dirname, 'config.json');
const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));

// apiKey 支持 "${ENV_NAME}" 占位符 → 从环境变量读取,key 不落盘
function resolveSecret(v) {
  if (typeof v === 'string' && v.startsWith('${') && v.endsWith('}')) {
    return process.env[v.slice(2, -1)] || '';
  }
  return v;
}
const providers = {};
for (const [name, p] of Object.entries(config.providers)) {
  providers[name] = { ...p, apiKey: resolveSecret(p.apiKey) };
}

// ---------- 日志 ----------
const logDir = config.logDir.replace(/^~/, os.homedir());
fs.mkdirSync(logDir, { recursive: true });

function logFile() {
  const d = new Date();
  const day = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  return path.join(logDir, `proxy-${day}.jsonl`);
}

// 上游返回 OpenAI 兼容字段(prompt_tokens/completion_tokens)时映射为 Anthropic 字段
function normalizeUsage(u) {
  if (u.input_tokens != null || u.output_tokens != null) return u;
  const details = u.prompt_tokens_details || {};
  const hit = u.prompt_cache_hit_tokens ?? details.cached_tokens ?? 0;
  return {
    input_tokens: u.prompt_tokens ?? 0,
    output_tokens: u.completion_tokens ?? 0,
    cache_creation_input_tokens: u.prompt_cache_miss_tokens ?? Math.max(0, (u.prompt_tokens ?? 0) - hit),
    cache_read_input_tokens: hit
  };
}

function logUsage(provider, model, usage) {
  // 与 UsageParser.parseLine 兼容:usage 嵌套在 message 内,timestamp 为 ISO8601
  const rec = {
    id: crypto.randomUUID(),
    timestamp: new Date().toISOString(),
    provider,
    message: {
      model,
      usage: {
        input_tokens: usage.input_tokens ?? 0,
        output_tokens: usage.output_tokens ?? 0,
        cache_creation_input_tokens: usage.cache_creation_input_tokens ?? 0,
        cache_read_input_tokens: usage.cache_read_input_tokens ?? 0
      }
    }
  };
  fs.appendFileSync(logFile(), JSON.stringify(rec) + '\n');
}

// ---------- 路由 ----------
function routeProvider(model) {
  for (const r of config.routes) {
    if (model.startsWith(r.prefix)) return r.provider;
  }
  return config.defaultProvider;
}

function upstreamUrl(provider) {
  const p = providers[provider];
  if (!p.baseUrl) return null;
  return p.baseUrl.replace(/\/+$/, '') + p.path;
}

// ---------- 请求处理 ----------
async function handleChat(req, res, bodyText) {
  let body;
  try { body = JSON.parse(bodyText); } catch {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ error: { message: 'invalid JSON body' } }));
  }

  const model = body.model || '';
  const provider = routeProvider(model);
  const url = upstreamUrl(provider);
  if (!url) {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ error: { message: `provider '${provider}' 未配置 baseUrl` } }));
  }

  // stream 请求:确保上游返回 usage(OpenAI 兼容的 stream_options)
  // 上游若拒绝该字段则去掉重试一次
  let forwarded = body;
  let injected = false;
  if (body.stream && !body.stream_options?.include_usage) {
    forwarded = { ...body, stream_options: { ...(body.stream_options || {}), include_usage: true } };
    injected = true;
  }

  const doFetch = (payload) => fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${providers[provider].apiKey}`,
      'x-api-key': providers[provider].apiKey
    },
    body: JSON.stringify(payload)
  });

  let upstream;
  try {
    upstream = await doFetch(forwarded);
    if (injected && (upstream.status === 400 || upstream.status === 422)) {
      upstream = await doFetch(body); // 重试不带 stream_options
    }
  } catch (e) {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ error: { message: `upstream error: ${e.message}` } }));
  }

  res.writeHead(upstream.status, {
    'Content-Type': upstream.headers.get('content-type') || 'application/json',
    'x-tokenwatch-provider': provider
  });

  // 非 stream:整包读,取 usage 记日志
  if (!body.stream) {
    const text = await upstream.text();
    res.end(text);
    let u = {};
    try { u = normalizeUsage(JSON.parse(text).usage || {}); } catch {}
    if (u.input_tokens != null || u.output_tokens != null) logUsage(provider, model, u);
    return;
  }

  // stream:逐块透传,收集含 usage 的块
  if (!upstream.body) return res.end();
  const reader = upstream.body.getReader();
  const decoder = new TextDecoder();
  let usage = null;
  let done = false;
  while (!done) {
    const { value, done: d } = await reader.read();
    done = d;
    if (value) {
      const chunk = decoder.decode(value, { stream: !done });
      res.write(chunk);
      // 收集 usage 字段(最终块或任意携带 usage 的块)
      for (const line of chunk.split('\n')) {
        if (!line.startsWith('data:')) continue;
        const data = line.slice(5).trim();
        if (!data || data === '[DONE]') continue;
        try {
          const obj = JSON.parse(data);
          if (obj.usage) usage = normalizeUsage(obj.usage);
        } catch {}
      }
    }
  }
  res.end();
  if (usage && (usage.input_tokens != null || usage.output_tokens != null)) {
    logUsage(provider, model, usage);
  }
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ ok: true }));
  }
  if (req.method !== 'POST' ||
      !(req.url === '/v1/chat/completions' || req.url === '/chat/completions')) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ error: { message: 'not found' } }));
  }

  let body = '';
  req.on('data', (c) => { body += c; if (body.length > 100e6) req.destroy(); });
  req.on('end', () => handleChat(req, res, body).catch((e) => {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: { message: `proxy error: ${e.message}` } }));
  }));
});

server.listen(config.port, config.host, () => {
  console.log(`TokenWatch proxy: http://${config.host}:${config.port}  (日志: ${logDir})`);
  console.log(`路由: ${config.routes.map(r => `${r.prefix}→${r.provider}`).join(', ')}, 默认→${config.defaultProvider}`);
});
