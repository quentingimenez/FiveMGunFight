/* Barre de modes de jeu + bouton JOUER.
   Chargé après app.js : window.Lobby existe déjà. ES5, IIFE, pas de module.

   Règles de conception :
   - la coquille et les cartes sont créées une seule fois ; un nouvel état met
     à jour les nœuds existants au lieu de reconstruire la grille. Un clic en
     cours (mousedown puis mouseup) survit donc toujours à un state ;
   - un seul écouteur de clic sur la grille (délégation), pas un listener par
     carte ;
   - l'état local se limite à ce que le serveur ne dit pas : sélection
     optimiste, action en vol, cooldown et watchdogs ;
   - les codes d'erreur NUI sont traduits ici, jamais affichés bruts. */
(function () {
  'use strict';

  var Lobby = window.Lobby;
  if (!Lobby) return;

  var host = document.getElementById('modes-bar');
  if (!host) return;

  var DEFAULT_COOLDOWN_MS = 1000;
  var COOLDOWN_MARGIN_MS = 250;
  var CONFIRM_TIMEOUT_MS = 1500;
  var SELECT_TIMEOUT_MS = 5000;
  var PLAY_TIMEOUT_MS = 6000;
  var LAUNCH_TIMEOUT_MS = 10000;

  var ERROR_MESSAGES = {
    callback_unreachable: "Le serveur n'a pas répondu. Réessaie.",
    nui_missing: "L'interface n'est pas connectée au jeu. Réessaie.",
    fetch_unavailable: "L'interface n'est pas connectée au jeu. Réessaie.",
    invalid_payload: 'La demande est invalide. Réessaie.',
    timeout: 'Le serveur met trop de temps à répondre. Réessaie.',
  };

  var ui = {
    grid: null,
    status: null,
    hint: null,
    play: null,
    playLabel: null,
    playSub: null,
    cardsById: Object.create(null),
    records: [],
    pendingModeId: null,
    selecting: false,
    playing: false,
    playCancel: false,
    launching: false,
    cooldownUntil: 0,
    selectSeq: 0,
    playSeq: 0,
    selectTimer: null,
    confirmTimer: null,
    playTimer: null,
    launchTimer: null,
    cooldownTimer: null,
  };

  function el(tag, className, text) {
    return Lobby.el(tag, className, text);
  }

  function icon(name, className) {
    return Lobby.icon(name, className);
  }

  function setText(node, value) {
    if (!node) return;
    var text = value === undefined || value === null ? '' : String(value);
    if (node.textContent !== text) node.textContent = text;
  }

  function toggleClass(node, name, enabled) {
    if (enabled) node.classList.add(name);
    else node.classList.remove(name);
  }

  function modes() {
    var state = Lobby.state;
    if (!state || !Array.isArray(state.modes)) return [];
    return state.modes;
  }

  function isLeader() {
    var state = Lobby.state;
    return !!(state && state.me && state.me.isLeader);
  }

  function serverSelectedId() {
    var state = Lobby.state;
    if (!state || !state.party || state.party.selectedMode == null) return null;
    return String(state.party.selectedMode);
  }

  function findMode(id) {
    var list = modes();
    for (var i = 0; i < list.length; i += 1) {
      if (list[i] && String(list[i].id) === String(id)) return list[i];
    }
    return null;
  }

  function firstAvailable() {
    var list = modes();
    for (var i = 0; i < list.length; i += 1) {
      if (list[i] && list[i].available && !list[i].placeholder) return list[i];
    }
    return null;
  }

  function selectedMode() {
    var mode = serverSelectedId() !== null ? findMode(serverSelectedId()) : null;
    if (mode && mode.available && !mode.placeholder) return mode;
    return firstAvailable();
  }

  function pendingMode() {
    return ui.pendingModeId === null ? null : findMode(ui.pendingModeId);
  }

  function viewMode() {
    var pending = pendingMode();
    if (pending && pending.available && !pending.placeholder) return pending;
    return selectedMode();
  }

  function currentQueue() {
    var state = Lobby.state;
    var queue = state && state.queue;
    if (!queue || typeof queue !== 'object') return null;
    return queue;
  }

  function canCancelQueue() {
    var queue = currentQueue();
    var state = Lobby.state;
    if (!queue || !state || !state.me) return false;
    if (!isLeader()) return false;
    if (queue.ownerId == null) return true;
    return Number(queue.ownerId) === Number(state.me.id);
  }

  function displayLabel(mode) {
    if (!mode) return 'Aucun mode';
    return mode.short || mode.label || mode.id || 'Mode';
  }

  function playersLabel(mode) {
    var n = Number(mode && mode.players) || 0;
    return n + (n === 1 ? ' joueur' : ' joueurs');
  }

  function cooldownMs() {
    var state = Lobby.state;
    var value = Number(state && state.modeCooldownMs);
    if (!(value >= 0 && value <= 60000)) value = DEFAULT_COOLDOWN_MS;
    return value;
  }

  function isCooldown() {
    return Date.now() < ui.cooldownUntil;
  }

  function errorMessage(result) {
    if (!result) return ERROR_MESSAGES.timeout;
    var code = result.error;
    if (typeof code === 'string' && ERROR_MESSAGES[code]) return ERROR_MESSAGES[code];
    return 'Action impossible pour le moment. Réessaie.';
  }

  /* ------------------------------------------------------------------ */
  /*  Coquille et cartes                                                */
  /* ------------------------------------------------------------------ */

  function ensureShell() {
    if (ui.grid) return;
    host.replaceChildren();

    var head = el('div', 'modes-head');
    var titles = el('div', 'modes-titles');
    titles.appendChild(el('p', 'eyebrow', 'MODES DE JEU'));
    titles.appendChild(el('h2', 'modes-title', 'Choisis ta partie'));
    ui.status = el('span', 'modes-status', 'Chargement…');
    ui.status.setAttribute('aria-live', 'polite');
    head.appendChild(titles);
    head.appendChild(ui.status);

    var layout = el('div', 'modes-layout');
    ui.grid = el('div', 'modes-grid');
    ui.grid.setAttribute('role', 'group');
    ui.grid.setAttribute('aria-label', 'Catalogue des modes de jeu');
    ui.grid.addEventListener('click', onGridClick);
    layout.appendChild(ui.grid);

    var actions = el('div', 'modes-actions');
    ui.play = el('button', 'btn primary mode-play');
    ui.play.type = 'button';
    ui.play.disabled = true;
    ui.play.setAttribute('aria-label', 'Lancer la partie');
    ui.play.appendChild(icon('play', 'mode-play-icon'));
    ui.playLabel = el('span', 'mode-play-label', 'JOUER');
    ui.play.appendChild(ui.playLabel);
    ui.playSub = el('span', 'mode-play-sub', '');
    ui.play.appendChild(ui.playSub);
    ui.play.addEventListener('click', onPlay);

    ui.hint = el('p', 'modes-hint', 'Connexion au serveur…');
    ui.hint.setAttribute('aria-live', 'polite');
    actions.appendChild(ui.play);
    actions.appendChild(ui.hint);
    layout.appendChild(actions);

    host.appendChild(head);
    host.appendChild(layout);
  }

  function createCard(id) {
    var node = el('button', 'mode-card');
    node.type = 'button';
    node.dataset.modeId = id;

    var iconWrap = el('span', 'mode-card-icon');
    var body = el('span', 'mode-card-body');
    var name = el('span', 'mode-card-name', '');
    var desc = el('span', 'mode-card-desc', '');
    var meta = el('span', 'mode-card-meta');
    meta.appendChild(icon('users', 'mode-meta-icon'));
    var players = el('span', 'mode-card-players', '');
    meta.appendChild(players);

    body.appendChild(name);
    body.appendChild(desc);
    body.appendChild(meta);
    node.appendChild(iconWrap);
    node.appendChild(body);

    return {
      id: id,
      node: node,
      iconWrap: iconWrap,
      name: name,
      desc: desc,
      meta: meta,
      players: players,
      badge: null,
      iconName: null,
      mode: null,
    };
  }

  function setBadge(record, label) {
    if (!label) {
      if (record.badge) {
        record.meta.removeChild(record.badge);
        record.badge = null;
      }
      return;
    }
    if (!record.badge) {
      record.badge = el('span', 'mode-card-badge');
      record.badge.setAttribute('aria-hidden', 'true');
      record.meta.appendChild(record.badge);
    }
    setText(record.badge, label);
  }

  function updateCardContent(record, mode) {
    record.mode = mode;
    setText(record.name, mode.label || mode.id || '');
    setText(record.desc, mode.description || '');
    setText(record.players, playersLabel(mode));

    var iconName = mode.icon || 'target';
    if (record.iconName !== iconName) {
      record.iconWrap.replaceChildren();
      record.iconWrap.appendChild(icon(iconName, 'mode-icon'));
      record.iconName = iconName;
    }

    var unavailable = !mode.available || !!mode.placeholder;
    setBadge(record, !unavailable ? '' : mode.placeholder ? 'BIENTÔT' : 'INDISPONIBLE');
    record.node.setAttribute(
      'aria-label',
      'Choisir le mode ' + (mode.label || mode.id || '') + (unavailable ? ' (indisponible)' : '')
    );
  }

  function syncCards(list) {
    var seen = Object.create(null);
    var records = [];
    var i;

    for (i = 0; i < list.length; i += 1) {
      var mode = list[i];
      if (!mode || mode.id === undefined || mode.id === null || mode.id === '') continue;
      var id = String(mode.id);
      if (seen[id]) continue;
      seen[id] = true;
      var record = ui.cardsById[id];
      if (!record) {
        record = createCard(id);
        ui.cardsById[id] = record;
      }
      updateCardContent(record, mode);
      records.push(record);
    }

    var ids = Object.keys(ui.cardsById);
    for (i = 0; i < ids.length; i += 1) {
      var key = ids[i];
      if (seen[key]) continue;
      var stale = ui.cardsById[key];
      if (stale.node.parentNode === ui.grid) ui.grid.removeChild(stale.node);
      delete ui.cardsById[key];
    }

    /* appendChild/insertBefore déplacent le nœud existant : aucun listener
       n'est perdu et le focus reste sur la carte active. */
    for (i = 0; i < records.length; i += 1) {
      var desired = records[i].node;
      var at = ui.grid.children[i] || null;
      if (at !== desired) ui.grid.insertBefore(desired, at);
    }

    ui.records = records;
  }

  function updateCardState(record) {
    var mode = record.mode;
    if (!mode) return;
    var available = !!mode.available && !mode.placeholder;
    var leader = isLeader();
    var selectedId = viewMode();
    var selected = selectedId && String(selectedId.id) === String(mode.id);
    var cooling = isCooldown();

    record.node.disabled = !available || ui.launching;
    toggleClass(record.node, 'is-selected', !!selected);
    toggleClass(record.node, 'is-locked', !leader);
    record.node.setAttribute('aria-pressed', selected ? 'true' : 'false');

    var title = '';
    if (!available) title = mode.placeholder ? 'Bientôt disponible' : 'Mode indisponible';
    else if (!leader) title = 'Le chef choisit le mode';
    else if (ui.launching) title = 'Lancement en cours';
    else if (cooling) title = 'Patiente une seconde';
    else if (ui.selecting) title = 'Sélection en cours';
    record.node.title = title;
  }

  /* ------------------------------------------------------------------ */
  /*  Rendu                                                             */
  /* ------------------------------------------------------------------ */

  function updateStatus(list) {
    var queue = currentQueue();
    if (queue) {
      var size = Number(queue.size) || 0;
      var min = Number(queue.min) || 20;
      setText(ui.status, 'Recherche serveur · ' + size + '/' + min + ' joueurs');
      return;
    }
    var current = viewMode();
    setText(
      ui.status,
      current
        ? 'Sélection : ' + displayLabel(current) + (list.length ? ' · ' + list.length + ' modes' : '')
        : 'Aucun mode disponible'
    );
  }

  function updatePlay() {
    var queue = currentQueue();
    var queuing = !!queue;
    var leader = isLeader();
    var current = selectedMode();
    var view = viewMode();
    var canCancel = queuing && canCancelQueue();
    var cooling = isCooldown();
    var canPlay;

    if (queuing) {
      canPlay = canCancel && !ui.playing && !ui.selecting && !ui.launching;
    } else {
      canPlay = !!(
        leader &&
        current &&
        current.available &&
        !current.placeholder &&
        !ui.launching &&
        !ui.playing &&
        !ui.selecting &&
        !ui.pendingModeId &&
        !cooling
      );
    }

    ui.play.disabled = !canPlay;
    ui.play.setAttribute('aria-disabled', canPlay ? 'false' : 'true');

    if (queuing) {
      var size = Number(queue.size) || 0;
      var min = Number(queue.min) || 20;
      var queueMode = findMode(queue.mode);
      setText(ui.playLabel, canCancel ? 'ANNULER' : 'RECHERCHE');
      setText(ui.playSub, queueMode ? displayLabel(queueMode) : queue.mode || 'Attaque de zone');
      ui.play.setAttribute('aria-label', canCancel ? 'Annuler la recherche' : 'Recherche en cours');
      ui.play.title = canCancel ? 'Annuler la recherche' : 'Recherche en cours';
      setText(ui.hint, 'Recherche ' + size + '/' + min);
      return;
    }

    setText(ui.playLabel, 'JOUER');
    setText(ui.playSub, view ? displayLabel(view) : 'Aucun mode');
    ui.play.setAttribute('aria-label', canPlay ? 'Lancer ' + displayLabel(view) : 'Lancement indisponible');

    var hint = '';
    if (!leader) hint = 'Le chef choisit le mode';
    else if (ui.launching) hint = 'Lancement en cours…';
    else if (ui.playing) hint = 'Lancement en cours…';
    else if (ui.selecting || ui.pendingModeId) hint = 'Sélection en cours…';
    else if (cooling) hint = 'Patiente une seconde…';
    else if (!current) hint = 'Aucun mode disponible';
    setText(ui.hint, hint);

    if (!leader) ui.play.title = 'Le chef choisit le mode';
    else if (ui.launching) ui.play.title = 'Lancement en cours';
    else if (cooling) ui.play.title = 'Patiente une seconde';
    else ui.play.title = '';
  }

  function render() {
    ensureShell();
    var state = Lobby.state;
    if (!state) return;

    var list = modes();
    syncCards(list);
    for (var i = 0; i < ui.records.length; i += 1) updateCardState(ui.records[i]);
    updateStatus(list);
    updatePlay();
  }

  /* ------------------------------------------------------------------ */
  /*  Cooldown et timers                                                */
  /* ------------------------------------------------------------------ */

  function clearCooldown() {
    if (ui.cooldownTimer) {
      window.clearTimeout(ui.cooldownTimer);
      ui.cooldownTimer = null;
    }
    ui.cooldownUntil = 0;
  }

  function startCooldown(ms) {
    var duration = Number(ms) || 0;
    if (duration > 0) duration += COOLDOWN_MARGIN_MS;
    clearCooldown();
    if (duration <= 0) return;
    ui.cooldownUntil = Date.now() + duration;
    ui.cooldownTimer = window.setTimeout(function () {
      ui.cooldownTimer = null;
      ui.cooldownUntil = 0;
      render();
    }, duration + 20);
  }

  function clearSelectTimer() {
    if (ui.selectTimer) {
      window.clearTimeout(ui.selectTimer);
      ui.selectTimer = null;
    }
  }

  function clearConfirmTimer() {
    if (ui.confirmTimer) {
      window.clearTimeout(ui.confirmTimer);
      ui.confirmTimer = null;
    }
  }

  function clearPlayTimer() {
    if (ui.playTimer) {
      window.clearTimeout(ui.playTimer);
      ui.playTimer = null;
    }
  }

  function clearLaunchTimer() {
    if (ui.launchTimer) {
      window.clearTimeout(ui.launchTimer);
      ui.launchTimer = null;
    }
  }

  function startLaunchWatchdog() {
    clearLaunchTimer();
    ui.launchTimer = window.setTimeout(function () {
      ui.launchTimer = null;
      if (!ui.launching) return;
      ui.launching = false;
      Lobby.toast('Lancement non confirmé par le serveur. Réessaie.', 'error');
      render();
    }, LAUNCH_TIMEOUT_MS);
  }

  /* ------------------------------------------------------------------ */
  /*  Actions                                                           */
  /* ------------------------------------------------------------------ */

  function onGridClick(event) {
    var node = event.target;
    while (node && node !== ui.grid) {
      if (node.classList && node.classList.contains('mode-card')) {
        onSelect(node.dataset.modeId);
        return;
      }
      node = node.parentNode;
    }
  }

  function onSelect(id) {
    var mode = findMode(id);
    if (!mode) return;

    if (!isLeader()) {
      Lobby.toast('Le chef choisit le mode.', 'info');
      return;
    }
    if (!mode.available || mode.placeholder) return;
    if (ui.launching || ui.selecting || ui.playing) return;
    if (isCooldown()) {
      render();
      return;
    }
    if (ui.pendingModeId !== null && String(ui.pendingModeId) === String(mode.id)) return;
    if (serverSelectedId() === String(mode.id) && ui.pendingModeId === null) return;

    requestSelect(mode);
  }

  function selectionConfirmed() {
    return ui.pendingModeId !== null && serverSelectedId() === String(ui.pendingModeId);
  }

  /* Le relais répond avant le traitement serveur : on accorde un court délai
     au prochain état pour confirmer la sélection optimiste. Un état qui ne la
     confirme pas ne doit pas annuler ce délai, sinon le pending resterait
     bloqué (et JOUER désactivé) après un refus silencieux du serveur. */
  function scheduleConfirm() {
    clearConfirmTimer();
    var seq = ui.selectSeq;
    ui.confirmTimer = window.setTimeout(function () {
      ui.confirmTimer = null;
      if (seq !== ui.selectSeq) return;
      if (ui.pendingModeId !== null && !selectionConfirmed()) {
        ui.pendingModeId = null;
        ui.selecting = false;
        ui.selectSeq += 1; /* ignore une réponse tardive */
        clearSelectTimer();
        render();
      }
    }, CONFIRM_TIMEOUT_MS);
  }

  function requestSelect(mode) {
    var seq = ++ui.selectSeq;
    ui.pendingModeId = String(mode.id);
    ui.selecting = true;
    clearSelectTimer();
    clearConfirmTimer();
    startCooldown(cooldownMs());
    render();

    ui.selectTimer = window.setTimeout(function () {
      if (seq !== ui.selectSeq) return;
      ui.selectSeq += 1; /* invalide la réponse en vol */
      ui.selecting = false;
      if (ui.pendingModeId !== null && !selectionConfirmed()) ui.pendingModeId = null;
      Lobby.toast(errorMessage({ error: 'timeout' }), 'error');
      render();
    }, SELECT_TIMEOUT_MS);

    Lobby.send('selectMode', { mode: mode.id }).then(function (result) {
      if (seq !== ui.selectSeq) return;
      clearSelectTimer();
      ui.selecting = false;

      if (result && result.ok === false) {
        ui.pendingModeId = null;
        clearCooldown();
        Lobby.toast(errorMessage(result), 'error');
        render();
        return;
      }

      /* La réponse du relais part avant le traitement serveur : on attend le
         prochain état pour confirmer, avec un délai de sécurité. */
      if (ui.pendingModeId !== null) scheduleConfirm();
      render();
    });
  }

  function onPlay() {
    if (ui.play.disabled) return;
    if (ui.launching || ui.selecting || ui.playing || ui.pendingModeId !== null || isCooldown()) return;
    if (!isLeader()) {
      Lobby.toast('Le chef choisit le mode.', 'info');
      return;
    }

    var queue = currentQueue();
    var mode = selectedMode();
    if (!queue && (!mode || !mode.available || mode.placeholder)) return;

    var seq = ++ui.playSeq;
    ui.playing = true;
    ui.playCancel = false;
    clearPlayTimer();
    ui.playTimer = window.setTimeout(function () {
      if (seq !== ui.playSeq) return;
      var cancelled = ui.playCancel;
      ui.playing = false;
      ui.playCancel = false;
      ui.playTimer = null;
      Lobby.toast(
        cancelled
          ? "L'annulation n'a pas été confirmée. Réessaie."
          : "Le serveur n'a pas confirmé le lancement. Réessaie.",
        'error'
      );
      render();
    }, PLAY_TIMEOUT_MS);
    render();

    var callback = 'play';
    var payload = { mode: mode && mode.id };
    if (queue && canCancelQueue()) {
      callback = 'selectMode';
      payload = { mode: queue.mode || (mode && mode.id), cancel: true };
      ui.playCancel = true;
    }

    Lobby.send(callback, payload).then(function (result) {
      if (seq !== ui.playSeq) return;
      if (result && result.ok === false) {
        ui.playing = false;
        ui.playCancel = false;
        clearPlayTimer();
        Lobby.toast(errorMessage(result), 'error');
        render();
        return;
      }
      /* Une annulation est immédiate : la réponse du relais suffit. Un
         lancement garde `playing` jusqu'au state/launching, pour ne pas
         réactiver le bouton pendant la préparation. */
      if (callback === 'selectMode') {
        ui.playing = false;
        ui.playCancel = false;
        clearPlayTimer();
        render();
      }
    });
  }

  /* ------------------------------------------------------------------ */
  /*  Événements Lobby                                                  */
  /* ------------------------------------------------------------------ */

  function onState(next) {
    var launching = !!(next && next.party && next.party.launching === true);
    var selected = next && next.party && next.party.selectedMode;
    var confirmed =
      ui.pendingModeId !== null &&
      selected != null &&
      String(selected) === String(ui.pendingModeId);

    if (confirmed) {
      /* Le serveur a appliqué la sélection : la réponse du relais n'a plus
         besoin d'être traitée, et le pending est levé tout de suite. */
      ui.pendingModeId = null;
      ui.selecting = false;
      ui.selectSeq += 1;
      clearSelectTimer();
      clearConfirmTimer();
    } else if (ui.pendingModeId !== null && !ui.confirmTimer) {
      scheduleConfirm();
    }

    if (launching) {
      ui.pendingModeId = null;
      ui.selecting = false;
      clearSelectTimer();
      clearConfirmTimer();
      if (!ui.launching) {
        ui.launching = true;
        ui.playing = false;
        ui.playCancel = false;
        ui.playSeq += 1;
        clearPlayTimer();
        startLaunchWatchdog();
      }
    } else if (ui.launching) {
      ui.launching = false;
      clearLaunchTimer();
    }

    /* Une file visible ou un lancement confirme que `play` a été traité. Une
       annulation attend sa réponse immédiate avant de relâcher le bouton. */
    if (next && (next.queue || launching) && ui.playing && !ui.playCancel) {
      ui.playing = false;
      ui.playSeq += 1;
      clearPlayTimer();
    }

    render();
  }

  function onLaunching() {
    ui.launching = true;
    ui.playing = false;
    ui.playCancel = false;
    ui.selecting = false;
    ui.pendingModeId = null;
    ui.selectSeq += 1;
    ui.playSeq += 1;
    clearSelectTimer();
    clearPlayTimer();
    clearConfirmTimer();
    startLaunchWatchdog();
    render();
  }

  function onClose() {
    clearSelectTimer();
    clearConfirmTimer();
    clearPlayTimer();
    clearLaunchTimer();
    clearCooldown();
    ui.selecting = false;
    ui.playing = false;
    ui.playCancel = false;
    ui.launching = false;
    ui.pendingModeId = null;
    ui.selectSeq += 1;
    ui.playSeq += 1;
  }

  ensureShell();
  Lobby.on('state', onState);
  Lobby.on('launching', onLaunching);
  Lobby.on('close', onClose);
  render();
})();
