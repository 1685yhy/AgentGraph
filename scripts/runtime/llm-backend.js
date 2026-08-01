#!/usr/bin/env node
/* ═══════ AgentGraph LLM Backend ═══════
 * Pluggable LLM API adapter. Supports OpenAI, Anthropic, DeepSeek.
 *
 * Config via env vars:
 *   AG_LLM_PROVIDER=anthropic|openai|deepseek (default: anthropic)
 *   AG_LLM_API_KEY=sk-...
 *   AG_LLM_MODEL=claude-sonnet-5-20251001 (provider-specific default)
 *   AG_LLM_BASE_URL=https://... (optional, overrides default base URL)
 *   AG_LLM_MAX_TOKENS=4096 (default)
 *   AG_LLM_TEMPERATURE=0.7 (default)
 *   AG_LLM_FALLBACK_PROVIDER=deepseek (optional failover)

 * Usage:
 *   node scripts/runtime/llm-backend.js --prompt "..."          # stdin → stdout
 *   node scripts/runtime/llm-backend.js --system "..." --prompt "..."
 *   node scripts/runtime/llm-backend.js --list-providers
 */

const https = require('https');
const http = require('http');
const { readFileSync } = require('fs');

// ── Provider configs ──
const PROVIDERS = {
  anthropic: {
    baseUrl: 'https://api.anthropic.com/v1/messages',
    defaultModel: 'claude-sonnet-5-20251001',
    buildRequest: (model, system, prompt, maxTokens, temp) => ({
      model, max_tokens: maxTokens, temperature: temp,
      system: [{ type: 'text', text: system }],
      messages: [{ role: 'user', content: prompt }]
    }),
    buildHeaders: (apiKey) => ({
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json'
    }),
    parseResponse: (data) => ({
      text: data.content?.[0]?.text || '',
      usage: { input: data.usage?.input_tokens || 0, output: data.usage?.output_tokens || 0 }
    })
  },
  openai: {
    baseUrl: 'https://api.openai.com/v1/chat/completions',
    defaultModel: 'gpt-4o',
    buildRequest: (model, system, prompt, maxTokens, temp) => ({
      model, max_tokens: maxTokens, temperature: temp,
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: prompt }
      ]
    }),
    buildHeaders: (apiKey) => ({
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    }),
    parseResponse: (data) => ({
      text: data.choices?.[0]?.message?.content || '',
      usage: { input: data.usage?.prompt_tokens || 0, output: data.usage?.completion_tokens || 0 }
    })
  },
  deepseek: {
    baseUrl: 'https://api.deepseek.com/v1/chat/completions',
    defaultModel: 'deepseek-chat',
    buildRequest: (model, system, prompt, maxTokens, temp) => ({
      model, max_tokens: maxTokens, temperature: temp,
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: prompt }
      ]
    }),
    buildHeaders: (apiKey) => ({
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json'
    }),
    parseResponse: (data) => ({
      text: data.choices?.[0]?.message?.content || '',
      usage: { input: data.usage?.prompt_tokens || 0, output: data.usage?.completion_tokens || 0 }
    })
  }
};

// ── HTTP request helper ──
function httpRequest(url, opts, body) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const transport = parsed.protocol === 'https:' ? https : http;
    const req = transport.request(url, opts, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.error) reject(new Error(`${json.error.type || 'API'}: ${json.error.message || JSON.stringify(json.error)}`));
          else resolve(json);
        } catch(e) { reject(new Error(`Parse error: ${data.substring(0,200)}`)); }
      });
    });
    req.on('error', reject);
    req.setTimeout(opts.timeout || 120000, () => { req.destroy(); reject(new Error('Request timeout')); });
    req.write(body);
    req.end();
  });
}

// ── Main call ──
async function callLLM(opts = {}) {
  const provider = opts.provider || process.env.AG_LLM_PROVIDER || 'anthropic';
  const apiKey = opts.apiKey || process.env.AG_LLM_API_KEY || '';
  const model = opts.model || process.env.AG_LLM_MODEL || PROVIDERS[provider]?.defaultModel || '';
  const maxTokens = opts.maxTokens || parseInt(process.env.AG_LLM_MAX_TOKENS || '4096');
  const temperature = opts.temperature ?? parseFloat(process.env.AG_LLM_TEMPERATURE || '0.7');
  const baseUrl = opts.baseUrl || process.env.AG_LLM_BASE_URL || PROVIDERS[provider]?.baseUrl || '';

  if (!apiKey && provider !== 'mock') {
    throw new Error(`No API key for ${provider}. Set AG_LLM_API_KEY env var.`);
  }

  const cfg = PROVIDERS[provider];
  if (!cfg) throw new Error(`Unknown provider: ${provider}. Available: ${Object.keys(PROVIDERS).join(', ')}`);

  const body = JSON.stringify(cfg.buildRequest(model, opts.system || '', opts.prompt || '', maxTokens, temperature));
  const headers = cfg.buildHeaders(apiKey);
  headers['Content-Length'] = Buffer.byteLength(body);

  const response = await httpRequest(baseUrl, { method: 'POST', headers, timeout: 120000 }, body);

  // Handle streaming (SSE) for some APIs
  if (response.object === 'text_completion' && typeof response.choices === 'undefined') {
    // Non-streaming response
    const parsed = cfg.parseResponse(response);
    return { text: parsed.text, usage: parsed.usage, model: response.model || model, provider };
  }

  const parsed = cfg.parseResponse(response);
  return { text: parsed.text, usage: parsed.usage, model: response.model || model, provider };
}

// ── Failover wrapper ──
async function callLLMWithFailover(opts = {}) {
  try {
    return await callLLM(opts);
  } catch (e) {
    const fallback = process.env.AG_LLM_FALLBACK_PROVIDER;
    if (fallback && fallback !== (opts.provider || process.env.AG_LLM_PROVIDER)) {
      console.error(`[AgentGraph] Primary LLM failed: ${e.message}. Falling back to ${fallback}.`);
      return await callLLM({ ...opts, provider: fallback });
    }
    throw e;
  }
}

// ── CLI ──
if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.includes('--list-providers')) {
    console.log(JSON.stringify(Object.keys(PROVIDERS), null, 2));
    process.exit(0);
  }

  let system = '', prompt = '';
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--system' && i + 1 < args.length) { system = args[++i]; }
    else if (args[i] === '--prompt' && i + 1 < args.length) { prompt = args[++i]; }
  }

  // If no --prompt flag, read from stdin
  if (!prompt) {
    prompt = readFileSync('/dev/stdin', 'utf8').trim();
  }

  callLLMWithFailover({ system, prompt })
    .then(r => { console.log(r.text); process.exit(0); })
    .catch(e => { console.error(`[AgentGraph] LLM error: ${e.message}`); process.exit(1); });
}

module.exports = { callLLM, callLLMWithFailover, PROVIDERS };
