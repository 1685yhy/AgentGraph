# AgentGraph v0.7a — 真实 LLM 端到端验证 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用真实 DeepSeek LLM 跑通 `guild run` 完整链路（小任务落地页 + 中任务系统自选），证明端到端可交付，并把缺陷整理成 v0.7c backlog。

**Architecture:** 4 个任务：Task 1 点亮环境（.gitignore + .env.local + lib.sh 自动加载 + LLM 冒烟测试）→ Task 2 阶段1 小任务真实交付 → Task 3 阶段2 中任务质量闭环（修复回路 ≤5 轮）→ Task 4 阶段3 复盘（backlog + 证据报告 + 推送）。其中需要用户输入的步骤（API key、需求出题、计划批准）由主会话（协调者）与用户交互，不委派给子代理。

**Tech Stack:** Bash 3.2+, Node.js ≥18, DeepSeek API (deepseek-chat), guild CLI, superpowers:subagent-driven-development

**Spec:** `docs/superpowers/specs/2026-08-02-agentgraph-v0.7a-real-validation-design.md`

## Global Constraints

- LLM 只用 DeepSeek：`AG_LLM_PROVIDER=deepseek`、`AG_LLM_MODEL=deepseek-chat`
- `.env.local` 永不上传 git（必须忽略 + 不 `git add`）
- `bash scripts/self-test.sh` 18/18 无回归
- 阶段2 修复回路硬上限 5 轮，超限转人工判定
- classify 置信度 <0.8 时必须列出候选类型由用户选择，不自动放行
- 每阶段证据报告落盘 `docs/evidence/v0.7a/`（运行日志、Gate 输出、审查报告、修复记录）

---

### Task 1: 环境配置 — 真实 LLM 点亮

**Files:**
- Modify: `.gitignore`
- Create: `.env.local`（gitignored，含真实 key，不提交）
- Modify: `scripts/lib.sh`（顶部加 .env.local 自动加载）

**Interfaces:**
- Produces: `AG_LLM_PROVIDER=deepseek` / `AG_LLM_API_KEY=<user-key>` / `AG_LLM_MODEL=deepseek-chat` 环境变量，所有 guild 子命令（run/run-agent/classify）自动可见
- 后续任务依赖：Task 2/3 执行 `guild run` 时无需手动 export

- [ ] **Step 1: .gitignore 忽略 .env.local**

在 `.gitignore` 末尾追加：
```bash
# Local secrets (never committed)
.env.local
.env
```
验证：`git check-ignore .env.local` 输出 `.env.local` 即成功。

- [ ] **Step 2: 获取 DeepSeek API key 并写入 .env.local**

由主会话向用户索取 key（格式 `sk-...`，可在 platform.deepseek.com 创建）。创建 `.env.local`：
```bash
AG_LLM_PROVIDER=deepseek
AG_LLM_API_KEY=sk-xxx            # ← 替换为用户提供的真实 key
AG_LLM_MODEL=deepseek-chat
AG_LLM_MAX_TOKENS=4096
AG_LLM_TEMPERATURE=0.7
```
验证：`.env.local` 不出现在 `git status`（已忽略）；内容含真实 key。

- [ ] **Step 3: lib.sh 顶部加 .env.local 自动加载**

在 `scripts/lib.sh` 的 shebang/注释块之后、第一个函数之前插入：
```bash
# ── Local env (.env.local, gitignored) ──────────────────────────────
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../.env.local" ]]; then
  set -a
  . "$(dirname "${BASH_SOURCE[0]}")/../.env.local"
  set +a
fi
```
（lib.sh 被 nexus.sh、run.sh、agent-runner.sh、event-bus.sh 全部 source，一处加载全局生效。）

- [ ] **Step 4: LLM 冒烟测试（真实 DeepSeek 调用）**

```bash
cd /mnt/e/agentguild && . scripts/lib.sh && node scripts/runtime/llm-backend.js --prompt "只回复两个字：正常"
```
预期：输出 JSON，`text` 字段含"正常"，`usage` 有 token 数。若失败：检查 key 是否有效（400 = key 错，429 = 限流重试，网络错误检查代理）。

