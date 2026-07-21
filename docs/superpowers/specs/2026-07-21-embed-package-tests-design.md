# 将测试内容嵌入程序包设计

## 目标

统一 pgflow 的测试内容打包方式：测试内容作为最终程序安装树的一部分，放在与 `bin/` 同级的 `tests/` 目录中，不再生成独立测试包。保留 `include_tests` 参数，用于控制最终程序包是否包含测试内容。

## 最终包结构

启用测试内容时，程序包保持现有外层结构，并在 `content/` 下增加测试目录：

```text
.
├── content/
│   ├── bin/
│   ├── lib/
│   ├── share/
│   └── tests/
├── install.sh
└── patchelf/
```

只生成一个 `postgres-<version>-<system>-glibc<version>.tar.gz`。不再生成 `postgres-tests-<version>-<system>-glibc<version>.tar.gz`。

## 公共打包约定

`pipelines/common/pack.py` 继续统一提供：

- `include_tests` 参数，默认值仍为 `False`。
- `testsdir`，固定指向 `content/tests`。
- `copy_tests()` 扩展点，由需要携带测试内容的具体流水线实现。

父类删除只服务于独立测试包的 `tests_pkgname` 接口，并提供统一的测试内容准备方法。该方法仅在 `include_tests=True` 时调用 `copy_tests()`。具体流水线必须在最终程序包归档前调用该方法，从而保证测试内容与程序内容进入同一归档。

这项约定适用于后续所有流水线，不再采用独立测试归档。现有未使用测试接口的其他流水线不做无关重构。

## PostgreSQL 打包流程

`pack_postgres.stage3()` 的顺序调整为：

1. 复制 PostgreSQL 程序依赖。
2. 准备安装脚本及安装工具。
3. 根据 `include_tests` 决定是否调用 `copy_tests()`，将测试树及测试运行时放入 `content/tests/`。
4. 对完整的 `package/` 目录只归档一次。

当 `include_tests=True` 时，最终包包含 `content/tests/`；当其为 `False` 时，不准备测试内容，最终包不包含该目录。

## PostgreSQL 测试入口

测试入口为安装根目录中的 `tests/run.sh`，新接口为：

```text
tests/run.sh [make-target] [make-arg ...]
```

默认目标仍是 `installcheck-world`。脚本根据自身位置自动将 `tests/` 的上一级目录识别为 `PGHOME`，不再接收显式 `PGHOME` 参数，也不兼容旧调用方式。若推导出的目录不包含 `bin/`，脚本应明确报错。

安装脚本会把 `content/` 的全部内容复制到用户指定的安装目录，因此 `tests/` 与 `bin/`、`lib/`、`share/` 保持同级，测试入口在归档解压后和安装后都能使用相同的相对位置规则。

## 测试与验收

实施遵循测试驱动流程，先调整或增加测试并确认其因旧行为而失败，再修改生产代码。

自动化验证覆盖：

- `tests/run.sh` 无参数运行时自动从上一级定位 PGHOME，并使用默认 `installcheck-world`。
- 显式测试目标和额外 `make` 参数保持原样传递。
- 旧式 `tests/run.sh PGHOME ...` 不再作为合法接口。
- `pack_postgres` 在准备可选测试内容后只归档一次程序包。
- `include_tests=False` 时不调用 `copy_tests()`。
- 通过源码扫描确认公共父类及其他生产代码不再暴露独立测试包命名接口。

最终执行现有 shell 回归测试、Python 语法检查、目标流水线导入检查和变更范围的 diff 检查。若目标构建节点可用，再执行实际 PostgreSQL 打包并检查单一归档的目录内容；若未执行远端构建，交付说明必须明确这一验证边界。

## 非目标

- 不改变 PostgreSQL 测试用例、测试工具集合和依赖闭包准备逻辑。
- 不重构其他流水线各自的 `stage3()` 实现。
- 不保留独立测试包或旧测试入口的兼容层。
- 不改变 `include_tests` 的参数名和 PostgreSQL 中现有的默认值。
