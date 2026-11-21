// 全局状态与持久化:各行为模块共用的单一事实源
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::json;
use tauri::{AppHandle, Manager, WebviewWindow};
use tauri_plugin_global_shortcut::{Code, Modifiers};
use tauri_plugin_store::StoreExt;

pub const STORE: &str = "config.json"; // %APPDATA%\cn.douyinwin.desktop\
pub const CFG_VER: u64 = 3; // 几何语义版本:ver<3 的旧尺寸配置作废
pub const DEFAULT_W: f64 = 640.0;
pub const DEFAULT_H: f64 = 427.0;

pub static TOPMOST: AtomicBool = AtomicBool::new(true);
pub static ALPHA_PCT: AtomicU32 = AtomicU32::new(100); // 用户透明度 15-100(由 JS 应用)
pub static LAST_FLUSH: AtomicU64 = AtomicU64::new(0);

pub type Combo = (String, (Modifiers, Code));

static HOTKEY: OnceLock<Mutex<Option<Combo>>> = OnceLock::new();

pub fn hotkey() -> &'static Mutex<Option<Combo>> {
    HOTKEY.get_or_init(|| Mutex::new(None))
}

/// 存档几何合法性:拒绝最小化占位(-32000 屏外)与畸形尺寸
fn geo_sane(x: i32, y: i32, w: u32, h: u32) -> bool {
    x > -30000 && y > -30000 && w >= 200 && h >= 150
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// 旧标识符(cn.douyinwin.desktop)数据一次性迁移到 dev.nook.desktop,保住登录态与设置
pub fn migrate_legacy() {
    for var in ["APPDATA", "LOCALAPPDATA"] {
        let Some(root) = std::env::var_os(var) else { continue };
        let old = std::path::Path::new(&root).join("cn.douyinwin.desktop");
        let new = std::path::Path::new(&root).join("dev.nook.desktop");
        if old.is_dir() && !new.exists() {
            let _ = copy_dir(&old, &new);
        }
    }
}

fn copy_dir(from: &std::path::Path, to: &std::path::Path) -> std::io::Result<()> {
    std::fs::create_dir_all(to)?;
    for entry in std::fs::read_dir(from)? {
        let entry = entry?;
        let target = to.join(entry.file_name());
        if entry.file_type()?.is_dir() {
            copy_dir(&entry.path(), &target)?;
        } else {
            let _ = std::fs::copy(entry.path(), target);
        }
    }
    Ok(())
}

pub fn main_win(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window("main")
}

pub fn store_get(app: &AppHandle) -> Option<std::sync::Arc<tauri_plugin_store::Store<tauri::Wry>>> {
    app.store(STORE).ok()
}

/// plugin-store v2.5 的 save() 为同步写,文件很小;节流由 persist 负责
pub fn flush_store(app: &AppHandle) {
    if let Some(s) = store_get(app) {
        let _ = s.save();
    }
}

/// 启动读取:迁移旧版本、恢复透明度/置顶。返回(几何, 置顶)
pub fn init_from_store(app: &AppHandle) -> (Option<(i32, i32, u32, u32)>, bool) {
    let Some(s) = store_get(app) else {
        return (None, true);
    };
    let ver = s.get("ver").and_then(|v| v.as_u64()).unwrap_or(1);
    if ver < CFG_VER {
        s.delete("geo");
        s.set("ver", json!(CFG_VER));
        flush_store(app);
    }
    ALPHA_PCT.store(
        s.get("alpha").and_then(|v| v.as_u64()).unwrap_or(100) as u32,
        Ordering::Relaxed,
    );
    let top = s.get("topmost").and_then(|v| v.as_bool()).unwrap_or(true);
    TOPMOST.store(top, Ordering::Relaxed);
    let geo = if ver < CFG_VER {
        None
    } else {
        s.get("geo").and_then(|g| {
            let t = (
                g.get("x")?.as_i64()? as i32,
                g.get("y")?.as_i64()? as i32,
                g.get("w")?.as_u64()? as u32,
                g.get("h")?.as_u64()? as u32,
            );
            geo_sane(t.0, t.1, t.2, t.3).then_some(t)
        })
    };
    (geo, top)
}

/// 写内存并(节流或强制)落盘
pub fn persist(app: &AppHandle, flush: bool) {
    let Some(s) = store_get(app) else { return };
    if let Some(w) = main_win(app) {
        if !w.is_minimized().unwrap_or(false) {
            if let (Ok(p), Ok(z)) = (w.inner_position(), w.inner_size()) {
                if geo_sane(p.x, p.y, z.width, z.height) {
                    s.set("geo", json!({ "x": p.x, "y": p.y, "w": z.width, "h": z.height }));
                }
            }
        }
    }
    s.set("topmost", json!(TOPMOST.load(Ordering::Relaxed)));
    s.set("alpha", json!(ALPHA_PCT.load(Ordering::Relaxed)));
    if flush || now_ms().saturating_sub(LAST_FLUSH.load(Ordering::Relaxed)) > 900 {
        LAST_FLUSH.store(now_ms(), Ordering::Relaxed);
        flush_store(app);
    }
}

pub fn refresh_tray_menu(app: &AppHandle) {
    if let Some(tray) = app.tray_by_id("tray") {
        if let Ok(menu) = crate::ui::build_menu(app) {
            let _ = tray.set_menu(Some(menu));
        }
    }
}
