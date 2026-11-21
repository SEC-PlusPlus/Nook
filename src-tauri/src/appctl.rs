// 窗口行为:置顶 / 显隐 / 隐藏⇄唤回 / 尺寸预设(影院为纯页面层实现,不涉及窗口尺寸)
// 注:真正的"透明度"由注入脚本用 CSS opacity 实现(WebView2 内容不吃 Win32 整窗 alpha,
//     窗口本体以 transparent 模式创建);拖动时压暗也在 JS 里做,本模块只管数值存取。
use tauri::{AppHandle, PhysicalSize};

use crate::state::{main_win, persist, refresh_tray_menu, TOPMOST};

pub fn flip_topmost(app: &AppHandle) {
    let v = !TOPMOST.load(std::sync::atomic::Ordering::Relaxed);
    if let Some(w) = main_win(app) {
        let _ = w.set_always_on_top(v);
    }
    TOPMOST.store(v, std::sync::atomic::Ordering::Relaxed);
    persist(app, false);
    refresh_tray_menu(app);
}

pub fn toggle_visible(app: &AppHandle) {
    if let Some(w) = main_win(app) {
        if w.is_visible().unwrap_or(true) {
            let _ = w.hide();
        } else {
            show_main(app);
        }
    }
}

/// 显示并聚焦(若最小化则先还原)
pub fn show_main(app: &AppHandle) {
    if let Some(w) = main_win(app) {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
    }
}

/// 自定义快捷键/🗕语义:隐藏 ⇄ 唤回(不用系统最小化,规避透明窗任务栏空白)
pub fn toggle_minimize(app: &AppHandle) {
    let Some(w) = main_win(app) else { return };
    if w.is_visible().unwrap_or(true) {
        let _ = w.hide();
    } else {
        show_main(app);
    }
}

pub fn set_preset_size(app: &AppHandle, lw: f64, lh: f64) {
    if let Some(win) = main_win(app) {
        if let Ok(sf) = win.scale_factor() {
            let _ = win.set_size(PhysicalSize::new((lw * sf) as u32, (lh * sf) as u32));
        }
        persist(app, false);
    }
}


