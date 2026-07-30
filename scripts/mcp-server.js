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
  plan: {
    description: 'AI task analysis — natural language task → product type + agents + modules + gates. Use this FIRST for any new task.',
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
        type: { type: 'string', enum: ['wechat-game','miniapp','web-app','dashboard','api-service','landing-page','corp-site','admin-system','mobile-app'] }
      },
      required: ['type']
    }
  },
  capabilities: {
    description: 'List ALL 9 product types AgentGraph can deliver. Use to explore what kinds of products are supported.',
    inputSchema: { type: 'object', properties: {} }
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

const IMPL = {
  plan: (args) => runGuild(`plan ${args.task}`),
  capability: (args) => runGuild(`capability ${args.type}`),
  capabilities: () => runGuild('capabilities'),
  chain: (args) => runGuild(`chain ${args.task}`),
  dispatch: (args) => runGuild(`dispatch ${args.agent} "${args.task}"`),
  agents: () => runGuild('agents'),
  gate: (args) => runGuild(`gate --handoff ${args.handoff}`),
  fix: (args) => {
    let cmd = `fix --file ${args.file}`;
    if (args.all) cmd += ' --all';
    if (args['dry-run']) cmd += ' --dry-run';
    return runGuild(cmd);
  },
  doctor: () => runGuild('doctor'),
  init: (args) => runGuild(`init --template ${args.template} ${args.directory}`),
  templates: () => runGuild('templates'),
  status: (args) => runGuild(args.all ? 'status --all' : 'status'),
  memory: (args) => {
    if (args.all) return runGuild('memory --all');
    return runGuild(`memory ${args.agent || ''}`);
  },
  help: () => {
    const manifest = JSON.parse(readFileSync(join(REPO_ROOT, 'ai-manifest.json'), 'utf8'));
    return JSON.stringify(manifest, null, 2);
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
            result: { content: [{ type: 'text', text: typeof result === 'string' ? result : JSON.stringify(result, null, 2) }] }
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
