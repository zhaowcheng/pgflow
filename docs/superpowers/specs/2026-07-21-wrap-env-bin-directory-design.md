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
- `envs` 是写入 wrapper 的 `NAME=VALUE` 环境变量列表。

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

每个 wrapper 通过自身位置计算 `$TOPDIR`，写入指定环境变量，再使用 `exec` 调用对应的 `.bin/<程序名>`。隐藏的是父目录，程序文件名本身不带点号，因此错误信息中的程序名保持为 `initdb` 等原名称。

## 目录项与失败处理

- 包装原 `bin` 目录中的全部非目录项，包括普通文件和符号链接。
- 遇到子目录时直接失败；本功能只处理扁平的可执行程序目录。
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
