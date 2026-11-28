// =============================================================================
//  gf_maps - interface de l'éditeur de maps
// =============================================================================
const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'gf_maps';
const $ = (s) => document.querySelector(s);

function post(name, data = {}) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).catch(() => {});
}

const STEPS = {
    redzone: [
        { title: 'Cercle de la zone', help: 'Clic gauche sur la carte pour placer le centre. Règle la taille avec le curseur, ou Maj + molette.' },
        { title: 'Points d\'apparition', help: 'Clic gauche pour ajouter un point où les joueurs apparaissent À PIED (en dehors du cercle, pas trop loin). Clic droit retire le dernier.' },
        { title: 'Points véhicule', help: 'Clic gauche pour ajouter un point où le joueur prend sa voiture (touche E), près des points d\'apparition. La voiture est automatiquement tournée vers la zone. Clic droit retire le dernier.' },
        { title: 'Nom de la map', help: 'Donne un nom à cette redzone puis enregistre.' },
    ],
    attack: [
        { title: 'Délimitation de la zone', help: 'Clic gauche pour poser les points du contour, dans l\'ordre. Clique sur le premier point (jaune) ou sur « Fermer la zone » pour la refermer. Clic droit retire le dernier point.' },
        { title: 'Départ des attaquants', help: 'Clic gauche pour placer le point d\'apparition des attaquants, en dehors de la zone.' },
        { title: 'Départ des défenseurs', help: 'Clic gauche pour placer le point d\'apparition des défenseurs, à l\'intérieur de la zone.' },
        { title: 'Nom de la map', help: 'Donne un nom à cette zone d\'attaque puis enregistre.' },
    ],
};

let state = { open: false, editing: false };
let maps = { redzone: [], attack: [] };
let tab = 'redzone';

// ------------------------------------------------------------------ Validation des étapes
function stepValid(s) {
    if (s.kind === 'redzone') {
        if (s.step === 1) return s.hasCenter;
        if (s.step === 2) return s.spawnCount > 0;
        if (s.step === 3) return s.garageCount > 0;
        return true;
    }
    if (s.step === 1) return s.closed;
    if (s.step === 2) return s.hasAttackSpawn;
    if (s.step === 3) return s.hasDefenseSpawn;
    return true;
}

function stepStatus(s) {
    if (s.kind === 'redzone') {
        if (s.step === 1) return s.hasCenter ? ['Centre placé ✔', 'good'] : ['Clique sur la carte pour placer le centre', ''];
        if (s.step === 2) return s.spawnCount > 0 ? [`${s.spawnCount} point(s) d'apparition ✔`, 'good'] : ['Aucun point d\'apparition', ''];
        if (s.step === 3) return s.garageCount > 0 ? [`${s.garageCount} point(s) véhicule ✔`, 'good'] : ['Aucun point véhicule', ''];
        return ['', ''];
    }
    if (s.step === 1) {
        if (s.closed) return [`Zone fermée (${s.pointCount} points) ✔`, 'good'];
        return [`${s.pointCount} point(s) — ${s.pointCount >= 3 ? 'ferme la zone pour continuer' : 'minimum 3'}`, ''];
    }
    if (s.step === 2) return s.hasAttackSpawn ? ['Départ des attaquants placé ✔', 'good'] : ['Pas encore placé', ''];
    if (s.step === 3) {
        if (!s.hasDefenseSpawn) return ['Pas encore placé', ''];
        if (s.defenseInside === false) return ['Attention : ce point est en dehors de la zone', 'warn'];
        return ['Départ des défenseurs placé ✔', 'good'];
    }
    return ['', ''];
}

