/* Éditeur de personnage complet.
   IIFE ES5, aucune dépendance : le ped est rendu par le jeu derrière la NUI.
   Ce module construit les contrôles, garde un modèle d'apparence complet et
   envoie previewCharacter / createCharacter / saveAppearance via Lobby.send.
   Le catalogue (drawables, textures, overlays) vient du client Lua : la NUI ne
   devine jamais les maxima, qui dépendent des DLC installés. */
(function () {
  'use strict';

  var Lobby = window.Lobby;
  if (!Lobby || typeof Lobby.el !== 'function') return;

  var el = Lobby.el;
  var icon = Lobby.icon;

  var PREVIEW_DELAY = 120;
  var SUBMIT_TIMEOUT = 9000;
  var DEFAULT_SEED = 1337;
  var MAX_RENDERED_TATTOOS = 160;

  var PARENT_NAMES = [
    'Ava', 'Alex', 'Sam', 'Charlie', 'Dominique', 'Claude', 'Camille', 'Sacha',
    'Alix', 'Andréa', 'Élie', 'Noa', 'Maël', 'Lou', 'Eden', 'Célian',
    'Léa', 'Chloé', 'Manon', 'Sofia', 'Inès', 'Jade', 'Mila', 'Emma',
    'Lina', 'Zoé', 'Nora', 'Yasmine', 'Alice', 'Rose', 'Anna', 'Julie',
    'Clara', 'Sarah', 'Léna', 'Eva', 'Mia', 'Luna', 'Nour', 'Ambre',
    'Juliette', 'Charlotte', 'Maëlys', 'Élodie', 'Marion', 'Océane'
  ];
  var PARENT_COUNT = PARENT_NAMES.length;
  var EYE_COLORS = ['#2f6f6a', '#4f86a8', '#6b7f3a', '#8a5a2b', '#5a4636', '#1f2933'];
  var EYE_NAMES = ['Vert', 'Bleu', 'Noisette', 'Ambre', 'Marron', 'Noir'];

  var TAB_DEFS = [
    { id: 'identity', label: 'Identité', icon: 'spark' },
    { id: 'face', label: 'Visage', icon: 'users' },
    { id: 'hair', label: 'Cheveux', icon: 'spark' },
    { id: 'outfit', label: 'Tenue', icon: 'shield' },
    { id: 'props', label: 'Accessoires', icon: 'crown' },
    { id: 'tattoos', label: 'Tatouages', icon: 'target' }
  ];

  var ZONES = [
    { id: 'ZONE_HEAD', label: 'Tête' },
    { id: 'ZONE_TORSO', label: 'Torse' },
    { id: 'ZONE_LEFT_ARM', label: 'Bras gauche' },
    { id: 'ZONE_RIGHT_ARM', label: 'Bras droit' },
    { id: 'ZONE_LEFT_LEG', label: 'Jambe gauche' },
    { id: 'ZONE_RIGHT_LEG', label: 'Jambe droite' }
  ];
  var ZONE_BY_ID = {};
  for (var zi = 0; zi < ZONES.length; zi += 1) ZONE_BY_ID[ZONES[zi].id] = ZONES[zi];

  var COMPONENT_LABELS = {
    1: 'Masque',
    3: 'Veste / torse',
    4: 'Jambes',
    5: 'Sac',
    6: 'Chaussures',
    7: 'Accessoires',
    8: 'Sous-vêtement',
    9: 'Gilet pare-balles',
    10: 'Décalques',
    11: 'Chemise / haut'
  };
  var COMPONENT_IDS = [1, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  var PROP_LABELS = {
    0: 'Chapeau',
    1: 'Lunettes',
    2: 'Boucles d\'oreilles',
    6: 'Montre',
    7: 'Bracelet'
  };
  var PROP_IDS = [0, 1, 2, 6, 7];

  var OVERLAY_LABELS = {
    0: 'Imperfections',
    1: 'Barbe',
    2: 'Sourcils',
    3: 'Âge',
    4: 'Maquillage',
    5: 'Blush',
    6: 'Teint',
    7: 'Dommages du soleil',
    8: 'Rouge à lèvres',
    9: 'Taches de rousseur',
    10: 'Poitrine',
    11: 'Imperfections corporelles',
    12: 'Imperfections supplémentaires'
  };
  var OVERLAY_IDS = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  var OVERLAY_COLOR_TYPE = { 1: 1, 2: 1, 10: 1, 4: 2, 5: 2, 8: 2 };
  var OVERLAY_COLORIZED = { 1: true, 2: true, 4: true, 5: true, 8: true, 10: true };

  var FEATURE_LABELS = [
    'Nez — largeur', 'Nez — hauteur', 'Nez — longueur', 'Nez — courbure',
    'Nez — pointe', 'Nez — arête', 'Joues — largeur', 'Joues — hauteur',
    'Mâchoire — largeur', 'Mâchoire — forme', 'Menton — hauteur', 'Menton — largeur',
    'Sourcils — hauteur', 'Sourcils — profondeur', 'Yeux — ouverture',
    'Lèvres — épaisseur', 'Lèvres — largeur', 'Pommettes — hauteur',
    'Pommettes — largeur', 'Cou — largeur'
  ];

  var root = null;
  var built = false;
  var model = {
    mode: 'create',
    name: '',
    gender: 'male',
    seed: DEFAULT_SEED,
    skin: 0,
    appearance: null,
    activeTab: 'identity',
    tattooZone: 'ALL',
    tattooQuery: '',
    catalog: null,
    tattooData: null,
    tattooError: false,
    limits: { nameMin: 3, nameMax: 20, skins: 5, maxTattoos: 24, maxTattoosPerZone: 4 },
    submitting: false,
    dirty: false,
    nameTouched: false
  };

  var refs = {
    panel: null,
    title: null,
    eyebrow: null,
    subtitle: null,
    tabs: null,
    body: null,
    panes: {},
    nameInput: null,
    nameCount: null,
    nameError: null,
    genderRow: null,
    faceBody: null,
    hairBody: null,
    outfitBody: null,
    propsBody: null,
    tattooSearch: null,
    tattooZones: null,
    tattooCount: null,
    tattooList: null,
    submitButton: null,
    submitLabel: null,
    cancelButton: null,
    randomButton: null,
    resetButton: null,
    editBanner: null,
    angleButtons: []
  };

  var faceSync = [];
  var hairSync = [];
  var outfitSync = [];
  var propSync = [];
  var tattooZoneButtons = [];
  var genderButtons = [];
  var parentSync = { selects: [] };
  var previewTimer = null;
  var submitTimer = null;
  var previewSeq = 0;
  var syncSeq = 0;
  var pendingDefaults = false;
  var createHandled = false;
  var initialisedFromCreator = false;

  // ------------------------------------------------------------------ outils
  function $(selector, scope) {
    return (scope || document).querySelector(selector);
  }

  function clampNumber(value, minimum, maximum, fallback) {
    var n = Number(value);
    if (!isFinite(n)) n = fallback;
    if (n < minimum) n = minimum;
    if (n > maximum) n = maximum;
    return n;
  }

  function clampInt(value, minimum, maximum, fallback) {
    return Math.floor(clampNumber(value, minimum, maximum, fallback));
  }

  function clone(value) {
    if (!value || typeof value !== 'object') return value;
    var out = Array.isArray(value) ? [] : {};
    for (var key in value) {
      if (Object.prototype.hasOwnProperty.call(value, key)) out[key] = clone(value[key]);
    }
    return out;
  }

  function nameChars(value) {
    if (typeof Array.from === 'function') return Array.from(value);
    var m = String(value).match(/[\uD800-\uDBFF][\uDC00-\uDFFF]|[\s\S]/g);
    return m || [];
  }

  function normalizeName(value) {
    var out = String(value == null ? '' : value).replace(/[\u0000-\u001f\u007f]/g, '');
    out = out.replace(/\s+/g, ' ').trim();
    var chars = nameChars(out);
    if (chars.length > model.limits.nameMax) out = chars.slice(0, model.limits.nameMax).join('');
    return out;
  }

  function nameValid(value) {
    var length = nameChars(normalizeName(value)).length;
    return length >= model.limits.nameMin && length <= model.limits.nameMax;
  }

  function readLimits() {
    var fromState = (Lobby.state && Lobby.state.limits) || {};
    model.limits.nameMin = clampInt(fromState.nameMin, 1, 100, 3);
    model.limits.nameMax = clampInt(fromState.nameMax, model.limits.nameMin, 100, 20);
    model.limits.skins = clampInt(fromState.skins, 1, 20, 5);
    model.limits.maxTattoos = clampInt(fromState.maxTattoos, 1, 64, 24);
    model.limits.maxTattoosPerZone = clampInt(fromState.maxTattoosPerZone, 1, 12, 4);
  }

  function toast(message, level) {
    if (Lobby && typeof Lobby.toast === 'function') Lobby.toast(message, level);
  }

  // -------------------------------------------------------------- apparence
  function defaultAppearance() {
    var appearance = {
      head: {
        shapeFirst: 0,
        shapeSecond: 1,
        shapeMix: 0,
        skinFirst: 0,
        skinSecond: 1,
        skinMix: 0,
        thirdMix: 0
      },
      features: {},
      hair: { drawable: 0, texture: 0, color: 0, highlight: 0 },
      eyeColor: 0,
      overlays: {},
      components: {},
      props: {},
      tattoos: []
    };
    var i;
    for (i = 1; i <= 20; i += 1) appearance.features[i] = 0;
    for (i = 0; i < COMPONENT_IDS.length; i += 1) {
      appearance.components[COMPONENT_IDS[i]] = { drawable: 0, texture: 0 };
    }
    for (i = 0; i < PROP_IDS.length; i += 1) {
      appearance.props[PROP_IDS[i]] = { drawable: -1, texture: 0 };
    }
    for (i = 0; i < OVERLAY_IDS.length; i += 1) {
      appearance.overlays[OVERLAY_IDS[i]] = {
        index: 0, color: 0, highlight: 0, opacity: 1, colorType: 0
      };
    }
    return appearance;
  }

  // Les tables Lua sérialisées en JSON peuvent porter des clés numériques
  // (`"3"`) là où le modèle travaille avec des nombres. Sans cette lecture
  // tolérante, les vêtements, accessoires et overlays retombaient sur le
  // personnage par défaut à chaque réponse du client.
  function at(source, id) {
    if (!source || typeof source !== 'object') return undefined;
    if (source[id] !== undefined) return source[id];
    return source[String(id)];
  }

  function normalizeAppearance(raw) {
    var base = defaultAppearance();
    if (!raw || typeof raw !== 'object') return base;

    var head = raw.head && typeof raw.head === 'object' ? raw.head : {};
    base.head.shapeFirst = clampInt(head.shapeFirst, 0, 45, base.head.shapeFirst);
    base.head.shapeSecond = clampInt(head.shapeSecond, 0, 45, base.head.shapeSecond);
    base.head.shapeMix = clampNumber(head.shapeMix, 0, 1, base.head.shapeMix);
    base.head.skinFirst = clampInt(head.skinFirst, 0, 4, base.head.skinFirst);
    base.head.skinSecond = clampInt(head.skinSecond, 0, 4, base.head.skinSecond);
    base.head.skinMix = clampNumber(head.skinMix, 0, 1, base.head.skinMix);
    base.head.thirdMix = 0;

    var features = raw.features && typeof raw.features === 'object' ? raw.features : {};
    for (var i = 1; i <= 20; i += 1) {
      base.features[i] = Math.round(clampNumber(at(features, i), -1, 1, 0) * 1000) / 1000;
    }

    var hair = raw.hair && typeof raw.hair === 'object' ? raw.hair : {};
    base.hair.drawable = clampInt(hair.drawable, 0, 255, 0);
    base.hair.texture = clampInt(hair.texture, 0, 99, 0);
    base.hair.color = clampInt(hair.color, 0, 63, 0);
    base.hair.highlight = clampInt(hair.highlight, 0, 63, 0);
    base.eyeColor = clampInt(raw.eyeColor, 0, 5, 0);

    var overlays = raw.overlays && typeof raw.overlays === 'object' ? raw.overlays : {};
    for (i = 0; i < OVERLAY_IDS.length; i += 1) {
      var id = OVERLAY_IDS[i];
      var entry = at(overlays, id);
      if (entry && typeof entry === 'object') {
        base.overlays[id] = {
          index: clampInt(entry.index, 0, 99, 0),
          color: clampInt(entry.color, 0, 63, 0),
          highlight: clampInt(entry.highlight, 0, 63, 0),
          opacity: clampNumber(entry.opacity, 0, 1, 1),
          colorType: clampInt(entry.colorType, 0, 2, OVERLAY_COLOR_TYPE[id] || 0)
        };
      }
    }

    var components = raw.components && typeof raw.components === 'object' ? raw.components : {};
    for (i = 0; i < COMPONENT_IDS.length; i += 1) {
      var componentId = COMPONENT_IDS[i];
      var component = at(components, componentId);
      base.components[componentId] = {
        drawable: clampInt(component && component.drawable, 0, 999, 0),
        texture: clampInt(component && component.texture, 0, 99, 0)
      };
    }

    var props = raw.props && typeof raw.props === 'object' ? raw.props : {};
    for (i = 0; i < PROP_IDS.length; i += 1) {
      var propId = PROP_IDS[i];
      var prop = at(props, propId);
      var drawable = clampInt(prop && prop.drawable, -1, 999, -1);
      base.props[propId] = {
        drawable: drawable,
        texture: drawable >= 0 ? clampInt(prop && prop.texture, 0, 99, 0) : 0
      };
    }

    var tattoos = Array.isArray(raw.tattoos) ? raw.tattoos : [];
    var seen = {};
    var perZone = {};
    for (i = 0; i < tattoos.length; i += 1) {
      var tattoo = tattoos[i];
      if (!tattoo || typeof tattoo !== 'object') continue;
      var collection = String(tattoo.collection || '');
      var overlay = String(tattoo.overlay || '');
      var zone = String(tattoo.zone || '');
      if (!/^[A-Za-z0-9_]+$/.test(collection) || !/^[A-Za-z0-9_]+$/.test(overlay)) continue;
      if (!ZONE_BY_ID[zone]) continue;
      var key = collection + '|' + overlay;
      var zoneCount = perZone[zone] || 0;
      if (seen[key] || base.tattoos.length >= model.limits.maxTattoos) continue;
      if (zoneCount >= model.limits.maxTattoosPerZone) continue;
      seen[key] = true;
      perZone[zone] = zoneCount + 1;
      base.tattoos.push({ collection: collection, overlay: overlay, zone: zone });
    }

    return base;
  }

  function selectedTattoo(entry) {
    var appearance = model.appearance;
    if (!appearance || !appearance.tattoos) return false;
    var overlay = tattooOverlay(entry);
    if (!overlay) return false;
    for (var i = 0; i < appearance.tattoos.length; i += 1) {
      var item = appearance.tattoos[i];
      if (item.collection === entry[0] && item.overlay === overlay) return true;
    }
    return false;
  }

  function tattooOverlay(entry) {
    if (!entry) return '';
    return model.gender === 'female' ? (entry[2] || '') : (entry[1] || '');
  }

  // ------------------------------------------------------------- catalogue
  function componentInfo(id) {
    if (!model.catalog || !model.catalog.components) return { count: 1, textures: [1] };
    return model.catalog.components[String(id)] || { count: 1, textures: [1] };
  }

  function componentCount(id) {
    var info = componentInfo(id);
    return Math.max(1, Number(info.count) || 1);
  }

  function componentTextureCount(id, drawable) {
    var info = componentInfo(id);
    var textures = info.textures || [];
    return Math.max(1, Number(textures[drawable]) || 1);
  }

  function propInfo(id) {
    if (!model.catalog || !model.catalog.props) return { count: 1, textures: [1] };
    return model.catalog.props[String(id)] || { count: 1, textures: [1] };
  }

  function propCount(id) {
    return Math.max(1, Number(propInfo(id).count) || 1);
  }

  function propTextureCount(id, drawable) {
    var textures = propInfo(id).textures || [];
    return Math.max(1, Number(textures[drawable]) || 1);
  }

  function overlayCount(id) {
    if (!model.catalog || !model.catalog.overlays) return 1;
    return Math.max(1, Number(model.catalog.overlays[String(id)]) || 1);
  }

  function hairInfo() {
    return componentInfo(2);
  }

  function hairDrawableCount() {
    return componentCount(2);
  }

  function hairTextureCount(drawable) {
    return componentTextureCount(2, drawable);
  }

  // ------------------------------------------------------------- composants
  function section(title, hint) {
    var node = el('section', 'editor-section');
    var head = el('div', 'editor-section-head');
    head.appendChild(el('h2', 'editor-section-title', title));
    if (hint) head.appendChild(el('p', 'editor-section-hint', hint));
    node.appendChild(head);
    return node;
  }

  function makeStepper(label, getValue, setValue, getMin, getMax, format) {
    var row = el('div', 'editor-row');
    var head = el('div', 'editor-row-head');
    head.appendChild(el('span', 'editor-row-label', label));
    var out = el('span', 'editor-row-value', '');
    head.appendChild(out);
    row.appendChild(head);

    var controls = el('div', 'editor-stepper');
    var minus = el('button', 'editor-step', '−');
    minus.type = 'button';
    var plus = el('button', 'editor-step', '+');
    plus.type = 'button';
    controls.appendChild(minus);
    controls.appendChild(out === null ? el('span', '', '') : el('span', 'editor-step-readout', ''));
    var readout = controls.lastChild;
    controls.appendChild(plus);
    row.appendChild(controls);

    function render() {
      var value = getValue();
      var minimum = getMin();
      var maximum = getMax();
      var text = format ? format(value) : String(value);
      out.textContent = text;
      readout.textContent = text;
      minus.disabled = value <= minimum;
      plus.disabled = value >= maximum;
    }

    minus.addEventListener('click', function () {
      var value = getValue();
      if (value <= getMin()) return;
      setValue(value - 1);
      render();
      refreshControls();
      schedulePreview(false);
    });
    plus.addEventListener('click', function () {
      var value = getValue();
      if (value >= getMax()) return;
      setValue(value + 1);
      render();
      refreshControls();
      schedulePreview(false);
    });

    render();
    return { row: row, sync: render };
  }

  function updateSliderProgress(input) {
    var minimum = Number(input.min);
    var maximum = Number(input.max);
    var value = Number(input.value);
    var ratio = maximum > minimum ? (value - minimum) / (maximum - minimum) : 0;
    ratio = Math.max(0, Math.min(1, ratio));
    input.style.setProperty('--progress', (ratio * 100).toFixed(2) + '%');
  }

  function makeRange(label, getValue, setValue, getMin, getMax, step, format) {
    var row = el('div', 'editor-range');
    var head = el('div', 'editor-row-head');
    head.appendChild(el('span', 'editor-row-label', label));
    var out = el('span', 'editor-row-value', '');
    head.appendChild(out);
    row.appendChild(head);

    var input = document.createElement('input');
    input.type = 'range';
    input.className = 'editor-slider';
    input.min = String(getMin());
    input.max = String(getMax());
    input.step = String(step);
    input.value = String(getValue());
    updateSliderProgress(input);
    row.appendChild(input);

    function renderText() {
      var value = getValue();
      out.textContent = format ? format(value) : String(value);
    }

    input.addEventListener('input', function () {
      setValue(parseFloat(input.value));
      updateSliderProgress(input);
      renderText();
      schedulePreview(false);
    });

    renderText();
    return {
      row: row,
      sync: function () {
        input.min = String(getMin());
        input.max = String(getMax());
        input.value = String(getValue());
        updateSliderProgress(input);
        renderText();
      }
    };
  }

  function makeSwatches(label, getValue, setValue, colors, names) {
    var row = el('div', 'editor-swatches-row');
    var head = el('div', 'editor-row-head');
    head.appendChild(el('span', 'editor-row-label', label));
    var out = el('span', 'editor-row-value', '');
    head.appendChild(out);
    row.appendChild(head);

    var strip = el('div', 'editor-swatches');
    var buttons = [];
    for (var i = 0; i < colors.length; i += 1) {
      (function (index) {
        var button = el('button', 'editor-swatch');
        button.type = 'button';
        button.style.background = colors[index];
        button.setAttribute('aria-label', (names && names[index]) || ('Couleur ' + String(index + 1)));
        button.setAttribute('aria-pressed', 'false');
        button.addEventListener('click', function () {
          setValue(index);
          sync();
          schedulePreview(false);
        });
        strip.appendChild(button);
        buttons.push(button);
      }(i));
    }
    row.appendChild(strip);

    function sync() {
      var value = getValue();
      out.textContent = (names && names[value]) || ('#' + String(value));
      for (var i = 0; i < buttons.length; i += 1) {
        buttons[i].classList.toggle('is-selected', i === value);
        buttons[i].setAttribute('aria-pressed', i === value ? 'true' : 'false');
      }
    }

    sync();
    return { row: row, sync: sync };
  }

  // ------------------------------------------------------------------ onglets
  function buildTabs() {
    var nav = el('nav', 'editor-tabs');
    nav.setAttribute('role', 'tablist');
    nav.setAttribute('aria-label', 'Catégories de personnalisation');
    for (var i = 0; i < TAB_DEFS.length; i += 1) {
      (function (tab) {
        var button = el('button', 'editor-tab');
        button.type = 'button';
        button.setAttribute('role', 'tab');
        button.setAttribute('data-tab', tab.id);
        button.setAttribute('aria-selected', 'false');
        button.appendChild(icon(tab.icon, 'editor-tab-icon'));
        button.appendChild(el('span', 'editor-tab-label', tab.label));
        button.addEventListener('click', function () {
          model.activeTab = tab.id;
          renderTabs();
          renderPanes();
        });
        nav.appendChild(button);
      }(TAB_DEFS[i]));
    }
    refs.tabs = nav;
    return nav;
  }

  function renderTabs() {
    if (!refs.tabs) return;
    var buttons = refs.tabs.querySelectorAll('.editor-tab');
    for (var i = 0; i < buttons.length; i += 1) {
      var active = buttons[i].getAttribute('data-tab') === model.activeTab;
      buttons[i].classList.toggle('is-active', active);
      buttons[i].setAttribute('aria-selected', active ? 'true' : 'false');
    }
  }

  function renderPanes() {
    for (var id in refs.panes) {
      if (!Object.prototype.hasOwnProperty.call(refs.panes, id)) continue;
      refs.panes[id].classList.toggle('hidden', id !== model.activeTab);
    }
    if (model.activeTab === 'tattoos') renderTattooList();
  }

  // ------------------------------------------------------------------ identité
  function buildIdentity(pane) {
    var intro = el('p', 'editor-intro', 'Le nom et le genre sont figés après la création. Tout le reste se règle en direct.');
    pane.appendChild(intro);

    var nameSection = section('Identité', '3 à 20 caractères, accents acceptés.');
    var group = el('div', 'editor-field');
    var label = el('label', 'editor-label', 'Nom du personnage');
    label.setAttribute('for', 'creator-name');
    group.appendChild(label);
    var wrap = el('div', 'editor-input-wrap');
    var input = el('input', 'editor-input');
    input.id = 'creator-name';
    input.type = 'text';
    input.autocomplete = 'off';
    input.spellcheck = false;
    input.placeholder = 'Ex. Vex';
    input.setAttribute('aria-describedby', 'creator-name-hint creator-name-error');
    input.setAttribute('aria-invalid', 'false');
    wrap.appendChild(input);
    var count = el('span', 'editor-count', '0 / ' + String(model.limits.nameMax));
    count.setAttribute('aria-hidden', 'true');
    wrap.appendChild(count);
    group.appendChild(wrap);
    var hint = el('p', 'editor-hint', String(model.limits.nameMin) + ' à ' + String(model.limits.nameMax) + ' caractères.');
    hint.id = 'creator-name-hint';
    group.appendChild(hint);
    var error = el('p', 'editor-error', '');
    error.id = 'creator-name-error';
    error.setAttribute('aria-live', 'polite');
    group.appendChild(error);
    nameSection.appendChild(group);

    input.addEventListener('input', function () {
      var normalized = normalizeName(input.value);
      if (input.value !== normalized) input.value = normalized;
      model.name = normalized;
      model.nameTouched = true;
      model.dirty = true;
      refreshIdentity();
    });
    input.addEventListener('keydown', function (event) {
      if (event.key === 'Enter') {
        event.preventDefault();
        submit();
      }
    });

    refs.nameInput = input;
    refs.nameCount = count;
    refs.nameError = error;
    pane.appendChild(nameSection);

    var genderSection = section('Genre', 'Le modèle 3D change immédiatement.');
    var genderRow = el('div', 'editor-choice-row');
    var genderDefs = [
      { value: 'male', label: 'Homme', icon: 'male' },
      { value: 'female', label: 'Femme', icon: 'female' }
    ];
    for (var i = 0; i < genderDefs.length; i += 1) {
      (function (def) {
        var button = el('button', 'editor-choice');
        button.type = 'button';
        button.setAttribute('data-value', def.value);
        button.setAttribute('aria-pressed', 'false');
        button.appendChild(icon(def.icon, 'editor-choice-icon'));
        button.appendChild(el('span', 'editor-choice-label', def.label));
        button.addEventListener('click', function () {
          if (model.mode === 'edit' || model.submitting) return;
          if (model.gender === def.value) return;
          model.gender = def.value;
          model.appearance.tattoos = [];
          model.dirty = true;
          requestDefaults(true);
          refreshIdentity();
        });
        genderRow.appendChild(button);
        genderButtons.push(button);
      }(genderDefs[i]));
    }
    genderSection.appendChild(genderRow);
    refs.genderRow = genderRow;
    pane.appendChild(genderSection);
  }

  function refreshIdentity() {
    if (refs.nameInput) {
      if (document.activeElement !== refs.nameInput) refs.nameInput.value = model.name;
      refs.nameInput.disabled = model.mode === 'edit' || model.submitting;
      refs.nameInput.minLength = model.limits.nameMin;
    }
    var length = nameChars(model.name).length;
    if (refs.nameCount) refs.nameCount.textContent = String(length) + ' / ' + String(model.limits.nameMax);
    var message = '';
    if (length === 0) message = 'Nom requis (' + String(model.limits.nameMin) + '–' + String(model.limits.nameMax) + ' caractères).';
    else if (length < model.limits.nameMin) message = 'Trop court : ' + String(model.limits.nameMin) + ' caractères minimum.';
    else if (length > model.limits.nameMax) message = 'Trop long : ' + String(model.limits.nameMax) + ' caractères maximum.';
    if (!model.nameTouched && !model.submitting) message = '';
    if (refs.nameError) {
      refs.nameError.textContent = message;
      refs.nameError.classList.toggle('is-visible', !!message);
    }
    if (refs.nameInput) {
      refs.nameInput.setAttribute('aria-invalid', message ? 'true' : 'false');
      refs.nameInput.classList.toggle('is-invalid', !!message);
    }
    for (var i = 0; i < genderButtons.length; i += 1) {
      var active = genderButtons[i].getAttribute('data-value') === model.gender;
      genderButtons[i].classList.toggle('is-selected', active);
      genderButtons[i].setAttribute('aria-pressed', active ? 'true' : 'false');
      genderButtons[i].disabled = model.mode === 'edit' || model.submitting;
    }
    if (refs.submitButton) {
      refs.submitButton.disabled = model.submitting || (model.mode === 'create' && !nameValid(model.name));
    }
  }

  // ------------------------------------------------------------------- visage
  function parentTone(index) {
    return clampInt(index, 0, PARENT_COUNT - 1, 0) % 5;
  }

  function parentName(index) {
    return PARENT_NAMES[clampInt(index, 0, PARENT_COUNT - 1, 0)] || 'Visage';
  }

  function parentOptionLabel(index) {
    return parentName(index);
  }

  function buildParentPicker() {
    var wrap = el('div', 'editor-heritage');
    var grid = el('div', 'editor-parent-selects');

    for (var s = 0; s < 2; s += 1) {
      (function (slot) {
        var field = el('label', 'editor-parent-field');
        var label = el('span', 'editor-label', slot === 0 ? 'Parent A' : 'Parent B');
        label.setAttribute('for', 'creator-parent-' + String(slot));
        field.appendChild(label);

        var select = el('select', 'editor-select');
        select.id = 'creator-parent-' + String(slot);
        select.setAttribute('aria-label', slot === 0 ? 'Parent A' : 'Parent B');
        for (var i = 0; i < PARENT_COUNT; i += 1) {
          var option = document.createElement('option');
          option.value = String(i);
          option.textContent = parentOptionLabel(i);
          select.appendChild(option);
        }
        select.addEventListener('change', function () {
          var index = clampInt(select.value, 0, PARENT_COUNT - 1, 0);
          var head = model.appearance.head;
          if (slot === 0) {
            head.shapeFirst = index;
            head.skinFirst = parentTone(index);
          } else {
            head.shapeSecond = index;
            head.skinSecond = parentTone(index);
          }
          refreshParents();
          schedulePreview(false);
        });

        field.appendChild(select);
        grid.appendChild(field);
        parentSync.selects.push(select);
      }(s));
    }

    wrap.appendChild(grid);
    return wrap;
  }

  function refreshParents() {
    if (!model.appearance) return;
    var head = model.appearance.head;
    var values = [head.shapeFirst, head.shapeSecond];
    for (var s = 0; s < 2; s += 1) {
      var index = clampInt(values[s], 0, PARENT_COUNT - 1, 0);
      if (parentSync.selects[s]) {
        var next = String(index);
        if (parentSync.selects[s].value !== next) parentSync.selects[s].value = next;
      }
    }
  }

  function buildFace(pane) {
    while (pane.firstChild) pane.removeChild(pane.firstChild);
    faceSync = [];
    parentSync.selects = [];

    var heritage = section('Héritage', 'Deux visages de base déterminent les traits et la carnation. Choisis un parent dans chaque liste, puis règle la ressemblance.');
    heritage.appendChild(buildParentPicker());

    var resemblance = makeRange('Ressemblance', function () {
      return model.appearance.head.shapeMix;
    }, function (v) {
      model.appearance.head.shapeMix = clampNumber(v, 0, 1, 0);
    }, function () { return 0; }, function () { return 1; }, 0.01, function (v) { return Math.round(v * 100) + ' %'; });
    heritage.appendChild(resemblance.row);

    var tone = makeRange('Teint de peau', function () {
      return model.appearance.head.skinMix;
    }, function (v) {
      model.appearance.head.skinMix = clampNumber(v, 0, 1, 0);
    }, function () { return 0; }, function () { return 1; }, 0.01, function (v) { return Math.round(v * 100) + ' %'; });
    heritage.appendChild(tone.row);
    faceSync.push(resemblance, tone, { sync: refreshParents });
    pane.appendChild(heritage);

    var eyes = section('Yeux', 'Six teintes disponibles.');
    var eyeSwatches = makeSwatches('Couleur des yeux', function () { return model.appearance.eyeColor; }, function (v) {
      model.appearance.eyeColor = clampInt(v, 0, 5, 0);
    }, EYE_COLORS, EYE_NAMES);
    eyes.appendChild(eyeSwatches.row);
    faceSync.push(eyeSwatches);
    pane.appendChild(eyes);

    var traits = section('Traits', 'Vingt curseurs, de -100 à +100.');
    for (var i = 1; i <= 20; i += 1) {
      (function (index) {
        var range = makeRange(FEATURE_LABELS[index - 1], function () {
          return model.appearance.features[index];
        }, function (v) {
          model.appearance.features[index] = Math.round(clampNumber(v, -1, 1, 0) * 1000) / 1000;
        }, function () { return -1; }, function () { return 1; }, 0.01, function (v) {
          return (v > 0 ? '+' : '') + Math.round(v * 100);
        });
        traits.appendChild(range.row);
        faceSync.push(range);
      }(i));
    }
    pane.appendChild(traits);

    var details = section('Détails', 'Barbe, maquillage, marques : chaque couche se règle séparément.');
    for (var o = 0; o < OVERLAY_IDS.length; o += 1) {
      (function (id) {
        var entry = model.appearance.overlays[id];
        var row = el('div', 'editor-overlay');
        var head = el('div', 'editor-overlay-head');
        head.appendChild(el('span', 'editor-overlay-label', OVERLAY_LABELS[id]));
        var value = el('span', 'editor-overlay-value', '');
        head.appendChild(value);
        row.appendChild(head);

        var controls = el('div', 'editor-overlay-controls');
        var stepper = makeStepper(
          '',
          function () { return model.appearance.overlays[id].index; },
          function (v) {
            var entryNow = model.appearance.overlays[id];
            entryNow.index = clampInt(v, 0, Math.max(0, overlayCount(id) - 1), 0);
            entryNow.colorType = OVERLAY_COLOR_TYPE[id] || 0;
            if (entryNow.index > 0 && entryNow.opacity <= 0) entryNow.opacity = 0.5;
          },
          function () { return 0; },
          function () { return Math.max(0, overlayCount(id) - 1); },
          function (v) { return v === 0 ? 'Aucun' : ('N° ' + String(v)); }
        );
        controls.appendChild(stepper.row);
        row.appendChild(controls);

        var opacity = makeRange('Opacité', function () {
          return model.appearance.overlays[id].opacity;
        }, function (v) {
          model.appearance.overlays[id].opacity = clampNumber(v, 0, 1, 1);
        }, function () { return 0; }, function () { return 1; }, 0.05, function (v) {
          return Math.round(v * 100) + ' %';
        });
        opacity.row.classList.add('editor-overlay-opacity');
        row.appendChild(opacity.row);

        var colorRow = null;
        if (OVERLAY_COLORIZED[id]) {
          colorRow = makeRange('Couleur', function () {
            return model.appearance.overlays[id].color;
          }, function (v) {
            model.appearance.overlays[id].color = clampInt(v, 0, 63, 0);
          }, function () { return 0; }, function () { return 63; }, 1, function (v) {
            return '#' + String(v);
          });
          row.appendChild(colorRow.row);
        }

        function sync() {
          var now = model.appearance.overlays[id];
          value.textContent = now.index === 0 ? 'Aucun' : ('N° ' + String(now.index));
          row.classList.toggle('is-off', now.index === 0);
          stepper.sync();
          opacity.sync();
          if (colorRow) colorRow.sync();
        }
        sync();
        faceSync.push({ sync: sync });
        details.appendChild(row);
      }(OVERLAY_IDS[o]));
    }
    pane.appendChild(details);
  }

  // ------------------------------------------------------------------ cheveux
  function buildHair(pane) {
    while (pane.firstChild) pane.removeChild(pane.firstChild);
    hairSync = [];
    var maxDrawable = hairDrawableCount();
    if (model.appearance.hair.drawable >= maxDrawable) {
      model.appearance.hair.drawable = maxDrawable - 1;
      model.appearance.hair.texture = 0;
    }
    var maxTexture = hairTextureCount(model.appearance.hair.drawable);
    if (model.appearance.hair.texture >= maxTexture) model.appearance.hair.texture = 0;

    var hair = section('Cheveux', 'Coupe, texture, couleur et reflets.');
    var drawable = makeStepper('Coupe', function () {
      return model.appearance.hair.drawable;
    }, function (v) {
      model.appearance.hair.drawable = clampInt(v, 0, hairDrawableCount() - 1, 0);
      model.appearance.hair.texture = 0;
    }, function () { return 0; }, function () { return hairDrawableCount() - 1; }, function (v) {
      return 'N° ' + String(v);
    });
    hair.appendChild(drawable.row);

    var texture = makeStepper('Texture', function () {
      return model.appearance.hair.texture;
    }, function (v) {
      model.appearance.hair.texture = clampInt(v, 0, hairTextureCount(model.appearance.hair.drawable) - 1, 0);
    }, function () { return 0; }, function () { return hairTextureCount(model.appearance.hair.drawable) - 1; }, function (v) {
      return 'N° ' + String(v);
    });
    hair.appendChild(texture.row);

    var color = makeRange('Couleur', function () {
      return model.appearance.hair.color;
    }, function (v) {
      model.appearance.hair.color = clampInt(v, 0, 63, 0);
    }, function () { return 0; }, function () { return 63; }, 1, function (v) { return '#' + String(v); });
    hair.appendChild(color.row);

    var highlight = makeRange('Reflets', function () {
      return model.appearance.hair.highlight;
    }, function (v) {
      model.appearance.hair.highlight = clampInt(v, 0, 63, 0);
    }, function () { return 0; }, function () { return 63; }, 1, function (v) { return '#' + String(v); });
    hair.appendChild(highlight.row);
    pane.appendChild(hair);

    hairSync.push(drawable, texture, color, highlight);
  }

  // -------------------------------------------------------------------- tenue
  function buildOutfit(pane) {
    while (pane.firstChild) pane.removeChild(pane.firstChild);
    outfitSync = [];
    var outfit = section('Tenue', 'Chaque pièce est bornée aux variations installées sur le serveur.');
    for (var i = 0; i < COMPONENT_IDS.length; i += 1) {
      (function (id) {
        var row = el('div', 'editor-component');
        var head = el('div', 'editor-component-head');
        head.appendChild(el('span', 'editor-component-label', COMPONENT_LABELS[id] || ('Composant ' + String(id))));
        head.appendChild(el('span', 'editor-component-value', ''));
        row.appendChild(head);

        var drawable = makeStepper('Modèle', function () {
          return model.appearance.components[id].drawable;
        }, function (v) {
          var next = clampInt(v, 0, componentCount(id) - 1, 0);
          model.appearance.components[id].drawable = next;
          var maxTexture = componentTextureCount(id, next);
          if (model.appearance.components[id].texture >= maxTexture) {
            model.appearance.components[id].texture = 0;
          }
        }, function () { return 0; }, function () { return componentCount(id) - 1; }, function (v) {
          return 'N° ' + String(v);
        });
        row.appendChild(drawable.row);

        var texture = makeStepper('Texture', function () {
          return model.appearance.components[id].texture;
        }, function (v) {
          model.appearance.components[id].texture = clampInt(
            v, 0, componentTextureCount(id, model.appearance.components[id].drawable) - 1, 0
          );
        }, function () { return 0; }, function () {
          return componentTextureCount(id, model.appearance.components[id].drawable) - 1;
        }, function (v) { return 'N° ' + String(v); });
        row.appendChild(texture.row);
        outfit.appendChild(row);
        outfitSync.push(drawable, texture);
      }(COMPONENT_IDS[i]));
    }
    pane.appendChild(outfit);
  }

  // ------------------------------------------------------------- accessoires
  function buildProps(pane) {
    while (pane.firstChild) pane.removeChild(pane.firstChild);
    propSync = [];
    var props = section('Accessoires', 'Chapeau, lunettes, boucles, montre et bracelet.');
    for (var i = 0; i < PROP_IDS.length; i += 1) {
      (function (id) {
        var row = el('div', 'editor-component');
        var head = el('div', 'editor-component-head');
        head.appendChild(el('span', 'editor-component-label', PROP_LABELS[id] || ('Accessoire ' + String(id))));
        head.appendChild(el('span', 'editor-component-value', ''));
        row.appendChild(head);

        var drawable = makeStepper('Modèle', function () {
          return model.appearance.props[id].drawable;
        }, function (v) {
          var next = clampInt(v, -1, propCount(id) - 1, -1);
          model.appearance.props[id].drawable = next;
          if (next < 0) model.appearance.props[id].texture = 0;
        }, function () { return -1; }, function () { return propCount(id) - 1; }, function (v) {
          return v < 0 ? 'Aucun' : ('N° ' + String(v));
        });
        row.appendChild(drawable.row);

        var texture = makeStepper('Texture', function () {
          return model.appearance.props[id].texture;
        }, function (v) {
          model.appearance.props[id].texture = clampInt(
            v, 0, propTextureCount(id, model.appearance.props[id].drawable) - 1, 0
          );
        }, function () { return 0; }, function () {
          if (model.appearance.props[id].drawable < 0) return 0;
          return propTextureCount(id, model.appearance.props[id].drawable) - 1;
        }, function (v) { return 'N° ' + String(v); });
        row.appendChild(texture.row);
        props.appendChild(row);
        propSync.push(drawable, texture);
      }(PROP_IDS[i]));
    }
    pane.appendChild(props);
  }

  // ---------------------------------------------------------------- tatouages
  function buildTattoos(pane) {
    var intro = el('p', 'editor-intro', 'Tatouages vanilla : choisis par zone, dans la limite de ' +
      String(model.limits.maxTattoos) + ' au total et ' + String(model.limits.maxTattoosPerZone) + ' par zone.');
    pane.appendChild(intro);

    var tools = el('div', 'editor-tattoo-tools');
    var search = el('input', 'editor-input editor-tattoo-search');
    search.type = 'search';
    search.placeholder = 'Rechercher un tatouage…';
    search.setAttribute('aria-label', 'Rechercher un tatouage');
    search.value = model.tattooQuery;
    search.addEventListener('input', function () {
      model.tattooQuery = search.value;
      renderTattooList();
    });
    tools.appendChild(search);

    var zones = el('div', 'editor-tattoo-zones');
    var all = el('button', 'editor-zone is-active', 'Toutes');
    all.type = 'button';
    all.setAttribute('data-zone', 'ALL');
    all.addEventListener('click', function () {
      model.tattooZone = 'ALL';
      refreshTattooZones();
      renderTattooList();
    });
    zones.appendChild(all);
    tattooZoneButtons.push(all);
    for (var i = 0; i < ZONES.length; i += 1) {
      (function (zone) {
        var button = el('button', 'editor-zone', zone.label);
        button.type = 'button';
        button.setAttribute('data-zone', zone.id);
        button.addEventListener('click', function () {
          model.tattooZone = zone.id;
          refreshTattooZones();
          renderTattooList();
        });
        zones.appendChild(button);
        tattooZoneButtons.push(button);
      }(ZONES[i]));
    }
    tools.appendChild(zones);

    var count = el('p', 'editor-tattoo-count', '');
    tools.appendChild(count);
    pane.appendChild(tools);

    var list = el('div', 'editor-tattoo-list');
    pane.appendChild(list);

    refs.tattooSearch = search;
    refs.tattooZones = zones;
    refs.tattooCount = count;
    refs.tattooList = list;
    refreshTattooZones();
    renderTattooList();
  }

  function refreshTattooZones() {
    for (var i = 0; i < tattooZoneButtons.length; i += 1) {
      var active = tattooZoneButtons[i].getAttribute('data-zone') === model.tattooZone;
      tattooZoneButtons[i].classList.toggle('is-active', active);
      tattooZoneButtons[i].setAttribute('aria-pressed', active ? 'true' : 'false');
    }
  }

  function tattooSelectedCount() {
    return model.appearance.tattoos ? model.appearance.tattoos.length : 0;
  }

  function refreshTattooCount() {
    if (!refs.tattooCount) return;
    refs.tattooCount.textContent = String(tattooSelectedCount()) + ' / ' + String(model.limits.maxTattoos) + ' sélectionnés';
  }

  function renderTattooList() {
    var list = refs.tattooList;
    if (!list) return;
    refreshTattooCount();
    while (list.firstChild) list.removeChild(list.firstChild);

    if (!model.tattooData) {
      var message = el('p', 'editor-empty', model.tattooError
        ? 'Catalogue de tatouages indisponible.'
        : 'Chargement du catalogue de tatouages…');
      list.appendChild(message);
      return;
    }

    var data = model.tattooData.tattoos || [];
    var query = model.tattooQuery.trim().toLowerCase();
    var rendered = 0;
    var total = 0;
    for (var i = 0; i < data.length; i += 1) {
      var entry = data[i];
      var overlay = tattooOverlay(entry);
      if (!overlay) continue;
      if (model.tattooZone !== 'ALL' && entry[3] !== model.tattooZone) continue;
      if (query) {
        var haystack = (String(entry[4] || '') + ' ' + String(entry[0] || '')).toLowerCase();
        if (haystack.indexOf(query) === -1) continue;
      }
      total += 1;
      if (rendered >= MAX_RENDERED_TATTOOS) continue;
      rendered += 1;
      list.appendChild(makeTattooRow(entry));
    }

    if (total === 0) {
      list.appendChild(el('p', 'editor-empty', 'Aucun tatouage ne correspond à cette recherche.'));
    } else if (total > rendered) {
      list.appendChild(el('p', 'editor-hint', String(total - rendered) + ' autres résultats : affine la recherche.'));
    }
  }

  function makeTattooRow(entry) {
    var label = el('label', 'editor-tattoo');
    var checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.className = 'editor-tattoo-check';
    checkbox.checked = selectedTattoo(entry);
    checkbox.addEventListener('change', function () {
      var overlay = tattooOverlay(entry);
      if (!overlay) {
        checkbox.checked = false;
        return;
      }
      if (checkbox.checked) {
        var zone = entry[3];
        var perZone = 0;
        var exists = false;
        for (var i = 0; i < model.appearance.tattoos.length; i += 1) {
          var item = model.appearance.tattoos[i];
          if (item.zone === zone) perZone += 1;
          if (item.collection === entry[0] && item.overlay === overlay) exists = true;
        }
        if (exists) return;
        if (model.appearance.tattoos.length >= model.limits.maxTattoos) {
          checkbox.checked = false;
          toast('Maximum de ' + String(model.limits.maxTattoos) + ' tatouages atteint.', 'error');
          return;
        }
        if (perZone >= model.limits.maxTattoosPerZone) {
          checkbox.checked = false;
          toast('Maximum de ' + String(model.limits.maxTattoosPerZone) + ' tatouages pour cette zone.', 'error');
          return;
        }
        model.appearance.tattoos.push({
          collection: entry[0],
          overlay: overlay,
          zone: zone
        });
      } else {
        for (var j = model.appearance.tattoos.length - 1; j >= 0; j -= 1) {
          var current = model.appearance.tattoos[j];
          if (current.collection === entry[0] && current.overlay === overlay) {
            model.appearance.tattoos.splice(j, 1);
          }
        }
      }
      model.dirty = true;
      refreshTattooCount();
      schedulePreview(false);
    });

    var text = el('span', 'editor-tattoo-text');
    text.appendChild(el('strong', 'editor-tattoo-name', entry[4] || entry[0]));
    text.appendChild(el('span', 'editor-tattoo-meta', String(entry[0]) + ' · ' + String(entry[3])));
    label.appendChild(checkbox);
    label.appendChild(text);
    return label;
  }

  // ------------------------------------------------------------------- aperçu
  function schedulePreview(sync) {
    if (previewTimer) window.clearTimeout(previewTimer);
    if (sync) pendingDefaults = true;
    previewTimer = window.setTimeout(function () {
      previewTimer = null;
      sendPreview(pendingDefaults);
      pendingDefaults = false;
    }, PREVIEW_DELAY);
  }

  function requestDefaults(sync) {
    model.appearance.tattoos = [];
    pendingDefaults = true;
    schedulePreview(true);
    if (sync) refreshControls();
  }

  function sendPreview(forceDefaults) {
    var seq = ++previewSeq;
    if (forceDefaults) syncSeq = seq;
    var payload = {
      gender: model.gender,
      seed: model.seed,
      skin: model.skin,
      appearance: forceDefaults ? null : model.appearance
    };
    var result;
    try {
      result = Lobby.send('previewCharacter', payload);
    } catch (err) {
      toast('Aperçu indisponible : ' + (err && err.message ? err.message : 'erreur inconnue'), 'error');
      return;
    }
    if (!result || typeof result.then !== 'function') return;
    result.then(function (response) {
      if (!response || response.ok === false) {
        // Course au chargement : la page NUI peut envoyer son premier aperçu
        // avant que les callbacks Lua soient enregistrés. L'aperçu suivant
        // rétablit l'état ; inutile d'afficher une erreur de transport brute.
        if (response && response.error === 'callback_unreachable') return;
        toast(window.NUI.errorText(response && response.error, 'Impossible d\'afficher l\'aperçu.'), 'error');
        return;
      }
      if (!forceDefaults || seq !== syncSeq) return;
      syncSeq = 0;
      applyNormalized(response);
    });
  }

  function applyNormalized(response) {
    if (!response || typeof response !== 'object') return;
    if (response.gender === 'male' || response.gender === 'female') model.gender = response.gender;
    if (response.seed !== undefined) model.seed = clampInt(response.seed, 1, 2147483647, DEFAULT_SEED);
    if (response.skin !== undefined) model.skin = clampInt(response.skin, 0, 4, 0);
    if (response.appearance) model.appearance = normalizeAppearance(response.appearance);
    model.dirty = false;
    rebuildCatalogPanes();
    refreshAll();
  }

  // ------------------------------------------------------------------ boutons
  function buildActions() {
    var actions = el('footer', 'editor-actions');

    refs.randomButton = el('button', 'btn ghost editor-action', 'Aléatoire');
    refs.randomButton.type = 'button';
    refs.randomButton.appendChild(icon('repeat', 'editor-action-icon'));
    refs.randomButton.addEventListener('click', randomize);
    actions.appendChild(refs.randomButton);

    refs.resetButton = el('button', 'btn ghost editor-action', 'Réinitialiser');
    refs.resetButton.type = 'button';
    refs.resetButton.addEventListener('click', function () {
      requestDefaults(true);
      toast('Apparence réinitialisée sur le style de départ.', 'info');
    });
    actions.appendChild(refs.resetButton);

    refs.cancelButton = el('button', 'btn ghost editor-action', 'Annuler');
    refs.cancelButton.type = 'button';
    refs.cancelButton.classList.add('hidden');
    refs.cancelButton.addEventListener('click', cancelEdit);
    actions.appendChild(refs.cancelButton);

    refs.submitButton = el('button', 'btn primary editor-submit');
    refs.submitButton.type = 'button';
    refs.submitButton.appendChild(icon('check', 'editor-submit-icon'));
    refs.submitLabel = el('span', 'editor-submit-label', 'Créer mon personnage');
    refs.submitButton.appendChild(refs.submitLabel);
    refs.submitButton.addEventListener('click', submit);
    actions.appendChild(refs.submitButton);

    return actions;
  }

  function setSubmitting(active) {
    model.submitting = !!active;
    if (!active && submitTimer) {
      window.clearTimeout(submitTimer);
      submitTimer = null;
    }
    if (refs.submitButton) {
      refs.submitButton.disabled = model.submitting || (model.mode === 'create' && !nameValid(model.name));
      refs.submitButton.setAttribute('aria-busy', model.submitting ? 'true' : 'false');
    }
    if (refs.submitLabel) {
      refs.submitLabel.textContent = model.submitting
        ? (model.mode === 'edit' ? 'Enregistrement…' : 'Création…')
        : (model.mode === 'edit' ? 'Enregistrer l\'apparence' : 'Créer mon personnage');
    }
    refreshIdentity();
  }

  function randomSeed() {
    var seed = 0;
    try {
      if (window.crypto && typeof window.crypto.getRandomValues === 'function') {
        var bytes = new Uint32Array(1);
        window.crypto.getRandomValues(bytes);
        seed = bytes[0];
      }
    } catch (err) {
      seed = 0;
    }
    if (!seed) seed = Math.floor(Math.random() * 2147483647);
    return clampInt(seed, 1, 2147483647, DEFAULT_SEED);
  }

  function randomInt(minimum, maximum) {
    return minimum + Math.floor(Math.random() * (maximum - minimum + 1));
  }

  // Construit une apparence réellement aléatoire à partir du catalogue réel :
  // visage, traits, cheveux, overlays, vêtements et accessoires. On ne passe
  // plus par les défauts du seed, qui restent volontairement neutres pour
  // préserver le rendu des personnages v1.
  function randomAppearance() {
    var appearance = defaultAppearance();
    appearance.head.shapeFirst = randomInt(0, 45);
    appearance.head.shapeSecond = randomInt(0, 45);
    appearance.head.shapeMix = Math.round(Math.random() * 1000) / 1000;
    appearance.head.skinFirst = randomInt(0, 4);
    appearance.head.skinSecond = randomInt(0, 4);
    appearance.head.skinMix = Math.round(Math.random() * 1000) / 1000;

    var hairMax = hairDrawableCount() - 1;
    appearance.hair.drawable = randomInt(0, hairMax);
    appearance.hair.texture = randomInt(0, hairTextureCount(appearance.hair.drawable) - 1);
    appearance.hair.color = randomInt(0, 63);
    appearance.hair.highlight = randomInt(0, 63);
    appearance.eyeColor = randomInt(0, 5);

    for (var i = 1; i <= 20; i += 1) {
      appearance.features[i] = Math.round((Math.random() * 2 - 1) * 1000) / 1000;
    }

    for (i = 0; i < OVERLAY_IDS.length; i += 1) {
      var overlayId = OVERLAY_IDS[i];
      var maxIndex = overlayCount(overlayId) - 1;
      var forced = overlayId === 2;
      if (!forced && Math.random() > 0.45) continue;
      appearance.overlays[overlayId] = {
        index: maxIndex > 0 ? randomInt(1, maxIndex) : 0,
        color: randomInt(0, 63),
        highlight: randomInt(0, 63),
        opacity: forced ? 1 : Math.round((0.55 + Math.random() * 0.45) * 100) / 100,
        colorType: OVERLAY_COLOR_TYPE[overlayId] || 0
      };
    }
    if (model.gender === 'female') {
      appearance.overlays[1] = { index: 0, color: 0, highlight: 0, opacity: 1, colorType: 0 };
    }

    for (i = 0; i < COMPONENT_IDS.length; i += 1) {
      var componentId = COMPONENT_IDS[i];
      var drawable = randomInt(0, componentCount(componentId) - 1);
      // Le masque et le gilet restent souvent absents pour ne pas masquer le
      // visage ou la tenue ; les autres pièces sont toujours choisies.
      if ((componentId === 1 || componentId === 9) && Math.random() > 0.25) drawable = 0;
      appearance.components[componentId] = {
        drawable: drawable,
        texture: randomInt(0, componentTextureCount(componentId, drawable) - 1)
      };
    }

    for (i = 0; i < PROP_IDS.length; i += 1) {
      var propId = PROP_IDS[i];
      if (Math.random() > 0.35) {
        appearance.props[propId] = { drawable: -1, texture: 0 };
        continue;
      }
      var propDrawable = randomInt(0, propCount(propId) - 1);
      appearance.props[propId] = {
        drawable: propDrawable,
        texture: randomInt(0, propTextureCount(propId, propDrawable) - 1)
      };
    }

    appearance.tattoos = [];
    return appearance;
  }

  function randomize() {
    if (model.submitting) return;
    model.seed = randomSeed();
    model.skin = randomInt(0, 4);
    model.appearance = randomAppearance();
    model.dirty = true;
    schedulePreview(false);
    refreshAll();
    toast('Nouveau style généré.', 'info');
  }

  function submit() {
    if (model.submitting) return;
    if (model.mode === 'create') {
      if (!nameValid(model.name)) {
        model.nameTouched = true;
        refreshIdentity();
        if (refs.nameInput) refs.nameInput.focus();
        return;
      }
      createHandled = false;
      setSubmitting(true);
      if (submitTimer) window.clearTimeout(submitTimer);
      submitTimer = window.setTimeout(function () {
        if (!model.submitting) return;
        finishSubmit(false, 'La création prend trop de temps. Réessaie.');
      }, SUBMIT_TIMEOUT);
      var result;
      try {
        result = Lobby.send('createCharacter', {
          name: model.name,
          gender: model.gender,
          seed: model.seed,
          skin: model.skin,
          appearance: model.appearance
        });
      } catch (err) {
        finishSubmit(false, 'Création impossible : ' + (err && err.message ? err.message : 'erreur inconnue'));
        return;
      }
      if (!result || typeof result.then !== 'function') {
        finishSubmit(false, 'Création indisponible.');
        return;
      }
      result.then(function (response) {
        if (createHandled) return;
        if (response && response.ok === false) finishSubmit(false, window.NUI.errorText(response.error, 'Création refusée.'));
      });
      return;
    }

    setSubmitting(true);
    if (submitTimer) window.clearTimeout(submitTimer);
    submitTimer = window.setTimeout(function () {
      if (!model.submitting) return;
      finishSubmit(false, 'L\'enregistrement prend trop de temps. Réessaie.');
    }, SUBMIT_TIMEOUT);
    var save;
    try {
      save = Lobby.send('saveAppearance', {
        skin: model.skin,
        appearance: model.appearance
      });
    } catch (err) {
      finishSubmit(false, 'Enregistrement impossible : ' + (err && err.message ? err.message : 'erreur inconnue'));
      return;
    }
    if (!save || typeof save.then !== 'function') {
      finishSubmit(false, 'Enregistrement indisponible.');
      return;
    }
    save.then(function (response) {
      if (response && response.ok === false) finishSubmit(false, window.NUI.errorText(response.error, 'Enregistrement refusé.'));
    });
  }

  function finishSubmit(ok, message) {
    setSubmitting(false);
    if (!ok) {
      toast(message || 'Opération refusée.', 'error');
      if (refs.nameInput) refs.nameInput.focus();
    }
  }

  // --------------------------------------------------------------- état / édi.
  function readCharacter(character, mode) {
    character = character && typeof character === 'object' ? character : {};
    model.mode = mode === 'edit' ? 'edit' : 'create';
    model.name = normalizeName(character.name || '');
    model.gender = character.gender === 'female' ? 'female' : 'male';
    model.seed = clampInt(character.seed, 1, 2147483647, DEFAULT_SEED);
    model.skin = clampInt(character.skin, 0, 4, 0);
    model.appearance = normalizeAppearance(character.appearance);
    model.dirty = false;
    model.nameTouched = false;
    readLimits();
    initialisedFromCreator = true;
  }

  function applyCreator(data) {
    if (!data || typeof data !== 'object') return;
    readCharacter(data.character, data.mode);
    Lobby.setScreen('creator');
    renderMode();
    rebuildCatalogPanes();
    refreshAll();
  }

  function applyState(state) {
    if (!state) return;
    readLimits();
    if (model.mode === 'create' && !model.dirty && !initialisedFromCreator) {
      // Première ouverture sans message creator : le seed par défaut suffit.
      model.appearance = model.appearance || defaultAppearance();
    }
    refreshIdentity();
    if (refs.nameInput) refs.nameInput.minLength = model.limits.nameMin;
    if (refs.nameInput && model.mode === 'create' && !refs.nameInput.value && model.name) {
      refs.nameInput.value = model.name;
    }
  }

  function renderMode() {
    var editing = model.mode === 'edit';
    if (refs.title) refs.title.textContent = editing ? 'Modifie ton personnage' : 'Crée ton personnage';
    if (refs.eyebrow) refs.eyebrow.textContent = editing ? 'PERSONNAGE · APPARENCE' : 'PREMIÈRE CONNEXION';
    if (refs.subtitle) {
      refs.subtitle.textContent = editing
        ? 'Ajuste la coupe, la tenue et les tatouages. Le nom et le genre restent figés.'
        : 'Compose un visage, une coupe, une tenue et des tatouages. L\'aperçu se met à jour en direct.';
    }
    if (refs.editBanner) refs.editBanner.classList.toggle('hidden', !editing);
    if (refs.cancelButton) refs.cancelButton.classList.toggle('hidden', !editing);
    if (refs.submitLabel) {
      refs.submitLabel.textContent = editing ? 'Enregistrer l\'apparence' : 'Créer mon personnage';
    }
    if (refs.nameInput) refs.nameInput.disabled = editing || model.submitting;
    refreshIdentity();
  }

  function cancelEdit() {
    if (model.submitting) return;
    Lobby.send('cancelEdit', {});
    Lobby.releaseScreen();
    model.mode = 'create';
    model.dirty = false;
    renderMode();
  }

  function openEdit() {
    var state = Lobby.state;
    var character = state && state.me && state.me.character;
    if (!character) {
      toast('Crée d\'abord un personnage.', 'error');
      return;
    }
    readCharacter(character, 'edit');
    Lobby.setScreen('creator');
    renderMode();
    rebuildCatalogPanes();
    refreshAll();
    Lobby.send('editCharacter', {});
  }

  // ---------------------------------------------------------------- rendu
  function refreshControls() {
    if (!model.appearance) model.appearance = defaultAppearance();
    for (var i = 0; i < faceSync.length; i += 1) faceSync[i].sync();
    for (i = 0; i < hairSync.length; i += 1) hairSync[i].sync();
    for (i = 0; i < outfitSync.length; i += 1) outfitSync[i].sync();
    for (i = 0; i < propSync.length; i += 1) propSync[i].sync();
    refreshIdentity();
    refreshTattooCount();
  }

  function refreshAll() {
    if (!built) return;
    renderMode();
    refreshControls();
    renderPanes();
    if (model.activeTab === 'tattoos') renderTattooList();
    if (refs.submitButton) {
      refs.submitButton.disabled = model.submitting || (model.mode === 'create' && !nameValid(model.name));
    }
  }

  function rebuildCatalogPanes() {
    if (!built) return;
    if (refs.faceBody) buildFace(refs.faceBody);
    if (refs.hairBody) buildHair(refs.hairBody);
    if (refs.outfitBody) buildOutfit(refs.outfitBody);
    if (refs.propsBody) buildProps(refs.propsBody);
    if (refs.tattooList) renderTattooList();
  }

  // ------------------------------------------------------------------ shell
  function build() {
    if (built || !root) return;
    built = true;
    if (!model.appearance) model.appearance = defaultAppearance();

    var layout = el('div', 'creator-layout creator-layout-editor');

    var panel = el('section', 'creator-panel panel');
    panel.setAttribute('aria-label', 'Éditeur de personnage');
    refs.panel = panel;

    var brand = el('div', 'creator-brand');
    brand.appendChild(icon('logo', 'creator-brand-icon'));
    brand.appendChild(el('span', 'creator-brand-text', 'GUNFIGHT'));
    brand.appendChild(el('span', 'creator-brand-tag', 'ATELIER'));
    panel.appendChild(brand);

    var header = el('header', 'creator-header');
    refs.eyebrow = el('p', 'eyebrow creator-eyebrow', 'PREMIÈRE CONNEXION');
    header.appendChild(refs.eyebrow);
    refs.title = el('h1', 'creator-title', 'Crée ton personnage');
    refs.title.id = 'creator-title';
    header.appendChild(refs.title);
    refs.subtitle = el('p', 'creator-subtitle', 'Compose un visage, une coupe, une tenue et des tatouages.');
    header.appendChild(refs.subtitle);
    panel.appendChild(header);

    refs.editBanner = el('div', 'editor-banner hidden');
    refs.editBanner.appendChild(el('strong', '', 'MODE ÉDITION'));
    refs.editBanner.appendChild(el('span', '', ' Le nom et le genre sont figés.'));
    panel.appendChild(refs.editBanner);

    panel.appendChild(buildTabs());

    var body = el('div', 'editor-body');
    for (var i = 0; i < TAB_DEFS.length; i += 1) {
      var pane = el('section', 'editor-pane');
      pane.setAttribute('data-pane', TAB_DEFS[i].id);
      pane.setAttribute('role', 'tabpanel');
      pane.setAttribute('aria-label', TAB_DEFS[i].label);
      pane.classList.toggle('hidden', TAB_DEFS[i].id !== model.activeTab);
      body.appendChild(pane);
      refs.panes[TAB_DEFS[i].id] = pane;
    }
    refs.body = body;
    panel.appendChild(body);

    buildIdentity(refs.panes.identity);

    refs.faceBody = el('div', 'editor-stack');
    refs.panes.face.appendChild(refs.faceBody);
    buildFace(refs.faceBody);

    refs.hairBody = el('div', 'editor-stack');
    refs.panes.hair.appendChild(refs.hairBody);
    buildHair(refs.hairBody);

    refs.outfitBody = el('div', 'editor-stack');
    refs.panes.outfit.appendChild(refs.outfitBody);
    buildOutfit(refs.outfitBody);

    refs.propsBody = el('div', 'editor-stack');
    refs.panes.props.appendChild(refs.propsBody);
    buildProps(refs.propsBody);

    buildTattoos(refs.panes.tattoos);

    panel.appendChild(buildActions());
    panel.appendChild(el('p', 'creator-foot', 'Tout est enregistré à la validation. L\'aperçu local reste privé tant que tu n\'as pas validé.'));

    var stage = el('div', 'creator-stage');
    stage.setAttribute('aria-hidden', 'true');
    var badge = el('div', 'creator-stage-badge');
    badge.appendChild(el('span', 'creator-stage-dot'));
    badge.appendChild(el('span', '', 'APERÇU 3D'));
    stage.appendChild(badge);

    var angles = el('div', 'creator-stage-angles');
    var angleDefs = [
      { angle: -35, label: 'Profil G' },
      { angle: 0, label: 'Face' },
      { angle: 35, label: 'Profil D' },
      { angle: 180, label: 'Dos' }
    ];
    for (var a = 0; a < angleDefs.length; a += 1) {
      (function (def) {
        var button = el('button', 'creator-angle', def.label);
        button.type = 'button';
        button.addEventListener('click', function () {
          for (var k = 0; k < refs.angleButtons.length; k += 1) {
            refs.angleButtons[k].classList.toggle('is-active', refs.angleButtons[k] === button);
          }
          Lobby.send('previewAngle', { angle: def.angle });
        });
        if (def.angle === 0) button.classList.add('is-active');
        angles.appendChild(button);
        refs.angleButtons.push(button);
      }(angleDefs[a]));
    }
    stage.appendChild(angles);
    stage.appendChild(el('p', 'creator-stage-hint', 'Tourne le personnage pour vérifier le dos et les tatouages.'));

    layout.appendChild(panel);
    layout.appendChild(stage);
    root.replaceChildren(layout);

    // Le panneau est interactif, la scène reste traversable sauf ses boutons.
    panel.style.pointerEvents = 'auto';

    refreshAll();
  }

  // ---------------------------------------------------------------- messages
  function register() {
    Lobby.on('creatorCatalog', function (catalog) {
      if (!catalog || typeof catalog !== 'object') return;
      model.catalog = catalog;
      rebuildCatalogPanes();
      refreshAll();
    });
    Lobby.on('creator', function (data) {
      applyCreator(data);
    });
    Lobby.on('state', function (state) {
      applyState(state);
    });
    Lobby.on('appearanceResult', function (result) {
      if (result && result.ok) {
        finishSubmit(true);
        setSubmitting(false);
        model.mode = 'create';
        model.dirty = false;
        renderMode();
        Lobby.releaseScreen();
        toast('Apparence enregistrée.', 'success');
      } else {
        finishSubmit(false, window.NUI.errorText(result && result.error, 'Enregistrement refusé.'));
      }
    });
    Lobby.on('createResult', function (result) {
      if (result && result.ok) {
        createHandled = true;
        finishSubmit(true);
        setSubmitting(false);
        Lobby.releaseScreen();
      } else {
        finishSubmit(false, window.NUI.errorText(result && result.error, 'Création refusée.'));
      }
    });
  }

  function loadTattoos() {
    if (typeof window.fetch !== 'function') {
      model.tattooError = true;
      renderTattooList();
      return;
    }
    window.fetch('data/tattoos.json').then(function (response) {
      if (!response.ok) throw new Error('HTTP ' + response.status);
      return response.json();
    }).then(function (data) {
      if (!data || !Array.isArray(data.tattoos)) throw new Error('format');
      model.tattooData = data;
      model.tattooError = false;
      if (model.activeTab === 'tattoos') renderTattooList();
      refreshTattooCount();
    }).catch(function (err) {
      model.tattooError = true;
      renderTattooList();
      if (window.console && console.warn) console.warn('[gf_lobby] tatouages:', err);
    });
  }

  function init() {
    root = document.getElementById('creator-root');
    if (!root || !Lobby) return;
    readLimits();
    build();
    register();
    loadTattoos();
    if (Lobby.state) applyState(Lobby.state);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.Creator = {
    openEdit: openEdit,
    close: cancelEdit,
    get mode() { return model.mode; }
  };
})();
