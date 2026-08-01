# AgentGraph v0.5 — MCP 多框架适配层 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 升级 `scripts/mcp-server.js`，15 个 MCP Tool 覆盖完整公司 + Agent 超市两种模式，智能路由三级输出。

**Architecture:** 纯 Node.js 内置模块（child_process/fs/readline/http），所有 Tool 底层调 `guild` CLI。输出分三级：纯文本透传（Passthrough）、JSON 解析（JSON Parse）、组合调用（Composite）。不改 CLI，不改目录结构。

**Tech Stack:** Node.js (≥18), MCP Protocol 2024-11-05

**Spec:** `docs/superpowers/specs/2026-08-01-agentgraph-v0.5-mcp-adapter.md`

## Global Constraints

- 只改 `scripts/mcp-server.js`，不动其他文件
- 现有 14 个 Tool 向后兼容，schema 可扩展但不可删字段
- `capability.types` enum 必须 18 种（同步 capabilities.json）
- 不引入 npm 依赖，只用 Node.js 内置模块
- `bash scripts/self-test.sh` 18/18 通过

---

### Task 1: 重构基础架构 — 智能路由 + JSON 解析框架

**Files:**
- Modify: `scripts/mcp-server.js`

**Interfaces:**
- Consumes: 现有 `runGuild()`, `TOOLS`, `IMPL`, `MCPServer`
- Produces: `runGuildJson()`, `JSON_PARSE` set, `PASSTHROUGH` set, refactored `IMPL` dispatch

- [ ] **Step 1: 添加 JSON 解析工具函数**

在 `runGuild` 函数之后添加：

```javascript
// ── Smart routing helpers ──
function runGuildJson(args, opts = {}) {
  const cmd = typeof args === 'string' ? args : `${GUILD} ${args}`;
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
```

- [ ] **Step 2: 添加 list_agents 结构化输出**

修改现有 `agents` IMPL（或新增 `list_agents`），输出结构化 JSON。先保留 `agents` 文本输出不变，新增 `list_agents`：

```javascript
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
```

- [ ] **Step 3: 更新 capability types enum 为 18 种**

修改 `TOOLS.capability.inputSchema.properties.type.enum`：

```javascript
enum: ['wechat-game','miniapp','web-app','dashboard','api-service','landing-page',
       'corp-site','admin-system','mobile-app',
       'research-report','strategy-consulting','brand-identity','visual-design',
       'content-project','unity-game','unreal-game','infra-project','ai-ml-project']
```

同样更新 `TOOLS.capabilities` 的 description 为 `'List ALL 18 product types...'`

- [ ] **Step 4: 新增 get_capability 结构化输出**

```javascript
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
```

- [ ] **Step 5: 新增 list_gates**

```javascript
list_gates: () => {
  return JSON.stringify([
    { id: 1, name: 'completeness', label: '完整性', description: '检查所有必需交付物是否齐备' },
    { id: 2, name: 'syntax', label: '语法', description: 'JSON/HTML/JS/CSS 语法验证' },
    { id: 3, name: 'behavior', label: '行为', description: '运行时行为测试' },
    { id: 4, name: 'playability', label: '可玩性/可用性', description: '游戏可玩性或产品可用性检查' },
    { id: 5, name: 'agent-standards', label: 'Agent标准', description: 'Agent 交接合规性检查' }
  ], null, 2);
},
```

- [ ] **Step 6: 验证向后兼容 — 测试现有 Tool 仍可用**

```bash
cd /mnt/e/agentguild && node -e "
const { execSync } = require('child_process');
// 启动 MCP server 做 smoke test
const server = require('child_process').spawn('node', ['scripts/mcp-server.js'], { stdio: ['pipe', 'pipe', 'pipe'] });
server.stdin.write(JSON.stringify({jsonrpc:'2.0',id:1,method:'initialize',params:{protocolVersion:'2024-11-05',capabilities:{}}})+'\n');
server.stdin.write(JSON.stringify({jsonrpc:'2.0',id:2,method:'tools/list',params:{}})+'\n');
setTimeout(() => {
  server.kill();
  console.log('OK: MCP server starts and responds');
}, 3000);
server.stdout.on('data', d => console.log('RESPONSE:', d.toString().substring(0,200)));
"
```

- [ ] **Step 7: Commit**

```bash
cd /mnt/e/agentguild
git add scripts/mcp-server.js
git commit -m "refactor: mcp-server 智能路由框架 + list_agents/list_gates/get_capability

- 添加 runGuildJson() JSON 解析引擎(AG_AI_MODE=1)
- 三级路由: PASSTHROUGH/JSON_TOOLS/COMPOSITE
- capability types enum 9→18
- 新增: list_agents(结构化), get_capability(JSON), list_gates(结构化)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: 新增规划类 Tools — classify_task + generate_plan

**Files:**
- Modify: `scripts/mcp-server.js`

**Interfaces:**
- Consumes: Task 1 的 `runGuildJson()`, `jsonOrText()`
- Produces: `classify_task`, `generate_plan` (JSON 解析 CLI 输出)

- [ ] **Step 1: 添加 classify_task Tool 定义到 TOOLS**

```javascript
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
```

- [ ] **Step 2: 添加 classify_task IMPL**

```javascript
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
```

- [ ] **Step 3: 更新现有 plan Tool — 改用 JSON 模式**

修改 `IMPL.plan`，直接返回 JSON plan：

```javascript
plan: (args) => {
  try {
    const result = runGuildJson(`plan --json ${args.task}`);
    if (result && result.summary) {
      return JSON.stringify(result, null, 2);
    }
  } catch(e) { /* fall through */ }
  return runGuild(`plan ${args.task}`);
},
```

更新 `TOOLS.plan.description`：`'Generate full execution plan: classify → team → milestones → gates → risks. Returns structured JSON.'`

- [ ] **Step 4: 验证**

```bash
cd /mnt/e/agentguild

