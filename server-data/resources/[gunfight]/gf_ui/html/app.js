// =============================================================================
//  gf_ui - page HTML affichée par-dessus le jeu
// =============================================================================
const TEAM_COLORS = { A: '#ff5a5f', B: '#4ea8ff' };
const KILLFEED_MAX = 6;
const KILLFEED_TIME = 6000;

const $ = (sel, root = document) => root.querySelector(sel);

// Le texte vient du serveur (noms des joueurs) : on l'insère toujours
// comme texte, jamais comme HTML, pour éviter toute injection.
function el(tag, className, text) {
    const e = document.createElement(tag);
    if (className) e.className = className;
    if (text !== undefined && text !== null) e.textContent = String(text);
    return e;
}

function formatTime(sec) {
    sec = Math.max(0, Math.floor(sec));
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
}

// ------------------------------------------------------------------ HUD
function renderSide(node, side) {
    if (!side) { node.classList.add('hidden'); return; }
    node.classList.remove('hidden');
    $('.side-label', node).textContent = side.label ?? '';
    $('.side-value', node).textContent = side.value ?? '';
    $('.side-sub', node).textContent = side.sub ?? '';
    node.style.borderTopColor = side.color || '#9aa4b6';
}

function renderHud(d) {
    const hud = $('#hud');
    if (!d) { hud.classList.add('hidden'); return; }
    hud.classList.remove('hidden');

    $('.title', hud).textContent = d.title ?? '';
    $('.subtitle', hud).textContent = d.subtitle ?? '';

    const timer = $('.timer', hud);
    if (typeof d.timer === 'number') {
        timer.textContent = formatTime(d.timer);
        timer.classList.toggle('low', d.timer <= 10);
        timer.classList.remove('hidden');
    } else {
        timer.classList.add('hidden');
    }

    const badge = $('.badge', hud);
    badge.textContent = d.badge?.text ?? '';
    badge.style.background = d.badge?.color || '#f1f4f9';

    renderSide($('.side.left', hud), d.left);
    renderSide($('.side.right', hud), d.right);
}

// ------------------------------------------------------------------ Kill feed
function addKill(e) {
    const feed = $('#killfeed');
    const row = el('div', 'kf' + (e.involvesMe ? ' mine' : ''));

    if (e.killer) {
        const k = el('span', 'name', e.killer);
        k.style.color = TEAM_COLORS[e.killerTeam] || '#f1f4f9';
        row.appendChild(k);
        row.appendChild(el('span', 'weapon', e.weaponLabel ? `[${e.weaponLabel}]` : '✖'));
    } else {
        row.appendChild(el('span', 'weapon', '☠'));
    }
    const v = el('span', 'name', e.victim);
    v.style.color = TEAM_COLORS[e.victimTeam] || '#f1f4f9';
    row.appendChild(v);

    feed.prepend(row);
    while (feed.children.length > KILLFEED_MAX) feed.lastChild.remove();

    setTimeout(() => row.classList.add('fade'), KILLFEED_TIME);
    setTimeout(() => row.remove(), KILLFEED_TIME + 500);
}

// ------------------------------------------------------------------ Annonces
let announceTimer = null;
function announce(d) {
    const box = $('#announce');
    $('.a-title', box).textContent = d.title ?? '';
    $('.a-sub', box).textContent = d.subtitle ?? '';
    // relance l'animation
    box.classList.add('hidden');
    void box.offsetWidth;
    box.classList.remove('hidden');
    clearTimeout(announceTimer);
    announceTimer = setTimeout(() => box.classList.add('hidden'), d.duration || 3000);
}

// ------------------------------------------------------------------ Classement
function renderScoreboard(d) {
    const sb = $('#scoreboard');
    const thead = $('thead', sb);
    const tbody = $('tbody', sb);
    thead.replaceChildren();
    tbody.replaceChildren();

    if (!d) {
        $('.sb-title', sb).textContent = 'Classement';
        $('.sb-empty', sb).classList.remove('hidden');
        return;
    }
    $('.sb-title', sb).textContent = d.title ?? 'Classement';
    $('.sb-empty', sb).classList.toggle('hidden', (d.rows || []).length > 0);

    const hr = el('tr');
    (d.columns || []).forEach(c => hr.appendChild(el('th', null, c)));
    thead.appendChild(hr);

    (d.rows || []).forEach(r => {
        const tr = el('tr');
        (r.cells || []).forEach(c => tr.appendChild(el('td', null, c)));
        if (r.color && tr.firstChild) tr.firstChild.style.borderLeftColor = r.color;
        tbody.appendChild(tr);
    });
}

// ------------------------------------------------------------------ Messages du jeu
window.addEventListener('message', (event) => {
    const msg = event.data || {};
    switch (msg.type) {
        case 'hud': renderHud(msg.data); break;
        case 'killfeed': addKill(msg.data); break;
        case 'announce': announce(msg.data); break;
        case 'scoreboard': renderScoreboard(msg.data); break;
        case 'scoreboard_visible': $('#scoreboard').classList.toggle('hidden', !msg.visible); break;
    }
});
