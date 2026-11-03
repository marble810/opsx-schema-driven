# init.md — 把 `proposal-driven` OpenSpec schema 完善、打包并发布

> 这是一份**给 agent 执行的启动简报**。工作目录：`F:\Git\opsx-schema-driven`（空目录）。
> 读完本文件即可开工；文中所有路径、命令、预期输出都已在本机实测过（OpenSpec 1.14.0）。
> 与用户沟通用简体中文；每完成一个 Phase 停下来汇报，等确认再进下一个 Phase。

---

## 0. 目标与成功判定

一件事：把这个 schema 从"某个项目里的本地实验品"变成**一个可独立克隆、可验证、可跨项目安装的发布仓库**。

完成后满足：

1. `F:\Git\opsx-schema-driven` 是一个有提交历史的 git 仓库，远端为 GitHub 上新建的 `marble810/opsx-schema-driven`（名称/可见性见 §6 决策点）。
2. 仓库内容通过 `openspec schema validate proposal-driven`，且 `openspec schema which` 解析到仓库内副本。
3. 提供**一条命令**级别的安装方式（Windows junction / Unix symlink 指向用户级目录），并有 README 说明三种安装路径的取舍。
4. 打第一个 tag（默认 `v1.0.0`）并写 Release notes；**打 tag 前必须经用户确认**。
5. 仓库自身的 CI（如启用）能在干净环境跑通 validate + e2e smoke。

---

## 1. 背景：这套 schema 的来历（已从 session 里核实）

设计发生在 **2026-10-21 晚**，cwd 当时是 `F:\Git\NeckMaskMaker`（该仓库现已移到 `F:\Git\UnityScriptDev\Avatar\NeckMaskMaker`，其 `openspec/schemas/` 已被移除，从未提交进 git —— 即它一直是"本地试用件"，从未发布）。

| 时间（本地） | 来源 | 内容 |
|---|---|---|
| 22:47 | pi `C:\Users\ABC_G\.pi\agent\sessions\--F--Git-NeckMaskMaker--\2026-10-21T14-46-22-721Z_01a15eed-7501-7474-9461-7ff2b68f7da3.jsonl` | 起点：改成 proposal-driven、禁用 specs、design 末尾加"人类摘要（LLM 勿读）" |
| 22:56 | 同上 | 用户问："自定义的 schema 有办法封装成可复用的形式吗" → 回答了项目级/用户级/内置三级解析优先级、symlink、独立 git 仓库三种复用形态 |
| 22:59–23:34 | agy（Antigravity CLI）会话 `30438b50-55ca-489a-b4be-d6eba4e877ec`，记录在 `C:\Users\ABC_G\.gemini\antigravity-cli\brain\30438b50-55ca-489a-b4be-d6eba4e877ec\.system_generated\logs\transcript_full.jsonl` | 主体：以 generic 视角审视，给出 6 项优化；落地 `tasks` 追踪 + 独立 `FOR-HUMAN.md` |
| 23:40 | 同上 | 用户定调（**这就是本次任务的授权**）：「先将当前项目的 scheme 进行优化，以及对项目 specific 内容的去除，**我先试用一下，如果没问题我再将其打包成 github repo 分发到自己的其他项目中**」 |
| 23:43 | 同上 | 已完成重构并通过 CLI 校验；末尾还给了"打包后软链到 `%LOCALAPPDATA%\openspec\schemas` 实现全机零拷贝复用"的做法 |

也就是说：**试用期已经跑完（10-21 起在多个项目里用过），现在做的是收尾——定稿、打包、发布。**

需要上下文时去读上面两个文件（可 `grep -n "发布\|仓库\|schemas" ` 定位），不要凭记忆编造设计动机。

---

## 2. 基线资产（不要重新发明）

最完整的实现是 MagicMask 项目里那一份：

