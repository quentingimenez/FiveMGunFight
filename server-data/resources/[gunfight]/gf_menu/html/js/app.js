/* Menu pause : rendu du profil, panneaux du rail et protocole NUI.
   Toutes les valeurs viennent de l'état via textContent/createElement. */
(function () {
  'use strict';

  var DASH = '—';
  var SOON_KEYS = {
    crosshair: 1, shop: 1, crates: 1,
    battlepass: 1, contributor: 1, gameSettings: 1,
  };
  var MODE_LABELS = {
    lobby: 'DANS LE LOBBY',
    attack: 'ATTAQUE DE ZONE',
    redzone: 'REDZONE',
    autre: 'EN PARTIE',
  };

  var items = [];
  var current = 0;
  var state = null;
  var visible = false;
  var weaponScreen = null;
  var accessoryWeaponId = null;
  var accessoryPreviewRevision = 0;

  function $(id) {
    return document.getElementById(id);
  }

  function el(tag, className, textValue) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (textValue !== undefined && textValue !== null) node.textContent = String(textValue);
    return node;
  }

  function put(id, textValue) {
    var node = $(id);
    if (node) node.textContent = textValue;
  }

  function value(raw) {
    if (raw === null || raw === undefined || raw === '') return DASH;
    if (typeof raw === 'string') return raw;
    if (typeof raw === 'number' && Number.isFinite(raw)) return String(raw);
    return DASH;
  }

  function send(name, data) {
    try {
      if (!window.NUI || typeof window.NUI.post !== 'function') {
        return Promise.resolve({ ok: false });
      }
      var result = window.NUI.post(name, data || {});
      if (result && typeof result.catch === 'function') {
        return result.catch(function () {
          return { ok: false };
        });
      }
    } catch (err) {
      // file:// : aucun callback Lua, on continue sans rien afficher.
    }
    return Promise.resolve({ ok: false });
  }

  function renderProfile() {
    var me = state && state.me && typeof state.me === 'object' ? state.me : null;
    var stats = state && state.statsAvailable === true && state.stats ? state.stats : null;
    var name = value(me && me.name);
    var id = value(me && me.id);

    put('avatar', name === DASH ? DASH : name.charAt(0).toUpperCase());
    put('profile-name', name);
    put('profile-id', 'ID ' + id);
    put('stat-kd', stats ? value(stats.kd) : DASH);
    put('stat-wins', stats ? value(stats.wins) : DASH);
    put('stat-matches', stats ? value(stats.matches) : DASH);
    put('stat-session', stats ? value(stats.session) : DASH);
    put('stat-member', value(me && me.memberSince));

    var mode = value(me && me.modeLabel);
    if (mode === DASH && me && me.mode) mode = MODE_LABELS[me.mode] || DASH;
    put('mode-pill', mode);
  }

  function renderStatus() {
    var online = value(state && state.online);
    var max = value(state && state.maxPlayers);
    put('online-value', online + ' / ' + max + ' EN LIGNE');

    var badge = $('build-badge');
    if (!badge) return;
    var build = value(state && state.build);
    if (build === DASH) {
      badge.classList.add('hidden');
      badge.textContent = '';
    } else {
      badge.textContent = 'BUILD ' + build;
      badge.classList.remove('hidden');
    }
  }

  function basePanel(eyebrow, title) {
    var panel = el('div', 'stage-panel');
    panel.setAttribute('role', 'region');
    panel.setAttribute('aria-label', title);
    panel.appendChild(el('p', 'eyebrow', eyebrow));
    panel.appendChild(el('h2', 'stage-title', title));
    return panel;
  }

  function addText(panel, message) {
    panel.appendChild(el('p', 'stage-text', message));
  }

  function soonPanel(title) {
    var panel = basePanel('BIENTÔT', title);
    addText(panel, 'Cette section arrive dans une prochaine mise à jour.');
    return panel;
  }

  function weaponPanel(kind, data, photos) {
    var admin = kind === 'armory';
    var panel = basePanel(admin ? 'ADMINISTRATION' : 'ÉQUIPEMENT', admin ? 'ARMES' : 'CASIER');
    panel.classList.add('weapon-panel');
    addText(panel, admin ? 'Sélectionne une arme pour l’ajouter à ton casier.' : 'Choisis une arme pour chaque emplacement.');
    var weapons = admin ? data : data.weapons;
    var grid = el('div', 'weapon-grid');
    (Array.isArray(weapons) ? weapons : []).forEach(function (weapon) {
      var card = el('div', 'weapon-card');
      if (photos && photos[weapon.name]) {
        var image = el('img', 'weapon-photo');
        image.src = photos[weapon.name];
        image.alt = '';
        card.appendChild(image);
      } else {
        card.appendChild(el('div', 'weapon-placeholder', 'ARME'));
      }
      card.appendChild(el('strong', 'weapon-name', weapon.label));
      card.appendChild(el('span', 'weapon-category', weapon.category));
      var actions = el('div', 'weapon-actions');
      if (admin) {
        var give = el('button', 'btn', weapon.owned ? 'OBTENUE' : 'OBTENIR');
        give.type = 'button';
        give.disabled = weapon.owned;
        give.addEventListener('click', function () { send('giveWeapon', { id: weapon.id }); });
        actions.appendChild(give);
      } else {
        [1, 2].forEach(function (slot) {
          var selected = data['slot' + slot] === weapon.id;
          var equip = el('button', 'btn' + (selected ? ' is-equipped' : ''), selected ? 'ÉQUIPÉE ' + slot : 'EMPLACEMENT ' + slot);
          equip.type = 'button';
          equip.disabled = selected;
          equip.addEventListener('click', function () { send('equipWeapon', { id: weapon.id, slot: slot }); });
          actions.appendChild(equip);
        });
      }
      card.appendChild(actions);
      if (!admin && weapon.accessories && Object.keys(weapon.accessories).some(function (kind) {
        return !weapon.accessories[kind].hidden;
      })) {
        var customize = el('button', 'btn weapon-accessories', 'ACCESSOIRES');
        customize.type = 'button';
        customize.addEventListener('click', function () {
          accessoryWeaponId = weapon.id;
          accessoryPreviewRevision = 0;
          send('previewAccessories', { id: weapon.id, choices: weapon.selections || {} });
          showAccessories(data, photos);
        });
        card.appendChild(customize);
      }
      grid.appendChild(card);
    });
    panel.appendChild(grid);
    return panel;
  }

  function showWeapons(kind, data, photos) {
    var stage = $('stage');
    if (!stage || !visible) return;
    weaponScreen = kind;
    put('section-label', kind === 'armory' ? 'ARMES ADMIN' : 'CASIER');
    if (kind === 'locker' && accessoryWeaponId) {
      showAccessories(data, photos);
      return;
    }
    stage.replaceChildren(weaponPanel(kind, data, photos));
  }

  function accessoryLabel(kind, name, index) {
    if (kind === 'clip' && /^GF_[A-Z0-9_]+_CLIP_60$/.test(name)) return 'Chargeur 60 balles';
    if (kind === 'clip') return index === 0 ? 'Chargeur standard' : index === 1 ? 'Chargeur allongé' : 'Chargeur grande capacité';
    if (kind === 'sight' && name.indexOf('MACRO') >= 0) return 'Viseur compact';
    if (kind === 'sight' && name === 'SCARH_AIMPOINT') return 'Viseur Aimpoint';
    if (kind === 'sight' && name === 'SCARH_EOTECH') return 'Viseur EOTech';
    if (kind === 'sight' && (name === 'COMPONENT_AT_SCOPE_MAX' || name === 'GF_SCARH_SCOPE_TALL')) return 'Lunette de sniper';
    if (kind === 'sight' && name.indexOf('LARGE') >= 0) return 'Lunette longue portée';
    if (kind === 'sight' && name.indexOf('MEDIUM') >= 0) return 'Viseur moyen';
    return (kind === 'sight' ? 'Viseur' : kind === 'grip' ? 'Poignée' : kind === 'light' ? 'Lampe' : kind === 'laser' ? 'Laser' : 'Silencieux') + (index ? ' ' + (index + 1) : '');
  }

  function showAccessories(data, photos) {
    var stage = $('stage');
    var weapon = (data.weapons || []).find(function (item) { return item.id === accessoryWeaponId; });
    if (!weapon) { accessoryWeaponId = null; showWeapons('locker', data, photos); return; }
    var panel = basePanel('CASIER', 'ACCESSOIRES');
    panel.classList.add('weapon-panel');
    addText(panel, weapon.label);
    var status = el('p', 'stage-text', 'Choisis les accessoires pour les voir sur ton arme. Enregistre pour les conserver.');
    status.id = 'accessory-status';
    panel.appendChild(status);
    var selections = Object.assign({}, weapon.selections || {});
    var groups = weapon.accessories || {};
    var form = el('div', 'accessory-groups');
    Object.keys(groups).sort().forEach(function (kind) {
      var group = groups[kind];
      if (group.hidden) return;
      var label = el('label', 'accessory-group');
      label.appendChild(el('span', 'accessory-label', group.label));
      var select = el('select', 'accessory-select');
      if (kind !== 'clip') {
        var none = el('option', '', 'Aucun'); none.value = ''; select.appendChild(none);
      }
      (group.options || []).forEach(function (name, index) {
        var option = el('option', '', accessoryLabel(kind, name, index));
        option.value = name; select.appendChild(option);
      });
      select.value = Object.prototype.hasOwnProperty.call(selections, kind) ? selections[kind] : (group.default || '');
      select.addEventListener('change', function () {
        selections[kind] = select.value;
        put('accessory-status', 'Aperçu modifié. Enregistre pour conserver tes choix.');
        accessoryPreviewRevision += 1;
        send('updateAccessoryPreview', { id: weapon.id, choices: selections, revision: accessoryPreviewRevision });
      });
      label.appendChild(select); form.appendChild(label);
    });
    panel.appendChild(form);
    var actions = el('div', 'accessory-actions');
    var back = el('button', 'btn', 'RETOUR'); back.type = 'button';
    back.addEventListener('click', function () {
      send('closeAccessoryPreview', {});
      document.body.classList.remove('accessory-preview-active');
      accessoryWeaponId = null;
      showWeapons('locker', data, photos);
    });
    var save = el('button', 'btn is-equipped', 'ENREGISTRER'); save.type = 'button';
    save.addEventListener('click', function () { send('setAccessories', { id: weapon.id, choices: selections }); });
    actions.appendChild(back); actions.appendChild(save); panel.appendChild(actions);
    stage.replaceChildren(panel);
  }

  function rulesPanel() {
    var panel = basePanel('SERVEUR', 'RÈGLEMENT');
    var rules = state && Array.isArray(state.rules) ? state.rules : [];
    var list = el('ul', 'rules-list');
    for (var i = 0; i < rules.length; i += 1) {
      var rule = rules[i];
      if (!rule || typeof rule !== 'object') continue;
      var block = el('li', 'rule');
      block.appendChild(el('h3', 'rule-title', value(rule.title)));
      var lines = Array.isArray(rule.lines) ? rule.lines : [];
      for (var j = 0; j < lines.length; j += 1) {
        if (typeof lines[j] === 'string' && lines[j]) {
          block.appendChild(el('p', 'rule-line', lines[j]));
        }
      }
      list.appendChild(block);
    }
    if (!list.children.length) {
      addText(panel, 'Règlement indisponible pour le moment.');
    } else {
      panel.appendChild(list);
    }
    return panel;
  }

  function legacyCopy(url, done) {
    var input = document.createElement('textarea');
    input.value = url;
    input.setAttribute('readonly', '');
    input.style.position = 'fixed';
    input.style.opacity = '0';
    document.body.appendChild(input);
    var copied = false;
    try {
      input.select();
      copied = document.execCommand('copy');
    } catch (err) {
      copied = false;
    }
    document.body.removeChild(input);
    done(copied);
  }

  function copyLink(url, panel) {
    var status = panel.querySelector('.copy-status');
    if (!status) {
      status = el('p', 'copy-status');
      panel.appendChild(status);
    }
    function done(copied) {
      status.textContent = copied
        ? 'Lien copié.'
        : 'Copie impossible. Sélectionne le lien et copie-le manuellement.';
      status.classList.toggle('is-success', copied);
      status.classList.toggle('is-error', !copied);
    }
    if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
      navigator.clipboard.writeText(url).then(
        function () {
          done(true);
        },
        function () {
          legacyCopy(url, done);
        }
      );
      return;
    }
    legacyCopy(url, done);
  }

  function discordPanel() {
    var panel = basePanel('SERVEUR', 'DISCORD');
    var cfg = state && state.discord && typeof state.discord === 'object' ? state.discord : null;
    var url = cfg && typeof cfg.url === 'string' ? cfg.url.trim() : '';
    if (!url) {
      addText(panel, 'Aucun Discord configuré pour le moment.');
      return panel;
    }
    var link = el('p', 'discord-url', url);
    link.setAttribute('tabindex', '0');
    panel.appendChild(link);
    var actions = el('div', 'panel-actions');
    var button = el('button', 'btn', 'COPIER LE LIEN');
    button.type = 'button';
    button.addEventListener('click', function () {
      copyLink(url, panel);
    });
    actions.appendChild(button);
    panel.appendChild(actions);
    return panel;
  }

  function quitPanel() {
    var panel = basePanel('SERVEUR', 'QUITTER LE SERVEUR');
    addText(panel, 'Veux-tu vraiment quitter le serveur ? Cette action est définitive.');
    var actions = el('div', 'panel-actions');
    var confirm = el('button', 'btn btn-danger', 'QUITTER');
    confirm.type = 'button';
    confirm.addEventListener('click', function () {
      send('quit', {});
      hide();
    });
    var cancel = el('button', 'btn', 'ANNULER');
    cancel.type = 'button';
    cancel.addEventListener('click', resetStage);
    actions.appendChild(confirm);
    actions.appendChild(cancel);
    panel.appendChild(actions);
    return panel;
  }

  function resetStage() {
    var stage = $('stage');
    if (stage) stage.replaceChildren();
    put('section-label', 'MENU');
  }

  function setFocus(index, moveFocus) {
    if (!items.length) return;
    current = ((index % items.length) + items.length) % items.length;
    for (var i = 0; i < items.length; i += 1) {
      var on = i === current;
      items[i].classList.toggle('is-current', on);
      if (on) {
        items[i].setAttribute('aria-current', 'true');
      } else {
        items[i].removeAttribute('aria-current');
      }
    }
    if (moveFocus && items[current] && document.activeElement !== items[current]) focusCurrent();
  }

  function focusCurrent() {
    if (!items[current]) return;
    try {
      items[current].focus({ preventScroll: true });
    } catch (err) {
      items[current].focus();
    }
  }

  function activate(node) {
    if (accessoryWeaponId) {
      send('closeAccessoryPreview', {});
      document.body.classList.remove('accessory-preview-active');
    }
    var key = node.getAttribute('data-key');
    var child = node.querySelector('.rail-item-label');
    var label = child ? child.textContent : '';
    if (key === 'resume') {
      send('close', {});
      hide();
      return;
    }
    put('section-label', label);
    var stage = $('stage');
    if (!stage) return;
    stage.replaceChildren();
    var panel;
    accessoryWeaponId = null;
    weaponScreen = key === 'loadout' ? 'locker' : null;
    if (key === 'loadout') {
      panel = basePanel('ÉQUIPEMENT', 'CASIER');
      addText(panel, 'Chargement des armes…');
      send('locker', {});
    }
    else if (SOON_KEYS[key]) panel = soonPanel(label);
    else if (key === 'rules') panel = rulesPanel();
    else if (key === 'discord') panel = discordPanel();
    else if (key === 'quit') panel = quitPanel();
    else panel = soonPanel(label);
    stage.appendChild(panel);
  }

  function hide() {
    visible = false;
    document.body.classList.remove('accessory-preview-active');
    var menu = $('menu');
    if (menu) {
      menu.classList.add('hidden');
      menu.setAttribute('aria-hidden', 'true');
    }
    var veil = $('veil');
    if (veil) {
      veil.classList.add('hidden');
    }
    if (document.activeElement && typeof document.activeElement.blur === 'function') {
      document.activeElement.blur();
    }
    weaponScreen = null;
    accessoryWeaponId = null;
    resetStage();
    setFocus(0);
  }

  function show() {
    visible = true;
    var menu = $('menu');
    if (menu) {
      menu.classList.remove('hidden');
      menu.setAttribute('aria-hidden', 'false');
    }
    var veil = $('veil');
    if (veil) {
      veil.classList.remove('hidden');
    }
    renderProfile();
    renderStatus();
  }

  function onKeyDown(event) {
    if (!visible) return;
    var key = event.key;
    var stage = $('stage');
    if (stage && event.target && stage.contains(event.target) && event.target.tagName === 'SELECT'
        && (key === 'ArrowDown' || key === 'ArrowUp' || key === 'Enter' || key === ' ')) return;
    if (key === 'ArrowDown' || key === 'ArrowUp') {
      event.preventDefault();
      var delta = key === 'ArrowDown' ? 1 : -1;
      var next = window.GFMenuNav.nextIndex(items.length, current, delta);
      if (next >= 0) setFocus(next, true);
      return;
    }
    if (key === 'Escape') {
      event.preventDefault();
      send('close', {});
      hide();
      return;
    }
    if (key === 'Enter' || key === ' ' || key === 'Spacebar') {
      if (stage && event.target && stage.contains(event.target)) return;
      event.preventDefault();
      if (items[current]) activate(items[current]);
    }
  }

  function onMessage(event) {
    var message = event && event.data;
    if (!message || typeof message !== 'object' || typeof message.type !== 'string') return;
    var data = message.data && typeof message.data === 'object' ? message.data : {};
    if (message.type === 'accessoryPreviewReady' && visible && accessoryWeaponId) {
      document.body.classList.add('accessory-preview-active');
      return;
    }
    if (message.type === 'accessorySaved' && visible && accessoryWeaponId) {
      document.body.classList.remove('accessory-preview-active');
      accessoryWeaponId = null;
      send('close', {});
      hide();
      return;
    }
    if (message.type === 'armory' && visible) {
      showWeapons('armory', message.data || [], message.photos || {});
      return;
    }
    if (message.type === 'locker' && visible && weaponScreen === 'locker') {
      showWeapons('locker', data, message.photos || {});
      return;
    }
    if (message.type === 'state') {
      state = data;
      if (visible) {
        renderProfile();
        renderStatus();
      }
      return;
    }
    if (message.type === 'open') {
      show();
      resetStage();
      setFocus(0, true);
      return;
    }
    if (message.type === 'close') {
      hide();
    }
  }

  function boot() {
    items = Array.prototype.slice.call(document.querySelectorAll('#rail .rail-item'));
    for (var i = 0; i < items.length; i += 1) {
      (function (index, node) {
        node.addEventListener('mouseenter', function () {
          setFocus(index);
        });
        node.addEventListener('focus', function () {
          setFocus(index);
        });
        node.addEventListener('click', function () {
          setFocus(index);
          activate(node);
        });
      })(i, items[i]);
    }
    renderProfile();
    renderStatus();
    weaponScreen = null;
    resetStage();
    setFocus(0);
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('message', onMessage);
    send('ready', {});
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
