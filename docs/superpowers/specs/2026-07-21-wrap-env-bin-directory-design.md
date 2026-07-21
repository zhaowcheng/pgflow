# wrap_envs 目录级包装设计

## 背景

当前 `wrap_envs` 将每个目标程序改名为同目录下以点号开头的隐藏文件，例如把 `bin/initdb` 改为 `bin/.initdb`，再由 wrapper 执行隐藏文件。程序从执行路径获取名称时会得到 `.initdb`，导致错误信息出现容易误解的点号前缀。

## 目标

- 隐藏整个待包装的 `bin` 目录，而不是逐个隐藏程序。
- 在原位置重建同结构的 `bin` 目录，存放全部程序的同名 wrapper。
- 不再由调用方维护待包装程序白名单。
- 保持 wrapper 的环境变量注入、参数、退出码和信号传递行为。
- 同时支持正式包的 `bin` 和测试包的 `tools/bin`。

## 接口

Python 接口调整为：

```python
wrap_envs(node, topdir, bindir, envs)
```

- `topdir` 是包根目录，也是 wrapper 中 `$TOPDIR` 的值。
- `bindir` 是相对于 `topdir` 的待包装目录，例如 `bin` 或 `tools/bin`。
- `envs` 是写入 wrapper 的内部可信 `NAME=VALUE` shell 模板列表。值会原样写入双引号形式的 `export`，使 `$TOPDIR`、`$PATH` 等变量在 wrapper 运行时展开；该接口不接受未校验的外部或用户输入。

Shell 脚本相应接收 `TOPDIR BINDIR ENVS`，不再接收程序列表。

## 目录变换

脚本将 `topdir/bindir` 改名为同级的隐藏目录 `.bin`，然后在原路径创建新的 `bin` 目录。以正式包为例：

```text
package/bin/initdb       -> package/.bin/initdb
package/bin/postgres     -> package/.bin/postgres
package/bin/initdb       <- 新生成的 wrapper
package/bin/postgres     <- 新生成的 wrapper
```

测试包采用相同规则：`tests/tools/bin` 改名为 `tests/tools/.bin`，wrapper 仍将 `tests` 解析为 `$TOPDIR`。

每个 wrapper 通过自身位置计算 `$TOPDIR`，写入指定环境变量，再调用对应的 `.bin/<程序名>`。wrapper 使用 Bash 的 `exec -a`，把真实程序接收的 `argv[0]` 设置为可见 wrapper 的绝对路径。这样 PostgreSQL 对 `argv[0]` 调用 `realpath()` 后仍得到 `bin/<程序名>`，其 `find_my_exec()` / `make_relative_path()` 不会把隐藏的 `.bin` 当作安装目录。隐藏的是父目录，程序文件名本身不带点号，因此错误信息中的程序名也保持为 `initdb` 等原名称。

## 目录项与失败处理

- 包装原 `bin` 目录中的全部非目录程序项，包括普通文件，以及指向程序文件的符号链接。
- 遇到真实子目录或解析后指向目录的符号链接时直接失败；目录符号链接不属于“程序”，本功能只处理扁平的程序目录。
- 源 `bin` 不存在、目标 `.bin` 已存在、`bindir` 不是安全的相对路径或环境变量格式非法时，在移动目录前失败。
- 生成 wrapper 发生错误时返回非零状态，不把失败伪装成成功。
- 已包装目录再次执行时因 `.bin` 已存在而失败，避免覆盖原程序。

## 调用方调整

- 正式包使用 `wrap_envs(self.node, self.instdir, 'bin', envs)`。
- 测试包使用 `wrap_envs(self.node, self.testsdir, 'tools/bin', test_envs)`。
- 删除 `runtime_env_bins` 和 `test_env_bins` 白名单属性。

## 验证

新增 shell 回归测试，至少覆盖：

- 顶层 `bin` 和嵌套 `tools/bin` 的目录变换。
- 原目录内全部程序都有同名 wrapper。
- 环境变量、参数和退出码正确透传。
- 被执行程序观察到的名称不含点号前缀。
- `.bin` 冲突、非法路径、非法环境变量和目录项异常时安全失败。

最后执行相关 shell 测试、`venv/bin/python -m compileall pipelines`，并验证 xflow 能导入流水线；实际远端构建不在本次本地验证范围内。

## 最终审查修订

- 生成的 wrapper 从 POSIX sh 改为 `/bin/bash`，使用 Bash 内建的 `exec -a` 将可见 wrapper 的绝对路径传为真实程序的 `argv[0]`。固定解释器路径也避免测试工具目录位于 `PATH` 首位时，`#!/usr/bin/env bash` 重新找到被包装的 `bash` 而递归。
- 新增编译型 C 探针，同时打印 `argv[0]` 和 `realpath(argv[0])`。修复前两者指向 `.bin`，修复后两者都指向可见 `bin` wrapper 路径；原有名称、环境、参数与退出码验证继续保留。
- 预检测试增加“符号链接解析为目录”场景，确认失败发生在 `bin -> .bin` 移动之前。
- `envs` 保持内部可信 shell 模板语义，不做会阻止 `$TOPDIR`、`$PATH` 运行时展开的全量 shell 转义；调用方负责杜绝未校验外部输入。