```
F:\Git\UnityScriptDev\Avatar\MagicMask\openspec\schemas\proposal-driven\
├── schema.yaml
└── templates\{proposal,design,tasks,for-human}.md
```

已核对 sha256（供你在 Phase 1 判断"用户是否又改过"）：

```
39410c99…bc39  schema.yaml
791e7b56…1404  templates/proposal.md
32e3d1ff…79e3  templates/design.md
2a965fea…5a65  templates/tasks.md
63512db0…a377  templates/for-human.md
```

同名的另外两份是**旧版**（无 `for-human.md`、无 tasks 追踪），只作参考，不要作为基线：

- `F:\Git\unUDT\openspec\schemas\proposal-driven\`（早期版：proposal / design / tasks，无人类摘要）
- `F:\Git\MarbleVRCast\openspec\schemas\proposal-driven\`（同上，更早）

现状要点（基线已具备，**保留，别回退**）：

- `proposal → design → tasks → for-human` 四个 artifact；`design` 靠"短路过"保持可选。
- `apply: { requires: [proposal, tasks], tracks: tasks.md }` —— 进度追踪是通的。
- 全流程强制简体中文；`FOR-HUMAN.md` 顶部有"LLM 请勿阅读"横幅，`apply.instruction` 里禁止读取它。
- `## Why` / `## What Changes` 是 `openspec validate` 的硬性标题，必须保留。

---

## 3. 环境事实（已实测，可直接引用，别重复踩坑）

- OpenSpec `1.14.0`，全局装在 `C:\Users\ABC_G\AppData\Roaming\npm\node_modules\@fission-ai\openspec`。
- 解析优先级：`<project>/openspec/schemas/<name>/` → 用户级 `%LOCALAPPDATA%\openspec\schemas\<name>\`（Unix 为 `$XDG_DATA_HOME/openspec/schemas` 或 `~/.local/share/openspec/schemas`）→ npm 包内置；逐个覆盖。解析会**向上查找最近的 openspec root**。
- 目录符号链接/junction **原生支持**，实测 junction 在用户级目录里被识别为 `Source: user`。Windows 下 `mklink /J` 不需要管理员权限（`/D` 需要）。
- `openspec schema validate <name>` **不需要**先 `openspec init`；只要 cwd（或上级）存在 `openspec/schemas/<name>/` 即可。
- `openspec new change <name>` 在非 OpenSpec 项目里会**自动创建** `openspec/` root 并提示 `Run openspec init to finish`，可以忽略；但**不要在发布仓库里留下 `openspec/changes/`**，e2e 一律在临时目录做。
- `openspec doctor` **需要** openSpec root：只放 `openspec/config.yaml`（内容一行 `schema: proposal-driven`）即可 `OpenSpec root: ok`。
- 不要跑 `openspec init`：它会往仓库里塞一堆各工具的 agent 适配文件，对 schema 仓库是噪音。手写 `openspec/config.yaml` 就够。
- `openspec validate` 对不含 specs 的 change 会打印 `skip_specs is set in .openspec.yaml` 的 INFO —— 这是**预期行为**，不是错误。
- `schema.yaml` 里的 `version: 1` 是**schema 格式版本**，不是发布版本号。发布号用 git tag + CHANGELOG。

期望输出样例：

```
$ openspec schema validate proposal-driven
Note: Schema commands are experimental and may change.
✓ Schema 'proposal-driven' is valid

$ openspec schemas
  proposal-driven (project)
    ... description ...
    Artifacts: proposal → design → tasks → for-human
