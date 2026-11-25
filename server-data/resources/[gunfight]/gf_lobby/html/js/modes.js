/* Barre de modes de jeu + bouton JOUER.
   Chargé après app.js : window.Lobby existe déjà. ES5, IIFE, pas de module. */
(function () {
  'use strict';

  var Lobby = window.Lobby;
  if (!Lobby) return;

  var host = document.getElementById('modes-bar');
  if (!host) return;

  var launching = false;
  var playing = false;
  var cards = [];
  var playButton = null;
  var playSub = null;
  var playLabel = null;
  var statusNode = null;
  var hintNode = null;
  var pendingSelect = 0;
  var pendingPlay = 0;
  var launchTimer = null;

  function el(tag, className, text) {
    return Lobby.el(tag, className, text);
  }

  function icon(name, className) {
    return Lobby.icon(name, className);
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

  function findMode(id) {
    var list = modes();
    for (var i = 0; i < list.length; i += 1) {
      if (list[i] && list[i].id === id) return list[i];
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
    var state = Lobby.state;
    var id = state && state.party ? state.party.selectedMode : null;
    var mode = id ? findMode(id) : null;
    if (mode && mode.available && !mode.placeholder) return mode;
    return firstAvailable();
  }

  function displayLabel(mode) {
    if (!mode) return 'Aucun mode';
    return mode.short || mode.label || mode.id || 'Mode';
  }

  function playersLabel(mode) {
    var n = Number(mode && mode.players) || 0;
    return n + (n === 1 ? ' joueur' : ' joueurs');
  }

  function buildCard(mode) {
    var card = el('button', 'mode-card');
    card.type = 'button';
    card.setAttribute('role', 'button');
    card.dataset.modeId = mode.id == null ? '' : String(mode.id);
    card.setAttribute('aria-label', 'Choisir le mode ' + (mode.label || mode.id || ''));

    var unavailable = !mode.available || !!mode.placeholder;
    card.disabled = unavailable;
    card.setAttribute('aria-pressed', 'false');

    var iconWrap = el('span', 'mode-card-icon');
    iconWrap.appendChild(icon(mode.icon || 'target', 'mode-icon'));
    card.appendChild(iconWrap);

    var body = el('span', 'mode-card-body');
    var name = el('span', 'mode-card-name', mode.label || mode.id || '');
    var desc = el('span', 'mode-card-desc', mode.description || '');
    var meta = el('span', 'mode-card-meta');
    meta.appendChild(icon('users', 'mode-meta-icon'));
    meta.appendChild(el('span', 'mode-card-players', playersLabel(mode)));
    if (unavailable) {
      var badge = el('span', 'mode-card-badge', 'BIENTÔT');
      badge.setAttribute('aria-label', 'Bientôt disponible');
      meta.appendChild(badge);
    }
    body.appendChild(name);
    body.appendChild(desc);
    body.appendChild(meta);
    card.appendChild(body);

    card.addEventListener('click', function () {
      if (card.disabled || launching || playing) return;
      if (!isLeader()) {
        Lobby.toast('Le chef choisit le mode.', 'info');
        return;
      }
      if (mode.placeholder || !mode.available) return;
      var request = ++pendingSelect;
      playing = true;
      Lobby.send('selectMode', { mode: mode.id }).then(function (result) {
        if (request !== pendingSelect) return;
        playing = false;
        if (result && result.ok === false) {
          Lobby.toast(result.error || "Impossible de choisir le mode.", 'error');
          render();
        }
      });
    });

    card._mode = mode;
    return card;
  }

  function buildShell() {
    host.replaceChildren();

    var head = el('div', 'modes-head');
    var titles = el('div', 'modes-titles');
    titles.appendChild(el('p', 'eyebrow', 'MODES DE JEU'));
    titles.appendChild(el('h2', 'modes-title', 'Choisis ta partie'));
    statusNode = el('span', 'modes-status', '');
    statusNode.setAttribute('aria-live', 'polite');
    head.appendChild(titles);
    head.appendChild(statusNode);

    var layout = el('div', 'modes-layout');
    var grid = el('div', 'modes-grid');
    grid.setAttribute('role', 'group');
    grid.setAttribute('aria-label', 'Catalogue des modes de jeu');
    layout.appendChild(grid);

    var actions = el('div', 'modes-actions');
    playButton = el('button', 'btn primary mode-play');
    playButton.type = 'button';
    playButton.setAttribute('aria-label', 'Lancer la partie');
    playButton.appendChild(icon('play', 'mode-play-icon'));
    playLabel = el('span', 'mode-play-label', 'JOUER');
    playButton.appendChild(playLabel);
    playSub = el('span', 'mode-play-sub', '');
    playButton.appendChild(playSub);

    hintNode = el('p', 'modes-hint', '');
    hintNode.setAttribute('aria-live', 'polite');
    actions.appendChild(playButton);
    actions.appendChild(hintNode);
    layout.appendChild(actions);

    playButton.addEventListener('click', function () {
      var mode = selectedMode();
      if (!mode || playButton.disabled || launching || playing) return;
      if (!isLeader()) {
        Lobby.toast('Le chef choisit le mode.', 'info');
        return;
      }
      var request = ++pendingPlay;
      playing = true;
      clearLaunchTimer();
      launchTimer = window.setTimeout(finishAction, 6000);
      Lobby.send('play', { mode: mode.id }).then(function (result) {
        if (request !== pendingPlay) return;
        playing = false;
        if (result && result.ok === false) {
          clearLaunchTimer();
          launching = false;
          Lobby.toast(result.error || 'Impossible de lancer la partie.', 'error');
          render();
        }
      });
    });

    host.appendChild(head);
    host.appendChild(layout);
    return grid;
  }

  /* Le serveur n'envoie pas d'état après selectMode (relay simple) : sans
     garde-fou, playing resterait vrai jusqu'au prochain state et le bouton
     JOUER resterait grisé. Même logique pour play si launching n'arrive pas. */
  function clearLaunchTimer() {
    if (launchTimer !== null) {
      window.clearTimeout(launchTimer);
      launchTimer = null;
    }
  }

  function finishAction(notify) {
    clearLaunchTimer();
    pendingSelect = 0;
    pendingPlay = 0;
    playing = false;
    if (launching) {
      launching = false;
      if (notify !== false) {
        Lobby.toast('Lancement non confirmé par le serveur. Réessaie.', 'error');
      }
    }
    render();
  }

  function render() {
    if (!Lobby.state) return;

    var list = modes();
    var leader = isLeader();
    var current = selectedMode();
    var grid = host.querySelector('.modes-grid');
    if (!grid) grid = buildShell();
    else statusNode = host.querySelector('.modes-status');
    if (!statusNode) {
      buildShell();
      grid = host.querySelector('.modes-grid');
      statusNode = host.querySelector('.modes-status');
    }
    hintNode = host.querySelector('.modes-hint');
    playButton = host.querySelector('.mode-play');
    playSub = host.querySelector('.mode-play-sub');

    while (grid.firstChild) grid.removeChild(grid.firstChild);
    cards = [];
    for (var i = 0; i < list.length; i += 1) {
      if (!list[i]) continue;
      var card = buildCard(list[i]);
      cards.push(card);
      grid.appendChild(card);
    }

    var partySize = (Lobby.state && Lobby.state.party && Lobby.state.party.size) || 1;
    var currentId = current ? current.id : null;
    for (var j = 0; j < cards.length; j += 1) {
      var c = cards[j];
      var m = c._mode;
      var chosen = currentId != null && m.id === currentId;
      var blocked = !leader || !m.available || !!m.placeholder || launching || playing;
      c.classList.toggle('is-selected', chosen);
      c.classList.toggle('is-locked', !leader);
      c.setAttribute('aria-pressed', chosen ? 'true' : 'false');
      c.disabled = !m.available || !!m.placeholder || launching || playing;
      c.setAttribute('aria-disabled', blocked ? 'true' : 'false');
      c.title = !leader ? 'Le chef choisit le mode' : c.disabled ? 'Mode indisponible' : '';
    }

    statusNode.textContent = current
      ? 'Sélection : ' + displayLabel(current) + (list.length ? ' · ' + list.length + ' modes' : '')
      : 'Aucun mode disponible';

    var minPlayers = (current && current.minPlayers) || 1;
    var enoughPlayers = partySize >= minPlayers;
    var canPlay = !!(
      leader &&
      current &&
      current.available &&
      !current.placeholder &&
      enoughPlayers &&
      !launching &&
      !playing
    );
    playButton.disabled = !canPlay;
    playButton.setAttribute('aria-disabled', canPlay ? 'false' : 'true');
    playSub.textContent = current ? displayLabel(current) : 'Aucun mode';
    playButton.setAttribute(
      'aria-label',
      canPlay ? 'Lancer ' + displayLabel(current) : 'Lancement indisponible'
    );

    if (!leader) hintNode.textContent = 'Le chef choisit le mode';
    else if (!enoughPlayers) {
      hintNode.textContent = 'Il faut ' + minPlayers + ' joueurs (escouade : ' + partySize + ')';
    } else if (launching) hintNode.textContent = 'Lancement en cours…';
    else if (!current) hintNode.textContent = 'Aucun mode disponible';
    else hintNode.textContent = '';
  }

  Lobby.on('state', function (state) {
    var nextLaunching = !!(state && state.party && state.party.launching === true);
    if (nextLaunching) {
      launching = true;
      /* Watchdog : si aucun close ni state de fin n'arrive, libérer le bouton. */
      clearLaunchTimer();
      launchTimer = window.setTimeout(function () { finishAction(true); }, 10000);
    } else {
      if (launching) {
        /* Lancement confirmé par l'état : pas de faux toast d'échec. */
        finishAction(false);
      }
      clearLaunchTimer();
      launching = false;
      playing = false;
      /* pendingSelect / pendingPlay vivent jusqu'à finishAction() : ne pas
         les remettre à zéro ici (une réponse en vol resterait invalide). */
    }
    render(state);
  });
  Lobby.on('launching', function () {
    launching = true;
    playing = false;
    /* Le serveur signale le lancement par cet événement (pas forcément par un
       state) : watchdog de 10 s pour libérer le bouton si rien n'arrive. */
    clearLaunchTimer();
    launchTimer = window.setTimeout(function () { finishAction(true); }, 10000);
    render();
  });
  Lobby.on('close', function () {
    clearLaunchTimer();
    launching = false;
    playing = false;
    pendingSelect = 0;
    pendingPlay = 0;
    cards = [];
  });

  buildShell();
  render();
})();
