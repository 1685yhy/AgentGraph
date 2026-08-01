#!/usr/bin/env node
/* ═══════ AgentGraph MCP Server ═══════
 * Model Context Protocol server — exposes AgentGraph as AI-callable tools.
 * Claude Code / OpenClaw / Hermes / any MCP host can discover and call directly.
 *
 * AI no longer runs "bash guild xxx" — it calls agentgraph.plan("task").
 *
 * Usage:
 *   node scripts/mcp-server.js           # stdio mode (MCP protocol)
 *   node scripts/mcp-server.js --http 3000  # HTTP mode (for remote hosts)
 *   guild mcp                            # alias
 *
 * Register in .mcp.json:
 *   { "mcpServers": { "agentgraph": { "command": "node", "args": ["scripts/mcp-server.js"] } } }
 */

const { readFileSync, existsSync } = require('fs');
const { execSync } = require('child_process');
const { join } = require('path');
const readline = require('readline');

const REPO_ROOT = join(__dirname, '..');
const GUILD = join(REPO_ROOT, 'guild');

// ── Tool Registry ──
const TOOLS = {
  classify: {
    description: 'Classify a natural language task into a product type with confidence score. Use FIRST to understand what kind of project this is.',
    inputSchema: {
      type: 'object',
      properties: {
        task: { type: 'string', description: 'Natural language task. e.g. "帮我做供应商后台管理系统"' }
      },
      required: ['task']
    }
  },
  plan: {
    description: 'Generate full execution plan: classify → team → milestones → gates → risks. Returns structured JSON.',
    inputSchema: {
      type: 'object',
      properties: {
        task: { type: 'string', description: 'Natural language task description. e.g. "做一个供应商后台管理系统"' }
      },
      required: ['task']
    }
  },
  capability: {
    description: 'Show full capability of a product type — which agents, modules, gates. Use after plan to understand what a product type needs.',
    inputSchema: {
      type: 'object',
      properties: {
        type: { type: 'string', enum: ['wechat-game','miniapp','web-app','dashboard','api-service','landing-page',
          'corp-site','admin-system','mobile-app',
          'research-report','strategy-consulting','brand-identity','visual-design',
          'content-project','unity-game','unreal-game','infra-project','ai-ml-project'] }
      },
      required: ['type']
    }
  },
  capabilities: {
    description: 'List ALL 18 product types AgentGraph can deliver. Use to explore what kinds of products are supported.',
    inputSchema: { type: 'object', properties: {} }
  },
  get_capability: {
    description: 'Get full capability JSON for a product type directly from capabilities.json (agents, modules, gates).',
    inputSchema: {
      type: 'object',
      properties: {
        type: { type: 'string', enum: ['wechat-game','miniapp','web-app','dashboard','api-service','landing-page',
          'corp-site','admin-system','mobile-app',
          'research-report','strategy-consulting','brand-identity','visual-design',
          'content-project','unity-game','unreal-game','infra-project','ai-ml-project'] }
      },
      required: ['type']
    }
  },
  chain: {
    description: 'Generate full agent execution chain — shows all agents in order with dispatch commands.',
    inputSchema: {
      type: 'object',
      properties: {
        task: { type: 'string', description: 'Task description' }
      },
      required: ['task']
    }
  },
  dispatch: {
    description: 'Dispatch an agent with full context (identity + rules + memory). Agent prompt is loaded and ready for LLM execution.',
    inputSchema: {
      type: 'object',
      properties: {
        agent: { type: 'string', description: 'Agent slug, e.g. "product-manager", "frontend-engineer"' },
        task: { type: 'string', description: 'Task for this agent to perform' }
      },
      required: ['agent', 'task']
    }
  },
  agents: {
    description: 'List all 40 available agents with their roles. Use to find the right agent for a task.',
    inputSchema: { type: 'object', properties: {} }
  },
  list_agents: {
    description: 'List all agents as structured JSON (slug, name, emoji, short description, division) parsed from guild.config.json.',
    inputSchema: { type: 'object', properties: {} }
  },
  gate: {
    description: 'Run quality gates on a handoff. Returns pass/fail with details.',
    inputSchema: {
      type: 'object',
      properties: {
        handoff: { type: 'number', description: 'Handoff ID to check' }
      },
      required: ['handoff']
    }
  },
  list_gates: {
    description: 'List all 5 quality gates (id, name, label, description) — completeness, syntax, behavior, playability, agent-standards.',
    inputSchema: { type: 'object', properties: {} }
  },
  fix: {
    description: 'Auto-fix common gate failures. 7 fix strategies available.',
    inputSchema: {
      type: 'object',
      properties: {
        file: { type: 'string', description: 'HTML file to fix' },
        all: { type: 'boolean', description: 'Apply all fixes' },
        'dry-run': { type: 'boolean', description: 'Preview fixes without applying' }
      },
      required: ['file']
    }
  },
  doctor: {
    description: 'System health check — 7 diagnostic checks. Use to verify AgentGraph is working correctly.',
    inputSchema: { type: 'object', properties: {} }
  },
  init: {
    description: 'Initialize a new project from template. 9 templates available.',
    inputSchema: {
      type: 'object',
      properties: {
        template: { type: 'string', description: 'Template name' },
        directory: { type: 'string', description: 'Target directory' }
      },
      required: ['template', 'directory']
    }
  },
  templates: {
    description: 'List available project templates.',
    inputSchema: { type: 'object', properties: {} }
  },
  status: {
    description: 'Show project status — handoffs, dispatches, memory.',
    inputSchema: {
      type: 'object',
      properties: {
        all: { type: 'boolean', description: 'Show all status details' }
      }
    }
  },
  memory: {
    description: 'View agent memory/history. Agents remember past work.',
    inputSchema: {
      type: 'object',
      properties: {
        agent: { type: 'string', description: 'Agent slug' },
        all: { type: 'boolean', description: 'Show all agents' }
      }
    }
  },
  help: {
    description: 'Get full AI manifest — all commands, agents, product types, workflows.',
    inputSchema: { type: 'object', properties: {} }
  },
  create_handoff: {
    description: 'Create handoff from Agent A to Agent B — the core of AgentGraph collaboration.',
    inputSchema: {
      type: 'object',
      properties: {
        from: { type: 'string', description: 'Source agent slug' },
        to: { type: 'string', description: 'Target agent slug' },
        path: { type: 'string', description: 'Path to deliverables directory' },
        message: { type: 'string', description: 'Optional message' }
      },
      required: ['from', 'to', 'path']
    }
  },
  check_handoff: {
    description: 'Check handoff completeness — which artifacts are provided vs missing.',
    inputSchema: {
      type: 'object',
      properties: {
        handoff_id: { type: 'number', description: 'Handoff ID' }
      },
      required: ['handoff_id']
    }
  },
  list_handoffs: {
    description: 'List all handoffs, optionally filtered by status.',
    inputSchema: {
      type: 'object',
      properties: {
        status: { type: 'string', enum: ['draft', 'ready', 'accepted', 'incomplete', 'needs_fix'] }
      }
    }
  },
  run_graph: {
    description: 'Execute a named graph workflow. Use after plan to run the full agent pipeline.',
    inputSchema: {
      type: 'object',
      properties: {
        graph: { type: 'string', description: 'Graph name: feature-dev, game-mvp, research-report, unity-game, iterate, startup-mvp' },
        task: { type: 'string', description: 'Task description' },
        path: { type: 'string', description: 'Working directory path' },
        dry_run: { type: 'boolean', description: 'Preview without executing' }
      },
      required: ['graph', 'task']
    }
  },
  system_health: {
    description: 'Full system health check — agent count, handoff count, self-test summary, issues found.',
    inputSchema: { type: 'object', properties: {} }
  }
};

