// 自定义"一键最小化"全局快捷键:字符串解析、注册、校验、恢复
use tauri::AppHandle;
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut};

use crate::state::{self, hotkey, Combo};

fn key_to_code(k: &str) -> Option<Code> {
    let k = k.to_ascii_lowercase();
    let one = |ch: char| match ch {
        'a' => Some(Code::KeyA), 'b' => Some(Code::KeyB), 'c' => Some(Code::KeyC),
        'd' => Some(Code::KeyD), 'e' => Some(Code::KeyE), 'f' => Some(Code::KeyF),
        'g' => Some(Code::KeyG), 'h' => Some(Code::KeyH), 'i' => Some(Code::KeyI),
        'j' => Some(Code::KeyJ), 'k' => Some(Code::KeyK), 'l' => Some(Code::KeyL),
        'm' => Some(Code::KeyM), 'n' => Some(Code::KeyN), 'o' => Some(Code::KeyO),
        'p' => Some(Code::KeyP), 'q' => Some(Code::KeyQ), 'r' => Some(Code::KeyR),
        's' => Some(Code::KeyS), 't' => Some(Code::KeyT), 'u' => Some(Code::KeyU),
        'v' => Some(Code::KeyV), 'w' => Some(Code::KeyW), 'x' => Some(Code::KeyX),
        'y' => Some(Code::KeyY), 'z' => Some(Code::KeyZ),
        '0' => Some(Code::Digit0), '1' => Some(Code::Digit1), '2' => Some(Code::Digit2),
        '3' => Some(Code::Digit3), '4' => Some(Code::Digit4), '5' => Some(Code::Digit5),
        '6' => Some(Code::Digit6), '7' => Some(Code::Digit7), '8' => Some(Code::Digit8),
        '9' => Some(Code::Digit9),
        _ => None,
    };
    // 兼容浏览器 e.code 写法("KeyQ"/"Digit3")
    if let Some(rest) = k.strip_prefix("key") {
        let mut ch = rest.chars();
        if let (Some(c), None) = (ch.next(), ch.next()) {
            return one(c);
        }
    }
    if let Some(rest) = k.strip_prefix("digit") {
        let mut ch = rest.chars();
        if let (Some(c), None) = (ch.next(), ch.next()) {
            return one(c);
        }
    }
    if k.chars().count() == 1 {
        return one(k.chars().next().unwrap());
    }
    match k.as_str() {
        "f1" => Some(Code::F1), "f2" => Some(Code::F2), "f3" => Some(Code::F3),
        "f4" => Some(Code::F4), "f5" => Some(Code::F5), "f6" => Some(Code::F6),
        "f7" => Some(Code::F7), "f8" => Some(Code::F8), "f9" => Some(Code::F9),
        "f10" => Some(Code::F10), "f11" => Some(Code::F11), "f12" => Some(Code::F12),
        "space" => Some(Code::Space),
        "enter" | "return" => Some(Code::Enter),
        "tab" => Some(Code::Tab),
        "esc" | "escape" => Some(Code::Escape),
        "pause" => Some(Code::Pause),
        "scrolllock" => Some(Code::ScrollLock),
        _ => None,
    }
}

/// 无修饰键也允许按的键(单字母/数字全局劫持会废掉所有软件的打字)
fn standalone_safe(code: &Code) -> bool {
    matches!(
        code,
        Code::F1 | Code::F2 | Code::F3 | Code::F4 | Code::F5 | Code::F6
        | Code::F7 | Code::F8 | Code::F9 | Code::F10 | Code::F11 | Code::F12
        | Code::Pause | Code::ScrollLock
    )
}

/// "ctrl+alt+q" → (Modifiers, Code),含安全校验
pub fn parse_combo(s: &str) -> Result<(Modifiers, Code), String> {
    let parts: Vec<String> = s
        .split('+')
        .map(|p| p.trim().to_ascii_lowercase())
        .filter(|p| !p.is_empty())
        .collect();
    if parts.is_empty() {
        return Err("快捷键为空".into());
    }
    let code = key_to_code(parts.last().unwrap())
        .ok_or_else(|| format!("不支持的按键「{}」", parts.last().unwrap()))?;
    let mut mods = Modifiers::empty();
    for m in &parts[..parts.len() - 1] {
        mods |= match m.as_str() {
            "ctrl" | "control" => Modifiers::CONTROL,
            "alt" => Modifiers::ALT,
            "shift" => Modifiers::SHIFT,
            "win" | "super" | "meta" => Modifiers::SUPER,
            other => return Err(format!("不支持的组合键「{other}」")),
        };
    }
    if mods.is_empty() && !standalone_safe(&code) {
        return Err("单独字母/数字会全局劫持键盘,请搭配 Ctrl/Alt/Shift,或改用 F1-F12".into());
    }
    Ok((mods, code))
}

/// 注册(替换旧值);combo 为空 = 仅清除
pub fn register(app: &AppHandle, combo: &str) -> Result<(), String> {
    let old = hotkey().lock().unwrap().take();
    if let Some((_, (mods, code))) = old {
        let _ = app.global_shortcut().unregister(Shortcut::new(Some(mods), code));
    }
    let combo = combo.trim();
    if combo.is_empty() {
        if let Some(s) = state::store_get(app) {
            s.set("hotkey", serde_json::json!(""));
            state::flush_store(app);
        }
        return Ok(());
    }
    let (mods, code) = parse_combo(combo)?;
    app.global_shortcut()
        .register(Shortcut::new(Some(mods), code))
        .map_err(|e| format!("注册失败:{e}"))?;
    let parsed: Combo = (combo.to_string(), (mods, code));
    *hotkey().lock().unwrap() = Some(parsed);
    if let Some(s) = state::store_get(app) {
        s.set("hotkey", serde_json::json!(combo));
        state::flush_store(app);
    }
    Ok(())
}

/// 启动时恢复快捷键:从未配置过 → 默认 Ctrl+Q;显式清除过(空串) → 保持不注册
pub fn restore_from_store(app: &AppHandle) {
    let saved = state::store_get(app)
        .and_then(|s| s.get("hotkey").and_then(|v| v.as_str().map(String::from)));
    match saved {
        None => {
            let _ = register(app, "ctrl+q");
        }
        Some(hk) if !hk.is_empty() => {
            let _ = register(app, &hk);
        }
        _ => {}
    }
}

/// 快捷键事件中判定是否命中自定义组合
pub fn matches_custom(shortcut: &Shortcut) -> bool {
    hotkey()
        .lock()
        .unwrap()
        .as_ref()
        .map(|(_, (m, c))| shortcut.mods == *m && shortcut.key == *c)
        .unwrap_or(false)
}
