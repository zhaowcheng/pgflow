# 领域文档

工程 skills 探索代码库时，按以下规则使用本仓库的领域文档。

## 探索前读取

- 根目录的 `GLOSSARY.md`
- 如果根目录存在 `GLOSSARY-MAP.md`，按其中的指针读取与当前工作相关的各个 `GLOSSARY.md`
- `docs/adr/` 中涉及当前工作区域的 ADR
- 对于 multi-context 仓库，还应检查 `src/<context>/docs/adr/` 中的上下文级 ADR

上述文件或目录不存在时，直接继续，不报告缺失，也不预先建议创建。

`/domain-modeling` skill 会在领域术语或架构决策真正明确后，按需创建这些文件。

## 文件布局

本仓库采用 single-context 布局：

```text
/
├── GLOSSARY.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

如果以后改为 multi-context，可使用以下布局，并在根目录创建 `GLOSSARY-MAP.md`：

```text
/
├── GLOSSARY-MAP.md
├── docs/adr/                          ← 系统级决策
└── src/
    ├── ordering/
    │   ├── GLOSSARY.md
    │   └── docs/adr/                  ← 上下文级决策
    └── billing/
        ├── GLOSSARY.md
        └── docs/adr/
```

## 使用 glossary 中的词汇

当输出内容需要命名领域概念时，包括 issue 标题、重构建议、假设和测试名称，应使用 `GLOSSARY.md` 中定义的术语，避免改用 glossary 明确排除的同义词。

如果需要的概念尚未出现在 glossary 中，先判断是否使用了项目并不采用的自造术语；如果确实存在领域词汇缺口，记录下来供 `/domain-modeling` 处理。

## 标明 ADR 冲突

如果输出内容与现有 ADR 冲突，应明确指出冲突，不得静默覆盖。例如：

> 与 ADR-0007（event-sourced orders）冲突，但值得重新讨论，因为……
