# v0.7c Backlog — v0.7a 真实 LLM 端到端验证复盘缺陷清单

**日期**: 2026-08-02
**来源**: v0.7a 阶段1（小任务·落地页）与阶段2（中任务·创意方案+游戏原型）真实执行暴露的全部缺陷/改进点
**用途**: v0.7c（系统鲁棒性）输入
**证据索引**: `docs/evidence/v0.7a/stage1/report.md`、`docs/evidence/v0.7a/stage2/report.md`、`docs/evidence/v0.7a/stage1/review-ux.md`、`docs/evidence/v0.7a/stage2/review-blind.md`

---

## 一、运行时缺陷（Runtime）— 链路断点与自动化缺口

- [ ] D2: `guild run --graph` 只自动执行初始节点，下游节点需手动 `run-agent` + 手工创建 handoff 接力，全自动多 Agent 流转未闭环（阶段2，证据: stage2/report.md §五/§十）— **头号候选**
- [ ] D1: LLM 输出在 4096 token 处被截断（无闭合标签/JS 断裂/文档腰斩），无系统级兜底（拆段生成/续写自动重试/输出长度监控），两阶段累计 5 次截断（阶段1+2，证据: stage1/report.md §六、stage2/report.md §十）
- [ ] D3: QA 节点基于截断/注入的上游文本评审，无「读真实文件」能力，产生不实结论（阶段1：第4款隐藏/156字超限/#000000 标题 3 条均不实；阶段2：B-3 自我更正、N-1 与 E2E 不符、复测缺陷 ID 描述漂移）（阶段1+2，证据: stage1/report.md §四/§六、stage2/report.md §十）
- [ ] D7: agent-standards Gate 对无「成功指标」章节的 agent 静默 SKIP，未产出实际检查（阶段1+2，证据: gate-run1/2.log、gate-stage1/2-run1.log）
- [ ] D9: `guild run-agent --upstream <id>` 标志未被解析（`run_agent()` 只取位置参数 `$3`），`--upstream` 被当作 upstream 值，注入静默退化为 `(upstream content unavailable)`；仅按位置传参才能注入（阶段2，证据: stage2/report.md §十、scripts/runtime/agent-runner.sh）
- [ ] D10: 链式 handoff 单输入缺陷：finalize 节点仅注入 review 结论、未注入 write 详细稿 → 定稿为浓缩重写版（6.6KB vs 10.7KB 细节丢失），仅靠编排者以 annex 补救（阶段2，证据: stage2/report.md §十）
- [ ] D12: fix 节点无文件访问能力：补丁引用不存在的变量名（gameOver/currentAbsurd/renderResult/drawCards(3)），与实际代码 API 不匹配，无法直接应用（阶段2，证据: stage2/report.md §十、fix 输出 221940.md）
- [ ] D13: 无补丁应用机制：fix 节点输出「修复方案文档」而非机器可应用变更，系统无 diff/apply/merge 管线，每轮修复依赖编排者手工落地组装（阶段2，证据: stage2/report.md §十）
- [ ] D14: 编排者组装引入缺陷：①组装时未在 startRound 重新启用 drawBtn → 只能抽 1 次卡；②「逆袭翻倍」按钮条件与第 5 局保底必逆袭冲突 → 入口永不出现（阶段2，证据: stage2/report.md §十）
- [ ] D16: agent-runner 丢弃 LLM usage 字段：llm-backend.js 返回 usage 但 runner 只取 text，token 用量无法自动统计，花费只能按字节估算（阶段2，证据: stage2/report.md §十、scripts/runtime/agent-runner.sh）
- [ ] D17: e2e-script.py 限频断言恒真：限频检查行从未再次点击分享按钮，限频逻辑从未被真实测试，且恰好掩盖「确认分享后 resetGame 清零 lastShareTime 绕过限频」的产品缺陷（B-1）；修复轮 1 已重写断言并修复限频绕过（阶段2，证据: stage2/report.md §十、review-blind.md §二）
- [ ] E2E 限频断言恒真教训（I-1）：测试断言必须验证真实行为，禁止「检查屏不可见」式空转通过；本轮修复轮 1 已按此重写并 34/34 重跑（阶段2，证据: stage2/report.md §七 I-1、review-blind-fix1.md）
- [ ] 分类器关键词覆盖弱：游戏/广告变现/裂变/创意相关类型关键词缺失或过弱，需求被判为 miniapp 误判（阶段2，证据: stage2/report.md §二、classify-output.txt）
- [ ] classify `--json` 输出非 JSON：CLI 契约未实现——`guild classify … --json` 实际输出纯文本（原 classify-output.json 内容非 JSON，修复轮 1 已改名 .txt），仅隐含覆盖（阶段2，证据: stage2/report.md §二、classify-output.txt）
- [ ] gate 日志重跑无时间戳/退出码：重跑与拷贝不可区分，审计性弱化——未来轮次应输出时间戳与退出码（阶段1+2，证据: gate-run1/2.log、gate-stage1/2-run1.log、gate-stage2-fix1.log）

