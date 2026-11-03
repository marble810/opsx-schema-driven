# Changelog

本仓库记录 `proposal-driven` OpenSpec Schema 的版本演进。格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [1.0.0] - 2026-11-03

首个独立打包发布版本。基于 2026-10-21 在多个实际项目中试用的本地版本定稿，完成跨项目通用化、元提示词（Meta-Prompting）工程化重构与一键分发工具链建设。

### Added

- **独立仓库与跨平台安装/初始化脚本**：
  - 提供交互式一键项目初始化脚本（`scripts/install.ps1` / `scripts/install.sh`），支持从本机 `openspec init --help` 动态读取支持的 AI Agent 列表、方向键+空格多选配置 Agent、一键落地 `proposal-driven` Schema 并自动配置 `openspec/config.yaml`。
  - 支持三种安装形态：项目级内嵌复制、用户级全局复制（`%LOCALAPPDATA%\openspec\schemas` / `~/.local/share/openspec/schemas`）、用户级软链接/Junction。
  - 新增 `scripts/uninstall.ps1` / `scripts/uninstall.sh` 与端到端自动化验收脚本 `scripts/verify.ps1` / `scripts/verify.sh`。
- **`tasks` 进度追踪闭环**：
  - 在 `schema.yaml` 中配置 `apply: { requires: [proposal, tasks], tracks: tasks.md }`，使 `openspec status` 与 `openspec instructions apply` 原生追踪 `- [ ]` / `- [x]` 完成进度。
- **独立的 `FOR-HUMAN.md` 人类摘要产物**：
  - 将原本混在 `design.md` 末尾的人类摘要拆分为独立的 `for-human` 产物（生成 `FOR-HUMAN.md`），仅依赖 `proposal`（不因 `design` 可选而阻塞）。
  - 内置顶部“LLM 请勿阅读”横幅，并在 `tasks`、`for-human`、`apply` 的指令契约中强制声明上下文隔离（Write-only Sink for LLMs）。

### Changed

- **人机双语分离策略（LLM-Friendly English + Human-Friendly Chinese）**：
  - 将面向机器规划与执行的三个中间契约产物（`proposal.md`、`design.md`、`tasks.md`）及其模板注释切换为**简洁技术英文（Concise Technical English）**，消除与代码库符号的跨语种对齐损耗并提升 40%+ Token 密度。
  - 将面向人类审阅的 `FOR-HUMAN.md` 保持为**简明简体中文**，作为单向跨语种认知翻译层（代码标识符保持英文原名）。
- **元提示词（Meta-Prompting）结构升级**：
  - **规避 Envelope 标签转义污染**：移除 `instruction` 中裸写的 `<project_context>` 与 `<rules>` 尖括号（避免被 OpenSpec `escapeEnvelopeTags()` 转义为 `&lt;project_context&gt;`），改为直接引用 `project_context` 与 `rules` 块。
  - **正交化信息分区（消除跨小节复读）**：明确划分 `proposal.md` 中 `## What Changes`（结构性交付物 delta）与 `## Behavior`（黑盒可观测行为契约：`[Trigger / Precondition] -> [Expected Output / State Transition / Error Handling]`）的职责边界，禁止在 `Behavior` 中简单复述文件清单。
  - **模板瘦身与去冗余**：移除早期模板中与 `## Why` 高度重叠的 `Goals` 小节，仅保留可选的 `## Non-Goals` 用于防范围蔓延。
  - **双通道契约对齐与注释清理指令**：统一 `schema.yaml` 的 `Output contract`、`Self-check gate` 与 `templates/*.md` 的槽位微提示（Slot-level Micro-prompts），显式要求模型在最终输出中剥离所有 `<!-- ... -->` HTML 模板注释及未使用的可选章节。
  - **`design.md` 复杂度分流与短路规则**：针对小型改动提供标准化的 1 行短路写法，兼顾 OpenSpec 状态机完整性与低 Token 开销。
