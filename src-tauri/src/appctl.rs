// 窗口行为:置顶 / 显隐 / 最小化 / 尺寸预设 / 持久化透明度值 / VFS 等比适配窗口
// 注:真正的"透明度"由注入脚本用 CSS opacity 实现(WebView2 内容不吃 Win32 整窗 alpha,
//     窗口本体以 transparent 模式创建);拖动时压暗也在 JS 里做,本模块只管数值存取。
use std::sync::{Mutex, OnceLock};

use tauri::{AppHandle, PhysicalPosition, PhysicalSize};

use crate::state::{main_win, persist, refresh_tray_menu, TOPMOST};

/// VFS 进入前的窗口几何(物理像素),退出时一次性恢复
static VFS_SNAP: OnceLock<Mutex<Option<(i32, i32, u32, u32)>>> = OnceLock::new();
fn vfs_snap() -> &'static Mutex<Option<(i32, i32, u32, u32)>> {
    VFS_SNAP.get_or_init(|| Mutex::new(None))
}

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

pub fn minimize_main(app: &AppHandle) {
    if let Some(w) = main_win(app) {
        let _ = w.minimize();
    }
}

/// 自定义快捷键语义:最小化 ⇄ 弹回;若隐藏到托盘则唤出
pub fn toggle_minimize(app: &AppHandle) {
    let Some(w) = main_win(app) else { return };
    if !w.is_visible().unwrap_or(true) {
        show_main(app);
        return;
    }
    if w.is_minimized().unwrap_or(false) {
        let _ = w.unminimize();
        let _ = w.set_focus();
    } else {
        let _ = w.minimize();
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

/// VFS:把窗口尺寸改配成视频比例(在 92% 工作区内取最大,居中),首次进入存档几何
pub fn vfs_fit_window(app: &AppHandle, ar: f64) {
    let Some(w) = main_win(app) else { return };
    if let (Ok(p), Ok(z)) = (w.inner_position(), w.inner_size()) {
        let mut snap = vfs_snap().lock().unwrap();
        if snap.is_none() {
            *snap = Some((p.x, p.y, z.width, z.height));
        }
    }
    let Ok(Some(m)) = w.current_monitor() else { return };
    let wa = m.work_area();
    let sf = w.scale_factor().unwrap_or(1.0);
    let max_w = (wa.size.width as f64 * 0.92) as u32;
    let max_h = (wa.size.height as f64 * 0.92) as u32;
    let (min_w, min_h) = ((480.0 * sf) as u32, (320.0 * sf) as u32);
    let (tw, th) = if (max_w as f64) / (max_h as f64) >= ar {
        ((max_h as f64 * ar) as u32, max_h)
    } else {
        (max_w, (max_w as f64 / ar) as u32)
    };
    let (tw, th) = (tw.max(min_w), th.max(min_h));
    let x = wa.position.x + (wa.size.width as i32 - tw as i32) / 2;
    let y = wa.position.y + (wa.size.height as i32 - th as i32) / 2;
    let _ = w.set_size(PhysicalSize::new(tw, th));
    let _ = w.set_position(PhysicalPosition::new(x, y));
    persist(app, false);
}

/// VFS 退出:恢复进入前的几何
pub fn vfs_restore(app: &AppHandle) {
    if let Some((x, y, w_, h_)) = vfs_snap().lock().unwrap().take() {
        if let Some(w) = main_win(app) {
            let _ = w.set_size(PhysicalSize::new(w_, h_));
            let _ = w.set_position(PhysicalPosition::new(x, y));
            persist(app, false);
        }
    }
}

