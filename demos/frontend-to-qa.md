# Demo 3: Frontend Engineer → QA — 组件交付与质量验证交接

## 场景描述

前端工程师完成了"教师备课面板"核心组件的开发，需要将组件及其测试资产交接给 QA（Evidence Collector）。但组件的交付物缺少无障碍审计报告和测试覆盖率数据。前端补全后重新 handoff 通过，QA 接收并进入验证阶段。

## 前置条件

- 项目根目录 `~/agentguild`，`guild` CLI 可用
- `frontend-engineer` 已在 `guild.config.json` 中注册
- 需要先注册 `qa-engineer` 代理及其契约（见下面步骤 1-2）

## 步骤

### 1. 注册 QA Evidence Collector 代理

QA（Evidence Collector）不是默认注册的角色，需要先添加到配置中。

```bash
cd ~/agentguild

# 使用 jq 在 guild.config.json 的 agents 数组中添加 qa-engineer
jq '.agents += [{"slug": "qa-engineer", "division": "engineering", "file": "agents/engineering/qa-engineer.md"}]' \
  guild.config.json > guild.config.json.tmp && mv guild.config.json.tmp guild.config.json
```

### 2. 添加 QA 的契约定义

QA 需要从上游（前端工程师处）接收组件交付件并验证其质量。

```yaml
# 将以下内容追加到 contracts/guild-contracts.yml 的 contracts: 块中

  qa-engineer:
    delivers:
      - name: "带有测试覆盖率和无障碍评分的验证报告"
        description: "包含测试覆盖率、Lighthouse 评分、axe-core 违规数的质量报告"
      - name: "已签收的组件交付清单"
        description: "确认前端交付物完整且满足准入标准的签收记录"
    requires:
      - from: "前端工程师"
        items:
          - name: "带有单元测试和集成测试的可运行 React/TypeScript 组件"
            description: "组件代码及其配套测试，可在 CI 中独立运行并通过"
            required: true
          - name: "无障碍合规报告（axe-core、Lighthouse）"
            description: "包含 Lighthouse Accessibility 评分、axe-core 违规数及修复建议"
            required: true
```

> **注意**：实际部署时，建议使用 `agents/engineering/qa-engineer.md` 编写完整的 QA 代理身份定义文件，然后运行 `./guild/scripts/convert.sh` 自动生成契约配置。

### 3. 前端工程师准备组件交付物

前端完成了备课面板组件，但只提交了代码和 Storybook，缺少关键的测试覆盖率和无障碍报告。

```bash
mkdir -p /tmp/demo-component

cat > /tmp/demo-component/备课面板组件.tsx << 'EOF'
import React from 'react';

interface LessonPrepPanelProps {
  teacherId: string;
  lessonId: string;
  onSave: (data: unknown) => void;
}

export function LessonPrepPanel({ teacherId, lessonId, onSave }: LessonPrepPanelProps) {
  return (
    <div role="region" aria-label="备课面板">
      <h2>备课面板</h2>
      {/* 组件实现 */}
    </div>
  );
}
EOF

cat > /tmp/demo-component/备课面板.stories.tsx << 'EOF'
import type { Meta, StoryObj } from '@storybook/react';
import { LessonPrepPanel } from './备课面板组件';

const meta: Meta<typeof LessonPrepPanel> = {
  title: 'Teachers/LessonPrepPanel',
  component: LessonPrepPanel,
};

export default meta;

export const Default: StoryObj<typeof LessonPrepPanel> = {
  args: { teacherId: 't001', lessonId: 'l001', onSave: () => {} },
};

export const Empty: StoryObj<typeof LessonPrepPanel> = {
  args: { teacherId: 't001', lessonId: '', onSave: () => {} },
};

export const Error: StoryObj<typeof LessonPrepPanel> = {
  args: { teacherId: '', lessonId: 'l001', onSave: () => {} },
};
EOF
```

### 4. 前端发起交接（第一次 — 不完整）

```bash
cd ~/agentguild

./guild handoff \
  --from frontend-engineer \
  --to qa-engineer \
  --path /tmp/demo-component \
  --message "备课面板组件 v1.0 — 待 QA 验证"
```

**预期输出：**

```
创建交接 #2: frontend-engineer → qa-engineer
  状态: incomplete
  完整度: 0/2 项已提供
  [!!] 缺失 2 项:
       - 带有单元测试和集成测试的可运行 React/TypeScript 组件
       - 无障碍合规报告（axe-core、Lighthouse）
  记录: ~/agentguild/handoffs/2026-07-23-frontend-engineer-to-qa-engineer.json
```

检查发现两个问题：
1. 缺少单元测试和集成测试文件（只有组件代码，没有 `.test.tsx` 文件）
2. 缺少无障碍合规报告（没有 `axe-core` 或 `Lighthouse` 相关的文件或关键字）

### 5. 检查具体缺失项

```bash
./guild check --handoff 2
```

**预期输出：**

```
交接 #2: frontend-engineer → qa-engineer
状态: incomplete
时间: 2026-07-23T19:40:00+08:00
完整度: 0/2 项
缺失项:
  - 带有单元测试和集成测试的可运行 React/TypeScript 组件
  - 无障碍合规报告（axe-core、Lighthouse）
```

### 6. 前端补充测试和无障碍报告

