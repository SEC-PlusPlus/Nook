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
  let vfsSaved = null;      // [[el, cssText]] 祖先链样式还原
  let vfsHidden = null;     // [[el, display]] 侧栏/顶栏等旁支兄弟元素还原

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
    const z = Math.min(1.0, Math.max(0.42,
      Math.min(window.innerWidth / TARGET_CSS_W, window.innerHeight / TARGET_CSS_H)));
    const a = (dragSupp ? Math.min(userAlpha, 60) : userAlpha) / 100;
    const zs = z.toFixed(3);
    const as = a.toFixed(3);
    // VFS 激活时,包含视频的那棵子树豁免 zoom(fixed 元素在被缩放的祖先里会溢出视口)
    const fsTop = vfsOn ? window.__DYWIN_VFSTOP : null;
    for (const el of document.body.children) {
      if (el.nodeType === 1 && !SKIP.has(el.id) && el.style) {
        const want = el === fsTop ? '1.000' : zs;
        if (el.style.zoom !== want) el.style.zoom = want;
        if (el.style.opacity !== as) el.style.opacity = as;
      }
    }
  };
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

  // ===== 视频小窗全屏(VFS):接管播放容器 + 破除包含块劫持 + 看门狗自愈 =====
  const vfsBtnVisual = () => {
    const b = document.getElementById('dywin-fs');
    if (b) b.style.color = vfsOn ? '#5df2d6' : '';
  };
  let vfsAnchors = null;  // Set<el> 样式已存档的祖先
  let vfsHiddenSet = null; // Set<el> 已隐藏的旁支

  // 从视频上溯定位近似整屏的接管容器
  const vfsBoxEl = (v) => {
    let box = v;
    while (box && box !== document.body) {
      if (box.clientWidth >= innerWidth * 0.9 && box.clientHeight >= innerHeight * 0.8) return box;
      box = box.parentElement;
    }
    return v;
  };

  const vfsArchive = (el) => {
    if (!vfsAnchors.has(el)) {
      vfsSaved.push([el, el.style.cssText]);
      vfsAnchors.add(el);
    }
  };

  // 隐藏视频路径之外的旁支(左栏/顶栏/互动条);playerRoot 内部不动=控制层保留
  const vfsHideSiblings = (v) => {
    const boxEl = vfsBoxEl(v);
    const playerRoot = (v.closest && v.closest('[class*="xgplayer"]')) || v.parentElement;
    let cur = playerRoot;
    let guard = 0;
    while (cur && cur !== boxEl && cur.parentElement && cur.parentElement !== document.body && guard++ < 30) {
      const par = cur.parentElement;
      for (const sib of par.children) {
        if (sib !== cur && sib.nodeType === 1 && !SKIP.has(sib.id) && !vfsHiddenSet.has(sib)) {
          vfsHiddenSet.add(sib);
          vfsHidden.push([sib, sib.style.display]);
          sib.style.display = 'none';
        }
      }
      cur = par;
    }
    // VFS 期间豁免 zoom 的 body 直属祖先
    let topChild = boxEl;
    while (topChild.parentElement && topChild.parentElement !== document.body) {
      topChild = topChild.parentElement;
    }
    vfsArchive(topChild);
    window.__DYWIN_VFSTOP = topChild;
  };

  // 核心接管:破除会劫持 fixed 的祖先包含块,视频元素钉满视口,幂等可反复执行
  const vfsEnforce = () => {
    const v = document.querySelector('video');
    if (!v) return;
    let p = v;
    let guard = 0;
    while (p && p !== document.body && guard++ < 40) {
      vfsArchive(p);
      const s = p.style;
      // 无条件清除一切可劫持 fixed 包含块的属性(计算属性名跨引擎不可靠,宁可多清)
      s.setProperty('z-index', '2147483000', 'important');
      s.setProperty('transform', 'none', 'important');
      s.setProperty('filter', 'none', 'important');
      s.setProperty('backdrop-filter', 'none', 'important');
      s.setProperty('-webkit-backdrop-filter', 'none', 'important');
      s.setProperty('contain', 'none', 'important');
      s.setProperty('container-type', 'normal', 'important');
      s.setProperty('perspective', 'none', 'important');
      s.setProperty('will-change', 'auto', 'important');
      p = p.parentElement;
    }
    v.style.setProperty('position', 'fixed', 'important');
    v.style.setProperty('inset', '0', 'important');
    v.style.setProperty('width', '100vw', 'important');
    v.style.setProperty('height', '100vh', 'important');
    v.style.setProperty('margin', '0', 'important');
    v.style.setProperty('padding', '0', 'important');
    v.style.setProperty('background', 'transparent', 'important');
    v.style.setProperty('display', 'block', 'important');
    // cover:保持比例填满当前窗口,溢出均分裁切;窗口自由伸缩,视频实时贴合
    v.style.setProperty('object-fit', 'cover', 'important');
    vfsHideSiblings(v);
  };

  const toggleVfs = () => {
    if (vfsOn) {
      if (vfsSaved) for (const [el, txt] of vfsSaved) el.style.cssText = txt;
      if (vfsHidden) for (const [el, dsp] of vfsHidden) el.style.display = dsp;
      vfsSaved = null;
      vfsHidden = null;
      vfsAnchors = null;
      vfsHiddenSet = null;
      window.__DYWIN_VFSTOP = null;
      vfsOn = false;
      vfsBtnVisual();
      applyScale();
      return;
    }
    const v = document.querySelector('video');
    if (!v) return;
    vfsSaved = [];
    vfsHidden = [];
    vfsAnchors = new Set();
    vfsHiddenSet = new Set();
    vfsEnforce();
    vfsOn = true;
    vfsBtnVisual();
    applyScale();
  };


  // 安全开关:连播换节点等竞态下可能半途抛错——全部回滚,稍后自动重试一次,
  // 保证"要么完整进入影院,要么干净地什么都没发生"
  const safeToggleVfs = () => {
    const wasOn = vfsOn;
    try {
      toggleVfs();
    } catch (e) {
      try {
        if (vfsSaved) for (const [el, txt] of vfsSaved) el.style.cssText = txt;
        if (vfsHidden) for (const [el, dsp] of vfsHidden) el.style.display = dsp;
      } catch (_) { /* 回滚尽力而为 */ }
      vfsSaved = null; vfsHidden = null;
      vfsAnchors = null; vfsHiddenSet = null;
      window.__DYWIN_VFSTOP = null;
      vfsOn = false;
      vfsBtnVisual();
      applyScale();
      if (!wasOn) {
        setTimeout(() => {
          const v = document.querySelector('video');
          if (v && v.videoWidth && !vfsOn) { try { toggleVfs(); } catch (_) { } }
        }, 500);
      }
    }
  };
  window.__DYWIN_TOGGLE_VFS = safeToggleVfs;

  // 看门狗:播放器重写样式/自动连播换节点后自愈(窗口尺寸不动,cover 自动跟随)
  setInterval(() => {
    if (!vfsOn) return;
    const v = document.querySelector('video');
    if (!v) return;
    const b = v.getBoundingClientRect();
    if (Math.abs(b.top) > 2 || Math.abs(b.left) > 2
      || Math.abs(b.width - innerWidth) > 4 || Math.abs(b.height - innerHeight) > 4) {
      vfsEnforce();
      applyScale();
    }
  }, 600);

  // 抖音原生全屏请求 → 改道 VFS
  if (!Element.prototype.__DYWIN_FS_HIJACKED) {
    Element.prototype.__DYWIN_FS_HIJACKED = 1;
    const raf = Element.prototype.requestFullscreen;
    Element.prototype.requestFullscreen = function () {
      if (this.closest && this.closest('#dywin-bar,#dywin-panel')) return raf.apply(this, arguments);
      safeToggleVfs();
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
    const minBtn = mkBtn('dywin-min', '🗕', '最小化');
    const gearBtn = mkBtn('dywin-gear', '⚙', '设置面板');
    const lockBtn = mkBtn('dywin-lockbtn', '🔓', '锁住:屏蔽对视频的鼠标/滚轮/键盘误触(拖窗、把手仍可用)');
    const hideBtn = mkBtn('dywin-hide', '✕', '隐藏到托盘');

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
    drag.addEventListener('dblclick', safeToggleVfs);
    document.addEventListener('mousedown', (e) => {
      const w = tauriWin();
      if (e.altKey && w && !(e.target.closest && e.target.closest('#dywin-bar,#dywin-panel'))) {
        e.preventDefault(); dragStart(); w.startDragging();
      }
    }, true);
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && vfsOn) { safeToggleVfs(); e.stopPropagation(); }
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
    fsBtn.addEventListener('click', safeToggleVfs);
    minBtn.addEventListener('click', () => invoke('minimize_main_cmd').catch(() => {}));
    gearBtn.addEventListener('click', () => window.__DYWIN_PANEL.toggle());
    lockBtn.addEventListener('click', () => setLock(!locked));
    hideBtn.addEventListener('click', () => invoke('hide_main').catch(() => {}));

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
