/* Écran de création de personnage.
   IIFE ES5, aucun module, aucune dépendance. Le ped est rendu par le jeu
   derrière la NUI : ce module ne construit que le formulaire et n'envoie que
   des callbacks previewCharacter / createCharacter via Lobby.send. */
(function () {
  'use strict';

  var SKIN_NAMES = [
    'Carnation claire',
    'Carnation hâlée',
    'Carnation dorée',
    'Carnation brune',
    'Carnation sombre'
  ];
  var SKIN_COLORS = ['#f0c9a8', '#dba177', '#b97a52', '#8a5638', '#5b3524'];
  var STYLE_LABELS = ['Tenue 1', 'Tenue 2', 'Tenue 3', 'Tenue 4'];
  var DEFAULT_SEED = 1337;
  var DEFAULT_SKIN = 0;
  var PREVIEW_DELAY = 120;

  var root = null;
  var built = false;
  var current = { name: '', gender: 'male', seed: DEFAULT_SEED, skin: DEFAULT_SKIN };
  var limits = { nameMin: 3, nameMax: 20, skins: 5 };
  var nameInput = null;
  var nameError = null;
  var nameCount = null;
  var submitButton = null;
  var submitLabel = null;
  var stepText = null;
  var genderButtons = [];
  var skinButtons = [];
  var styleButtons = [];
  var previewTimer = null;
  var submitTimer = null;
  var submitting = false;
  var dirty = false;
  var listenerRegistered = false;
  var initialPreviewSent = false;
  var hadCharacter = false;
  var createHandled = false;

  function $(selector, scope) {
    return (scope || document).querySelector(selector);
  }

  function el(tag, className, text) {
    return window.Lobby.el(tag, className, text);
  }

  function icon(name, className) {
    return window.Lobby.icon(name, className);
  }

  function clampInt(value, min, max, fallback) {
    var n = Number(value);
    if (!isFinite(n)) return fallback;
    n = Math.floor(n);
    if (n < min) return min;
    if (n > max) return max;
    return n;
  }

  function readLimits() {
    var fromState = (window.Lobby.state && window.Lobby.state.limits) || {};
    limits.nameMin = clampInt(fromState.nameMin, 1, 100, 3);
    limits.nameMax = clampInt(fromState.nameMax, limits.nameMin, 100, 20);
    limits.skins = clampInt(fromState.skins, 1, 20, 5);
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
    if (chars.length > limits.nameMax) out = chars.slice(0, limits.nameMax).join('');
    return out;
  }

  function nameValid(value) {
    var n = normalizeName(value);
    var length = nameChars(n).length;
    return length >= limits.nameMin && length <= limits.nameMax;
  }

  function updateNameUi() {
    if (!nameInput || !nameCount || !nameError || !submitButton) return;
    var value = normalizeName(nameInput.value);
    var length = nameChars(value).length;
    nameCount.textContent = String(length) + ' / ' + String(limits.nameMax);
    var message = '';
    if (length === 0) {
      message = 'Nom requis (' + String(limits.nameMin) + '–' + String(limits.nameMax) + ' caractères).';
    } else if (length < limits.nameMin) {
      message = 'Trop court : ' + String(limits.nameMin) + ' caractères minimum.';
    } else if (length > limits.nameMax) {
      message = 'Trop long : ' + String(limits.nameMax) + ' caractères maximum.';
    }
    var invalid = !!message;
    nameError.textContent = message;
    nameError.classList.toggle('is-visible', invalid);
    nameInput.setAttribute('aria-invalid', invalid ? 'true' : 'false');
    nameInput.classList.toggle('is-invalid', invalid);
    submitButton.disabled = !nameValid(value) || submitting;
  }

  function updateGenderUi() {
    for (var i = 0; i < genderButtons.length; i += 1) {
      var active = genderButtons[i].getAttribute('data-value') === current.gender;
      genderButtons[i].classList.toggle('is-selected', active);
      genderButtons[i].setAttribute('aria-pressed', active ? 'true' : 'false');
    }
  }

  function updateSkinUi() {
    for (var i = 0; i < skinButtons.length; i += 1) {
      var active = Number(skinButtons[i].getAttribute('data-value')) === current.skin;
      skinButtons[i].classList.toggle('is-selected', active);
      skinButtons[i].setAttribute('aria-pressed', active ? 'true' : 'false');
    }
  }

  function updateStyleUi() {
    for (var i = 0; i < styleButtons.length; i += 1) {
      var active = Number(styleButtons[i].getAttribute('data-value')) === current.seed;
      styleButtons[i].classList.toggle('is-selected', active);
      styleButtons[i].setAttribute('aria-pressed', active ? 'true' : 'false');
    }
  }

  function updateSteps() {
    if (!stepText) return;
    var score = 0;
    if (nameValid(nameInput ? nameInput.value : '')) score += 1;
    score += 1; // genre : toujours défini
    score += 1; // carnation : toujours définie
    score += 1; // style : toujours défini
    stepText.textContent = String(score) + ' / 4';
    if (root) root.setAttribute('data-progress', String(score));
  }

  function refreshUi() {
    updateNameUi();
    updateGenderUi();
    updateSkinUi();
    updateStyleUi();
    updateSteps();
  }

  function sendPreview() {
    if (previewTimer) {
      window.clearTimeout(previewTimer);
      previewTimer = null;
    }
    var payload = {
      gender: current.gender,
      seed: current.seed,
      skin: current.skin
    };
    var result;
    try {
      result = window.Lobby.send('previewCharacter', payload);
    } catch (err) {
      window.Lobby.toast("Aperçu indisponible : " + (err && err.message ? err.message : 'erreur inconnue'), 'error');
      return;
    }
    if (result && typeof result.then === 'function') {
      result.then(function (response) {
        if (response && response.ok === false) {
          window.Lobby.toast(response.error || "Impossible d'afficher l'aperçu.", 'error');
        }
      });
    }
  }

  function schedulePreview() {
    if (previewTimer) window.clearTimeout(previewTimer);
    previewTimer = window.setTimeout(function () {
      previewTimer = null;
      sendPreview();
    }, PREVIEW_DELAY);
  }

  function markDirty() {
    dirty = true;
  }

  function onGenderClick(event) {
    var value = event.currentTarget.getAttribute('data-value');
    if (value !== 'male' && value !== 'female') return;
    if (value === current.gender) return;
    current.gender = value;
    markDirty();
    updateGenderUi();
    schedulePreview();
  }

  function onSkinClick(event) {
    var value = clampInt(event.currentTarget.getAttribute('data-value'), 0, limits.skins - 1, 0);
    if (value === current.skin) return;
    current.skin = value;
    markDirty();
    updateSkinUi();
    schedulePreview();
  }

  function onStyleClick(event) {
    var value = clampInt(event.currentTarget.getAttribute('data-value'), 0, 2147483647, DEFAULT_SEED);
    if (value === current.seed) return;
    current.seed = value;
    markDirty();
    updateStyleUi();
    schedulePreview();
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

  function onRandomClick() {
    var next = randomSeed();
    while (next === current.seed) next = randomSeed();
    current.seed = next;
    markDirty();
    updateStyleUi();
    schedulePreview();
  }

  function onNameInput() {
    var raw = nameInput.value;
    var normalized = normalizeName(raw);
    if (raw !== normalized) nameInput.value = normalized;
    current.name = normalized;
    markDirty();
    updateNameUi();
    updateSteps();
  }

  function onNameKeydown(event) {
    if (event.key === 'Enter') {
      event.preventDefault();
      onSubmit();
    }
  }

  function setSubmitting(active) {
    submitting = !!active;
    if (!active && submitTimer) {
      clearTimeout(submitTimer);
      submitTimer = null;
    }
    if (!submitButton) return;
    submitButton.disabled = submitting || !nameValid(nameInput ? nameInput.value : '');
    submitButton.setAttribute('aria-busy', submitting ? 'true' : 'false');
    if (submitLabel) submitLabel.textContent = submitting ? 'Création…' : 'Entrer dans le lobby';
    var spinner = $('.creator-submit-spinner', submitButton);
    if (spinner) spinner.classList.toggle('hidden', !submitting);
  }

  function finishCreate(ok, errorMessage) {
    if (createHandled && !ok) return;
    createHandled = true;
    setSubmitting(false);
    if (!ok) {
      window.Lobby.toast(errorMessage || 'Création refusée.', 'error');
      if (nameInput) nameInput.focus();
    }
  }

  function onSubmit() {
    if (submitting || !nameInput || !nameValid(nameInput.value)) return;
    var name = normalizeName(nameInput.value);
    current.name = name;
    nameInput.value = name;
    setSubmitting(true);
    createHandled = false;
    if (submitTimer) clearTimeout(submitTimer);
    submitTimer = setTimeout(function () {
      if (!submitting) return;
      finishCreate(false, 'La création prend trop de temps. Réessaie.');
    }, 8000);
    var payload = {
      name: name,
      gender: current.gender,
      seed: current.seed,
      skin: current.skin
    };
    var result;
    try {
      result = window.Lobby.send('createCharacter', payload);
    } catch (err) {
      finishCreate(false, 'Création impossible : ' + (err && err.message ? err.message : 'erreur inconnue'));
      return;
    }
    if (!result || typeof result.then !== 'function') {
      finishCreate(false, 'Création indisponible.');
      return;
    }
    result.then(function (response) {
      if (createHandled) return;
      if (response && response.ok === false) {
        finishCreate(false, response.error || 'Création refusée.');
      }
      // Succès du callback = accusé de réception : le serveur envoie ensuite
      // createResult et un état avec me.character. On attend ces événements
      // pour libérer le bouton (timer de secours déjà en place).
    });
  }

  function makeFieldset(legendText) {
    var field = el('fieldset', 'creator-fieldset');
    var legend = el('legend', 'creator-legend', legendText);
    field.appendChild(legend);
    return field;
  }

  function buildNameField(form) {
    var group = el('div', 'creator-field');
    var label = el('label', 'creator-label', 'Nom du personnage');
    label.setAttribute('for', 'creator-name');
    group.appendChild(label);

    var wrap = el('div', 'creator-input-wrap');
    nameInput = el('input', 'creator-input');
    nameInput.id = 'creator-name';
    nameInput.type = 'text';
    /* Pas de maxLength natif : il compterait les unités UTF-16 et bloquerait
       les emoji (2 unités) avant limits.nameMax codets. normalizeName() /
       nameChars() tronquent et comptent en codets, comme utf8.len serveur. */
    nameInput.minLength = limits.nameMin;
    nameInput.autocomplete = 'off';
    nameInput.spellcheck = false;
    nameInput.placeholder = 'Ex. Vex';
    nameInput.setAttribute('aria-describedby', 'creator-name-hint creator-name-error');
    nameInput.setAttribute('aria-invalid', 'false');
    wrap.appendChild(nameInput);

    nameCount = el('span', 'creator-count', '0 / ' + String(limits.nameMax));
    nameCount.setAttribute('aria-hidden', 'true');
    wrap.appendChild(nameCount);
    group.appendChild(wrap);

    var hint = el('p', 'creator-hint', String(limits.nameMin) + ' à ' + String(limits.nameMax) + ' caractères, accents acceptés.');
    hint.id = 'creator-name-hint';
    group.appendChild(hint);

    nameError = el('p', 'creator-error', '');
    nameError.id = 'creator-name-error';
    nameError.setAttribute('aria-live', 'polite');
    group.appendChild(nameError);

    nameInput.addEventListener('input', onNameInput);
    nameInput.addEventListener('keydown', onNameKeydown);
    form.appendChild(group);
  }

  function buildGenderField(form) {
    var field = makeFieldset('Genre');
    var row = el('div', 'creator-choice-row creator-gender-row');

    var options = [
      { value: 'male', label: 'Homme' },
      { value: 'female', label: 'Femme' }
    ];
    for (var i = 0; i < options.length; i += 1) {
      var option = options[i];
      var button = el('button', 'creator-choice creator-choice-gender');
      button.type = 'button';
      button.setAttribute('data-value', option.value);
      button.setAttribute('aria-label', option.label);
      button.setAttribute('aria-pressed', 'false');
      button.appendChild(icon(option.value, 'creator-choice-icon'));
      button.appendChild(el('span', 'creator-choice-label', option.label));
      button.addEventListener('click', onGenderClick);
      row.appendChild(button);
      genderButtons.push(button);
    }
    field.appendChild(row);
    form.appendChild(field);
  }

  function buildSkinField(form) {
    var field = makeFieldset('Carnation');
    var row = el('div', 'creator-skin-row');
    for (var i = 0; i < limits.skins; i += 1) {
      var button = el('button', 'creator-swatch');
      button.type = 'button';
      button.setAttribute('data-value', String(i));
      var label = SKIN_NAMES[i] || ('Carnation ' + String(i + 1));
      button.setAttribute('aria-label', label);
      button.setAttribute('aria-pressed', 'false');
      var dot = el('span', 'creator-swatch-dot');
      dot.style.background = SKIN_COLORS[i] || '#8a5638';
      dot.setAttribute('aria-hidden', 'true');
      button.appendChild(dot);
      button.addEventListener('click', onSkinClick);
      row.appendChild(button);
      skinButtons.push(button);
    }
    field.appendChild(row);
    form.appendChild(field);
  }

  function buildStyleField(form) {
    var field = makeFieldset('Style');
    var row = el('div', 'creator-style-row');
    for (var i = 0; i < STYLE_LABELS.length; i += 1) {
      var button = el('button', 'creator-choice creator-choice-style');
      button.type = 'button';
      button.setAttribute('data-value', String(1000 + i * 997));
      button.setAttribute('aria-label', STYLE_LABELS[i]);
      button.setAttribute('aria-pressed', 'false');
      button.appendChild(el('span', 'creator-style-num', String(i + 1)));
      button.appendChild(el('span', 'creator-choice-label', STYLE_LABELS[i]));
      button.addEventListener('click', onStyleClick);
      row.appendChild(button);
      styleButtons.push(button);
    }
    field.appendChild(row);

    var random = el('button', 'creator-random');
    random.type = 'button';
    random.appendChild(icon('repeat', 'creator-random-icon'));
    random.appendChild(el('span', '', 'Aléatoire'));
    random.addEventListener('click', onRandomClick);
    field.appendChild(random);
    form.appendChild(field);
  }

  function build() {
    if (built || !root) return;
    built = true;

    var layout = el('div', 'creator-layout');

    var panel = el('section', 'creator-panel panel');
    panel.setAttribute('aria-label', 'Formulaire de création');

    var brand = el('div', 'creator-brand');
    brand.appendChild(icon('logo', 'creator-brand-icon'));
    brand.appendChild(el('span', 'creator-brand-text', 'GUNFIGHT'));
    brand.appendChild(el('span', 'creator-brand-tag', 'LOBBY'));
    panel.appendChild(brand);

    var header = el('header', 'creator-header');
    header.appendChild(el('p', 'eyebrow creator-eyebrow', 'PREMIÈRE CONNEXION'));
    var title = el('h1', 'creator-title', 'Crée ton personnage');
    title.id = 'creator-title';
    header.appendChild(title);
    header.appendChild(el('p', 'creator-subtitle', 'Donne-lui une identité. Ton apparence apparaît à l\'écran en temps réel.'));
    var steps = el('div', 'creator-steps');
    steps.appendChild(el('span', 'creator-steps-label', 'PROGRESSION'));
    stepText = el('span', 'creator-steps-value', '4 / 4');
    steps.appendChild(stepText);
    var track = el('span', 'creator-steps-track');
    track.setAttribute('aria-hidden', 'true');
    track.appendChild(el('span', 'creator-steps-fill'));
    steps.appendChild(track);
    header.appendChild(steps);
    panel.appendChild(header);

    var form = el('form', 'creator-form');
    form.setAttribute('aria-labelledby', 'creator-title');
    form.addEventListener('submit', function (event) {
      event.preventDefault();
      onSubmit();
    });
    buildNameField(form);
    buildGenderField(form);
    buildSkinField(form);
    buildStyleField(form);
    panel.appendChild(form);

    submitButton = el('button', 'btn primary creator-submit');
    submitButton.type = 'submit';
    submitLabel = el('span', 'creator-submit-label', 'Entrer dans le lobby');
    submitButton.appendChild(icon('arrow', 'creator-submit-arrow'));
    submitButton.appendChild(submitLabel);
    var spinner = el('span', 'spinner creator-submit-spinner hidden');
    spinner.setAttribute('aria-hidden', 'true');
    submitButton.appendChild(spinner);
    form.appendChild(submitButton);

    panel.appendChild(el('p', 'creator-foot', 'Les choix sont enregistrés à la validation. Aucune donnée n\'est partagée avant.'));

    var stage = el('div', 'creator-stage');
    stage.setAttribute('aria-hidden', 'true');
    var stageBadge = el('div', 'creator-stage-badge');
    stageBadge.appendChild(el('span', 'creator-stage-dot'));
    stageBadge.appendChild(el('span', '', 'APERÇU 3D'));
    stage.appendChild(stageBadge);
    var stageHint = el('p', 'creator-stage-hint', 'Ton personnage est affiché derrière cette interface.');
    stage.appendChild(stageHint);

    layout.appendChild(panel);
    layout.appendChild(stage);
    root.replaceChildren(layout);
    refreshUi();
  }

  function applyState(state) {
    if (!state) return;
    var character = state.me && state.me.character;
    if (character) {
      if (submitTimer) {
        clearTimeout(submitTimer);
        submitTimer = null;
      }
      createHandled = true;
      setSubmitting(false);
      dirty = false;
      hadCharacter = true;
      return; // app.js bascule déjà sur l'écran lobby
    }

    /* /resetchar : retour à la création, même si une requête était en vol. */
    if (submitting) {
      if (submitTimer) {
        clearTimeout(submitTimer);
        submitTimer = null;
      }
      createHandled = false;
      setSubmitting(false);
    }

    if (hadCharacter) {
      initialPreviewSent = false;
      dirty = false;
    }
    hadCharacter = false;

    readLimits();
    /* maxLength volontairement absent : troncature en codets par normalizeName. */
    nameInput.minLength = limits.nameMin;

    if (!dirty) {
      var seed = character && character.seed !== undefined ? character.seed : DEFAULT_SEED;
      var skin = character && character.skin !== undefined ? character.skin : DEFAULT_SKIN;
      var gender = character && (character.gender === 'male' || character.gender === 'female')
        ? character.gender
        : 'male';
      current.gender = gender;
      current.seed = clampInt(seed, 1, 2147483647, DEFAULT_SEED);
      current.skin = clampInt(skin, 0, limits.skins - 1, DEFAULT_SKIN);
      current.name = character && character.name ? normalizeName(character.name) : '';
      nameInput.value = current.name;
      refreshUi();
      if (!initialPreviewSent) {
        initialPreviewSent = true;
        sendPreview(); // aperçu immédiat, une seule fois
      }
    }
  }

  function registerState() {
    if (listenerRegistered) return;
    listenerRegistered = true;
    window.Lobby.on('state', function (state) {
      if (!root) return;
      applyState(state);
    });
    window.Lobby.on('createResult', function (result) {
      if (!root || !result || createHandled) return;
      if (result.ok === true) {
        finishCreate(true);
        return;
      }
      finishCreate(false, result.error || 'Création refusée.');
    });
    if (window.Lobby.state) applyState(window.Lobby.state);
  }

  function init() {
    root = document.getElementById('creator-root');
    if (!root || !window.Lobby) return;
    readLimits();
    build();
    registerState();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
