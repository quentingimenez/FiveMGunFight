// Menu de custom du véhicule de base (/customveh, admin).
// Chaque changement est envoyé au client Lua (« change ») qui l'applique à l'aperçu.

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'gf_vehicles';
const $ = (s, r = document) => r.querySelector(s);

// Teintes approximatives des couleurs GTA (pour les pastilles)
const GAME_HEX = {
    0: '#0d1116', 4: '#a5a9a7', 111: '#f0f0f0', 27: '#c00e1a', 38: '#f78616', 89: '#f5d711',
    92: '#98d223', 53: '#155c2d', 64: '#2354a1', 70: '#0b9cf1', 145: '#6b1fa5', 135: '#f21f99',
    158: '#c2944f', 120: '#c8c8c8',
};

let options = null;
let props = {};

function post(name, data = {}) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).then(r => r.json()).catch(() => ({}));
}

function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
}

function change(rebuild = false) {
    post('change', { props, rebuild }).then(res => {
        if (rebuild && res && res.mods) { options = res; render(); }
    });
}

const hex = c => c ? '#' + [c.r, c.g, c.b].map(v => v.toString(16).padStart(2, '0')).join('') : '#ffffff';
const rgb = h => ({ r: parseInt(h.slice(1, 3), 16), g: parseInt(h.slice(3, 5), 16), b: parseInt(h.slice(5, 7), 16) });

function field(label, child) {
    const f = el('div', 'field');
    f.appendChild(el('label', null, label));
    f.appendChild(child);
    return f;
}

// Choix dans une liste avec flèches gauche/droite. choices = [{ id, label }]
function stepper(choices, value, onPick) {
    const box = el('div', 'stepper');
    const prev = el('button', null, '‹');
    const val = el('div', 'value');
    const next = el('button', null, '›');
    let idx = Math.max(0, choices.findIndex(c => c.id === value));
    const show = () => { val.textContent = choices[idx] ? choices[idx].label : '-'; };
    const move = d => {
        idx = (idx + d + choices.length) % choices.length;
        show();
        onPick(choices[idx].id);
    };
    prev.onclick = () => move(-1);
    next.onclick = () => move(1);
    show();
    box.append(prev, val, next);
    return box;
}

const listOf = (labels, withDefault) => {
    const l = labels.map((label, id) => ({ id, label }));
    return withDefault ? [{ id: undefined, label: 'Origine' }].concat(l) : l;
};

function swatches(value, onPick) {
    const box = el('div', 'swatches');
    const all = [{ id: undefined, label: 'Origine' }].concat(options.gameColors);
    all.forEach(c => {
        const s = el('div', 'swatch' + (c.id === value ? ' on' : ''));
        s.title = c.label;
        s.style.background = c.id === undefined ? 'repeating-linear-gradient(45deg,#444 0 4px,#222 4px 8px)' : (GAME_HEX[c.id] || '#888');
        s.onclick = () => {
            box.querySelectorAll('.swatch').forEach(x => x.classList.remove('on'));
            s.classList.add('on');
            onPick(c.id);
        };
        box.appendChild(s);
    });
    return box;
}

function colorInput(value, onPick) {
    const row = el('div', 'row');
    const input = el('input');
    input.type = 'color';
    input.value = hex(value);
    input.oninput = () => onPick(rgb(input.value));
    row.appendChild(input);
    return row;
}

function toggle(text, checked, onPick) {
    const lab = el('label', 'toggle');
    const box = el('input');
    box.type = 'checkbox';
    box.checked = !!checked;
    box.onchange = () => onPick(box.checked);
    lab.append(box, el('span', null, text));
    return lab;
}

function set(key, value, rebuild) {
    if (value === undefined) delete props[key]; else props[key] = value;
    change(rebuild);
}

function setMod(type, id) {
    props.mods = props.mods || {};
    props.mods[String(type)] = id;
    change();
}

// Silhouette affichée tant que html/img/vehicles/<modèle>.png n'existe pas
const CAR_SVG = 'M3 13l2-5c.5-1.2 1.6-2 2.9-2h8.2c1.3 0 2.4.8 2.9 2l2 5h1a2 2 0 0 1 2 2v3h-2a3 3 0 0 1-6 0H10a3 3 0 0 1-6 0H2v-3a2 2 0 0 1 1-2zm4-1h12l-1.4-3.4c-.2-.4-.6-.6-1-.6H9.4c-.4 0-.8.2-1 .6z';
function vehiclePhoto(model) {
    const box = el('div', 'photo');
    const img = new Image();
    img.onerror = () => {
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('viewBox', '0 0 26 22');
        const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        p.setAttribute('d', CAR_SVG);
        svg.appendChild(p);
        box.replaceChildren(svg);
    };
    img.src = `img/vehicles/${encodeURIComponent(model)}.png`;
    box.appendChild(img);
    return box;
}

