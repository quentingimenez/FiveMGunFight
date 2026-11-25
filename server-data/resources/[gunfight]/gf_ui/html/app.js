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

// ------------------------------------------------------------------ Sons (générés, pas de fichier)
const VOLUME = 0.35; // volume général des sons (0 à 1)
let audio = null;

function tone(freq, start, duration, type = 'sine', gain = 1, endFreq = null) {
    try {
        audio = audio || new (window.AudioContext || window.webkitAudioContext)();
        if (audio.state === 'suspended') audio.resume();
        const t0 = audio.currentTime + start;
        const osc = audio.createOscillator();
        const g = audio.createGain();
        osc.type = type;
        osc.frequency.setValueAtTime(freq, t0);
        if (endFreq) osc.frequency.exponentialRampToValueAtTime(endFreq, t0 + duration);
        g.gain.setValueAtTime(0.0001, t0);
        g.gain.exponentialRampToValueAtTime(VOLUME * gain, t0 + 0.005);
        g.gain.exponentialRampToValueAtTime(0.0001, t0 + duration);
        osc.connect(g).connect(audio.destination);
        osc.start(t0);
        osc.stop(t0 + duration + 0.02);
    } catch (e) { /* audio indisponible */ }
}

// Petit « tic » sec à chaque touche
function playHit() {
    tone(1800, 0, 0.045, 'square', 0.25);
    tone(3200, 0, 0.03, 'sine', 0.2);
}

// « Ding » de kill, plus aigu à chaque kill enchaîné
function playKill(count) {
    const k = Math.pow(1.122, Math.min(count, 8) - 1); // +1 ton par kill
    tone(660 * k, 0, 0.12, 'triangle', 0.8);
    tone(990 * k, 0.07, 0.22, 'sine', 0.7);
    if (count >= 2) tone(1320 * k, 0.14, 0.25, 'sine', 0.5);
}

// ------------------------------------------------------------------ Hitmarker & dégâts
function showHit(d) {
    const hm = $('#hitmarker');
    hm.classList.remove('show', 'kill');
    void hm.offsetWidth;
    if (d.fatal) hm.classList.add('kill');
    hm.classList.add('show');

    if (d.damage > 0) {
        const n = el('div', 'dmg' + (d.fatal ? ' fatal' : ''), d.damage);
        n.style.left = `${18 + Math.random() * 26}px`;
        n.style.top = `${-34 + Math.random() * 22}px`;
        $('#damage').appendChild(n);
        setTimeout(() => n.remove(), 850);
    }
    playHit();
}

// ------------------------------------------------------------------ Multi-kills
const MULTI = {
    2: { text: 'DOUBLÉ',     color: '#ffd84d' },
    3: { text: 'TRIPLÉ',     color: '#ffa23d' },
    4: { text: 'QUADRUPLÉ',  color: '#ff6b3d' },
    5: { text: 'QUINTUPLÉ',  color: '#ff3b5c' },
    6: { text: 'SEXTUPLÉ',   color: '#e23bff' },
};

let medalTimer = null;
function showKill(d) {
    const medal = $('#medal');
    const count = d.count || 1;
    const m = count >= 7 ? { text: `INARRÊTABLE ×${count}`, color: '#b13bff' } : MULTI[count];

    $('.m-title', medal).textContent = m ? m.text : 'ÉLIMINÉ';
    $('.m-title', medal).style.color = m ? m.color : '#ffffff';
    $('.m-title', medal).style.fontSize = m ? '' : '24px';
    $('.m-sub', medal).textContent = d.victim ? `✖ ${d.victim}` : '';

    medal.classList.remove('hidden', 'pop');
    void medal.offsetWidth;
    medal.classList.add('pop');
    clearTimeout(medalTimer);
    medalTimer = setTimeout(() => medal.classList.add('hidden'), m ? 2600 : 1600);

    const hm = $('#hitmarker');
    hm.classList.remove('show');
    void hm.offsetWidth;
    hm.classList.add('kill', 'show');
    playKill(count);
}

// ------------------------------------------------------------------ Messages du jeu
window.addEventListener('message', (event) => {
    const msg = event.data || {};
    switch (msg.type) {
        case 'hud': renderHud(msg.data); break;
        case 'killfeed': addKill(msg.data); break;
        case 'killfeed_clear': $('#killfeed').replaceChildren(); break;
        case 'hit': showHit(msg.data || {}); break;
        case 'kill': showKill(msg.data || {}); break;
        case 'announce': announce(msg.data); break;
        case 'scoreboard': renderScoreboard(msg.data); break;
        case 'scoreboard_visible': $('#scoreboard').classList.toggle('hidden', !msg.visible); break;
    }
});
