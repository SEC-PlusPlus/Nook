// DouYinWin —— 把抖音装进一个可钉桌面的悬浮小窗
// 模块分工:state=全局状态/持久化,appctl=窗口行为,hotkeys=自定义快捷键,
//           ui=托盘,commands=JS 命令面,pin=M3 桌面层(未接线)
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod appctl;
mod commands;
mod hotkeys;
mod state;
mod ui;

use std::sync::atomic::Ordering;

use tauri::{
    AppHandle, PhysicalPosition, PhysicalSize, WebviewUrl, WebviewWindowBuilder, WindowEvent,
};
use tauri_plugin_global_shortcut::{
    Builder as ShortcutBuilder, Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState,
};

use state::{main_win, persist, DEFAULT_H, DEFAULT_W};

/// 把手脚本:ECDC + 页面加载后 eval 双通道注入,幂等守卫在脚本内部
/// (wry 的 initialization_script 在外部 URL 上不执行,eval 通道才是主力)
const INJECT_JS: &str = include_str!("../inject/douyin.js");

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            appctl::show_main(app);
        }))
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(
            ShortcutBuilder::new()
                .with_handler(|app, shortcut, event| {
                    if event.state != ShortcutState::Pressed {
                        return;
                    }
                    match shortcut.key {
                        Code::KeyD => appctl::toggle_visible(app),
                        Code::KeyT => appctl::flip_topmost(app),
                        _ => {
                            if hotkeys::matches_custom(shortcut) {
                                appctl::toggle_minimize(app);
                            }
                        }
                    }
                })
                .build(),
        )
        .invoke_handler(tauri::generate_handler![
            commands::toggle_topmost,
            commands::hide_main,
            commands::show_main_cmd,
            commands::minimize_main_cmd,
            commands::get_settings,
            commands::set_opacity,
            commands::set_hotkey,
            commands::set_size_preset,
        ])
        .setup(|app| {
            state::migrate_legacy(); // 旧标识符数据一次性搬家
            let handle: AppHandle = app.handle().clone();
            let (geo, _top) = state::init_from_store(&handle);

            let builder = WebviewWindowBuilder::new(
                &handle,
                "main",
                WebviewUrl::External("https://www.douyin.com".parse()?),
            )
            .title("Nook")
            .inner_size(DEFAULT_W, DEFAULT_H)
            .min_inner_size(480.0, 320.0)
            .resizable(true)
            .decorations(false)
            // 真 see-through:窗口本体透明,内容由 JS 的 CSS opacity 压
            .transparent(true)
            .shadow(false)
            .always_on_top(state::TOPMOST.load(Ordering::Relaxed))
            .visible(false)
            .focused(true)
            .initialization_script(INJECT_JS)
            .on_page_load(|webview, payload| {
                if let tauri::webview::PageLoadEvent::Finished = payload.event() {
                    let _ = webview.eval(INJECT_JS);
                }
            })
            .additional_browser_args(&{
                // debug 构建开 CDP 端口供自动化验收;release 不带
                let dev = if cfg!(debug_assertions) {
                    " --remote-debugging-port=9222"
                } else {
                    ""
                };
                format!(
                    "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection \
                     --autoplay-policy=no-user-gesture-required{dev}"
                )
            });
            let win = builder.center().build()?;

            if let Some((x, y, w, h)) = geo {
                let _ = win.set_position(PhysicalPosition::new(x, y));
                let _ = win.set_size(PhysicalSize::new(w, h));
            }
            win.show()?;

            let a = handle.clone();
            win.on_window_event(move |ev| match ev {
                WindowEvent::CloseRequested { api, .. } => {
                    api.prevent_close();
                    if let Some(w) = main_win(&a) {
                        let _ = w.hide();
                    }
                }
                WindowEvent::Moved(_) | WindowEvent::Resized(_) => persist(&a, false),
                _ => {}
            });

            ui::init_tray(&handle)?;

            handle.global_shortcut().register_multiple(vec![
                Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyD),
                Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyT),
            ])?;
            hotkeys::restore_from_store(&handle);

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("DouYinWin 启动失败")
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                persist(app, true);
            }
        });
}