// ------------------------------------------------------------------ Liste
function renderList() {
    document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.kind === tab));
    $('#btn-new').textContent = tab === 'redzone' ? '+ Nouvelle redzone' : '+ Nouvelle zone d\'attaque';

    const list = $('#map-list');
    list.replaceChildren();
    const items = maps[tab] || [];
    $('#list-empty').classList.toggle('hidden', items.length > 0);

    const active = items.filter(m => m.enabled !== false).length;
    $('#active-count').textContent = items.length
        ? `${active} / ${items.length} map(s) en jeu`
        : '';

    items.forEach(m => {
        const li = document.createElement('li');
        const on = m.enabled !== false;
        li.classList.toggle('off', !on);

        // Case à cocher : la map est-elle jouée ?
        const check = document.createElement('label');
        check.className = 'check';
        check.title = on ? 'En jeu (décocher pour la retirer)' : 'Retirée du jeu (cocher pour l\'ajouter)';
        const box = document.createElement('input');
        box.type = 'checkbox';
        box.checked = on;
        box.onchange = () => post('toggle', { kind: tab, id: m.id, enabled: box.checked });
        const mark = document.createElement('span');
        check.append(box, mark);

        const info = document.createElement('div');
        info.className = 'info';
        const name = document.createElement('div');
        name.className = 'name';
        name.textContent = m.name;
        const meta = document.createElement('div');
        meta.className = 'meta';
        meta.textContent = (tab === 'redzone'
            ? `Rayon ${Math.round(m.radius)} m · ${m.spawns.length} apparition(s) · ${(m.garages || []).length} véhicule(s)`
            : `${m.points.length} points`) + (on ? '' : ' · retirée');
        info.append(name, meta);

        const edit = document.createElement('button');
        edit.className = 'secondary';
        edit.textContent = 'Modifier';
        edit.onclick = () => { $('#name').dataset.touched = ''; post('startEdit', { kind: tab, id: m.id }); };

        const del = document.createElement('button');
        del.className = 'danger';
        del.textContent = 'Supprimer';
        del.onclick = () => {
            if (!del.classList.contains('confirm')) {
                del.classList.add('confirm');
                del.textContent = 'Confirmer ?';
                setTimeout(() => { del.classList.remove('confirm'); del.textContent = 'Supprimer'; }, 3000);
                return;
            }
            post('delete', { kind: tab, id: m.id });
        };

        li.append(check, info, edit, del);
        list.appendChild(li);
    });
}

// ------------------------------------------------------------------ Édition
function renderEdit(s) {
    const steps = STEPS[s.kind];
    const def = steps[s.step - 1];
    const last = s.step === steps.length;

    $('.edit-kind').textContent = (s.id ? 'Modification · ' : 'Création · ') + (s.kind === 'redzone' ? 'Redzone' : 'Attaque de zone');

    const ol = $('#steps');
    ol.replaceChildren();
    steps.forEach((_, i) => {
        const li = document.createElement('li');
        if (i + 1 < s.step) li.className = 'done';
        if (i + 1 === s.step) li.className = 'current';
        ol.appendChild(li);
    });

    $('#step-title').textContent = `${s.step}. ${def.title}`;
    $('#step-help').textContent = def.help;

    const showRadius = s.kind === 'redzone' && s.step === 1;
    $('#radius-box').classList.toggle('hidden', !showRadius);
    if (showRadius && document.activeElement !== $('#radius')) {
        $('#radius').value = Math.round(s.radius || 80);
        $('#radius-value').textContent = Math.round(s.radius || 80);
    }

    $('#btn-close-poly').classList.toggle('hidden', !(s.kind === 'attack' && s.step === 1 && !s.closed));
    $('#btn-close-poly').disabled = s.pointCount < 3;

    $('#name-box').classList.toggle('hidden', !last);
    if (last && document.activeElement !== $('#name') && !$('#name').dataset.touched) {
        $('#name').value = s.name || '';
    }

    const [text, cls] = stepStatus(s);
    const st = $('#step-status');
    st.textContent = text;
    st.className = 'status ' + cls;

    $('#btn-prev').disabled = s.step === 1;
    $('#btn-next').classList.toggle('hidden', last);
    $('#btn-next').disabled = !stepValid(s);
    $('#btn-save').classList.toggle('hidden', !last);

    // La carte ne capte la souris que sur les étapes où l'on place des points
    $('#canvas').classList.toggle('hidden', last);
}

function render() {
    $('#root').classList.toggle('hidden', !state.open);
    if (!state.open) return;
    $('#view-list').classList.toggle('hidden', state.editing);
    $('#view-edit').classList.toggle('hidden', !state.editing);
    if (!state.editing) $('#canvas').classList.add('hidden');
    if (state.editing) renderEdit(state); else renderList();
}

// ------------------------------------------------------------------ Toast
let toastTimer;
function toast(text, error) {
    const t = $('#toast');
    t.textContent = text;
    t.classList.toggle('error', !!error);
    t.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.add('hidden'), 3000);
}