- [ ] **Step 5: 基线自测 18/18**

```bash
cd /mnt/e/agentguild && bash scripts/self-test.sh
```
预期：末尾 `18 passed, 0 failed / 18 total`。

- [ ] **Step 6: 提交**

```bash
cd /mnt/e/agentguild && git add .gitignore scripts/lib.sh && git commit -m "chore: v0.7a 环境配置 — .env.local 自动加载 + 忽略"
```
⚠️ 只 add 上面两个文件，**禁止** `git add .env.local`。

---

### Task 2: 阶段1 小任务 — 落地页真实交付

**Files:**
- Create: `docs/evidence/v0.7a/stage1/report.md`（证据报告）
- Create: 交付物（guild 运行时自动生成，路径由 run 输出指明）
- 业务文件（可能）：修复回路产生的修改

**Interfaces:**
- Consumes: Task 1 的 env 配置（真实 LLM 已通）
- Produces: 阶段1 证据报告；暴露的缺陷列表（供 Task 4 汇总）

- [ ] **Step 1: 起草落地页需求并请用户确认**

由主会话向用户展示需求草稿，例如：
> "做一个独立咖啡品牌落地页，包含：品牌主视觉 Hero 区、产品菜单区（4 款咖啡）、门店信息 + 预约按钮、移动端适配。风格：温暖木质调。"

用户确认或修改后定稿。

- [ ] **Step 2: 真实执行完整链路**

```bash
cd /mnt/e/agentguild && guild run --graph feature-dev --task "<定稿需求>" --yes
```
预期：classify → 解析 Graph → 多 Agent 依次执行（每节点调真实 DeepSeek）→ 全部节点 completed。记录：执行日志全文、各节点耗时、token 用量。

- [ ] **Step 3: 检查交付物与 Gate**

```bash
cd /mnt/e/agentguild && guild gate <deliverable-path>   # 按 run 输出的交付路径
```
预期：记录每个 Gate 通过/失败明细。交付物清单：列出产物文件、确认产物非空且可打开。

- [ ] **Step 4: 独立审查（不同角色盲审）**

主会话派发 1 个审查子代理（角色与执行 Agent 不同，如 ux-researcher 视角）审查交付物，输出审查报告（阻断性问题 / 建议 / 通过）。审查意见落盘到 stage1 证据目录。

- [ ] **Step 5: Gate 失败时走 1 轮轻量修复**

若 Gate 有失败项：生成修复任务 → 对应 Agent 修复 → 重跑 Gate。1 轮后仍失败则记录缺陷、不阻塞继续。

- [ ] **Step 6: 写阶段1证据报告**

创建 `docs/evidence/v0.7a/stage1/report.md`，包含：需求定稿、运行日志摘要、Gate 明细、独立审查意见、修复记录（如有）、缺陷清单、token 用量与花费估算。

- [ ] **Step 7: 提交**

```bash
cd /mnt/e/agentguild && git add docs/evidence/v0.7a/ && git commit -m "docs: v0.7a 阶段1 小任务证据报告 (落地页)"
```

---

### Task 3: 阶段2 中任务 — 系统自选质量闭环

**Files:**
- Create: `docs/evidence/v0.7a/stage2/report.md`
- Create: 交付物（guild 运行时生成）
- 业务文件（可能）：修复回路产生的修改

**Interfaces:**
- Consumes: Task 1 env；Task 2 的链路经验（已知坑提前规避）
- Produces: 中任务交付物 + 修复记录 + 证据报告（Task 4 汇总）

- [ ] **Step 1: 收集用户的真实业务需求**

主会话向用户索取一句话真实需求（如："做一个供应商管理系统，支持注册登录、供应商资料管理"）。用户出题后进入下一步。

- [ ] **Step 2: 系统分类 + 置信度检查**