// ── Tool Implementations ──
function runGuild(args) {
  try {
    const result = execSync(`${GUILD} ${args}`, {
      cwd: REPO_ROOT,
      timeout: 30000,
      maxBuffer: 1024 * 1024,
      encoding: 'utf8'
    });
    return result;
  } catch (e) {
    return e.stdout || '' + '\n' + (e.stderr || '') + '\nExit: ' + (e.status || 1);
  }
}

// ── Smart routing helpers ──
function runGuildJson(args, opts = {}) {
  // Accept either a bare subcommand ("plan ...", GUILD prefix added) or a full command line
  const cmd = (typeof args === 'string' && args.startsWith(GUILD)) ? args : `${GUILD} ${args}`;
  try {
    const result = execSync(cmd, {
      cwd: REPO_ROOT,
      timeout: opts.timeout || 30000,
      maxBuffer: opts.maxBuffer || 1024 * 1024,
      encoding: 'utf8',
      env: { ...process.env, AG_AI_MODE: '1' }
    });
    // Try to extract JSON from output (may have stderr noise)
    const jsonMatch = result.match(/(\{[\s\S]*\}|\[[\s\S]*\])/);
    if (jsonMatch) {
      try { return JSON.parse(jsonMatch[0]); }
      catch(e) { /* fall through */ }
    }
    return { _raw: result.trim() };
  } catch (e) {
    const output = (e.stdout || '') + '\n' + (e.stderr || '');
    const jsonMatch = output.match(/(\{[\s\S]*\}|\[[\s\S]*\])/);
    if (jsonMatch) {
      try { return JSON.parse(jsonMatch[0]); }
      catch(ex) { return { _error: output.trim(), _exit: e.status || 1 }; }
    }
    return { _error: output.trim(), _exit: e.status || 1 };
  }
}