```

---

## 4. 交付物规格

目标目录树（`init.md` 保留在根，作为过程记录）：

```
F:\Git\opsx-schema-driven\
├── init.md
├── README.md                 # 门面：它解决什么、怎么装、怎么验证、已知取舍
├── LICENSE                   # 见 §6 决策点，默认 MIT
├── CHANGELOG.md              # 从 v1.0.0 开始记；写"相对 2026-10-21 试用版改了什么"
├── .gitignore
├── openspec/
│   ├── config.yaml           # 内容至少 `schema: proposal-driven`（让本仓库自己通过 doctor）
│   └── schemas/
│       └── proposal-driven/
│           ├── schema.yaml
│           └── templates/{proposal,design,tasks,for-human}.md
├── scripts/
│   ├── install.ps1           # 用户级安装（junction/symlink），可重复执行、幂等
│   ├── install.sh            # 同上，bash
│   ├── uninstall.ps1/.sh     # 只删链接，不删用户源仓库
│   └── verify.ps1/.sh        # §5 P3 的验收脚本，CI 也复用它
├── examples/                 # 可选：一个填好的最小 change，供人看"长什么样"
└── .github/workflows/validate.yml   # 可选：push/PR 时跑 validate + smoke
```

硬性要求：

- **目录名 = `schema.yaml` 的 `name` = `proposal-driven`**（三个现有项目都在用这个名字，改名会破坏它们）。
- `templates/` 下只放被 `schema.yaml` 引用到的文件；每个 `template:` 都有对应文件。
- README 必须写清：解决的痛点、四个 artifact 的依赖图、`design` 为什么是"可选但会显示未完成"、`FOR-HUMAN.md` 的隔离约定与它的**语义上限**（LLM 仍会读到文件，只是被禁止引用）、支持/实测的 OpenSpec 版本（1.14.0）、三种安装方式的取舍、卸载方法、简体中文是**有意为之的默认**（自用优先）。
- 脚本必须是幂等的：重复 install 不报错、已存在时给出明确提示；路径都要 quote，能处理空格。
- 脚本里不要硬编码 `F:\Git`，用脚本自身位置推导仓库根。

---

## 5. 执行阶段（每阶段结束汇报 + 等确认）

### P0 · 预检（只读，2 分钟）

```powershell
openspec --version
git config --get user.name; git config --get user.email
gh auth status
Test-Path 'F:\Git\UnityScriptDev\Avatar\MagicMask\openspec\schemas\proposal-driven\schema.yaml'
gh repo view marble810/opsx-schema-driven   # 期望 404 / not found；若已存在，停下来问用户
```

把结果贴给用户；任何一项不符合就停。

### P1 · 内容定稿

1. 从 MagicMask 复制 `schema.yaml` + `templates/` 到 `openspec/schemas/proposal-driven/`（先比对 §2 的 sha256，若不同说明用户后来改过，以**现文件**为准并如实说明）。
2. 通读一遍，只做**去具体化**与**契约清晰化**两类改动，不要重写风格：
   - 清掉仍残留的项目特有词汇（若发现 `Unity`/`VPM`/`NeckMaskMaker`/`MagicMask`/`GUID`/`asmdef` 之类）。
   - 检查 instruction 里是否有"再调用 CLI 去拿 context/rules"这类自指冗余（`<project_context>`/`<rules>` 本来就在同一 prompt 里）。
   - 检查每个 artifact 的输出契约、required/optional 标注、`Done check` 是否与模板小节**一致**（模板缺节 / 多节是常见的漂移点）。
   - `for-human` 的 `requires` 目前只有 `proposal`（不依赖 design，因为 design 可选）—— 确认这个取舍，别"顺手"加上 design。
3. 写 `CHANGELOG.md`：`v1.0.0` 相对 2026-10-21 试用版的变化（至少写清四项：tasks 追踪闭环、for-human 独立产物、What Changes/Behavior 边界、模板去 Goals/Non-Goals 冗余）。
4. 写 `README.md`（按 §4 的必含项）。

验收：`openspec schema validate proposal-driven` 通过，且 `openspec schemas` 里 artifact 顺序是 `proposal → design → tasks → for-human`。

### P2 · 自举与 git 历史

```powershell
cd F:\Git\opsx-schema-driven
printf 'schema: proposal-driven\n' > openspec/config.yaml
openspec doctor          # 期望 OpenSpec root: ok
git init -b main
# .gitignore：至少忽略 openspec/changes/ 、临时校验目录
git add -A; git commit -m "feat: package proposal-driven schema as standalone repo"
```

提交粒度：基线导入 / 内容定稿 / 脚本 / 文档 分开提交，便于 review。**不要一次大提交。**

验收：`git log --oneline` 至少 2 条；`git status` 干净。

### P3 · 脚本与 e2e 验收

必须覆盖（写进 `scripts/verify.*`，本地与 CI 同一套）：

1. validate：`openspec schema validate proposal-driven`。
2. 冷启动 e2e：在**临时目录**里
   ```bash
   mkdir -p "$TMP/probe" && cd "$TMP/probe"
   openspec new change smoke --schema proposal-driven
   # 期望 status 出现 4 个 artifact，design/tasks/for-human 显示 blocked by proposal
   # 写最小 proposal.md（Why/What Changes）+ tasks.md（含 1 个 [x] 和 1 个 [ ]）
   openspec validate --all          # 期望 1 passed（skip_specs INFO 属正常）
   openspec status --change smoke   # 期望 2/4，且 tasks 已 [x]
   openspec instructions apply --change smoke --json
   #   期望 taskTrackingConfigured: true，progress.total > 0
   ```
3. 安装路径 e2e：把用户级目录指向仓库副本（`mklink /J`），在**空的**临时目录里确认 `openspec schema which proposal-driven` → `Source: user`。
   - ⚠ 这一步会动用户全局目录 `%LOCALAPPDATA%\openspec\schemas`。**先问用户**：可以覆盖/新建，还是仅用 `LOCALAPPDATA=<临时伪目录>` 环境变量做假根验证（更安全，实测可行）。默认选后者。
4. 清理：临时目录删干净；不要在仓库里留下 probe。

验收：`scripts/verify.ps1`（和 `.sh`）在干净目录下 exit code 0，输出可读；把关键输出贴给用户。

### P4 · 发布（每一步都要用户点头）

1. `gh repo create marble810/opsx-schema-driven --<visibility> --source . --remote origin`（visibility 按 §6 决策）。
2. `git push -u origin main`；`gh repo view --web` 结果确认。
3. 写 `v1.0.0` 的 Release notes（内容 = CHANGELOG 的 v1.0.0 段 + 安装三行命令），**先贴给用户看**。
4. `git tag -a v1.0.0 -m "proposal-driven v1.0.0"` + `git push origin v1.0.0` + `gh release create`。
5. 发布后在用户自己的一个项目上做一次真实安装（用户指定哪个项目，不要自己挑），确认 `config.yaml` 写 `schema: proposal-driven` 后 `openspec status` 正常。

### P5 · 收尾

- 更新 `init.md` 顶部加一行"**已完成：v1.0.0 @ <date>，远端 <url>**"，让这份简报可归档。
- 三个项目里的旧副本（MagicMask / unUDT / MarbleVRCast）**不要动**——它们是历史记录，是否替换成"用户级安装"由用户决定，你只提出选项。
- 把 §8 的 backlog 原样带进 README 的 "Known limitations"，或建议用户开 issue。

---

## 6. 需要用户确认的决策点（问一次，别反复问）

| # | 决策 | 默认建议 |
|---|---|---|
| 1 | 仓库名 | `opsx-schema-driven`（已按此建目录）；若想以后放多个 schema，叫 `opsx-schemas` 更合适 —— 让用户选 |
| 2 | 可见性 | public（"发布为可复用 schema"的字面意思）；若要保留私人习惯（强制中文），private 也合理 |
| 3 | LICENSE | MIT |
| 4 | schema 名 | 保持 `proposal-driven`（不改名，避免破坏 3 个项目） |
| 5 | 是否保留"全中文"为默认 | 保留；README 声明这是设计选择，language-neutral 变体进 backlog |
| 6 | 是否启用 CI | 启用（ubuntu + windows 各跑一次 verify） |
| 7 | 首个 tag | `v1.0.0` |

---

## 7. 红线

- 不 `force push`；不改写已发布 tag。
- 不把用户的凭据/token 写进仓库；`gh auth` 走本机 keyring。
- 不为了"验证"去改 MagicMask / unUDT / MarbleVRCast / NeckMaskMaker 里的现有 schema 或 changes。
- 不引入构建步骤/npm 依赖来"打包" schema —— 它本质就是一个纯文本目录，多一层工具链只会增加维护成本。
- 不用 `openspec store`、`openspec schema fork` 做分发（前者是规划数据仓库，后者只能复制到当前项目，都不是分发机制）。
- 不在仓库里留 `openspec/changes/`、临时探测目录、`node_modules`。

---

## 8. Backlog（不阻塞 v1.0.0，写进 README 的 Known limitations）

来自 2026-10-21 的 generic 审视，仍未闭环的部分：

1. **`design` 的"可选"与状态机冲突**：OpenSpec 对普通 artifact 没有 `optional: true`，只要声明了 design，`status` 就会把它标成 `ready`，`/opsx:ff` 会推着 agent 去写它。现用"单行短路说明"缓解。彻底方案：拆成 `proposal-driven`（无 design）与 `proposal-design` 两个 schema，或等上游支持 optional artifact。
2. **`for-human` 参与 planning 完成度**：现在必须 4/4 才算 complete，`for-human` 会挡在 `isPlanningComplete` 前面。评估是否值得把它移出主链（例如只作为 `apply` 结束后的收尾动作）。
3. **"LLM 禁读"的语义上限**：文件一旦被读取，token 已进上下文；禁令只能约束引用行为。当前做法可接受，但 README 应如实写明这是"约定"而非"物理隔离"。
4. **语言耦合**：中文规则写在 schema 内部，对公开分发不友好。可选演进：抽成 `proposal-driven`（英文契约）+ `proposal-driven-zh`（继承式副本）。
5. **CLI 契约标注**：`## Why`/`## What Changes` 是解析器硬依赖，值得在 schema 里以显式注释标红（当前已在 instruction 文字里提到，可再强化）。