function selectVehicle(model) {
    if (model === options.model) return;
    post('selectVehicle', { model }).then(res => {
        if (!res || !res.options) return;
        options = res.options;
        props = res.props && typeof res.props === 'object' && !Array.isArray(res.props) ? res.props : {};
        if (Array.isArray(props.mods)) props.mods = {};
        render();
    });
}

function render() {
    const vehicle = $('section[data-tab=vehicle]');
    const grid = el('div', 'vehicles');
    (options.vehicles || []).forEach(v => {
        const card = el('div', 'vcard' + (v.model === options.model ? ' on' : ''));
        card.appendChild(vehiclePhoto(v.model));
        card.appendChild(el('div', 'name', v.label));
        if (v.model === options.base) card.appendChild(el('span', 'badge', 'ACTUEL'));
        card.onclick = () => selectVehicle(v.model);
        grid.appendChild(card);
    });
    vehicle.replaceChildren(grid);

    const paint = $('section[data-tab=paint]');
    paint.replaceChildren(
        field('Type de peinture', stepper(listOf(options.paintTypes, true), props.paintType, v => set('paintType', v))),
        field('Couleur principale', colorInput(props.primary, v => set('primary', v))),
        field('Couleur secondaire', colorInput(props.secondary, v => set('secondary', v))),
        field('Nacré', swatches(props.pearl, v => set('pearl', v))),
    );

    const parts = $('section[data-tab=parts]');
    parts.replaceChildren();
    if (!options.mods.length) parts.appendChild(el('div', 'empty', 'Ce véhicule n\'a pas de pièces modifiables.'));
    options.mods.forEach(m => {
        const cur = props.mods && props.mods[String(m.type)];
        parts.appendChild(field(m.label, stepper(m.choices, cur === undefined ? -1 : cur, v => setMod(m.type, v))));
    });

    const wheels = $('section[data-tab=wheels]');
    const curWheel = props.mods && props.mods['23'];
    wheels.replaceChildren(
        field('Type de jantes', stepper(listOf(options.wheelTypes, true), props.wheelType, v => {
            if (props.mods) delete props.mods['23'];
            set('wheelType', v, true);
        })),
        field('Modèle de jantes', stepper(options.wheels, curWheel === undefined ? -1 : curWheel, v => setMod(23, v))),
        field('Couleur des jantes', swatches(props.wheelColor, v => set('wheelColor', v))),
    );

    const lights = $('section[data-tab=lights]');
    lights.replaceChildren(
        toggle('Phares xénon', props.xenon, v => set('xenon', v || undefined)),
        field('Couleur des xénons', stepper(listOf(options.xenonColors, false), props.xenonColor ?? 0, v => set('xenonColor', v))),
        toggle('Néons', props.neon, v => set('neon', v || undefined)),
        field('Couleur des néons', colorInput(props.neonColor || { r: 168, g: 85, b: 247 }, v => set('neonColor', v))),
        field('Teinte des vitres', stepper(listOf(options.windowTints, true), props.windowTint, v => set('windowTint', v))),
    );

    const plate = $('section[data-tab=plate]');
    const text = el('input');
    text.type = 'text';
    text.maxLength = options.plateMax;
    text.value = props.plate || '';
    text.placeholder = 'GUNFIGHT';
    text.oninput = () => {
        text.value = text.value.toUpperCase().replace(/[^A-Z0-9 ]/g, '');
        set('plate', text.value.trim() || undefined);
    };
    plate.replaceChildren(
        field('Texte', text),
        field('Style', stepper(listOf(options.plateStyles, true), props.plateStyle, v => set('plateStyle', v))),
    );
}

// Onglets
document.querySelectorAll('.tabs button').forEach(b => {
    b.onclick = () => {
        document.querySelectorAll('.tabs button, .body section').forEach(x => x.classList.remove('on'));
        b.classList.add('on');
        $(`section[data-tab=${b.dataset.tab}]`).classList.add('on');
    };
});
document.querySelectorAll('[data-rot]').forEach(b => {
    b.onclick = () => post('rotate', { delta: Number(b.dataset.rot) });
});
$('.save').onclick = () => post('save');
$('.close').onclick = () => post('close');
$('.reset').onclick = () => post('reset').then(res => {
    props = {};
    if (res && res.options) options = res.options;
    render();
});
document.addEventListener('keydown', e => { if (e.key === 'Escape') post('close'); });

window.addEventListener('message', e => {
    const msg = e.data || {};
    if (msg.type === 'open') {
        options = msg.options;
        props = msg.props && typeof msg.props === 'object' && !Array.isArray(msg.props) ? JSON.parse(JSON.stringify(msg.props)) : {};
        if (Array.isArray(props.mods)) props.mods = {};
        render();
        $('#menu').classList.remove('hidden');
    } else if (msg.type === 'close') {
        $('#menu').classList.add('hidden');
    }
});
