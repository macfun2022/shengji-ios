/* 升级 客户端 */
(function () {
  const G = window.Game;
  let ws = null;
  let me = { seat: null, code: null };
  let lastState = null;
  let kittySel = new Set();
  // 纯客户端：连接同一局域网内的主机（主机由电脑或装了 Node 的手机运行 server.js）
  const $ = (id) => document.getElementById(id);
  const show = (id) => $(id).classList.remove('hidden');
  const hide = (id) => $(id).classList.add('hidden');

  function toast(msg, ms) {
    const t = $('toast'); t.textContent = msg; t.classList.remove('hidden');
    clearTimeout(t._t); if (ms) t._t = setTimeout(() => t.classList.add('hidden'), ms);
  }
  function send(obj) { if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj)); }

  // 支持从原生 App 传入 ?host=&port=&name=（Android WebView / iOS WKWebView 注入）
  const qs = (function () {
    const o = {};
    (location.search || '').replace(/^\?/, '').split('&').forEach(function (kv) {
      if (!kv) return;
      const i = kv.indexOf('=');
      o[decodeURIComponent(kv.slice(0, i))] = decodeURIComponent(kv.slice(i + 1));
    });
    return o;
  })();
  let overrideHost = qs.host || '';
  let overridePort = qs.port || '';
  // 昵称优先级：URL 参数 > 本地记忆 > 空
  let savedName = '';
  try { savedName = localStorage.getItem('shengji_name') || ''; } catch (e) {}
  if (qs.name && $('name')) $('name').value = qs.name;
  else if (savedName && $('name')) $('name').value = savedName;
  if (overrideHost && $('host')) $('host').value = overrideHost;

  function wsUrl() {
    let host = $('host').value.trim() || overrideHost;
    const port = overridePort || location.port || '3000';
    if (!host) host = (location.hostname || 'localhost');
    return `ws://${host}:${port}`;
  }

  function connect() {
    const url = wsUrl();
    ws = new WebSocket(url);
    ws.onopen = () => {
      const name = $('name').value.trim() || '玩家';
      try { localStorage.setItem('shengji_name', name); } catch (e) {}
      if ($('code').value.trim()) {
        send({ type: 'join', code: $('code').value.trim().toUpperCase(), name });
      } else {
        send({ type: 'create', name, level: '2' });
      }
    };
    ws.onmessage = (e) => {
      const m = JSON.parse(e.data);
      if (m.type === 'state') { lastState = m.room; render(m.room); }
      else if (m.type === 'error') {
        $('conn-msg').textContent = m.msg;
        if (!$('screen-game').classList.contains('hidden')) toast(m.msg, 2500);
      }
      else if (m.type === 'created') { me.code = m.code; hide('screen-connect'); show('screen-game'); }
      else if (m.type === 'joined') { me.seat = m.seat; me.code = m.code; hide('screen-connect'); show('screen-game'); }
    };
    ws.onerror = () => {
      $('conn-msg').textContent = '连接失败：检查主机 IP 与 WiFi 是否同一局域网';
    };
    ws.onclose = () => { if ($('screen-game').classList.contains('hidden') === false) toast('与主机断开', 3000); };
  }

  $('btn-create').onclick = () => { $('code').value = ''; connect(); };
  $('btn-join').onclick = () => { if (!$('code').value.trim()) { $('conn-msg').textContent = '请填写房间码'; return; } connect(); };

  // 原生壳（Android/iOS WebView）注入了 host 参数：自动建房/进房，跳过手动表单。
  // 带 code 参数则加入指定房间；否则创建（服务端已有房间时会自动回落为加入）。
  if (overrideHost) {
    if (qs.code) $('code').value = qs.code;
    connect();
  }

  /* ----------------------------- 渲染 ----------------------------- */
  function isTrump(card) { return G.isTrump(card, lastState.trumpSuit, lastState.level); }

  function cardEl(card, opts) {
    opts = opts || {};
    const el = document.createElement('div');
    el.className = 'card' + (opts.small ? ' small' : '');
    if (card.isJoker) {
      el.classList.add('joker');
      el.innerHTML = `<div class="r">${card.joker === 'big' ? '大猫' : '小猫'}</div>`;
    } else {
      if (card.suit === '♥' || card.suit === '♦') el.classList.add('red');
      el.innerHTML = `<div class="r">${card.rank}</div><div class="s">${card.suit}</div>` +
        (card.point ? `<div class="pt">${card.point}</div>` : '');
    }
    if (isTrump(card)) el.classList.add('trump');
    el.dataset.id = card.id;
    return el;
  }

  function render(st) {
    $('room-info').textContent = '房间 ' + st.code + ' · 你是座位' + st.youSeat + (st.seats[st.youSeat]?.isDealer ? '(庄)' : '');
    $('level-info').textContent = '级数 ' + st.level + (st.trumpSuit ? ' · 主' + st.trumpSuit : ' · 未定主');

    // 座位
    const seats = $('seats'); seats.innerHTML = '';
    st.seats.forEach((s, i) => {
      if (!s) return;
      const d = document.createElement('div');
      d.className = 'seat' + (i === st.youSeat ? ' you' : '') + (s.isDealer ? ' dealer' : '') + (st.turnSeat === i ? ' turn' : '');
      d.innerHTML = `<div class="nm">${s.name}${i === st.youSeat ? '(你)' : ''}</div>` +
        `<div class="cnt">${s.online ? s.handCount + '张' : '<span class="off">离线</span>'}</div>`;
      seats.appendChild(d);
    });

    // 分数
    $('scores').innerHTML = `庄家方 <b>${st.teamPoints.dealer}</b> · 对家方 <b>${st.teamPoints.defender}</b> 分`;

    // 出牌区
    const trick = $('trick'); trick.innerHTML = '';
    const pos = {
      0: { left: '50%', bottom: '0', transform: 'translateX(-50%)' },
      1: { left: '0', top: '50%', transform: 'translateY(-50%)' },
      2: { left: '50%', top: '0', transform: 'translateX(-50%)' },
      3: { right: '0', top: '50%', transform: 'translateY(-50%)' },
    };
    st.trick.forEach((p) => {
      const wrap = document.createElement('div');
      wrap.style.position = 'absolute';
      Object.assign(wrap.style, pos[p.seat] || {});
      wrap.appendChild(cardEl(p.card, { small: true }));
      trick.appendChild(wrap);
    });

    // 手牌
    renderHand(st);

    // 面板
    hide('bid-panel'); hide('kitty-panel');
    if (st.phase === 'bidding') renderBid(st);
    else if (st.phase === 'kitty' && st.youSeat === st.dealerSeat) renderKitty(st);
    else if (st.phase === 'result') renderResult(st);
  }

  function sortHand(hand) {
    return hand.slice().sort((a, b) => {
      const ta = isTrump(a) ? 0 : 1, tb = isTrump(b) ? 0 : 1;
      if (ta !== tb) return ta - tb; // 主在前
      if (ta === 0) return G.trumpOrder(b, lastState.trumpSuit, lastState.level) - G.trumpOrder(a, lastState.trumpSuit, lastState.level);
      const sa = G.SUITS.indexOf(a.suit), sb = G.SUITS.indexOf(b.suit);
      if (sa !== sb) return sa - sb;
      return G.RANK_VALUE[b.rank] - G.RANK_VALUE[a.rank];
    });
  }

  function renderHand(st) {
    const hand = $('hand'); hand.innerHTML = '';
    const myTurn = st.turnSeat === st.youSeat && st.phase === 'playing';
    sortHand(st.hand).forEach((card) => {
      const el = cardEl(card);
      const legal = myTurn && G.isLegalPlay(st.hand, st.trick, card, st.trumpSuit, st.level);
      if (!myTurn) el.classList.add('disabled');
      else if (legal) el.classList.add('legal', 'playable');
      else el.classList.add('disabled');
      el.onclick = () => {
        if (!myTurn) { toast('还没轮到你', 1200); return; }
        if (!legal) { toast('必须跟出相同花色（无该花色才能出主/贴副）', 2000); return; }
        send({ type: 'play', cardId: card.id });
      };
      hand.appendChild(el);
    });
  }

  /* 亮主 */
  function renderBid(st) {
    show('bid-panel');
    const box = $('bid-cards'); box.innerHTML = '';
    const lvlCards = st.hand.filter(c => c.rank === st.level && !c.isJoker);
    if (lvlCards.length) {
      lvlCards.forEach((c) => {
        const el = cardEl(c);
        el.classList.add('playable');
        el.onclick = () => send({ type: 'bid', cards: [c.id] });
        box.appendChild(el);
      });
      $('bid-status').textContent = '点你的级数牌即可亮主（单张定主花色，可抢亮）。';
    } else {
      $('bid-status').textContent = '你手里没有当前级数牌，只能“不亮”。';
    }
    const bids = st.bids.map(b => `座位${b.seat}(${b.count}张)`).join('、') || '暂无';
    $('bid-status').textContent += ` 当前亮主：${bids}`;
  }
  $('btn-pass').onclick = () => send({ type: 'pass' });
  $('btn-bidend').onclick = () => send({ type: 'bidEnd' });

  /* 抠底 */
  function renderKitty(st) {
    show('kitty-panel');
    kittySel = new Set();
    const box = $('kitty-cards'); box.innerHTML = '';
    const combined = st.hand.concat(st.kittyVisible || []);
    combined.forEach((c) => {
      const el = cardEl(c);
      el.classList.add('playable');
      el.onclick = () => {
        if (kittySel.has(c.id)) kittySel.delete(c.id); else kittySel.add(c.id);
        el.classList.toggle('legal', kittySel.has(c.id));
        updateKittyBtn(st);
      };
      box.appendChild(el);
    });
    updateKittyBtn(st);
  }
  function updateKittyBtn(st) {
    const sel = [...kittySel];
    const hasScore = sel.some(id => {
      const all = st.hand.concat(st.kittyVisible || []);
      const c = all.find(x => x.id === id);
      return c && c.point > 0;
    });
    const btn = $('btn-kitty');
    btn.disabled = !(sel.length === 6 && !hasScore);
    $('kitty-status').textContent = sel.length === 6 && hasScore ? '底牌含分牌，不可确认' : `已选 ${sel.length}/6`;
  }
  $('btn-kitty').onclick = () => {
    if (!$('btn-kitty').disabled) send({ type: 'setKitty', discardIds: [...kittySel] });
  };

  /* 结算 */
  function renderResult(st) {
    const old = $('result-overlay'); if (old) old.remove();
    const oc = st.lastOutcome;
    let html = `<div style="position:absolute;inset:0;background:rgba(0,0,0,.78);display:flex;align-items:center;justify-content:center;z-index:30">
      <div style="background:var(--panel);padding:22px;border-radius:16px;text-align:center;max-width:320px">
        <h2 style="color:var(--gold);margin:0 0 10px">本局结束</h2>
        <p>对家吃 <b>${oc.defenderPoints}</b> 分，庄家方吃 <b>${oc.dealerPoints}</b> 分</p>
        <p style="font-size:18px">${oc.note}</p>
        <p>级数 <b>${oc.fromLevel}</b> → <b>${oc.toLevel}</b></p>`;
    if (st.youSeat === st.dealerSeat) {
      html += `<button class="primary" id="btn-next" style="margin-top:12px">开始下一局</button>`;
    } else {
      html += `<p style="color:var(--muted);font-size:13px">等待庄家开始下一局…</p>`;
    }
    html += `</div></div>`;
    const ov = document.createElement('div');
    ov.id = 'result-overlay'; ov.innerHTML = html;
    document.body.appendChild(ov);
    if (st.youSeat === st.dealerSeat) {
      $('btn-next').onclick = () => { ov.remove(); send({ type: 'next' }); };
    }
  }
  // 清除旧 overlay（状态变化且非 result 时）
  const _render = render;
  render = function (st) {
    const old = $('result-overlay');
    if (old && st.phase !== 'result') old.remove();
    _render(st);
  };
})();