// Routing levels
const PASSTHROUGH = new Set(['agents', 'templates', 'help', 'fix', 'status', 'chain']);
const JSON_TOOLS = new Set(['plan', 'capability', 'capabilities', 'dispatch', 'gate',
  'doctor', 'init', 'memory', 'classify', 'create_handoff', 'check_handoff',
  'list_handoffs', 'run_graph', 'system_health', 'get_agent', 'list_gates']);
const COMPOSITE = new Set(['system_health']);

function jsonOrText(result) {
  if (result && typeof result === 'object' && !result._raw && !result._error) {
    return JSON.stringify(result, null, 2);
  }
  return typeof result === 'string' ? result : (result._raw || result._error || JSON.stringify(result));
}

const IMPL = {
  // ── JSON_TOOLS: parsed via runGuildJson (AG_AI_MODE=1, JSON extracted) ──
  classify: (args) => {
    const result = runGuildJson(`classify --json ${args.task}`);
    // If guild classify returned JSON directly, use it; otherwise parse text
    if (result && result.type) {
      return JSON.stringify(result, null, 2);
    }
    // Fallback: parse text output
    const text = runGuild(`classify ${args.task}`);
    const typeMatch = text.match(/\(([a-z][a-z-]+)\)/);
    const confMatch = text.match(/置信度[：:]\s*([\d.]+)/);
    return JSON.stringify({
      type: typeMatch ? typeMatch[1] : 'unknown',
      confidence: confMatch ? parseFloat(confMatch[1]) : 0,
      _raw: text
    }, null, 2);
  },
  plan: (args) => {
    try {
      const result = runGuildJson(`plan --json ${args.task}`);
      if (result && result.summary) {
        return JSON.stringify(result, null, 2);
      }
    } catch(e) { /* fall through */ }
    return runGuild(`plan ${args.task}`);
  },
  capability: (args) => runGuildJson(`capability ${args.type}`),
  capabilities: () => runGuildJson('capabilities'),
  dispatch: (args) => runGuildJson(`dispatch ${args.agent} "${args.task}"`),
  gate: (args) => runGuildJson(`gate --handoff ${args.handoff}`),
  doctor: () => runGuildJson('doctor'),
  init: (args) => runGuildJson(`init --template ${args.template} ${args.directory}`),
  memory: (args) => {
    if (args.all) return runGuildJson('memory --all');
    return runGuildJson(`memory ${args.agent || ''}`);
  },

  // ── PASSTHROUGH: text output kept as-is ──
  chain: (args) => runGuild(`chain ${args.task}`),
  agents: () => runGuild('agents'),
  fix: (args) => {
    let cmd = `fix --file ${args.file}`;
    if (args.all) cmd += ' --all';
    if (args['dry-run']) cmd += ' --dry-run';
    return runGuild(cmd);
  },
  templates: () => runGuild('templates'),
  status: (args) => runGuild(args.all ? 'status --all' : 'status'),
  help: () => {
    const manifest = JSON.parse(readFileSync(join(REPO_ROOT, 'ai-manifest.json'), 'utf8'));
    // Add MCP-specific metadata
    manifest.mcp_server = {
      version: '0.5.0',
      tool_count: Object.keys(TOOLS).length,
      routing: { passthrough: [...PASSTHROUGH], json: [...JSON_TOOLS], composite: [...COMPOSITE] }
    };
    return JSON.stringify(manifest, null, 2);
  },

  // ── Structured discovery tools (v0.5) ──
  list_agents: () => {
    // Parse agent list from guild.config.json for structured output
    try {
      const config = JSON.parse(readFileSync(join(REPO_ROOT, 'guild.config.json'), 'utf8'));
      const agents = config.agents.map(a => {
        const file = join(REPO_ROOT, a.file);
        let emoji = '', short = '';
        if (existsSync(file)) {
          const content = readFileSync(file, 'utf8');
          const emojiMatch = content.match(/^emoji:\s*(.+)$/m);
          const shortMatch = content.match(/^short:\s*(.+)$/m);
          emoji = emojiMatch ? emojiMatch[1].trim() : '';
          short = shortMatch ? shortMatch[1].trim() : '';
        }
        return {
          slug: a.slug,
          name: a.division ? a.slug.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase()) : a.slug,
          emoji,
          short,
          division: a.division
        };
      });
      return JSON.stringify(agents, null, 2);
    } catch(e) {
      return runGuild('agents');
    }
  },
  get_capability: (args) => {
    try {
      const caps = JSON.parse(readFileSync(join(REPO_ROOT, 'capabilities.json'), 'utf8'));
      const t = caps.product_types[args.type];
      if (!t) return JSON.stringify({ error: `Unknown type: ${args.type}`, available: Object.keys(caps.product_types) });
      return JSON.stringify(t, null, 2);
    } catch(e) {
      return runGuild(`capability ${args.type}`);
    }
  },
  list_gates: () => {
    return JSON.stringify([
      { id: 1, name: 'completeness', label: '完整性', description: '检查所有必需交付物是否齐备' },
      { id: 2, name: 'syntax', label: '语法', description: 'JSON/HTML/JS/CSS 语法验证' },
      { id: 3, name: 'behavior', label: '行为', description: '运行时行为测试' },
      { id: 4, name: 'playability', label: '可玩性/可用性', description: '游戏可玩性或产品可用性检查' },
      { id: 5, name: 'agent-standards', label: 'Agent标准', description: 'Agent 交接合规性检查' }
    ], null, 2);
  },

  // ── Execution / check / health tools (v0.5 Task 3) ──
  create_handoff: (args) => {
    // 路径加引号防止空格分割（cmd_handoff 按位置取参）
    let cmd = `handoff --from ${args.from} --to ${args.to} --path "${args.path}"`;
    if (args.message) cmd += ` --message "${args.message}"`;
    const output = runGuild(cmd);
    // Parse handoff ID from output
    const idMatch = output.match(/#(\d+)/);
    return JSON.stringify({
      handoff_id: idMatch ? parseInt(idMatch[1]) : null,
      from: args.from, to: args.to, path: args.path,
      _output: output.trim()
    }, null, 2);
  },
  check_handoff: (args) => {
    const output = runGuild(`check --handoff ${args.handoff_id}`);
    // 实际 CLI 输出为「完整度: X/Y 项」+「所有必需项已满足 ✓」，
    // brief 的 missing/provided 正则不匹配，改为主解析完整度行、保留原正则兜底
    const completeMatch = output.match(/完整度[:：]\s*(\d+)\s*\/\s*(\d+)/);
    const providedNum = completeMatch ? completeMatch[1]
      : ((output.match(/provided[：:]\s*(\d+)/i) || [null, '0'])[1]);
    const missingNum = completeMatch ? String(parseInt(completeMatch[2]) - parseInt(completeMatch[1]))
      : ((output.match(/missing[：:]\s*(\d+)/i) || [null, '0'])[1]);
    // 用状态行判断，避免 'incomplete' 包含 'complete' 子串的误判
    const statusMatch = output.match(/状态[:：]\s*([\w-]+)/);
    const passed = (statusMatch && statusMatch[1] === 'ready')
      || output.includes('所有必需项已满足')
      || output.includes('[OK]')
      || /\bcomplete\b/.test(output);
    return JSON.stringify({
      handoff_id: args.handoff_id,
      passed,
      provided: parseInt(providedNum) || 0,
      missing: parseInt(missingNum) || 0,
      _output: output.trim()
    }, null, 2);
  },
  list_handoffs: (args) => {
    let cmd = 'list --handoffs';
    if (args.status) cmd += ` --status ${args.status}`;
    const output = runGuild(cmd);
    // CLI 端 list.sh 尚不消费 --status（实测被忽略），改为客户端按行过滤 "(status)" 标记
    if (args.status) {
      return output.split('\n').filter(line => line.includes(`(${args.status})`)).join('\n');
    }
    return output;
  },
  run_graph: (args) => {
    let cmd = `graph run --graph ${args.graph} --path ${args.path || '/tmp/agentgraph-run'}`;
    if (args.dry_run) cmd += ' --dry-run';
    const output = runGuild(cmd);
    // Parse node statuses from 节点明细 ([OK]/[FAIL] 行)
    const completed = [];
    const failed = [];
    const completedRe = /\[OK\].*?(\w+)/g;
    const failedRe = /\[FAIL\].*?(\w+)/g;
    let m;
    while ((m = completedRe.exec(output)) !== null) completed.push(m[1]);
    while ((m = failedRe.exec(output)) !== null) failed.push(m[1]);
    let status = failed.length === 0 ? 'success' : 'partial_failure';
    // 图不存在/执行出错时 CLI 输出错误标记，判定为 error
    if (output.includes('Graph file not found') || /\[ERR\]/.test(output)) status = 'error';
    return JSON.stringify({
      graph: args.graph,
      status,
      nodes: { completed, failed },
      _output: output.trim()
    }, null, 2);
  },
  system_health: () => {
    const results = {};
    try {
      // Doctor check
      const doctor = runGuild('doctor');
      results.doctor = doctor.trim();

      // Agent count
      try {
        const config = JSON.parse(readFileSync(join(REPO_ROOT, 'guild.config.json'), 'utf8'));
        results.agent_count = config.agents.length;
      } catch(e) { results.agent_count = 'unknown'; }

      // Handoff count
      try {
        const hdir = join(REPO_ROOT, 'handoffs');
        if (existsSync(hdir)) {
          results.handoff_count = require('fs').readdirSync(hdir).filter(f => f.endsWith('.json') && !f.startsWith('self-test-')).length;
        } else { results.handoff_count = 0; }
      } catch(e) { results.handoff_count = 'unknown'; }

      // Quick self-test
      const selfTest = execSync('bash scripts/self-test.sh --quick', {
        cwd: REPO_ROOT, timeout: 30000, encoding: 'utf8'
      });
      const passMatch = selfTest.match(/(\d+)\s+passed/);
      const failMatch = selfTest.match(/(\d+)\s+failed/);
      results.self_test = {
        passed: passMatch ? parseInt(passMatch[1]) : 0,
        failed: failMatch ? parseInt(failMatch[1]) : 0
      };

      results.status = (results.self_test.failed === 0) ? 'healthy' : 'degraded';
      results.issues = [];
      if (results.self_test.failed > 0) results.issues.push(`${results.self_test.failed} self-tests failing`);
      if (results.agent_count === 'unknown') results.issues.push('Cannot read agent config');
      if (results.handoff_count === 'unknown') results.issues.push('Cannot read handoffs directory');

      return JSON.stringify(results, null, 2);
    } catch(e) {
      return JSON.stringify({ status: 'error', error: e.message }, null, 2);
    }
  }
};

