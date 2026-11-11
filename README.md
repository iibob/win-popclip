# WinPopClip
<img width="621" height="183" alt="image" src="https://github.com/user-attachments/assets/89d0e6b7-6479-4c3b-aa84-c4be1538ceab" />

Windows 版 [PopClip](https://www.popclip.app)：选中文本后，在鼠标旁弹出悬浮小菜单，一键复制、剪切、粘贴、打开链接 / 文件夹，或直接搜索、翻译。

基于 **AutoHotkey v2** 编写，单文件、零依赖、无需安装。

## 功能

- **自动弹出**：框选 / 双击 / 三击 / Shift+点击选中文本后，鼠标旁弹出菜单
- **快捷键**：支持自定义快捷键、单击 Ctrl 弹出菜单
- **智能识别**：自动判断选中内容是 URL、本地路径、邮箱地址，显示对应动作
- **搜索与翻译**：百度 / 谷歌 / 必应搜索，Google 翻译、百度翻译，URL 模板可自定义
- **进程过滤**：黑 / 白名单模式，支持自定义规则

## 环境要求

- Windows 10 / 11
- AutoHotkey `v2.0`

## 使用

1. 安装 [AutoHotkey v2.0](https://www.autohotkey.com/)
2. 下载 `WinPopClip.ahk`，双击运行
3. 首次运行会在同目录自动生成配置文件 `WinPopClip_config.ini`
4. 手动修改配置后，双击托盘图标即可重新加载配置

设置开机自启动：
按 `Win+R` 输入 `shell:startup` 回车，然后把 `WinPopClip.ahk` 的快捷方式放进打开的文件夹即可。

## 触发方式

| 方式      | 说明                     | 配置修改                     |
| ------- | ---------------------- | ------------------------ |
| 自动弹出    | 选中文本并松开鼠标左键，菜单出现在鼠标上方  | `[General] AutoPopup`    |
| 快捷键     | 默认 `F1`，可自定义组合键，留空则不使用 | `[General] ManualHotkey` |
| 单击 Ctrl | 选中文本后单击弹出菜单 | `[General] CtrlTap`      |

> 菜单显示时再次单击 Ctrl、点击别处、滚动滚轮、右键、按任意键或切换窗口都会关闭。

## 配置

所有配置集中在 `WinPopClip_config.ini`，主要段落：

| 段落                 | 作用                                           |
| ------------------ | -------------------------------------------- |
| [General]        | 自动弹出、快捷键、Ctrl 单击、取词延迟、自动隐藏、圆角、进程模式           |
| [Process]        | 进程过滤列表（`blacklist` 不弹 / `whitelist` 仅这些弹）    |
| [CopyInsert]     | 终端类进程改用 `Ctrl+Insert` 复制（终端里 `Ctrl+C` 是中断信号） |
| [CtrlTapExclude] | 这些进程里单击 Ctrl 不弹菜单（虚拟机 / 远程桌面）                |
| [Menu]           | 菜单项及顺序，用 `\|` 分隔，删掉某项即隐藏                     |
| [Search]         | 搜索 / 翻译 URL 模板，支持 `{q}` 与 `{tl}` 占位符         |
| [Style]          | 字体、字号、按钮高度与内边距、配色（十六进制色值不带 `#`）              |

可用菜单项：

```
Copy  Cut  Paste  OpenUrl  OpenFolder  OpenFile  MailTo  Baidu  Google  Bing  BaiduTranslate  Translate
```

> `OpenUrl` / `OpenFolder` / `OpenFile` / `MailTo` 仅在选中内容匹配时出现；`Translate` 是谷歌翻译。

## 已知限制

- 取词依赖模拟 `Ctrl+C`（终端类为 `Ctrl+Insert`），仅对支持复制的应用有效
- 部分带菜单栏的程序（如记事本）中，含 `Alt` 的快捷键组合可能触发菜单栏，导致取词失败
- 密码管理器、远程桌面默认排除在自动弹出之外，避免干扰