// ------------------------------------------------------------------ Événements
document.querySelectorAll('.tab').forEach(t => t.addEventListener('click', () => { tab = t.dataset.kind; renderList(); }));
$('#btn-new').onclick = () => { $('#name').dataset.touched = ''; post('startEdit', { kind: tab }); };
$('#btn-close').onclick = () => post('close');
$('#btn-cancel').onclick = () => post('cancelEdit');
$('#btn-prev').onclick = () => post('step', { step: state.step - 1 });
$('#btn-next').onclick = () => post('step', { step: state.step + 1 });
$('#btn-close-poly').onclick = () => post('closePolygon');
$('#btn-save').onclick = () => {
    const name = $('#name').value.trim();
    if (!name) return toast('Donne un nom à la map', true);
    post('save', { name });
};

$('#radius').addEventListener('input', (e) => {
    $('#radius-value').textContent = e.target.value;
    post('radius', { value: Number(e.target.value) });
});

const nameInput = $('#name');
nameInput.addEventListener('focus', () => post('typing', { on: true }));
nameInput.addEventListener('blur', () => post('typing', { on: false }));
nameInput.addEventListener('input', () => { nameInput.dataset.touched = '1'; });
nameInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#btn-save').click(); });

// Angle de vue : boutons du panneau
document.querySelectorAll('[data-cam]').forEach(b => b.addEventListener('click', () => post('camera', { action: b.dataset.cam })));

// Angle de vue : molette maintenue + glisser. Les déplacements sont cumulés
// et envoyés au plus une fois par image (~16 ms), en pixels.
let orbit = null;
let orbitTimer = null;
function flushOrbit() {
    clearTimeout(orbitTimer);
    orbitTimer = null;
    if (!orbit || (orbit.dx === 0 && orbit.dy === 0)) return;
    post('camera', { dx: orbit.dx, dy: orbit.dy });
    orbit.dx = 0;
    orbit.dy = 0;
}
function stopOrbit() {
    if (!orbit) return;
    flushOrbit();
    orbit = null;
    canvas.classList.remove('orbiting');
}

// Souris sur la carte
const canvas = $('#canvas');
canvas.addEventListener('contextmenu', (e) => e.preventDefault());
canvas.addEventListener('auxclick', (e) => e.preventDefault());
canvas.addEventListener('mousedown', (e) => {
    if (e.button === 1) {
        e.preventDefault(); // pas de défilement automatique du navigateur
        orbit = { x: e.clientX, y: e.clientY, dx: 0, dy: 0 };
        canvas.classList.add('orbiting');
        return;
    }
    if (e.button !== 0 && e.button !== 2) return;
    post('click', { x: e.clientX / window.innerWidth, y: e.clientY / window.innerHeight, button: e.button });
});
window.addEventListener('mousemove', (e) => {
    if (!orbit) return;
    orbit.dx += e.clientX - orbit.x;
    orbit.dy += e.clientY - orbit.y;
    orbit.x = e.clientX;
    orbit.y = e.clientY;
    if (!orbitTimer) orbitTimer = setTimeout(flushOrbit, 16);
});
window.addEventListener('mouseup', (e) => { if (e.button === 1) stopOrbit(); });
window.addEventListener('blur', stopOrbit);
let lastHover = 0;
canvas.addEventListener('mousemove', (e) => {
    if (orbit) return;
    const now = performance.now();
    if (now - lastHover < 50) return;
    lastHover = now;
    post('hover', { x: e.clientX / window.innerWidth, y: e.clientY / window.innerHeight });
});
window.addEventListener('wheel', (e) => {
    if (!state.editing || e.target.closest('#panel')) return;
    post('wheel', { delta: e.deltaY, shift: e.shiftKey });
}, { passive: true });

window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && state.open && !state.editing) post('close');
});

window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.type === 'state') {
        const wasEditing = state.editing;
        state = msg.state;
        maps = msg.maps || maps;
        if (!state.editing && wasEditing) { nameInput.dataset.touched = ''; nameInput.blur(); stopOrbit(); }
        render();
    } else if (msg.type === 'toast') {
        toast(msg.text, msg.error);
    }
});
