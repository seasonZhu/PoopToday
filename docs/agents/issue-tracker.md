# 本地 Markdown 任务跟踪

任务与规格保存在 `.scratch/` 下。

## 文件约定

- 每个功能使用独立目录 `.scratch/<feature-slug>/`。
- 规格文件为 `.scratch/<feature-slug>/spec.md`。
- 实施任务按票据独立保存为 `.scratch/<feature-slug>/issues/<NN>-<slug>.md`，编号从 `01` 开始。
- 在任务文件顶部附近使用 `Status:` 行记录分诊状态，状态值见 `triage-labels.md`。
- 评论与讨论历史追加到文件底部的 `## 评论` 小节。

## 发布与读取任务

技能要求发布到任务跟踪器时，按上述约定创建文件，并按需创建目录。

技能要求获取相关任务时，读取用户提供的文件路径。仅提供编号且存在多个匹配项时，先确认所属功能。

## Wayfinder 工作约定

- 工作地图保存在 `.scratch/<effort>/map.md`，记录笔记、已确定决策和待澄清问题。
- 子任务保存在 `.scratch/<effort>/issues/NN-<slug>.md`，编号从 `01` 开始，正文记录问题。
- 使用 `Type:` 行记录类型，取值为 `research`、`prototype`、`grilling` 或 `task`。
- 使用 `Status:` 行记录执行状态，领取后为 `claimed`，解决后为 `resolved`。该状态独立于分诊标签。
- 使用 `Blocked by: NN, NN` 行记录依赖。所有依赖均为 `resolved` 后，任务才解除阻塞。
- 选择下一项任务时，扫描尚未解决、未被领取且无阻塞的子任务，优先选择编号最小的任务。
- 开始工作前，将状态设为 `claimed` 并保存。
- 完成后，在 `## 答案` 小节追加结论，将状态设为 `resolved`，并在地图的已确定决策中追加摘要与文件链接。