# 测试 classify via guild CLI (底层)
AG_AI_MODE=1 ./guild classify --json "做供应商后台"
# Expected: { type: "admin-system", confidence: 0.8, ... }

# 测试 plan --json
AG_AI_MODE=1 ./guild plan --json "做塔罗小程序" 2>/dev/null | node -e "process.stdin.resume();let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const j=JSON.parse(d);console.log('type:',j.product_type,'team:',j.team.members.length)})"
# Expected: type: miniapp team: N
```

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/agentguild
git add scripts/mcp-server.js
git commit -m "feat: mcp-server classify_task + generate_plan (JSON解析)

classify_task: guild classify --json → 结构化输出
plan: 改用 guild plan --json → 直接返回 JSON plan

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: 新增执行+检查+健康类 Tools

**Files:**
- Modify: `scripts/mcp-server.js`

**Interfaces:**
- Consumes: Task 1-2 的基础设施
- Produces: `create_handoff`, `check_handoff`, `list_handoffs`, `run_graph`, `system_health`, 重构的 `dispatch`, `gate`

- [ ] **Step 1: 添加 create_handoff + check_handoff + list_handoffs**

```javascript
// TOOLS 注册
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
```

```javascript
// IMPL
create_handoff: (args) => {
  let cmd = `handoff --from ${args.from} --to ${args.to} --path ${args.path}`;
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
  const passed = output.includes('[OK]') || output.includes('complete');
  const missingMatch = output.match(/missing[：:]\s*(\d+)/i);
  const providedMatch = output.match(/provided[：:]\s*(\d+)/i);
  return JSON.stringify({
    handoff_id: args.handoff_id,
    passed,
    provided: providedMatch ? parseInt(providedMatch[1]) : 0,
    missing: missingMatch ? parseInt(missingMatch[1]) : 0,
    _output: output.trim()
  }, null, 2);
},
list_handoffs: (args) => {
  let cmd = 'list --handoffs';
  if (args.status) cmd += ` --status ${args.status}`;
  return runGuild(cmd);
},
```

- [ ] **Step 2: 添加 run_graph**

```javascript
// TOOLS
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
```

```javascript
// IMPL
run_graph: (args) => {
  let cmd = `graph run --graph ${args.graph} --path ${args.path || '/tmp/agentgraph-run'}`;
  if (args.dry_run) cmd += ' --dry-run';
  const output = runGuild(cmd);
  // Parse node statuses
  const completed = [];
  const failed = [];
  const completedRe = /\[OK\].*?(\w+)/g;
  const failedRe = /\[FAIL\].*?(\w+)/g;
  let m;
  while ((m = completedRe.exec(output)) !== null) completed.push(m[1]);
  while ((m = failedRe.exec(output)) !== null) failed.push(m[1]);
  return JSON.stringify({
    graph: args.graph,
    status: failed.length === 0 ? 'success' : 'partial_failure',
    nodes: { completed, failed },
    _output: output.trim()
  }, null, 2);
},
```

- [ ] **Step 3: 添加 system_health（组合调用）**

```javascript
// TOOLS
system_health: {
  description: 'Full system health check — agent count, handoff count, self-test summary, issues found.',
  inputSchema: { type: 'object', properties: {} }
},
```

```javascript
// IMPL (Level 3 composite)
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
},
```

- [ ] **Step 4: 验证所有新 Tool**

```bash
cd /mnt/e/agentguild

# 测试 create_handoff
./guild handoff --from product-manager --to ux-researcher --path /tmp/test-handoff 2>&1 | head -5

# 测试 system_health
node -e "
const {execSync} = require('child_process');
// Quick inline test of composite logic
const config = JSON.parse(require('fs').readFileSync('guild.config.json','utf8'));
console.log('agent_count:', config.agents.length);
const hdir = 'handoffs';
const hcount = require('fs').readdirSync(hdir).filter(f=>f.endsWith('.json')&&!f.startsWith('self-test-')).length;
console.log('handoff_count:', hcount);
console.log('OK');
" && echo "system_health components OK"
```

- [ ] **Step 5: Commit**

```bash
cd /mnt/e/agentguild
git add scripts/mcp-server.js
git commit -m "feat: mcp-server 执行+检查+健康 Tools (create_handoff/run_graph/system_health)

create_handoff: Agent A→B 交接，返回 handoff_id
check_handoff: 完整性检查，返回 passed/provided/missing
list_handoffs: 交接列表(支持 status 过滤)
run_graph: Graph 工作流执行(支持 dry-run)
system_health: doctor + agent_count + handoff_count + self-test 组合

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 最终验证 + 文档

**Files:**
- Modify: `scripts/mcp-server.js` (final cleanup)
- Modify: `docs/superpowers/plans/` (this plan)

- [ ] **Step 1: 更新 TOOLS.help 输出使 AI 框架可发现新 Tool**

```javascript
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
```

- [ ] **Step 2: 运行完整自测**

```bash
cd /mnt/e/agentguild && bash scripts/self-test.sh
```
Expected: 18/18 全部通过

- [ ] **Step 3: Node.js 语法检查**

```bash
cd /mnt/e/agentguild && node --check scripts/mcp-server.js && echo "OK"
```
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
cd /mnt/e/agentguild
git add scripts/mcp-server.js
git commit -m "chore: mcp-server v0.5 最终验证 + help 元数据

help Tool 返回 mcp_server metadata (version/tool_count/routing)
self-test 18/18 通过
node --check 语法通过

Co-Authored-By: Claude <noreply@anthropic.com>"
```
