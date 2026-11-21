// 供注入页面调用的命令面(远程 origin,需在 permissions/app-commands.toml 授权)
use serde_json::{json, Value};
use std::sync::atomic::Ordering;
use tauri::AppHandle;

use crate::appctl;
use crate::hotkeys;
use crate::state::{self, ALPHA_PCT, TOPMOST};

#[tauri::command]
pub fn toggle_topmost(app: AppHandle) {
    appctl::flip_topmost(&app);
}

/// 把手 ✕:直接退出程序(先落盘再退)
#[tauri::command]
pub fn quit_app(app: AppHandle) {
    state::persist(&app, true);
    app.exit(0);
}

#[tauri::command]
pub fn show_main_cmd(app: AppHandle) {
    appctl::show_main(&app);
}

/// 把手 🗕:隐藏到托盘(透明窗的系统最小化在 Win11 任务栏是空白,故用隐藏替代)
#[tauri::command]
pub fn hide_main(app: AppHandle) {
    if let Some(w) = state::main_win(&app) {
        let _ = w.hide();
    }
}

#[tauri::command]
pub fn get_settings(_app: AppHandle) -> Value {
    json!({
        "opacity": ALPHA_PCT.load(Ordering::Relaxed),
        "hotkey": current_hotkey_str(),
        "topmost": TOPMOST.load(Ordering::Relaxed),
    })
}

fn current_hotkey_str() -> String {
    state::hotkey()
        .lock()
        .unwrap()
        .as_ref()
        .map(|(s, _)| s.clone())
        .unwrap_or_default()
}

/// 只存值;实际视觉透明度由注入脚本的 CSS opacity 应用
#[tauri::command]
pub fn set_opacity(app: AppHandle, pct: u32) {
    ALPHA_PCT.store(pct.clamp(15, 100), Ordering::Relaxed);
    state::persist(&app, false);
}

#[tauri::command]
pub fn set_hotkey(app: AppHandle, combo: String) -> Result<(), String> {
    hotkeys::register(&app, &combo)
}

#[tauri::command]
pub fn set_size_preset(app: AppHandle, which: String) {
    match which.as_str() {
        "small" => appctl::set_preset_size(&app, 480.0, 320.0),
        "big" => appctl::set_preset_size(&app, 800.0, 534.0),
        _ => appctl::set_preset_size(&app, state::DEFAULT_W, state::DEFAULT_H),
    }
}

/// VFS:窗口按视频宽高比自动配型(ar = 视频宽/高)
#[tauri::command]
pub fn vfs_fit_window(app: AppHandle, ar: f64) {
    if ar.is_finite() && (0.2..=5.0).contains(&ar) {
        appctl::vfs_fit_window(&app, ar);
    }
}

/// VFS 退出:恢复原几何
#[tauri::command]
pub fn vfs_restore_cmd(app: AppHandle) {
    appctl::vfs_restore(&app);
}