## 二、模板缺口（Template）— 模板/门禁内容导致交付质量或误报

- [ ] D11: 「免费游玩」需求点未显式覆盖：定稿/详细稿均无「免费」表述（仅隐含于纯广告收入模型），playability 文档模式关键词与实际语义不匹配产生 WARN（阶段2，证据: stage2/report.md §十、gate-stage1-run1.log）
- [ ] D15: LLM 输出 emoji 编码丢失/乱码残留：按钮文案、QA 报告、详细稿「漏斗析/低频扰」等乱码（修复轮 1 已清理交付物与报告内残留；根因在 LLM 输出管线编码处理）（阶段2，证据: stage2/report.md §十）
- [ ] D6: 行为门禁对非游戏交付物误报：behavior/playability Gate 为游戏向指标（开始交互/音频手势/复玩/Canvas），对落地页/文档类交付物误报；canvas 检查对无 canvas 的游戏也跑（阶段1+2，证据: stage1/report.md §三/§六、gate-stage2-run1.log；无按交付类型选择 gate 的机制）
- [ ] D4: `scripts/test-runner.sh` bash 算术 bug：第 182/186/232 行算术比较产生语法错误（`[[: 0\n0: syntax error`），try-catch/localStorage 两项检查结果失真（阶段1，证据: stage1/report.md §六、gate-run1/2.log；阶段2 未复现，留存观察）

## 三、质量差距（Quality）— 交付物与「用户不用改」标准的差距

- [ ] 阶段1 UX 盲审 8 条建议（review-ux.md）：输入框高仅 19px（<44px 触控推荐，按钮 40px）、白字按钮对比度 3.27:1 未达 WCAG AA、菜单描述 15.2px 偏小、alert() 原生反馈+无真实后端、`.story-section` padding 覆盖容器、弹窗未用 `<form>`、emoji 装饰跨端观感、320px 品牌字偏满/safe-area 未用（阶段1，证据: stage1/review-ux.md §四）
- [ ] 阶段2 盲审建议：最近品类竞品对照（人生重开模拟器/运势测试 H5）未补，定稿仍自称「市场上没有的创意」；收入模型口径与分享频率限制口径已由修复轮 1 C-1 统一，竞品对照本轮未补（阶段2，证据: review-blind.md §一、review-blind-fix1.md；定稿 grep「人生重开」=0）
- [ ] M9: 卡牌「选中」高亮纯装饰无玩法语义，易造成玩家预期落空（阶段2，证据: review-blind.md §2.3、stage2/report.md §七）
- [ ] 创意方案「市场上没有」表述过度：实为已验证品类（文案生成+结果分享）的差异化成衣，需收敛表述（阶段2，证据: review-blind.md §一）
- [ ] M2: gameState 死变量：仅因行为门禁关键词检查而插入，从未被读取；需给 gate 换依赖（真实状态守卫检测）或移除变量（阶段2，证据: review-blind.md §2.2、stage2/report.md §七）
- [ ] 阶段1 报告遗留：review-ux.md 行数口径（91 行 vs 实际）、stage1/report.md §四 判定措辞（「有条件通过」vs review-ux.md「✅通过」）不一致，需统一（阶段1，协调者注记，证据: stage1/review-ux.md、stage1/report.md）
