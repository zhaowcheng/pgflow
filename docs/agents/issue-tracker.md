# Issue tracker：本地 Markdown

本仓库的 issue 和 spec 使用 `.scratch/` 下的 Markdown 文件管理。

## 约定

- 每个 feature 使用一个目录：`.scratch/<feature-slug>/`
- Spec 文件为 `.scratch/<feature-slug>/spec.md`
- 每个实施任务使用一个独立文件：
  `.scratch/<feature-slug>/issues/<NN>-<slug>.md`
- 任务编号从 `01` 开始；不要把多个任务合并到一个文件
- Triage 状态记录在 issue 文件开头附近的 `Status:` 行中；角色字符串参见 `triage-labels.md`
- 评论和对话历史追加到文件末尾的 `## Comments` 标题下

## 当 skill 要求“发布到 issue tracker”时

在 `.scratch/<feature-slug>/` 下创建相应文件；目录不存在时一并创建。

## 当 skill 要求“获取相关 ticket”时

读取指定路径中的文件。用户通常会直接提供文件路径或 issue 编号。

## Wayfinding 操作

供 `/wayfinder` 使用。一个 map 对应多个 ticket 子文件。

- **Map**：`.scratch/<effort>/map.md`，正文包含 Notes、Decisions-so-far 和 Fog
- **子 ticket**：
  `.scratch/<effort>/issues/NN-<slug>.md`，从 `01` 开始编号，问题写在正文中；
  `Type:` 行记录 ticket 类型（`research`、`prototype`、`grilling` 或 `task`）；
  `Status:` 行记录 `claimed` 或 `resolved`
- **阻塞关系**：在文件开头附近使用 `Blocked by: NN, NN`；
  列出的所有 ticket 均为 `resolved` 后，当前 ticket 才解除阻塞
- **Frontier**：扫描 `.scratch/<effort>/issues/`，查找未关闭、未阻塞且未认领的文件；
  编号最小者优先
- **认领**：开始工作前，将 `Status:` 设置为 `claimed` 并保存
- **解决**：把答案追加到 `## Answer` 标题下，将 `Status:` 设置为 `resolved`，
  然后把上下文指针（摘要及链接）追加到 `map.md` 的 Decisions-so-far 中
