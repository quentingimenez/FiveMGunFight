/* Panneau de vote de la carte, juste au-dessus de la barre de modes.
   Chargé après app.js / modes.js : window.Lobby existe déjà. ES5, IIFE,
   pas de module, même philosophie que modes.js :
   - la coquille est créée une seule fois ; un nouvel état met à jour les
     nœuds existants au lieu de reconstruire la rangée ;
   - un seul écouteur de clic sur la rangée (délégation) ;
   - le vote est envoyé tel quel au serveur, qui retire un vote déjà posé ;
   - les boutons sont désactivés 600 ms après un clic, et un state reçu
     entre-temps ne doit pas les réactiver prématurément. */
(function () {
  'use strict';

  var Lobby = window.Lobby;
  if (!Lobby) return;

  var host = document.getElementById('map-vote');
  if (!host) return;

  var VOTE_COOLDOWN_MS = 600;
  var ERROR_MESSAGE = 'Le vote n’a pas été pris en compte. Réessaie.';

  var ui = {
    row: null,
    buttonsById: Object.create(null),
    records: [],
    cooldownUntil: 0,
    cooldownTimer: null,
  };

  function el(tag, className, text) {
    return Lobby.el(tag, className, text);
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

  function currentQueue() {
    var state = Lobby.state;
    return state && state.queue ? state.queue : null;
  }

  /* Le panneau n'a de sens que dans la file, et seulement s'il y a au moins
     deux cartes entre lesquelles choisir. */
  function maps() {
    var queue = currentQueue();
    if (!queue || queue.joined !== true || !Array.isArray(queue.maps)) return null;
    if (queue.maps.length < 2) return null;
    return queue.maps;
  }

  function myVoteId() {
    var queue = currentQueue();
    if (!queue || queue.myVote === undefined || queue.myVote === null || queue.myVote === '') return null;
    return String(queue.myVote);
  }

  function displayName(map) {
    if (!map) return '';
    return map.name || map.label || map.id || 'Carte';
  }

  function voteCount(map) {
    var value = Number(map && map.votes);
    if (!isFinite(value) || value < 0) value = 0;
    return Math.floor(value);
  }

  /* ------------------------------------------------------------------ */
  /*  Coquille et boutons                                                */
  /* ------------------------------------------------------------------ */

  function ensureShell() {
    if (ui.row) return;
    host.replaceChildren();
    host.appendChild(el('p', 'eyebrow', 'VOTE DE LA CARTE'));
    ui.row = el('div', 'map-vote-row');
    ui.row.setAttribute('role', 'group');
    ui.row.setAttribute('aria-label', 'Cartes proposées');
    ui.row.addEventListener('click', onRowClick);
    host.appendChild(ui.row);
  }

  function createButton(id) {
    var node = el('button', 'map-vote-card');
    node.type = 'button';
    node.dataset.mapId = id;
    node.appendChild(el('span', 'map-vote-name', ''));
    node.appendChild(el('span', 'map-vote-count', ''));
    return { id: id, node: node };
  }

  function syncButtons(list) {
    var seen = Object.create(null);
    var records = [];
    var i;

    for (i = 0; i < list.length; i += 1) {
      var map = list[i];
      if (!map || map.id === undefined || map.id === null || map.id === '') continue;
      var id = String(map.id);
      /* Des ids manquants ou dupliqués sont ignorés : un seul bouton par id,
         réutilisé d'un état à l'autre. */
      if (seen[id]) continue;
      seen[id] = true;
      var record = ui.buttonsById[id];
      if (!record) {
        record = createButton(id);
        ui.buttonsById[id] = record;
      }
      record.map = map;
      setText(record.node.firstChild, displayName(map));
      setText(record.node.lastChild, voteCount(map));
      records.push(record);
    }

    var ids = Object.keys(ui.buttonsById);
    for (i = 0; i < ids.length; i += 1) {
      var key = ids[i];
      if (seen[key]) continue;
      var stale = ui.buttonsById[key];
      if (stale.node.parentNode === ui.row) ui.row.removeChild(stale.node);
      delete ui.buttonsById[key];
    }

    /* insertBefore déplace le nœud existant : aucun listener n'est perdu. */
    for (i = 0; i < records.length; i += 1) {
      var desired = records[i].node;
      var at = ui.row.children[i] || null;
      if (at !== desired) ui.row.insertBefore(desired, at);
    }

    ui.records = records;
  }

  /* ------------------------------------------------------------------ */
  /*  Rendu                                                             */
  /* ------------------------------------------------------------------ */

  function isCooling() {
    return Date.now() < ui.cooldownUntil;
  }

  function render() {
    ensureShell();
    var list = maps();
    var visible = !!list;

    toggleClass(host, 'hidden', !visible);
    toggleClass(document.body, 'map-voting', visible);

    if (!visible) return;

    syncButtons(list);
    var mine = myVoteId();
    for (var i = 0; i < ui.records.length; i += 1) {
      var record = ui.records[i];
      var selected = mine !== null && mine === record.id;
      toggleClass(record.node, 'is-mine', selected);
      record.node.setAttribute('aria-pressed', selected ? 'true' : 'false');
      record.node.disabled = isCooling();
      record.node.setAttribute(
        'aria-label',
        'Voter ' + displayName(record.map) + ' · ' + voteCount(record.map) + ' vote(s)'
      );
    }
  }

  /* ------------------------------------------------------------------ */
  /*  Cooldown                                                          */
  /* ------------------------------------------------------------------ */

  function startCooldown() {
    if (ui.cooldownTimer) window.clearTimeout(ui.cooldownTimer);
    ui.cooldownUntil = Date.now() + VOTE_COOLDOWN_MS;
    ui.cooldownTimer = window.setTimeout(function () {
      ui.cooldownTimer = null;
      ui.cooldownUntil = 0;
      render();
    }, VOTE_COOLDOWN_MS + 20);
  }

  function resetCooldown() {
    if (ui.cooldownTimer) window.clearTimeout(ui.cooldownTimer);
    ui.cooldownTimer = null;
    ui.cooldownUntil = 0;
  }

  /* ------------------------------------------------------------------ */
  /*  Actions                                                           */
  /* ------------------------------------------------------------------ */

  function onRowClick(event) {
    var node = event.target;
    while (node && node !== ui.row) {
      if (node.classList && node.classList.contains('map-vote-card')) {
        requestVote(node.dataset.mapId);
        return;
      }
      node = node.parentNode;
    }
  }

  function requestVote(id) {
    if (id === undefined || id === null || id === '') return;
    if (isCooling()) return;
    var queue = currentQueue();
    if (!queue || queue.joined !== true || !Array.isArray(queue.maps)) return;

    var found = false;
    for (var i = 0; i < queue.maps.length; i += 1) {
      var map = queue.maps[i];
      if (map && map.id !== undefined && map.id !== null && String(map.id) === String(id)) {
        found = true;
        break;
      }
    }
    if (!found) return;

    /* Cooldown posé avant l'envoi : un state reçu pendant la requête ne
       réactive pas les boutons (isCooling() reste vrai jusqu'au timer). */
    startCooldown();
    render();

    Lobby.send('voteMap', { id: id }).then(function (result) {
      if (result && result.ok === false) Lobby.toast(ERROR_MESSAGE, 'error');
      render();
    });
  }

  /* ------------------------------------------------------------------ */
  /*  Événements Lobby                                                  */
  /* ------------------------------------------------------------------ */

  function onState() {
    render();
  }

  function onClose() {
    resetCooldown();
    toggleClass(host, 'hidden', true);
    toggleClass(document.body, 'map-voting', false);
  }

  ensureShell();
  Lobby.on('state', onState);
  Lobby.on('close', onClose);
  render();
})();