// ── MCP Protocol Handler ──
class MCPServer {
  constructor() {
    this.tools = TOOLS;
    this.name = 'AgentGraph';
    this.version = '3.0.0';
  }

  async handleRequest(request) {
    const { method, params, id } = request;

    switch (method) {
      case 'initialize':
        return {
          jsonrpc: '2.0', id,
          result: {
            protocolVersion: '2024-11-05',
            serverInfo: { name: this.name, version: this.version },
            capabilities: { tools: {} }
          }
        };

      case 'tools/list':
        return {
          jsonrpc: '2.0', id,
          result: {
            tools: Object.entries(this.tools).map(([name, def]) => ({
              name,
              description: def.description,
              inputSchema: def.inputSchema
            }))
          }
        };

      case 'tools/call':
        const { name, arguments: args } = params;
        const impl = IMPL[name];
        if (!impl) {
          return {
            jsonrpc: '2.0', id,
            error: { code: -32601, message: `Unknown tool: ${name}` }
          };
        }
        try {
          const result = await Promise.resolve(impl(args || {}));
          return {
            jsonrpc: '2.0', id,
            result: { content: [{ type: 'text', text: jsonOrText(result) }] }
          };
        } catch (e) {
          return {
            jsonrpc: '2.0', id,
            result: { content: [{ type: 'text', text: `Error: ${e.message}\nFix: Check guild ${name} --help for usage.` }], isError: true }
          };
        }

      case 'notifications/initialized':
        return null; // No response needed for notifications

      default:
        return {
          jsonrpc: '2.0', id,
          error: { code: -32601, message: `Unknown method: ${method}` }
        };
    }
  }

