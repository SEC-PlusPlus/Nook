# 🦀 Nook

> **A pocket-sized corner window that keeps Douyin playing while you get things done.**
> **一枚待在桌角、让你干活时也能瞟一眼抖音的小窗。**

English | [中文](#中文)

Nook turns Douyin's web player into a borderless always-on-top window that settles into a corner of your screen and stays out of your way — until you peek.

Dim it until the video floats over your work. Lock it so a stray click or scroll can't pause playback or flip past your place. One key sends the video edge-to-edge in the window, and the window resizes itself to the video's aspect ratio — no letterbox, no crop. `Ctrl+Q` blinks it away; `Ctrl+Q` again blinks it back.

Built on Rust and the system WebView2 runtime: one ~12 MB executable, no Electron bundle, no telemetry. Your position, size, opacity, hotkeys and login all live on your own machine.

## Features

| | |
|---|---|
| 🪟 **True transparency** | fade the whole window into whatever's underneath, then see through it |
| 🔒 **Misclick lock** | clicks, double-clicks, wheels and page hotkeys all bounce off while you work |
| ⛶ **Mini-theater** | video fills the window; the window fits the video's aspect ratio; `Esc` releases |
| ⚡ **Blink minimize** | `Ctrl+Q` away, `Ctrl+Q` back — even from the tray |
| 📐 **Adaptive zoom** | page content scales to any window size, drag the frameless edges freely |
| 🧘 **Lightweight** | Rust + Tauri + system WebView2, ~12 MB single binary |
| 💾 **Local-only** | everything persists in one config file; no accounts, no analytics |

## Get it

**Windows 10/11 (WebView2 preinstalled):** grab `Nook_x.y.z_x64-setup.exe` from the [`releases/`](releases/) folder in this repo (or GitHub Releases once tagged), or build it yourself (see below).

Controls at a glance — the floating handle (fades when idle, hover to wake):
`⠿⠿ 置顶(pin) · slider(opacity) · ⛶(theater) · 🗕(minimize) · ⚙(settings) · 🔓(lock) · ✕(hide)`
Drag by `⠿⠿` or Alt+drag anywhere; double-click `⠿⠿` toggles theater mode. System tray has the full menu. `Ctrl+Alt+D` show/hide · `Ctrl+Alt+T` pin-on-top.

> Third-party player, unaffiliated with ByteDance. Personal use only. It does not modify, crack or scrape the platform — it just frames the official web player.

---

## 中文

Nook 把抖音网页播放器变成一枚无边框、置顶的桌面小窗,安静待在屏幕角落,尽量不打扰你——除非你想瞟一眼。

拉低透明度,让视频浮在工作之上;上锁之后,误点、双击、滚轮、快捷键统统碰不到它;一个键让视频撑满小窗,窗口自动匹配视频比例,零黑边零裁切;`Ctrl+Q` 一键收走,再按一次弹回(藏在托盘里也能唤出)。

基于 Rust 与系统 WebView2:约 12MB 单文件,无 Electron、无遥测。位置、大小、透明度、快捷键、登录态全部只存本机。

**安装**:Win10/11 自带 WebView2,直接跑 `Nook_x.y.z_x64-setup.exe`(Releases 下载,当前版本 v0.7.0,安装于 `%LOCALAPPDATA%\Programs\Nook`,免管理员)。

**上手**:悬浮把手 `⠿⠿ 置顶 滑条 ⛶ 🗕 ⚙ 🔓 ✕`,闲置自动淡出;托盘右键有全套菜单;`Ctrl+Alt+D` 显隐、`Ctrl+Alt+T` 置顶、`Ctrl+Q` 闪现最小化(⚙ 里可改键)。

> 非官方第三方工具,与字节跳动无关联,仅供个人使用;不破解、不抓取、不修改平台数据。

## 构建 / Build

```bash
# 需要:Rust 工具链 + VS Build Tools(C++)+ Node(仅 CLI 用)
cd src-tauri
cargo build --release              # 便携版:target/release/nook.exe
# NSIS 安装包(离线,无需从 GitHub 下载打包工具):
#   在 tools/installer/ 下执行 "%LOCALAPPDATA%\tauri\NSIS\makensis.exe" installer.nsi
#   产物 → src-tauri/target/release/bundle/nsis/Nook_*-setup.exe,并同步到 releases/
```

首次编译走 rsproxy 镜像(`.cargo/config.toml`,仅本项目生效)。测试 GUI 一律用 release:debug 版随启动它的终端一起退出,且会开 CDP 调试端口(9222)。

### 模块分工 / Code map

| 文件 | 职责 |
|---|---|
| `src-tauri/src/main.rs` | 装配:插件、命令注册、窗口创建、注入双通道、旧数据迁移 |
| `src-tauri/src/state.rs` | 全局状态 + 持久化(几何合法性过滤、legacy 搬家) |
| `src-tauri/src/appctl.rs` | 置顶/显隐/最小化⇄弹回/尺寸/VFS 窗口配型 |
| `src-tauri/src/hotkeys.rs` | 自定义快捷键:解析、校验、注册(默认 Ctrl+Q) |
| `src-tauri/src/ui.rs` | 托盘 |
| `src-tauri/src/commands.rs` | 远程页命令面(ACL:`permissions/app-commands.toml`) |
| `src-tauri/inject/douyin.js` | 把手/透明/锁/迷你影院/设置面板/等比自适应 |
| `tools/draw_logo.ps1` | logo 绘制源(GDI,改坐标即可重画)→ `npx @tauri-apps/cli icon` |

### 实现要点(踩坑记录,勿回退)

- 透明:WebView2 不吃 Win32 整窗 alpha;= 窗口 `transparent(true)` + JS 对 body 子元素设 CSS `opacity`,且 html/body 背景必须置 transparent
- 注入:wry 的 `initialization_script` 在外部 URL 上不执行;靠 `on_page_load(Finished)+eval` 兜底,脚本自带幂等守卫
- ACL:远程页调用自定义命令必须 `permissions/app-commands.toml` 白名单 + capability 引用,否则 invoke 静默挂起
- 迷你影院:video `fixed` 满视口 + 祖先链无条件破除 transform/filter/backdrop-filter/contain/container-type/perspective/will-change(包含块劫持);600ms 看门狗自愈(播放器重写样式/连播换节点);窗口按 `videoWidth/videoHeight` 配型
- 几何:最小化占位坐标(-32000)不落盘;存档读取带合法性过滤;配置以 `ver` 字段做迁移
- 重编前先杀进程,运行中的 exe 被锁会报 os error 5

## License

Source is published for now without a license file (all rights reserved by author) — licensing decision pending. ⚠️ 若你打算开源授权,告诉我选哪个许可证我来补 LICENSE 文件。
