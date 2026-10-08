# Smooth-start 使用与验证

此分支基于 fork 的 `dev`（9.3.1），保留该版本的后台加载和临时文件功能。

## 启用

插件管理器配置：

```lua
{ "EmmetZ/kitty-scrollback.nvim", branch = "dev" }
```

Kitty 配置中的路径应指向同一份插件：

```conf
action_alias kitty_scrollback_nvim kitten /path/to/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py --smooth-start --env NVIM_APPNAME=ksb-nvim
```

`--smooth-start` 必须位于 `--nvim-args` 之前。`ksb-nvim` 是可选的独立
Neovim 配置；共用按键由该配置自行加载，插件不会读取其他用户配置文件。

## 行为

- 启动期间保留原终端画面，在右上角显示一个旋转图标，无加载文字。
- 图标通过 Kitty 独立绘制层显示，不写入源终端，不启动额外加载进程。
- 导入内容、定位光标和绘制首帧后立即显示 scrollback，清除图标并释放缓冲输入。
- 就绪后显示倒序行号 `[当前行/总行数]`，最底行为 1；总数包括空行。
- 行号使用主题正文颜色并加粗，跟随当前 scrollback 分屏，横向移动不重复改写。
- 普通模式限制在行尾后一格；最右列打开粘贴窗口时回退到下一行。
- Neovim 0.12 成功导入后清除进程结束标记，并避免导入额外产生尾部空行。
- 错误提示或超过五秒仍未就绪时显示 Neovim，以便处理错误或退出。

`status_window.enabled = false` 禁用状态显示，`style_simple = true` 使用
ASCII 图标，`autoclose = true` 在行号出现一秒后关闭它。
禁用和 ASCII 设置在 Neovim 配置加载后应用，此前使用默认图标。
Kitty 缺少原生绘制接口时回退为保留原画面、就绪后直接显示行号。
该绘制接口属于 Kitty 内部接口，目前实测版本为 0.49.2。

## 验证

适配到 9.3.1 后完成：

- 7 项 Python 生命周期测试和 9 项 Plenary 行号测试。
- `make check`、Lua 格式检查与 `git diff --check`。
- 独立 Kitty 的普通/smooth 启动、主/专用配置、Neovim 0.12/0.11 验证。
- 实际按键、行号更新、右对齐、分屏、粘贴窗口和退出验证。
- 延迟启动期间的图标与缓冲按键、ASCII/禁用、提前关闭、错误和五秒兜底验证。

未运行完整屏幕快照测试集，原有就绪图标快照仍需适配倒序行号显示。