  async start() {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: false });
    for await (const line of rl) {
      try {
        const request = JSON.parse(line);
        const response = await this.handleRequest(request);
        if (response) process.stdout.write(JSON.stringify(response) + '\n');
      } catch (e) {
        process.stderr.write(`MCP parse error: ${e.message}\n`);
      }
    }
  }
}

// ── HTTP Mode (for remote hosts without stdio MCP) ──
function startHTTP(port) {
  const http = require('http');
  const server = new MCPServer();
  http.createServer(async (req, res) => {
    if (req.method === 'POST' && req.url === '/mcp') {
      let body = '';
      req.on('data', c => body += c);
      req.on('end', async () => {
        const response = await server.handleRequest(JSON.parse(body));
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify(response));
      });
    } else if (req.url === '/tools') {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ tools: TOOLS }));
    } else {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('AgentGraph MCP Server v3.0.0\nPOST /mcp for MCP protocol\nGET /tools for tool list');
    }
  }).listen(port, () => {
    process.stderr.write(`AgentGraph MCP HTTP server on port ${port}\n`);
  });
}

// ── Main ──
const args = process.argv.slice(2);
if (args.includes('--http')) {
  const port = parseInt(args[args.indexOf('--http') + 1]) || 3000;
  startHTTP(port);
} else {
  new MCPServer().start().catch(e => { process.stderr.write(`MCP server error: ${e.message}\n`); process.exit(1); });
}
