// 系统托盘:菜单构建与响应
use tauri::menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem};
use tauri::tray::{TrayIconBuilder, TrayIconEvent};
use tauri::AppHandle;

use crate::appctl;
use crate::state::{main_win, persist, DEFAULT_H, DEFAULT_W, TOPMOST};

pub fn build_menu(app: &AppHandle) -> tauri::Result<Menu<tauri::Wry>> {
    let top_now = TOPMOST.load(std::sync::atomic::Ordering::Relaxed);
    let show = MenuItem::with_id(app, "show", "显示 / 隐藏  (Ctrl+Alt+D)", true, None::<&str>)?;
    let top = MenuItem::with_id(
        app,
        "top",
        format!("置顶: {}  (Ctrl+Alt+T)", if top_now { "开" } else { "关" }),
        true,
        None::<&str>,
    )?;
    let sep1 = PredefinedMenuItem::separator(app)?;
    let ws = MenuItem::with_id(app, "w_small", "大小: 小 480×320", true, None::<&str>)?;
    let wm = MenuItem::with_id(
        app,
        "w_std",
        &format!("大小: 标准 {}×{}", DEFAULT_W as u32, DEFAULT_H as u32),
        true,
        None::<&str>,
    )?;
    let wb = MenuItem::with_id(app, "w_big", "大小: 大 800×534", true, None::<&str>)?;
    let rl = MenuItem::with_id(app, "reload", "刷新页面", true, None::<&str>)?;
    let st = MenuItem::with_id(app, "settings", "设置面板(快捷键/大小)", true, None::<&str>)?;
    let sep2 = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
    Menu::with_items(app, &[&show, &sep1, &top, &ws, &wm, &wb, &rl, &st, &sep2, &quit])
}

fn open_panel_js(app: &AppHandle) {
    if let Some(w) = main_win(app) {
        let _ = w.show();
        let _ = w.eval("if(window.__DYWIN_PANEL)__DYWIN_PANEL.toggle(true)");
    }
}

pub fn on_menu(app: &AppHandle, event: &MenuEvent) {
    match event.id.as_ref() {
        "show" => appctl::toggle_visible(app),
        "top" => appctl::flip_topmost(app),
        "w_small" => appctl::set_preset_size(app, 480.0, 320.0),
        "w_std" => appctl::set_preset_size(app, DEFAULT_W, DEFAULT_H),
        "w_big" => appctl::set_preset_size(app, 800.0, 534.0),
        "reload" => {
            if let Some(w) = main_win(app) {
                let _ = w.eval("location.reload()");
            }
        }
        "settings" => open_panel_js(app),
        "quit" => {
            persist(app, true);
            app.exit(0);
        }
        _ => {}
    }
}

/// 创建托盘(在 setup 中调用一次)
pub fn init_tray(app: &AppHandle) -> tauri::Result<()> {
    let _tray = TrayIconBuilder::with_id("tray")
        .menu(&build_menu(app)?)
        .icon(tauri::include_image!("icons/32x32.png"))
        .tooltip("Nook —— 右键菜单,双击唤出")
        .on_menu_event(|app, event| on_menu(app, &event))
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::DoubleClick { .. } = event {
                appctl::show_main(tray.app_handle());
            }
        })
        .build(app)?;
    Ok(())
}