---

## 9. 完成定义（DoD）

- [ ] 仓库可克隆、`openspec schema validate` 通过、`doctor` 通过
- [ ] `scripts/verify.*` 一键跑通 e2e（含 apply 进度 > 0）
- [ ] README 覆盖：痛点、依赖图、安装三法、隔离约定与上限、支持版本、卸载
- [ ] CHANGELOG v1.0.0 写明相对试用版的变化
- [ ] 远端仓库 + `v1.0.0` tag + Release notes 已发布，且经用户确认
- [ ] 至少一个真实项目完成"用户级安装 + `schema: proposal-driven`"验证
- [ ] `init.md` 顶部标注完成状态，仓库 `git status` 干净

---

## 10. 附录：怎么自己去核对历史

```powershell
# pi 侧（设计前半段：可复用机制、封装方案）
Select-String -Path 'C:\Users\ABC_G\.pi\agent\sessions\--F--Git-NeckMaskMaker--\*.jsonl' `
  -Pattern 'proposal-driven|可复用|openspec-schemas' -List

# agy 侧（generic 审视 + tasks/FOR-HUMAN 落地 + 发布建议）
$f='C:\Users\ABC_G\.gemini\antigravity-cli\brain\30438b50-55ca-489a-b4be-d6eba4e877ec\.system_generated\logs\transcript_full.jsonl'
Select-String -Path $f -Pattern '试用|GitHub 仓库|LOCALAPPDATA' | Select-Object -First 10
```

会话 id `30438b50-55ca-489a-b4be-d6eba4e877ec` 可用 `agy --conversation 30438b50-55ca-489a-b4be-d6eba4e877ec` 在原 cwd 下继续。