```bash
cd /mnt/e/agentguild && guild classify "<用户需求>" --json
```
预期：输出类型 + 置信度。**置信度 ≥0.8** → 继续；**<0.8** → 展示候选类型列表，由用户选择后继续（禁止自动放行）。

- [ ] **Step 3: 生成计划 + 用户批准**

```bash
cd /mnt/e/agentguild && guild plan "<用户需求>"
```
主会话向用户展示计划（Agent 团队、里程碑、门禁），用户批准或要求调整。批准后记录计划文件路径，从计划中取 graph 名（无则用 `feature-dev`）。

- [ ] **Step 4: 全链路真实执行**

```bash
cd /mnt/e/agentguild && guild run --graph <graph名> --task "<用户需求>" --yes
```
预期：完整执行链全部 completed。记录日志、耗时、token 用量。

- [ ] **Step 5: Gate 检查 + 独立审查**

```bash
cd /mnt/e/agentguild && guild gate <deliverable-path>
```
主会话派发 1 个独立审查子代理（角色与执行者不同，如 qa-engineer + ux 双视角），输出审查报告：阻断性缺陷清单（必改）/ 建议清单。

- [ ] **Step 6: 修复回路（≤5 轮）**

循环（每轮 = 一个 fix 任务）：
1. 取审查报告中的阻断性缺陷（有则进入修复，无则跳出循环）
2. 生成修复任务 → 派发修复子代理（对应角色 Agent 视角）
3. 重跑受影响 Gate → 记录结果
4. 轮次 ≥5 仍未全清 → 停止，转人工判定（主会话向用户汇报，用户决定：继续/接受现状）

- [ ] **Step 7: 写阶段2证据报告**

创建 `docs/evidence/v0.7a/stage2/report.md`：需求、分类结果与置信度、批准的计划、执行日志摘要、Gate 明细、审查报告、每轮修复记录（缺陷→修复→验证→结果）、最终交付物清单、token 用量与花费估算。

- [ ] **Step 8: 提交**

```bash
cd /mnt/e/agentguild && git add docs/evidence/v0.7a/ && git commit -m "docs: v0.7a 阶段2 中任务证据报告"
```

---

### Task 4: 阶段3 复盘 — backlog + 收尾交付

**Files:**
- Create: `docs/superpowers/specs/backlog-v0.7c.md`
- Modify: `docs/evidence/v0.7a/`（汇总报告）

**Interfaces:**
- Consumes: Task 2/3 的缺陷清单、花费记录
- Produces: v0.7c 输入 backlog；最终验收报告

- [ ] **Step 1: 汇总缺陷到 backlog**

创建 `docs/superpowers/specs/backlog-v0.7c.md`，把 Task 2/3 暴露的所有缺陷/改进点分类整理：
- 运行时缺陷（Runtime）：链路断点、重试问题、超时、JSON 解析
- 模板缺口（Template）：某类型模板内容不足导致交付质量差
- 质量差距（Quality）：交付物与"用户不用改"标准的具体差距
- 每项格式：`- [ ] <缺陷>（阶段X，证据: <报告文件>）`

- [ ] **Step 2: 最终回归自测**

```bash
cd /mnt/e/agentguild && bash scripts/self-test.sh
```
预期：18/18。

- [ ] **Step 3: 写汇总报告 + 成本核算**

在 `docs/evidence/v0.7a/report.md` 汇总：两阶段执行统计（节点数、LLM 调用次数、总 token、花费估算）、成功标准逐条核对（对照 spec §2 七条）、缺陷总数与分布、backlog 链接。

- [ ] **Step 4: 推送 GitHub**

```bash
cd /mnt/e/agentguild && git add -A && git commit -m "docs: v0.7a 复盘汇总 + v0.7c backlog" && git push origin main
```
⚠️ 推送前确认 `git status` 无 `.env.local`（`git check-ignore .env.local` 必须输出路径）。

- [ ] **Step 5: 向用户交付验收**

主会话向用户汇报：两件交付物位置、成功标准达成情况、花费、backlog 摘要，请用户亲自验收交付物（"用户不用改"是否达成）。
