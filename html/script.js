// rsg-prison countdown HUD. The server syncs the remaining seconds every ~10s; the page counts down locally in between.
(() => {
  const hud = document.getElementById('jail-hud');
  const time = document.getElementById('jh-time'), fill = document.getElementById('jh-fill'), sub = document.getElementById('jh-sub');
  let end = 0, total = 1, timer = null, subText = '', readyText = '';
  const fmt = (s) => { s = Math.max(0, Math.ceil(s)); const m = Math.floor(s / 60); return `${String(m).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`; };
  const tick = () => {
    const left = Math.max(0, (end - Date.now()) / 1000);
    time.textContent = fmt(left);
    fill.style.width = (100 - (left / total) * 100) + '%'; // fills up as the sentence is served
    sub.textContent = left <= 0 ? readyText : subText;    // waiting for the server to release
  };
  window.addEventListener('message', ({ data }) => {
    const m = data || {};
    if (m.action === 'jail:hud') {
      // keep the full sentence length across syncs: a sync without a total must not restart the bar
      const fresh = hud.classList.contains('hidden');
      total = Math.max(1, m.total || 0, m.left, fresh ? 0 : total);
      end = Date.now() + m.left * 1000;
      document.getElementById('jh-title').textContent = m.title || '';
      subText = m.sub || ''; readyText = m.ready || subText;
      hud.classList.remove('hidden'); tick();
      if (!timer) timer = setInterval(tick, 1000);
    } else if (m.action === 'jail:hide') {
      hud.classList.add('hidden'); clearInterval(timer); timer = null;
    }
  });
})();
