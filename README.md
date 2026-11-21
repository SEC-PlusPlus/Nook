# 🦀 Nook

> **桌角的一枚闲窗** —— A pocket-sized corner window that keeps Douyin playing while you get things done.

[**中文**](#中文) | [English](#english)

---

## 中文

Nook 把抖音网页播放器变成一枚无边框、置顶的桌面小窗,安静待在屏幕角落,尽量不打扰你——除非你想瞟一眼。

拉低透明度,让视频浮在工作之上;上锁之后,误点、双击、滚轮、快捷键统统碰不到它;一个键让视频撑满小窗,窗口自动匹配视频比例(零黑边);`Ctrl+Q` 一键收走,再按一次弹回(藏在托盘里也能唤出)。

基于 Rust 与系统 WebView2:约 12MB 单文件,无 Electron、无遥测。位置、大小、透明度、快捷键、登录态全部只存本机。

### 功能

- 🪟 **真透明** —— 整个窗口淡进底下的工作区,透过它看清后面
- 🔒 **防误触锁** —— 干活时点击/双击/滚轮/快捷键全部屏蔽,视频纹丝不动;拖窗照常
- ⛶ **迷你影院** —— 视频撑满小窗,窗口自动匹配视频比例,`Esc` 还原
- ⚡ **一键闪现** —— `Ctrl+Q` 收走、再按弹回,托盘隐藏状态也能直接唤出
- 📐 **等比自适应** —— 窗口任意缩放,页面内容整体跟随缩放;无边框边缘可直接拖拽改大小
- 🧘 **轻装上阵** —— Rust + Tauri + 系统 WebView2,安装包仅 2.5MB
- 💾 **数据不过夜** —— 一切存在本机一个配置文件,无账号体系,无数据统计

### 下载安装

**Windows 10 / 11**(自带 WebView2,免管理员,装于当前用户目录):

👉 **[Nook_0.7.3_x64-setup.exe](https://github.com/SEC-PlusPlus/Nook/raw/main/releases/Nook_0.7.3_x64-setup.exe)**(2.5MB,双击安装)

### 上手

悬浮把手(闲置自动淡出,鼠标移过去唤醒):`⠿⠿ 置顶 [透明度滑条] ⛶ 🗕 ⚙ 🔓 ✕`

- `⠿⠿` 按住拖动 · **双击 = 迷你影院** · 页面任意处 **Alt+按住左键** 也可拖
- `⚙` 设置面板:自定义快捷键(默认 `Ctrl+Q`)、窗口大小预设
- 托盘右键:全套菜单;双击托盘图标:唤出窗口
- `Ctrl+Alt+D` 显隐 · `Ctrl+Alt+T` 置顶 · `Ctrl+Q` 收到托盘⇄唤回
- `✕` = 直接退出程序;`Alt+F4` = 隐藏到托盘,不是退出

> 非官方第三方工具,与字节跳动无关联,仅供个人使用;不破解、不抓取、不修改平台数据。

---

## English

Nook turns Douyin's web player into a borderless always-on-top window that settles into a corner of your screen and stays out of your way — until you peek.

Dim it until the video floats over your work. Lock it so a stray click or scroll can't pause playback or flip past your place. One key sends the video edge-to-edge — the window snaps to the video's aspect ratio, no letterbox; `Esc` restores. `Ctrl+Q` blinks it to the tray; press again to bring it back.

Built on Rust and the system WebView2 runtime: one ~12 MB executable, no Electron, no telemetry. Your position, size, opacity, hotkeys and login all live on your own machine.

### Features

- 🪟 **True transparency** — fade the whole window into whatever's underneath
- 🔒 **Misclick lock** — clicks, double-clicks, wheels and page hotkeys all bounce off while you work
- ⛶ **Mini-theater** — video fills the window; the window auto-fits the video's aspect ratio; `Esc` restores
- ⚡ **Blink minimize** — `Ctrl+Q` away, `Ctrl+Q` back, even from the tray
- 📐 **Adaptive zoom** — page content scales to any window size; frameless edges resize natively
- 🧘 **Lightweight** — Rust + Tauri + system WebView2; 2.5 MB installer
- 💾 **Local-only** — one config file, no accounts, no analytics

### Download & install

**Windows 10 / 11** (WebView2 preinstalled; per-user install, no admin required):

👉 **[Nook_0.7.3_x64-setup.exe](https://github.com/SEC-PlusPlus/Nook/raw/main/releases/Nook_0.7.3_x64-setup.exe)** (2.5 MB)

### Controls

Floating handle (fades when idle, hover to wake): `⠿⠿ Pin · opacity slider · ⛶ Theater · 🗕 To-tray · ⚙ Settings · 🔓 Lock · ✕ Quit`

Drag by `⠿⠿`, double-click it for mini-theater, or Alt+drag anywhere. `Ctrl+Alt+D` show/hide · `Ctrl+Alt+T` pin-on-top · `Ctrl+Q` to tray and back. `✕` quits the app; Alt+F4 hides it to the tray.

> Third-party player, unaffiliated with ByteDance. Personal use only.

---

## 构建 / Build

```bash
# 需要 Rust 工具链 + VS Build Tools(C++)+ Node(仅 CLI 用)
cd src-tauri
cargo build --release              # 便携版:target/release/nook.exe
# NSIS 安装包(离线,不依赖 GitHub 下载):
#   在 tools/installer/ 下执行 "%LOCALAPPDATA%\tauri\NSIS\makensis.exe" installer.nsi
#   产物 → target/release/bundle/nsis/Nook_*-setup.exe,同步复制到 releases/
```

首次拉 Rust 依赖走 rsproxy 镜像(`.cargo/config.toml`,仅本项目生效)。

## 项目结构 / Code map

| 文件 | 职责 |
|---|---|
| `src-tauri/src/main.rs` | 装配:插件、命令注册、窗口创建、脚本注入、旧数据迁移 |
| `src-tauri/src/state.rs` | 全局状态与持久化 |
| `src-tauri/src/appctl.rs` | 置顶 / 显隐 / 最小化⇄弹回 / 尺寸预设 |
| `src-tauri/src/hotkeys.rs` | 全局快捷键解析与注册 |
| `src-tauri/src/ui.rs` | 系统托盘 |
| `src-tauri/src/commands.rs` | 页面侧命令面(ACL:`permissions/app-commands.toml`) |
| `src-tauri/inject/douyin.js` | 把手 / 透明 / 锁 / 迷你影院 / 自适应缩放 |
| `tools/installer/` | NSIS 安装包脚本 |
| `tools/draw_logo.ps1` | logo 绘制源(GDI)|
| `tools/verify/` | CDP 自动化验证脚本 |
| `releases/` | 发布的安装包 |
