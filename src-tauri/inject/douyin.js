// 注入到抖音网页:悬浮把手 / 真透明(CSS opacity)/ 视频小窗全屏(VFS)/ 设置面板
// 通道:ECDC + Rust eval 双注入,顶部幂等守卫;样式全走 CSSOM,免疫页面 CSP。
(() => {
  if (window.__DYWIN_BOOTED) return;
  window.__DYWIN_BOOTED = 1;

  const tauriWin = () => window.__TAURI__ && window.__TAURI__.window
    ? window.__TAURI__.window.getCurrentWindow() : null;
  const invoke = (cmd, args) => window.__TAURI__ && window.__TAURI__.core
    ? window.__TAURI__.core.invoke(cmd, args || {}) : Promise.reject('no tauri bridge');
  const css = (el, txt) => { el.style.cssText += txt; };
  const SKIP = new Set(['dywin-bar', 'dywin-panel', 'dywin-lock']);

  // ===== 锁(防误触):屏蔽层吞掉对视频内容的鼠标/滚轮/右键;把手与面板不受影响 =====
  let locked = false;
  const setLock = (on) => {
    locked = on;
    let ov = document.getElementById('dywin-lock');
    if (on && !ov && document.body) {
      ov = document.createElement('div');
      ov.id = 'dywin-lock';
      css(ov, 'position:fixed;inset:0;z-index:2147483000;background:transparent;cursor:default;');
      ['pointerdown', 'mousedown', 'mouseup', 'click', 'dblclick', 'contextmenu', 'wheel']
        .forEach((t) => ov.addEventListener(t, (e) => {
          e.preventDefault(); e.stopPropagation();
        }, { passive: false }));
      document.body.appendChild(ov);
    } else if (!on && ov) {
      ov.remove();
    }
    const b = document.getElementById('dywin-lockbtn');
    if (b) {
      b.textContent = on ? '🔒' : '🔓';
      b.style.color = on ? '#5df2d6' : '#9db4cc';
    }
  };
  window.__DYWIN_SET_LOCK = setLock;

  let userAlpha = 100;      // 15-100
  let dragSupp = false;     // 拖动中 → 压暗
  let vfsOn = false;
  let vfsSaved = null;      // [[player, origParent, cssText]] 退出时送播放器回家
  let vfsLoopGuard = null;  // 重播/防回填/防自动连播 守卫

  // 屏幕上正在播的"大视频"(按面积判定:横窗播竖屏时宽不足,不能按宽高各自卡阈值)
  // IIFE 顶层定义:applyScale 与 zenApply 两个闭包共用
  const bigVisibleVideo = () => {
    const area = innerWidth * innerHeight;
    for (const x of document.querySelectorAll('video')) {
      const b = x.getBoundingClientRect();
      if (b.width * b.height >= area * 0.15 && b.bottom > 0 && b.top < innerHeight) return x;
    }
    return null;
  };

  // ===== 等比缩放 + 真透明:作用于 body 直属子元素(把手/面板/视频层除外) =====
  const TARGET_CSS_W = 1280;
  const TARGET_CSS_H = 820; // 给播放页控制条留足 css 高度,避免底部被裁
  const applyScale = () => {
    if (!document.body) return;
    // 页面底板透明:否则 alpha 再低也只是"淡灰纱",看不到窗口下面的软件
    if (document.body.style.background !== 'transparent') document.body.style.background = 'transparent';
    if (document.documentElement.style.background !== 'transparent') {
      document.documentElement.style.background = 'transparent';
    }
    // 正在看"大视频"(播放页/feed 播放态/影院宿主)时整页豁免 zoom:
    // 抖音播放器自适配窗口,我们的 zoom 撞上其 100vh 内部布局会产生画中画式错位
    const playerVisible = () => !!bigVisibleVideo();
    const z = playerVisible() ? 1.0 : Math.min(1.0, Math.max(0.42,
      Math.min(window.innerWidth / TARGET_CSS_W, window.innerHeight / TARGET_CSS_H)));
    const a = (dragSupp ? Math.min(userAlpha, 60) : userAlpha) / 100;
    const zs = z.toFixed(3);
    const as = a.toFixed(3);
    // 影院宿主永远豁免 zoom;透明度照常作用于宿主
    for (const el of document.body.children) {
      if (el.nodeType === 1 && !SKIP.has(el.id) && el.style) {
        const want = el.id === 'dywin-vfsbox' ? '1.000' : zs;
        if (el.style.zoom !== want) el.style.zoom = want;
        if (el.style.opacity !== as) el.style.opacity = as;
      }
    }
    zenApply();
  };

  // ===== 沉浸(zen):播放态把三栏外观栏缩小,把空间让给视频 =====
  // 目标三栏:左导航栏(精选/推荐)、顶栏(搜索/更多/通知)、右导航(上一/下一条)。
  // 手法=对栏元素设 zoom 0.55 等比缩小(display:none 版被否:用户要"缩小"非隐藏);
  // 含视频的祖先保护,互动按钮条(在视频右侧但属播放器内部)天然不在候选;
  // 回网格(无大视频)自动还原;影院态跳过;开关持久化,⚙ 面板可关。
  const ZEN_SHRINK = '0.55';
  let zenOn;
  try { zenOn = localStorage.getItem('nook.zen') !== '0'; } catch (_) { zenOn = true; }
  const zenShrunk = new Map(); // el -> 原 zoom 值
  const zenApply = () => {
    for (const [el, z] of zenShrunk) {
      if (z) el.style.zoom = z; else el.style.removeProperty('zoom');
    }
    zenShrunk.clear();
    if (!zenOn || vfsOn || !document.body) return;
    const v = bigVisibleVideo();
    if (!v) return;
    const vb = v.getBoundingClientRect();
    const protect = new Set();
    for (let a = v; a; a = a.parentElement) protect.add(a);
    protect.add(document.documentElement);
    protect.add(document.body);
    const matched = [];
    const consider = (el) => {
      if (el.nodeType !== 1 || protect.has(el) || SKIP.has(el.id) || zenShrunk.has(el)) return;
      if (el.contains(v)) return; // 含视频的子树不碰
      const b = el.getBoundingClientRect();
      if (b.width <= 0 || b.height <= 0) return;
      const thin = innerWidth * 0.24;
      const leftRail = b.left <= 10 && b.right <= vb.left + 24
        && b.height >= innerHeight * 0.3 && b.width <= thin;
      // 右导航(上一/下一条):在视频右缘且留空隙,不碰播放器内部的互动按钮
      const rightRail = b.left >= vb.right + 4 && b.right >= innerWidth - 12
        && b.height >= innerHeight * 0.3 && b.width <= thin;
      const topBar = b.top <= 8 && b.height <= 96 && b.width >= innerWidth * 0.4;
      if (leftRail || rightRail || topBar) matched.push(el);
    };
    // 有界扫描:深度 ≤9;必须下钻含视频的祖先(栏与视频同父),
    // 安全性由 consider 内的 protect/contains 保证
    const stack = [[document.body, 0]];
    while (stack.length) {
      const [node, d] = stack.pop();
      for (const c of node.children) {
        consider(c);
        if (d < 9) stack.push([c, d + 1]);
      }
    }
    // 去重:只保留最外层栏(嵌套命中会让 zoom 叠乘,0.55×0.55 就过度了)
    for (const el of matched) {
      if (matched.some((o) => o !== el && o.contains(el))) continue;
      zenShrunk.set(el, el.style.zoom || '');
      el.style.zoom = ZEN_SHRINK;
    }
  };
  window.__DYWIN_ZEN = zenApply; // 调试/面板钩子
  let scaleT;
  const scheduleScale = () => { clearTimeout(scaleT); scaleT = setTimeout(applyScale, 120); };
  window.addEventListener('resize', scheduleScale);
  if (document.documentElement) {
    new MutationObserver(scheduleScale)
      .observe(document.documentElement, { childList: true });
  }
  setInterval(applyScale, 3000);
  if (typeof CSSStyleSheet === 'function' && document.adoptedStyleSheets) {
    try {
      const ss = new CSSStyleSheet();
      ss.replaceSync('::-webkit-scrollbar{width:0!important;height:0!important}');
      document.adoptedStyleSheets = [...document.adoptedStyleSheets, ss];
    } catch (e) { }
  }

// ===== 影院(单视频聚焦模式)=====
  // 进入:当前视频的播放器搬进顶层宿主——窗口保持现状可随意 resize(宿主随视口自适应);
  // 屏蔽滑动(wheel 被宿主吞掉、滚动键在 keydown 层拦截);视频播完自动重播;
  // 想看别的视频:Esc/⛶ 退出,播放器回家。进入/退出对页面零布局侵入。
  const vfsBtnVisual = () => {
    const b = document.getElementById('dywin-fs');
    if (b) b.style.color = vfsOn ? '#5df2d6' : '';
  };

  // 当前可见的 video
  const vfsCurrentVideo = () => {
    const all = document.querySelectorAll('video');
    let fallback = null;
    for (const x of all) {
      const b = x.getBoundingClientRect();
      if (b.width > 0 && b.top > -b.height * 0.5 && b.top < innerHeight * 0.5) return x;
      if (!fallback) fallback = x;
    }
    return fallback;
  };

  const vfsPlayerOf = (v) => (v.closest && v.closest('[class*="xgplayer"]')) || v.parentElement || v;

  // 影院态隐藏播放器底栏(进度条+暂停/连播/清屏/倍速/音量那行):
  // 几何判定=视频下缘一带的横条,只缩最外层;每轮重判(位置会变),退出全量还原
  const vfsCtl = new Map(); // el -> 原 display
  const vfsRestoreCtl = () => {
    for (const [el, disp] of vfsCtl) { try { el.style.display = disp; } catch (_) { } }
    vfsCtl.clear();
  };
  const vfsHideCtl = (pl) => {
    const vv = pl.querySelector('video');
    if (!vv) return;
    const vb = vv.getBoundingClientRect();
    vfsRestoreCtl();
    const cands = [];
    for (const el of pl.querySelectorAll('*')) {
      if (el.contains(vv)) continue; // 含视频的容器不碰
      const b = el.getBoundingClientRect();
      if (b.height <= 0 || b.height > 110) continue;
      if (b.width < Math.max(160, vb.width) * 0.6) continue;
      if (b.top >= vb.bottom - 110 && b.bottom <= innerHeight + 6) cands.push(el);
    }
    for (const el of cands) {
      if (cands.some((o) => o !== el && o.contains(el))) continue;
      vfsCtl.set(el, el.style.display);
      el.style.display = 'none';
    }
  };

  const vfsStyleTick = () => {
    if (!vfsOn || !vfsSaved || !vfsSaved[0]) return;
    const vv = vfsSaved[0][0].querySelector('video');
    if (!vv) return;
    vfsHideCtl(vfsSaved[0][0]);
    // 防播放器回填样式:逐轮重刷。contain=画面按原始比例完整居中,窗口比例不合时只出黑边,
    // 不裁切不拉伸(即"原视频等比例缩小")
    vv.style.setProperty('width', '100%', 'important');
    vv.style.setProperty('height', '100%', 'important');
    vv.style.setProperty('object-fit', 'contain', 'important');
    // 播完重播
    if (vv.ended || vv.currentTime >= vv.duration - 0.3 && vv.duration) {
      try { vv.currentTime = 0; vv.play(); } catch (_) { }
    }
    // 抖音在宿主外自动播下一条 → 摁住它
    for (const other of document.querySelectorAll('video')) {
      if (other !== vv && !other.paused) { try { other.pause(); } catch (_) { } }
    }
  };

  const toggleVfs = () => {
    if (vfsOn) {
      // 退出:播放器回家、样式还原、宿主移除、守卫清除
      for (const [el, parent, txt] of (vfsSaved || [])) {
        try { el.style.cssText = txt; } catch (_) { }
        try { if (parent && parent.isConnected) parent.appendChild(el); else el.remove(); } catch (_) { }
      }
      vfsSaved = null;
      if (vfsLoopGuard) { clearInterval(vfsLoopGuard); vfsLoopGuard = null; }
      vfsRestoreCtl();
      const host = document.getElementById('dywin-vfsbox');
      if (host) host.remove();
      window.__DYWIN_VFSTOP = null;
      vfsOn = false;
      vfsBtnVisual();
      applyScale();
      return;
    }
    const v = vfsCurrentVideo();
    if (!v) return;
    const pl = vfsPlayerOf(v);
    vfsSaved = [[pl, pl.parentElement, pl.style.cssText]]; // 回家的路
    const host = document.createElement('div');
    host.id = 'dywin-vfsbox';
    css(host, `position:fixed;inset:0;z-index:2147483600;background:transparent;overflow:hidden;
      display:flex;align-items:center;justify-content:center;`);
    // 滑动屏蔽:wheel 在宿主层吞掉(播放器内控件的点击不受影响)
    host.addEventListener('wheel', (e) => { e.preventDefault(); e.stopPropagation(); }, { passive: false });
    document.body.appendChild(host);
    pl.style.setProperty('width', '100%', 'important');
    pl.style.setProperty('height', '100%', 'important');
    pl.style.setProperty('margin', '0', 'important');
    host.appendChild(pl); // 移动 DOM 不中断播放
    vfsOn = true;
    window.__DYWIN_VFSTOP = true;
    vfsStyleTick();
    vfsLoopGuard = setInterval(vfsStyleTick, 400);
    vfsBtnVisual();
    applyScale();
  };
  window.__DYWIN_TOGGLE_VFS = toggleVfs;

    // 抖音原生全屏请求 → 改道 VFS
  if (!Element.prototype.__DYWIN_FS_HIJACKED) {
    Element.prototype.__DYWIN_FS_HIJACKED = 1;
    const raf = Element.prototype.requestFullscreen;
    Element.prototype.requestFullscreen = function () {
      if (this.closest && this.closest('#dywin-bar,#dywin-panel')) return raf.apply(this, arguments);
      toggleVfs();
      return Promise.resolve(null);
    };
  }

  // ===== 把手 =====
  const mount = () => {
    if (!document.body) return false;

    const bar = document.createElement('div');
    bar.id = 'dywin-bar';
    css(bar, `position:fixed;top:4px;left:50%;transform:translateX(-50%);
      z-index:2147483647;display:flex;gap:8px;align-items:center;
      padding:3px 12px;border-radius:15px;background:rgba(12,12,16,.85);
      color:#bbb;font:12px/1.5 -apple-system,'Segoe UI','Microsoft YaHei',sans-serif;
      user-select:none;opacity:.35;transition:opacity .25s ease;
      box-shadow:0 2px 10px rgba(0,0,0,.4);`);
    bar.addEventListener('mouseenter', () => { bar.style.opacity = '1'; });
    bar.addEventListener('mouseleave', () => { bar.style.opacity = '.35'; });

    const mkBtn = (id, label, title) => {
      const s = document.createElement('span');
      s.id = id; s.textContent = label; s.title = title || '';
      css(s, `cursor:pointer;padding:1px 8px;border-radius:9px;color:#9db4cc;white-space:nowrap;`);
      bar.appendChild(s);
      return s;
    };

    const drag = document.createElement('span');
    drag.id = 'dywin-drag';
    drag.textContent = '⠿⠿';
    drag.title = '按住拖动;双击=视频铺满小窗;页面任意处 Alt+按住左键也可拖';
    css(drag, `cursor:move;letter-spacing:3px;color:#999;padding:0 2px;`);
    bar.appendChild(drag);

    const topBtn = mkBtn('dywin-top', '置顶', '窗口置顶开关');
    const slider = document.createElement('input');
    slider.id = 'dywin-alpha';
    slider.type = 'range'; slider.min = '15'; slider.max = '100'; slider.value = String(userAlpha);
    slider.title = '透明度:能透过去看到桌面(拖动窗口时自动更透)';
    css(slider, `width:86px;height:4px;cursor:pointer;accent-color:#25f4ee;`);
    bar.appendChild(slider);

    const fsBtn = mkBtn('dywin-fs', '⛶', '视频铺满小窗(Esc 还原)');
    const minBtn = mkBtn('dywin-min', '🗕', '隐藏到托盘(Ctrl+Q 同样收放)');
    const gearBtn = mkBtn('dywin-gear', '⚙', '设置面板');
    const lockBtn = mkBtn('dywin-lockbtn', '🔓', '锁住:屏蔽对视频的鼠标/滚轮/键盘误触(拖窗、把手仍可用)');
    const hideBtn = mkBtn('dywin-hide', '✕', '关闭并退出程序');

    document.body.appendChild(bar);
    applyScale();

    // 拖动(含拖动期压暗)
    const dragStart = () => { if (!dragSupp) { dragSupp = true; applyScale(); } };
    const dragEnd = () => { if (dragSupp) { dragSupp = false; applyScale(); } };
    drag.addEventListener('mousedown', (e) => {
      const w = tauriWin();
      if (w) { e.preventDefault(); e.stopPropagation(); dragStart(); w.startDragging(); }
    });
    window.addEventListener('mouseup', dragEnd, true);
    drag.addEventListener('dblclick', toggleVfs);
    document.addEventListener('mousedown', (e) => {
      const w = tauriWin();
      if (e.altKey && w && !(e.target.closest && e.target.closest('#dywin-bar,#dywin-panel'))) {
        e.preventDefault(); dragStart(); w.startDragging();
      }
    }, true);
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && vfsOn) { toggleVfs(); e.stopPropagation(); }
      // 影院模式:滚动键被吞(想看下一条请先退出影院)
      if (vfsOn && ['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End'].includes(e.key)
        && !(e.target && e.target.closest && e.target.closest('#dywin-bar,#dywin-panel'))) {
        e.preventDefault();
        e.stopPropagation();
      }
      // 锁定时屏蔽页面快捷键(空格/方向键等);录入快捷键与 Esc 放行
      if (locked && !recording && e.key !== 'Escape'
        && !(e.target && e.target.closest && e.target.closest('#dywin-bar,#dywin-panel'))) {
        e.preventDefault();
        e.stopPropagation();
      }
    }, true);

    // 按钮
    const flip = (el, on) => { el._on = on; el.style.color = on ? '#5df2d6' : '#9db4cc'; };
    topBtn.addEventListener('click', () => {
      invoke('toggle_topmost').then(() => flip(topBtn, !topBtn._on)).catch(() => { topBtn.style.color = '#f77'; });
    });
    fsBtn.addEventListener('click', toggleVfs);
    minBtn.addEventListener('click', () => invoke('hide_main').catch(() => {}));
    gearBtn.addEventListener('click', () => window.__DYWIN_PANEL.toggle());
    lockBtn.addEventListener('click', () => setLock(!locked));
    hideBtn.addEventListener('click', () => invoke('quit_app').catch(() => {}));

    // 滑条:本地即时应用 + 防抖持久化
    let sendT;
    slider.addEventListener('input', () => {
      userAlpha = +slider.value;
      applyScale();
      clearTimeout(sendT);
      sendT = setTimeout(() => { invoke('set_opacity', { pct: userAlpha }).catch(() => {}); }, 250);
    });
    slider.addEventListener('mousedown', (e) => e.stopPropagation());

    // ===== 设置面板(页面内小组件,不新开窗口) =====
    const panel = document.createElement('div');
    panel.id = 'dywin-panel';
    css(panel, `position:fixed;top:34px;left:50%;transform:translateX(-50%);
      z-index:2147483647;display:none;flex-direction:column;gap:8px;width:300px;
      padding:12px 14px;border-radius:12px;background:rgba(16,16,22,.96);
      color:#cfcfd8;font:12px/1.6 -apple-system,'Segoe UI','Microsoft YaHei',sans-serif;
      box-shadow:0 6px 24px rgba(0,0,0,.5);`);
    panel.innerHTML = `
      <div style="font-weight:600;color:#fff">设置</div>
      <div>一键最小化快捷键:</div>
      <div data-kcap style="padding:6px 8px;border:1px dashed #3a3a48;border-radius:8px;text-align:center;color:#8a8a98;cursor:pointer;background:rgba(0,0,0,.25)">点击录入</div>
      <div style="display:flex;gap:6px"><button data-kapply style="flex:1">应用</button><button data-kclear style="flex:1">清除</button></div>
      <div data-kmsg style="min-height:16px;font-size:11px;color:#8a8a98"></div>
      <div style="border-top:1px solid #2c2c38;padding-top:8px">窗口大小:</div>
      <div style="display:flex;gap:6px"><button data-size="small">小</button><button data-size="std">标准</button><button data-size="big">大</button></div>
      <label data-zenrow style="display:flex;align-items:center;gap:6px;border-top:1px solid #2c2c38;padding-top:8px;cursor:pointer">
        <input type="checkbox" data-zen style="accent-color:#25f4ee"> 沉浸:播放时缩小左/上/右三栏
      </label>
      <div style="color:#666;font-size:11px">透明滑条在把手上;窗口边缘可直接拖拽缩放</div>`;
    document.body.appendChild(panel);
    const BTN = `padding:5px 0;border-radius:7px;border:1px solid #34343f;background:#26262f;color:#d0d0d8;cursor:pointer;font-size:12px;flex:1`;
    panel.querySelectorAll('button').forEach((b) => { css(b, BTN); });

    const kcap = panel.querySelector('[data-kcap]');
    const kmsg = panel.querySelector('[data-kmsg]');
    const kapply = panel.querySelector('[data-kapply]');
    const kclear = panel.querySelector('[data-kclear]');
    let recording = false, pendingCombo = '';
    const codeName = (c) => {
      const m1 = /^Key([A-Z])$/.exec(c); if (m1) return m1[1].toLowerCase();
      const m2 = /^Digit(\d)$/.exec(c); if (m2) return m2[1];
      return c.toLowerCase();
    };
    document.addEventListener('keydown', (e) => {
      if (!recording) return;
      e.preventDefault(); e.stopPropagation();
      if (e.key === 'Escape') { recording = false; kcap.textContent = pendingCombo || '点击录入'; return; }
      const mods = [];
      if (e.ctrlKey) mods.push('ctrl');
      if (e.altKey) mods.push('alt');
      if (e.shiftKey) mods.push('shift');
      if (e.metaKey) mods.push('win');
      const k = codeName(e.code);
      if (['control', 'alt', 'shift', 'meta', 'os'].includes(k)) return;
      pendingCombo = [...mods, k].join('+');
      kcap.textContent = pendingCombo;
    }, true);
    kcap.addEventListener('click', () => {
      recording = true; pendingCombo = '';
      kcap.textContent = '按下按键…(Esc 取消)';
      kcap.style.borderColor = '#25f4ee';
    });
    kapply.addEventListener('click', () => {
      if (!pendingCombo) return;
      invoke('set_hotkey', { combo: pendingCombo })
        .then(() => { kmsg.style.color = '#5df2d6'; kmsg.textContent = '已生效:' + pendingCombo; recording = false; kcap.style.borderColor = ''; })
        .catch((err) => { kmsg.style.color = '#f77'; kmsg.textContent = String(err).slice(0, 90); });
    });
    kclear.addEventListener('click', () => {
      invoke('set_hotkey', { combo: '' })
        .then(() => { pendingCombo = ''; kcap.textContent = '未设置'; kmsg.textContent = '已清除'; })
        .catch(() => {});
    });
    const zenCb = panel.querySelector('[data-zen]');
    zenCb.checked = zenOn;
    zenCb.addEventListener('change', () => {
      zenOn = zenCb.checked;
      try { localStorage.setItem('nook.zen', zenOn ? '1' : '0'); } catch (_) { }
      applyScale();
    });

    panel.querySelectorAll('[data-size]').forEach((b) => {
      b.addEventListener('click', () => invoke('set_size_preset', { which: b.dataset.size }).catch(() => {}));
    });

    window.__DYWIN_PANEL = {
      toggle(force) {
        const open = force === true || panel.style.display === 'none';
        panel.style.display = open ? 'flex' : 'none';
      },
    };

    // 状态同步
    invoke('get_settings').then((s) => {
      if (!s) return;
      if (typeof s.opacity === 'number') { userAlpha = s.opacity; slider.value = String(s.opacity); applyScale(); }
      if (typeof s.topmost === 'boolean') flip(topBtn, s.topmost);
      if (s.hotkey) { pendingCombo = s.hotkey; kcap.textContent = s.hotkey; }
    }).catch(() => {});

    // 闲置淡出
    let fade;
    const poke = () => {
      bar.style.opacity = '1';
      clearTimeout(fade);
      fade = setTimeout(() => { bar.style.opacity = '.35'; }, 2500);
    };
    document.addEventListener('mousemove', poke);
    poke();
    return true;
  };

  if (!mount()) {
    let n = 0;
    const iv = setInterval(() => { if (mount() || ++n > 100) clearInterval(iv); }, 200);
  }
})();
