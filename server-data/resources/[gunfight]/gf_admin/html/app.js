(function () {
  'use strict';

  var FALLBACK_RESOURCE = 'gf_admin';
  var FEEDBACK_MS = 600;

  function byId(id) {
    return document.getElementById(id);
  }

  function safeString(value) {
    if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
      return String(value);
    }
    return '';
  }

  function idKey(value) {
    var text = safeString(value);
    return text === '' ? null : text;
  }

  function initials(value) {
    var parts = safeString(value).trim().split(/\s+/);
    var result = '';
    var taken = 0;
    for (var i = 0; i < parts.length && taken < 2; i += 1) {
      if (parts[i].length === 0) { continue; }
      result += parts[i].charAt(0);
      taken += 1;
    }
    return result.toUpperCase() || '?';
  }

  function modeLabel(value) {
    var mode = safeString(value).toLowerCase();
    if (mode === 'lobby') { return 'Lobby'; }
    if (mode === 'attack') { return 'Attaque'; }
    if (mode === 'redzone') { return 'Redzone'; }
    return '\u2014';
  }

  function teamLabel(value) {
    var team = safeString(value).toLowerCase();
    if (team === 'a') { return '\u00c9quipe A'; }
    if (team === 'b') { return '\u00c9quipe B'; }
    return '\u2014';
  }

  function getResourceName() {
    try {
      if (typeof GetParentResourceName === 'function') {
        var name = GetParentResourceName();
        if (typeof name === 'string' && name.trim().length > 0) {
          return name;
        }
      }
    } catch (error) {
      /* garder la ressource par defaut */
    }
    return FALLBACK_RESOURCE;
  }

  function post(endpoint, body) {
    var request = null;
    try {
      var payload = '{}';
      try {
        payload = JSON.stringify(body || {});
      } catch (error) {
        payload = '{}';
      }
      request = fetch('https://' + getResourceName() + '/' + endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: payload
      });
      if (request && typeof request.catch === 'function') {
        request.catch(function () {});
      }
    } catch (error) {
      request = null;
    }
    return request;
  }

  function run(command, args) {
    var list = Array.isArray(args) ? args : [];
    var stringArgs = [];
    for (var i = 0; i < list.length; i += 1) {
      var value = list[i];
      if (value === null || typeof value === 'undefined') {
        stringArgs.push('');
      } else {
        stringArgs.push(String(value));
      }
    }
    post('run', { command: safeString(command), args: stringArgs });
  }

  var state = {
    players: [],
    weapons: [],
    photos: {},
    playerQuery: '',
    weaponQuery: '',
    weaponCategory: '',
    hasSelection: false,
    selectedKey: null,
    selectedPlayer: null,
    hasWeaponSelection: false,
    selectedWeapon: null,
    activeTab: 'players'
  };

  var refs = {};
  var pendingConfirm = null;

  function clearNode(node) {
    if (!node) { return; }
    while (node.firstChild) {
      node.removeChild(node.firstChild);
    }
  }

  function normalizeRecord(raw) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) { return null; }
    var record = {};
    var keys = ['id', 'name', 'mode', 'team', 'ping', 'label', 'category'];
    for (var i = 0; i < keys.length; i += 1) {
      var value = raw[keys[i]];
      record[keys[i]] = typeof value === 'string' || typeof value === 'number' ? String(value) : '';
    }
    return record;
  }

  function findPlayer(key) {
    if (key === null) { return null; }
    for (var i = 0; i < state.players.length; i += 1) {
      if (idKey(state.players[i].id) === key) { return state.players[i]; }
    }
    return null;
  }

  function findWeapon(key) {
    if (key === null) { return null; }
    for (var i = 0; i < state.weapons.length; i += 1) {
      if (idKey(state.weapons[i].id) === key) { return state.weapons[i]; }
    }
    return null;
  }

  function clearSelection() {
    state.hasSelection = false;
    state.selectedKey = null;
    state.selectedPlayer = null;
  }

  function clearWeaponSelection() {
    state.hasWeaponSelection = false;
    state.selectedWeapon = null;
  }

  function safePhotoUrl(url) {
    if (typeof url !== 'string') { return null; }
    if (url.indexOf('data:image/') === 0 || url.indexOf('https://') === 0) { return url; }
    return null;
  }

  function withFeedback(button, action, after) {
    if (button) {
      button.disabled = true;
      button.classList.add('is-busy');
    }
    try {
      action();
    } catch (error) {
      /* un evenement ne doit jamais casser le panneau */
    }
    if (after) {
      try { after(); } catch (error) { /* ignore */ }
    }
    if (button) {
      window.setTimeout(function () {
        button.disabled = false;
        button.classList.remove('is-busy');
        if (button === refs.giveBtn) { updateGiveButton(); }
        if (button === refs.announceBtn) { updateAnnounceButton(); }
      }, FEEDBACK_MS);
    }
  }

  function execute(button, command, args, after) {
    withFeedback(button, function () {
      run(command, args);
    }, after);
  }

  function hideConfirm() {
    pendingConfirm = null;
    refs.confirmReason.value = '';
    refs.confirmReasonField.classList.add('hidden');
    refs.confirmOverlay.classList.add('hidden');
    refs.admin.removeAttribute('aria-hidden');
    refs.admin.removeAttribute('inert');
  }

  function cancelConfirm() {
    var action = pendingConfirm;
    hideConfirm();
    if (action && action.button) {
      try { action.button.focus(); } catch (error) { /* ignore */ }
    }
  }

  function askConfirm(message, command, args, button, useReason) {
    pendingConfirm = {
      command: command,
      args: args || [],
      button: button || null,
      useReason: useReason === true
    };
    refs.confirmMessage.textContent = message;
    refs.confirmReason.value = '';
    if (pendingConfirm.useReason) {
      refs.confirmReasonField.classList.remove('hidden');
    } else {
      refs.confirmReasonField.classList.add('hidden');
    }
    refs.confirmOverlay.classList.remove('hidden');
    refs.admin.setAttribute('aria-hidden', 'true');
    refs.admin.setAttribute('inert', '');
    var focusTarget = pendingConfirm.useReason ? refs.confirmReason : refs.confirmCancel;
    try { focusTarget.focus(); } catch (error) { /* ignore */ }
  }

  function openPanel() {
    refs.app.classList.remove('hidden');
    if (refs.tabButtons && refs.tabButtons.length > 0) {
      try { refs.tabButtons[0].focus(); } catch (error) { /* ignore */ }
    }
  }

  function closePanel() {
    if (!refs.confirmOverlay.classList.contains('hidden')) { hideConfirm(); }
    refs.app.classList.add('hidden');
  }

  function selectPlayer(player) {
    state.hasSelection = true;
    state.selectedKey = idKey(player.id);
    state.selectedPlayer = player;
    renderPlayerList();
    renderDetail();
  }

  function selectWeapon(weapon) {
    state.hasWeaponSelection = true;
    state.selectedWeapon = weapon;
    renderWeaponGrid();
  }

  function updateGiveButton() {
    if (!refs.giveBtn) { return; }
    if (refs.giveBtn.classList.contains('is-busy')) { return; }
    refs.giveBtn.disabled = !(state.hasSelection && state.hasWeaponSelection);
  }

  function updateAnnounceButton() {
    if (!refs.announceBtn || !refs.announceText || !refs.announceCount) { return; }
    var remaining = 120 - (refs.announceText.value || '').length;
    if (remaining < 0) { remaining = 0; }
    refs.announceCount.textContent = remaining + ' caractères restants';
    refs.announceBtn.disabled = refs.announceBtn.classList.contains('is-busy') ||
      (refs.announceText.value || '').trim().length === 0;
  }

  function updateChoiceGroup(nodes, attribute, current) {
    for (var i = 0; i < nodes.length; i += 1) {
      var active = safeString(nodes[i].getAttribute(attribute)).toLowerCase() === safeString(current).toLowerCase();
      nodes[i].setAttribute('aria-pressed', active ? 'true' : 'false');
      if (active) {
        nodes[i].classList.add('is-active');
      } else {
        nodes[i].classList.remove('is-active');
      }
    }
  }

  function makePlayerRow(player) {
    var row = document.createElement('button');
    row.type = 'button';
    row.className = 'player-row';
    row.setAttribute('role', 'option');
    var selected = state.hasSelection && state.selectedKey !== null && state.selectedKey === idKey(player.id);
    if (selected) { row.classList.add('is-selected'); }
    row.setAttribute('aria-selected', selected ? 'true' : 'false');

    var id = document.createElement('span');
    id.className = 'player-id';
    id.textContent = '#' + (player.id || '\u2014');

    var name = document.createElement('span');
    name.className = 'player-name';
    name.textContent = player.name || '\u2014';

    var meta = document.createElement('span');
    meta.className = 'player-meta';
    var mode = document.createElement('span');
    mode.className = 'player-mode';
    mode.textContent = modeLabel(player.mode);
    var team = document.createElement('span');
    team.className = 'player-team';
    team.textContent = teamLabel(player.team);
    var ping = document.createElement('span');
    ping.className = 'player-ping';
    ping.textContent = player.ping ? player.ping + ' ms' : '\u2014';
    meta.appendChild(mode);
    meta.appendChild(team);
    meta.appendChild(ping);

    row.appendChild(id);
    row.appendChild(name);
    row.appendChild(meta);
    row.addEventListener('click', function () {
      selectPlayer(player);
    });
    return row;
  }

  function renderPlayerList() {
    clearNode(refs.playerList);
    var query = state.playerQuery.toLowerCase();
    var fragment = document.createDocumentFragment();
    var count = 0;
    for (var i = 0; i < state.players.length; i += 1) {
      var player = state.players[i];
      if (query && player.name.toLowerCase().indexOf(query) === -1 && player.id.toLowerCase().indexOf(query) === -1) {
        continue;
      }
      fragment.appendChild(makePlayerRow(player));
      count += 1;
    }
    refs.playerList.appendChild(fragment);
    if (count === 0) {
      refs.playersEmpty.classList.remove('hidden');
    } else {
      refs.playersEmpty.classList.add('hidden');
    }
  }

  function renderDetail() {
    var player = state.selectedPlayer;
    if (!state.hasSelection || !player) {
      refs.detailEmpty.classList.remove('hidden');
      refs.detailBody.classList.add('hidden');
      updateGiveButton();
      return;
    }
    refs.detailEmpty.classList.add('hidden');
    refs.detailBody.classList.remove('hidden');
    refs.detailName.textContent = player.name || '\u2014';
    refs.detailId.textContent = 'ID ' + (player.id || '\u2014');
    refs.detailAvatar.textContent = initials(player.name || player.id);
    updateChoiceGroup(refs.modeButtons.querySelectorAll('[data-mode]'), 'data-mode', safeString(player.mode).toLowerCase());
    updateChoiceGroup(refs.teamButtons.querySelectorAll('[data-team]'), 'data-team', safeString(player.team).toLowerCase());
    updateGiveButton();
  }

  function renderWeaponFilters() {
    clearNode(refs.weaponFilters);
    var categories = [];
    var seen = Object.create(null);
    for (var i = 0; i < state.weapons.length; i += 1) {
      var category = state.weapons[i].category;
      if (category && !seen[category]) {
        seen[category] = true;
        categories.push(category);
      }
    }
    categories.sort();
    var options = [{ key: '', label: 'Toutes' }];
    for (var j = 0; j < categories.length; j += 1) {
      options.push({ key: categories[j], label: categories[j] });
    }
    var fragment = document.createDocumentFragment();
    for (var k = 0; k < options.length; k += 1) {
      (function (option) {
        var chip = document.createElement('button');
        chip.type = 'button';
        chip.className = 'chip';
        var active = option.key === state.weaponCategory;
        if (active) { chip.classList.add('is-active'); }
        chip.setAttribute('aria-pressed', active ? 'true' : 'false');
        chip.textContent = option.label;
        chip.addEventListener('click', function () {
          state.weaponCategory = option.key;
          renderWeaponFilters();
          renderWeaponGrid();
        });
        fragment.appendChild(chip);
      })(options[k]);
    }
    refs.weaponFilters.appendChild(fragment);
  }

  function makeWeaponCard(weapon) {
    var card = document.createElement('button');
    card.type = 'button';
    card.className = 'weapon-card';
    var selected = state.hasWeaponSelection && state.selectedWeapon !== null &&
      idKey(state.selectedWeapon.id) !== null && idKey(state.selectedWeapon.id) === idKey(weapon.id);
    if (selected) { card.classList.add('is-selected'); }
    card.setAttribute('aria-pressed', selected ? 'true' : 'false');

    var label = weapon.label || weapon.name || '\u2014';
    var photo = null;
    if (weapon.name && Object.prototype.hasOwnProperty.call(state.photos, weapon.name)) {
      photo = safePhotoUrl(state.photos[weapon.name]);
    }
    if (photo) {
      var img = document.createElement('img');
      img.className = 'weapon-photo';
      img.setAttribute('src', photo);
      img.setAttribute('alt', '');
      img.addEventListener('error', function () {
        var parent = img.parentNode;
        if (!parent) { return; }
        var fallback = document.createElement('span');
        fallback.className = 'weapon-placeholder';
        fallback.textContent = initials(label);
        parent.replaceChild(fallback, img);
      });
      card.appendChild(img);
    } else {
      var placeholder = document.createElement('span');
      placeholder.className = 'weapon-placeholder';
      placeholder.textContent = initials(label);
      card.appendChild(placeholder);
    }

    var name = document.createElement('span');
    name.className = 'weapon-name';
    name.textContent = label;
    var category = document.createElement('span');
    category.className = 'weapon-category';
    category.textContent = weapon.category || '\u2014';
    card.appendChild(name);
    card.appendChild(category);
    card.addEventListener('click', function () {
      selectWeapon(weapon);
    });
    return card;
  }

  function renderWeaponGrid() {
    clearNode(refs.weaponGrid);
    var query = state.weaponQuery.toLowerCase();
    var fragment = document.createDocumentFragment();
    var count = 0;
    for (var i = 0; i < state.weapons.length; i += 1) {
      var weapon = state.weapons[i];
      if (state.weaponCategory && weapon.category !== state.weaponCategory) { continue; }
      if (query) {
        var haystack = (weapon.name + ' ' + weapon.label + ' ' + weapon.category + ' ' + weapon.id).toLowerCase();
        if (haystack.indexOf(query) === -1) { continue; }
      }
      fragment.appendChild(makeWeaponCard(weapon));
      count += 1;
    }
    refs.weaponGrid.appendChild(fragment);
    if (count === 0) {
      refs.weaponsEmpty.classList.remove('hidden');
    } else {
      refs.weaponsEmpty.classList.add('hidden');
    }
    updateGiveButton();
  }

  function applyData(data, photos) {
    var rawPlayers = data && Array.isArray(data.players) ? data.players : [];
    var rawWeapons = data && Array.isArray(data.weapons) ? data.weapons : [];
    var players = [];
    var weapons = [];
    var i;

    for (i = 0; i < rawPlayers.length; i += 1) {
      var player = normalizeRecord(rawPlayers[i]);
      if (player) { players.push(player); }
    }
    for (i = 0; i < rawWeapons.length; i += 1) {
      var weapon = normalizeRecord(rawWeapons[i]);
      if (weapon) { weapons.push(weapon); }
    }

    state.players = players;
    state.weapons = weapons;
    state.photos = photos && typeof photos === 'object' && !Array.isArray(photos) ? photos : {};

    if (state.hasSelection) {
      var foundPlayer = findPlayer(state.selectedKey);
      if (foundPlayer) {
        state.selectedPlayer = foundPlayer;
      } else {
        clearSelection();
      }
    }
    if (state.hasWeaponSelection && state.selectedWeapon) {
      var foundWeapon = findWeapon(idKey(state.selectedWeapon.id));
      if (foundWeapon) {
        state.selectedWeapon = foundWeapon;
      } else {
        clearWeaponSelection();
      }
    }

    refs.playerCount.textContent = 'JOUEURS : ' + players.length;
    renderPlayerList();
    renderDetail();
    renderWeaponFilters();
    renderWeaponGrid();
  }

  function switchTab(name) {
    state.activeTab = name;
    var tabs = refs.tabs.querySelectorAll('.tab');
    var panels = document.querySelectorAll('.tabpanel');
    var i;
    for (i = 0; i < tabs.length; i += 1) {
      var active = tabs[i].getAttribute('data-tab') === name;
      tabs[i].classList.toggle('is-active', active);
      tabs[i].setAttribute('aria-selected', active ? 'true' : 'false');
      tabs[i].setAttribute('tabindex', active ? '0' : '-1');
    }
    for (i = 0; i < panels.length; i += 1) {
      var activePanel = panels[i].id === 'panel-' + name;
      if (activePanel) {
        panels[i].classList.remove('hidden');
      } else {
        panels[i].classList.add('hidden');
      }
    }
  }

  function onMessage(event) {
    var payload = event && event.data;
    if (typeof payload === 'string') {
      try {
        payload = JSON.parse(payload);
      } catch (error) {
        return;
      }
    }
    if (!payload || typeof payload !== 'object') { return; }
    if (payload.type === 'open') {
      openPanel();
    } else if (payload.type === 'close') {
      closePanel();
    } else if (payload.type === 'data') {
      applyData(payload.data, payload.photos);
    }
  }

  function onKeyDown(event) {
    if (!event) { return; }
    var key = event.key || (event.keyCode === 27 ? 'Escape' : '');
    if (key === 'Escape' || key === 'Esc') {
      if (!refs.confirmOverlay.classList.contains('hidden')) {
        event.preventDefault();
        cancelConfirm();
        return;
      }
      if (!refs.app.classList.contains('hidden')) {
        event.preventDefault();
        post('close', {});
        closePanel();
      }
      return;
    }
    if (key === 'Tab' && !refs.confirmOverlay.classList.contains('hidden')) {
      event.preventDefault();
      var showReason = !refs.confirmReasonField.classList.contains('hidden');
      var current = document.activeElement;
      var next;
      if (current === refs.confirmCancel) {
        next = showReason ? refs.confirmReason : refs.confirmOk;
      } else if (current === refs.confirmReason) {
        next = refs.confirmOk;
      } else {
        next = refs.confirmCancel;
      }
      try { next.focus(); } catch (error) { /* ignore */ }
    }
  }

  function wireEvents() {
    refs.refreshBtn.addEventListener('click', function () {
      withFeedback(refs.refreshBtn, function () {
        post('refresh', {});
      });
    });

    refs.closeBtn.addEventListener('click', function () {
      post('close', {});
      closePanel();
    });

    var tabButtons = refs.tabs.querySelectorAll('.tab');
    for (var i = 0; i < tabButtons.length; i += 1) {
      (function (tab) {
        tab.addEventListener('click', function () {
          switchTab(tab.getAttribute('data-tab'));
        });
      })(tabButtons[i]);
    }

    refs.tabs.addEventListener('keydown', function (event) {
      if (!event || (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft')) { return; }
      var names = ['players', 'matches', 'tools'];
      var index = names.indexOf(state.activeTab);
      if (index < 0) { index = 0; }
      index = (index + (event.key === 'ArrowRight' ? 1 : -1) + names.length) % names.length;
      switchTab(names[index]);
      var next = byId('tab-' + names[index]);
      if (next) {
        try { next.focus(); } catch (error) { /* ignore */ }
      }
      event.preventDefault();
    });

    refs.playerSearch.addEventListener('input', function () {
      state.playerQuery = refs.playerSearch.value || '';
      renderPlayerList();
    });

    refs.weaponSearch.addEventListener('input', function () {
      state.weaponQuery = refs.weaponSearch.value || '';
      renderWeaponGrid();
    });

    var modeButtons = refs.modeButtons.querySelectorAll('[data-mode]');
    for (var m = 0; m < modeButtons.length; m += 1) {
      (function (button) {
        button.addEventListener('click', function () {
          var player = state.selectedPlayer;
          if (!state.hasSelection || !player) { return; }
          var mode = button.getAttribute('data-mode');
          player.mode = mode;
          renderDetail();
          execute(button, 'setmode', [player.id, mode]);
        });
      })(modeButtons[m]);
    }

    var teamButtons = refs.teamButtons.querySelectorAll('[data-team]');
    for (var t = 0; t < teamButtons.length; t += 1) {
      (function (button) {
        button.addEventListener('click', function () {
          var player = state.selectedPlayer;
          if (!state.hasSelection || !player) { return; }
          var team = button.getAttribute('data-team');
          player.team = team;
          renderDetail();
          execute(button, 'setteam', [player.id, team]);
        });
      })(teamButtons[t]);
    }

    refs.resetChar.addEventListener('click', function () {
      var player = state.selectedPlayer;
      if (!state.hasSelection || !player) { return; }
      var name = player.name || ('ID ' + player.id);
      askConfirm('Reinitialiser le personnage de ' + name + ' ?', 'resetchar', [player.id], refs.resetChar);
    });

    var playerActionButtons = [
      { node: refs.gotoBtn, command: 'goto' },
      { node: refs.bringBtn, command: 'bring' },
      { node: refs.healBtn, command: 'heal' },
      { node: refs.freezeBtn, command: 'freeze' },
      { node: refs.spectateBtn, command: 'spectate' },
      { node: refs.screenBtn, command: 'screen' }
    ];
    for (var a = 0; a < playerActionButtons.length; a += 1) {
      (function (action) {
        action.node.addEventListener('click', function () {
          var player = state.selectedPlayer;
          if (!state.hasSelection || !player) { return; }
          execute(action.node, action.command, [player.id]);
        });
      })(playerActionButtons[a]);
    }

    refs.kickBtn.addEventListener('click', function () {
      var player = state.selectedPlayer;
      if (!state.hasSelection || !player) { return; }
      var name = player.name || ('ID ' + player.id);
      askConfirm('Expulser ' + name + ' ?', 'kick', [player.id], refs.kickBtn, true);
    });

    refs.announceText.addEventListener('input', function () {
      updateAnnounceButton();
    });

    refs.announceBtn.addEventListener('click', function () {
      var text = (refs.announceText.value || '').trim();
      if (text.length === 0) { updateAnnounceButton(); return; }
      execute(refs.announceBtn, 'announce', [text], function () {
        refs.announceText.value = '';
        updateAnnounceButton();
      });
    });

    refs.giveBtn.addEventListener('click', function () {
      if (!state.hasSelection || !state.hasWeaponSelection || !state.selectedWeapon) { return; }
      var player = state.selectedPlayer;
      var weapon = state.selectedWeapon;
      execute(refs.giveBtn, 'give', [player.id, weapon.id]);
    });

    var runButtons = document.querySelectorAll('[data-run]');
    for (var r = 0; r < runButtons.length; r += 1) {
      (function (button) {
        button.addEventListener('click', function () {
          var command = button.getAttribute('data-run') || '';
          var message = button.getAttribute('data-confirm');
          if (message) {
            askConfirm(message, command, [], button);
          } else {
            execute(button, command, []);
          }
        });
      })(runButtons[r]);
    }

    refs.confirmCancel.addEventListener('click', cancelConfirm);
    refs.confirmOk.addEventListener('click', function () {
      var action = pendingConfirm;
      var args = action ? action.args.slice() : [];
      if (action && action.useReason) {
        var reason = (refs.confirmReason.value || '').trim();
        if (reason.length > 80) { reason = reason.substring(0, 80); }
        if (reason.length > 0) { args.push(reason); }
      }
      hideConfirm();
      if (!action) { return; }
      execute(action.button, action.command, args);
    });
    refs.confirmOverlay.addEventListener('click', function (event) {
      if (event.target === refs.confirmOverlay) { cancelConfirm(); }
    });

    document.addEventListener('keydown', onKeyDown);
    window.addEventListener('message', onMessage);
  }

  function boot() {
    try {
      post('ready', {});

      refs.app = byId('app');
      refs.admin = byId('admin');
      refs.playerCount = byId('player-count');
      refs.refreshBtn = byId('btn-refresh');
      refs.closeBtn = byId('btn-close');
      refs.tabs = byId('tabs');
      refs.playerSearch = byId('player-search');
      refs.playerList = byId('player-list');
      refs.playersEmpty = byId('players-empty');
      refs.detailEmpty = byId('detail-empty');
      refs.detailBody = byId('detail-body');
      refs.detailAvatar = byId('detail-avatar');
      refs.detailId = byId('detail-id');
      refs.detailName = byId('detail-name');
      refs.modeButtons = byId('mode-buttons');
      refs.teamButtons = byId('team-buttons');
      refs.resetChar = byId('btn-resetchar');
      refs.gotoBtn = byId('btn-goto');
      refs.bringBtn = byId('btn-bring');
      refs.healBtn = byId('btn-heal');
      refs.freezeBtn = byId('btn-freeze');
      refs.spectateBtn = byId('btn-spectate');
      refs.screenBtn = byId('btn-screen');
      refs.kickBtn = byId('btn-kick');
      refs.announceText = byId('announce-text');
      refs.announceCount = byId('announce-count');
      refs.announceBtn = byId('btn-announce');
      refs.weaponSearch = byId('weapon-search');
      refs.weaponFilters = byId('weapon-filters');
      refs.weaponGrid = byId('weapon-grid');
      refs.weaponsEmpty = byId('weapons-empty');
      refs.giveBtn = byId('btn-give');
      refs.confirmOverlay = byId('confirm-overlay');
      refs.confirmMessage = byId('confirm-message');
      refs.confirmReasonField = byId('confirm-reason-field');
      refs.confirmReason = byId('confirm-reason');
      refs.confirmCancel = byId('confirm-cancel');
      refs.confirmOk = byId('confirm-ok');

      wireEvents();
      switchTab('players');
      renderPlayerList();
      renderDetail();
      renderWeaponFilters();
      renderWeaponGrid();
      updateAnnounceButton();
    } catch (error) {
      /* la page reste ouverte meme si une partie du panneau manque */
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