```bash
# 补充单元测试和集成测试
cat > /tmp/demo-component/备课面板组件.test.tsx << 'EOF'
import { render, screen } from '@testing-library/react';
import { describe, it, expect } from 'vitest';
import { LessonPrepPanel } from './备课面板组件';

describe('LessonPrepPanel', () => {
  it('renders the prep panel heading', () => {
    render(<LessonPrepPanel teacherId="t001" lessonId="l001" onSave={() => {}} />);
    expect(screen.getByRole('region')).toHaveAttribute('aria-label', '备课面板');
  });

  it('handles empty lesson gracefully', () => {
    render(<LessonPrepPanel teacherId="t001" lessonId="" onSave={() => {}} />);
    expect(screen.getByText(/备课面板/)).toBeInTheDocument();
  });

  it('handles missing teacher gracefully', () => {
    render(<LessonPrepPanel teacherId="" lessonId="l001" onSave={() => {}} />);
    expect(screen.getByRole('region')).toBeInTheDocument();
  });

  // 集成测试：模拟备课流程
  it('fires onSave when save triggered', async () => {
    const onSave = vi.fn();
    render(<LessonPrepPanel teacherId="t001" lessonId="l001" onSave={onSave} />);
    // ... save interaction flow
  });
});
EOF

# 补充无障碍合规报告
cat > /tmp/demo-component/无障碍审计报告.md << 'EOF'
# 无障碍合规报告 — 备课面板组件

## 审计工具
- axe-core v4.9.1
- Lighthouse v12.0 (Accessibility 分类)

## 审计结果
- Lighthouse Accessibility 评分: 100/100
- axe-core 违规数: 0（严重）, 0（中等）, 2（建议级别）
- 键盘导航：所有交互元素可通过 Tab + 方向键访问
- 颜色对比度：通过（组件文本对比度 > 7:1）

## 建议改进项
1. 为图表区域添加 `aria-label`（当前缺失，建议级别）
2. 考虑增加暗色模式支持（当前不在范围内）

## 验证状态
✓ 所有阻塞项（严重/中等）已修复
✓ 通过对标 WCAG 2.1 AA 标准
EOF

# 补充类型定义（增强交付件完整性）
cat > /tmp/demo-component/types.ts << 'EOF'
export interface LessonPrepPanelProps {
  teacherId: string;
  lessonId: string;
  onSave: (data: unknown) => void;
}

export type LessonPrepState = 'loading' | 'ready' | 'saving' | 'error';

export interface LessonTemplate {
  id: string;
  title: string;
  sections: TemplateSection[];
}
EOF
```

### 7. 前端重新发起交接（第二次 — 通过）

```bash
./guild handoff \
  --from frontend-engineer \
  --to qa-engineer \
  --path /tmp/demo-component \
  --message "备课面板组件 v1.1 — 含测试和审计报告"
```

**预期输出：**

```
创建交接 #3: frontend-engineer → qa-engineer
  状态: ready
  完整度: 2/2 项已提供
  记录: ~/agentguild/handoffs/2026-07-23-frontend-engineer-to-qa-engineer.json
```

所有必需项已满足，状态为 `ready`。

### 8. QA 工程师接收交接

```bash
./guild accept --handoff 3 --as qa-engineer
```

**预期输出：**

```
接收交接 #3 ...
交接 #3 已接收 — qa-engineer 开始工作
```

### 9. 用 list --contracts 查看所有注册契约

```bash
./guild list --contracts
```

**预期输出：**

```
已注册的交接契约:
  frontend-engineer: 产出 5 项, 需求 3 项
  backend-architect: 产出 5 项, 需求 3 项
  devops-engineer: 产出 2 项, 需求 3 项
  ai-engineer: 产出 4 项, 需求 3 项
  product-manager: 产出 5 项, 需求 3 项
  ux-researcher: 产出 5 项, 需求 3 项
  data-analyst: 产出 5 项, 需求 3 项
  tech-writer: 产出 5 项, 需求 3 项
  ui-designer: 产出 5 项, 需求 3 项
  brand-guardian: 产出 5 项, 需求 3 项
  interaction-designer: 产出 5 项, 需求 3 项
  creative-director: 产出 5 项, 需求 3 项
  qa-engineer: 产出 2 项, 需求 2 项
```

`qa-engineer` 已加入契约注册表，显示 2 项产出和 2 项需求。

## 关键点

- **创建新角色**：QA/Evidence Collector 不是套件预置角色，通过编辑 `guild.config.json` 注册新 `slug`，并在 `guild-contracts.yml` 中定义契约即可使用。整个流程零代码修改，纯配置驱动。
- **文件名匹配**：扫描器通过文件名模糊匹配识别交付件。`备课面板组件.test.tsx` 的 `.test` 后缀帮助扫描器将其归类为"测试"交付件；`无障碍审计报告.md` 中包含关键词"无障碍合规报告"被内容扫描捕获。
- **完整的 Deliverable 思维**：前端工程师的契约定义 5 项产出，但 QA 契约只要求其中 2 项（测试 + 无障碍）。在真实项目中，应根据下游角色定制需求范围，避免过度要求不相关项。
- **Agent 身份文件**：建议为新代理编写完整的 `.md` 身份文件（包括身份描述、核心任务、技术交付物、协作契约），然后运行 `convert.sh` 自动生成契约，而非手动编辑 YAML。
