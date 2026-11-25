/* État global, coquille du lobby et routage des messages NUI.
   Chargé avant les modules modes / escouade / création. */
(function () {
  'use strict';

  var BUILD = '7259e64';
  document.documentElement.setAttribute('data-build', BUILD);

  var ICONS = {
    logo:
      '<svg viewBox="0 0 32 32" fill="none" aria-hidden="true"><path d="M16 2.6 27.2 9v14L16 29.4 4.8 23V9L16 2.6Z" stroke="currentColor" stroke-width="1.6"/><circle cx="16" cy="16" r="6.1" stroke="currentColor" stroke-width="1.4"/><path d="M16 8.2v4.1M16 19.7v4.1M8.2 16h4.1M19.7 16h4.1" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>',
    target:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="12" cy="12" r="8.2" stroke="currentColor" stroke-width="1.7"/><circle cx="12" cy="12" r="3.1" stroke="currentColor" stroke-width="1.7"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
    zone:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m12 2.8 8 4.6v9.2l-8 4.6-8-4.6V7.4l8-4.6Z" stroke="currentColor" stroke-width="1.6"/><path d="M12 7.2v9.6M7.8 9.6l8.4 4.8M16.2 9.6l-8.4 4.8" stroke="currentColor" stroke-width="1.3" opacity=".75"/></svg>',
    weapon:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M3 10.4h13.2l2.4 2.1h2.4v1.7h-3.1l-2.1-1.7H9.4L8 15.2H5.8l1.1-3H3v-1.8Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><path d="M9.2 9v-2h4.2l1 1.5M8.6 10.4v3.1" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
    team:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="9" cy="8.2" r="3.1" stroke="currentColor" stroke-width="1.6"/><path d="M3.4 19.2c.4-3.2 2.6-5.1 5.6-5.1s5.2 1.9 5.6 5.1" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><path d="M15.3 6.2a2.6 2.6 0 0 1 0 5M16.1 14.5c2.4.3 4 2 4.4 4.7" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
    lock:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="4.8" y="10.2" width="14.4" height="10.3" rx="2" stroke="currentColor" stroke-width="1.6"/><path d="M8.2 10.2V8a3.8 3.8 0 0 1 7.6 0v2.2" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><path d="M12 14.5v2.2" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
    users:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="9.2" cy="8.4" r="3.2" stroke="currentColor" stroke-width="1.6"/><path d="M3.5 19.4c.4-3.4 2.7-5.3 5.7-5.3s5.3 1.9 5.7 5.3" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><path d="M15.8 5.6a3 3 0 0 1 0 5.7M16.7 14.3c2.3.4 3.8 2.1 4.1 4.6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>',
    crown:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m4 8.4 4.2 3L12 5.8l3.8 5.6 4.2-3-1.5 9.3H5.5L4 8.4Z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M6 20h12" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>',
    plus:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 5v14M5 12h14" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
    check:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m5 12.6 4.4 4.4L19 6.8" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    play:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M8 5.6v12.8L19 12 8 5.6Z" fill="currentColor"/></svg>',
    close:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
    search:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="10.8" cy="10.8" r="6.3" stroke="currentColor" stroke-width="1.7"/><path d="m15.6 15.6 4.1 4.1" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
    repeat:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M19.2 8.4A7.7 7.7 0 0 0 5.4 6.1L3.8 8M4.8 15.6a7.7 7.7 0 0 0 13.8 2.3l1.6-1.9" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><path d="M3.6 4.6v3.7h3.7M20.4 19.4v-3.7h-3.7" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    arrow:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M4.5 12h14M13.2 6.5 18.8 12l-5.6 5.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    male:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="10" cy="14" r="5.4" stroke="currentColor" stroke-width="1.7"/><path d="M14 10 20 4M15.2 4H20v4.8" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    female:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="12" cy="9" r="5.4" stroke="currentColor" stroke-width="1.7"/><path d="M12 14.4V22M8.8 18.3h6.4" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>',
    shield:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 2.9 20 6v6.1c0 4.6-3.2 7.5-8 9-4.8-1.5-8-4.4-8-9V6l8-3.1Z" stroke="currentColor" stroke-width="1.6"/><path d="m8.6 12.1 2.3 2.3 4.5-4.6" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    spark:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 2.8 14 9l6.2 2-6.2 2-2 6.2-2-6.2L3.8 11 10 9l2-6.2Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/></svg>',
    alert:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 3.4 21 20H3L12 3.4Z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 9v4.4M12 16.8v.1" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
    logout:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M14 4.5H6.5A1.5 1.5 0 0 0 5 6v12a1.5 1.5 0 0 0 1.5 1.5H14" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><path d="M11 12h9M16.3 7.7 20.6 12l-4.3 4.3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    chevron:
      '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m9 5.5 6.5 6.5L9 18.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  };

  var handlers = Object.create(null);
  var state = null;
  var ready = false;
  var heartbeatTimer = null;
  var bootFallback = null;
  var transitionTimer = null;
  var retryTimer = null;
  var syncTimer = null;
  var syncAttempts = 0;
  var syncDone = false;

  function $(selector, root) {
    return (root || document).querySelector(selector);
  }

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function icon(name, className) {
    var span = el('span', 'icon' + (className ? ' ' + className : ''));
    var svg = ICONS[name] || ICONS.alert;
    span.innerHTML = svg; // constantes locales uniquement
    span.setAttribute('aria-hidden', 'true');
    return span;
  }

  function send(name, data) {
    if (!window.NUI) return Promise.resolve({ ok: false, error: 'nui_missing' });
    return window.NUI.post(name, data);
  }

  function on(type, handler) {
    if (typeof handler !== 'function') return function () {};
    if (!handlers[type]) handlers[type] = [];
    handlers[type].push(handler);
    return function () {
      var list = handlers[type] || [];
      var index = list.indexOf(handler);
      if (index >= 0) list.splice(index, 1);
    };
  }

  function dispatch(type, data) {
    var list = handlers[type] || [];
    for (var i = 0; i < list.length; i += 1) {
      try {
        list[i](data);
      } catch (err) {
        console.error('[gf_lobby] handler ' + type, err);
      }
    }
  }

  function toast(message, level) {
    var root = $('#toasts');
    if (!root || !message) return;
    var kind = level === 'success' || level === 'error' ? level : 'info';
    var node = el('div', 'toast toast-' + kind);
    node.setAttribute('role', kind === 'error' ? 'alert' : 'status');
    node.appendChild(icon(kind === 'error' ? 'alert' : kind === 'success' ? 'check' : 'spark', 'toast-icon'));
    var body = el('div', 'toast-body');
    body.appendChild(el('p', 'toast-message', message));
    node.appendChild(body);
    root.appendChild(node);
    while (root.children.length > 5) root.removeChild(root.firstElementChild);
    window.setTimeout(function () {
      node.classList.add('is-leaving');
      window.setTimeout(function () {
        if (node.parentNode) node.parentNode.removeChild(node);
      }, 220);
    }, 4300);
  }

  function showTransition(title, subtitle) {
    var overlay = $('#transition-overlay');
    if (!overlay) return;
    $('#transition-title').textContent = title || 'Partie';
    $('#transition-subtitle').textContent = subtitle || 'Préparation de la partie…';
    overlay.classList.remove('hidden');
    overlay.setAttribute('aria-hidden', 'false');
    if (transitionTimer) window.clearTimeout(transitionTimer);
    transitionTimer = window.setTimeout(hideTransition, 10000);
  }

  function hideTransition() {
    var overlay = $('#transition-overlay');
    if (!overlay) return;
    overlay.classList.add('hidden');
    overlay.setAttribute('aria-hidden', 'true');
    if (transitionTimer) {
      window.clearTimeout(transitionTimer);
      transitionTimer = null;
    }
  }

  function displayName() {
    if (!state || !state.me) return '';
    var character = state.me.character;
    return (character && character.name) || state.me.name || 'Joueur';
  }

  function setScreen(screen) {
    var creator = screen === 'creator';
    document.body.classList.toggle('screen-creator', creator);
    document.body.classList.toggle('screen-lobby', !creator);
    var chrome = $('#lobby-chrome');
    var creatorRoot = $('#creator-root');
    if (chrome) chrome.classList.toggle('hidden', creator);
    if (creatorRoot) creatorRoot.classList.toggle('hidden', !creator);
  }

  function renderStatus() {
    var host = $('#topbar-status');
    if (!host || !state) return;
    host.replaceChildren();
    var online = Number(state.online) || 0;
    var pill = el('div', 'status-pill');
    pill.appendChild(el('span', 'status-dot'));
    pill.appendChild(el('span', 'status-label', 'CONNECTÉ'));
    var count = el('div', 'online-chip');
    count.appendChild(el('strong', '', String(online)));
    count.appendChild(el('span', '', 'EN LIGNE'));
    host.appendChild(pill);
    host.appendChild(count);
  }

  function buildBadge(suffix, level) {
    var badge = $('#build-badge');
    if (!badge) return;
    badge.textContent = 'BUILD ' + BUILD + (suffix ? ' · ' + suffix : '');
    badge.classList.remove('is-sync', 'is-ok', 'is-offline');
    if (level) badge.classList.add('is-' + level);
  }

  function stopSyncWatch() {
    if (syncTimer) {
      window.clearInterval(syncTimer);
      syncTimer = null;
    }
    syncAttempts = 0;
  }

  function startSyncWatch() {
    if (syncDone || syncTimer) return;
    syncTimer = window.setInterval(function () {
      if (syncDone || state) {
        stopSyncWatch();
        return;
      }
      syncAttempts += 1;
      if (syncAttempts > 3) {
        buildBadge('HORS LIGNE', 'offline');
        stopSyncWatch();
        return;
      }
      buildBadge('SYNC', 'sync');
      send('requestState', {});
    }, 2000);
  }

  function markSynced() {
    syncDone = true;
    stopSyncWatch();
    buildBadge('HOTFIX', 'ok');
  }

  function renderProfile() {
    var host = $('#profile-panel');
    if (!host || !state || !state.me) return;
    host.replaceChildren();
    var name = displayName() || 'Joueur';
    var id = Number(state.me.id) || 0;
    var initial = name.trim().charAt(0).toUpperCase() || '?';
    var leader = !!state.me.isLeader;
    var hue = (id * 47 + 18) % 360;

    var top = el('div', 'profile-top');
    var avatar = el('div', 'profile-avatar', initial);
    avatar.style.setProperty('--avatar-hue', String(hue));
    avatar.setAttribute('aria-hidden', 'true');
    top.appendChild(avatar);
    var identity = el('div', 'profile-identity');
    identity.appendChild(el('p', 'eyebrow', 'Profil'));
    identity.appendChild(el('h2', 'profile-name', name));
    identity.appendChild(el('p', 'profile-id', 'JOUEUR #' + id));
    top.appendChild(identity);
    host.appendChild(top);

    host.appendChild(el('div', 'profile-rule'));

    var stats = el('dl', 'profile-stats');
    var role = el('div', 'profile-stat');
    role.appendChild(el('dt', '', 'Rôle'));
    var roleValue = el('dd', 'role-value');
    roleValue.appendChild(icon(leader ? 'crown' : 'users'));
    roleValue.appendChild(el('span', '', leader ? "Chef d'escouade" : 'Membre'));
    role.appendChild(roleValue);
    stats.appendChild(role);

    var presence = el('div', 'profile-stat');
    presence.appendChild(el('dt', '', 'Statut'));
    var presenceValue = el('dd', 'presence-value');
    presenceValue.appendChild(el('span', 'status-dot'));
    presenceValue.appendChild(el('span', '', 'Dans le lobby'));
    presence.appendChild(presenceValue);
    stats.appendChild(presence);
    host.appendChild(stats);

    var foot = el('div', 'profile-foot');
    foot.appendChild(el('span', 'profile-foot-label', 'GUNFIGHT'));
    foot.appendChild(el('span', 'profile-foot-tag', 'LOBBY'));
    host.appendChild(foot);
  }

  function startHeartbeat() {
    if (heartbeatTimer) window.clearInterval(heartbeatTimer);
    heartbeatTimer = window.setInterval(function () {
      if (state) send('heartbeat', {});
    }, 2000);
  }

  function stopHeartbeat() {
    if (heartbeatTimer) {
      window.clearInterval(heartbeatTimer);
      heartbeatTimer = null;
    }
  }

  function revealApp() {
    var app = $('#app');
    var boot = $('#boot');
    if (app) app.classList.remove('hidden');
    if (boot) boot.classList.add('hidden');
    document.body.classList.remove('booting');
    if (bootFallback) {
      window.clearTimeout(bootFallback);
      bootFallback = null;
    }
  }

  function applyState(next) {
    if (!next || !next.me || !next.party || !Array.isArray(next.modes)) {
      console.warn('[gf_lobby] état incomplet ignoré');
      return;
    }
    state = next;
    markSynced();
    revealApp();
    renderStatus();
    renderProfile();
    setScreen(next.me.character ? 'lobby' : 'creator');
    if (next.party.launching !== true) hideTransition();
    startHeartbeat();
    dispatch('state', next);
  }

  function closeLobby() {
    state = null;
    syncDone = false;
    stopSyncWatch();
    buildBadge();
    stopHeartbeat();
    hideTransition();
    var app = $('#app');
    if (app) app.classList.add('hidden');
    var boot = $('#boot');
    if (boot) boot.classList.add('hidden');
    document.body.classList.remove('booting');
    dispatch('close', {});
  }

  function handleMessage(event) {
    var message = event && event.data;
    if (!message || typeof message.type !== 'string') return;
    var payload = message.data || {};
    if (message.type === 'state') {
      applyState(payload);
      return;
    }
    if (message.type === 'close') {
      closeLobby();
      return;
    }
    if (message.type === 'notice') {
      toast(payload.message || payload.text || '', payload.level);
      dispatch('notice', payload);
      return;
    }
    if (message.type === 'launching') {
      showTransition(payload.label || payload.mode || 'Partie');
      dispatch('launching', payload);
      return;
    }
    dispatch(message.type, payload);
  }

  function boot() {
    ready = true;
    var brandMark = $('#brand-mark');
    if (brandMark) brandMark.appendChild(icon('logo'));
    var bootMark = $('#boot-mark');
    if (bootMark) bootMark.appendChild(icon('logo'));

    var hint = $('#center-hint');
    if (hint) {
      hint.appendChild(el('p', 'hint-eyebrow', 'GUNFIGHT LOBBY'));
      hint.appendChild(el('p', 'hint-title', 'Ton escouade. Ton terrain.'));
      hint.appendChild(el('p', 'hint-sub', 'Invite tes amis, choisis un mode, lance la partie.'));
    }

    var retry = $('#boot-retry');
    if (retry) {
      retry.addEventListener('click', function () {
        retry.classList.add('hidden');
        var status = $('#boot-status');
        if (status) status.textContent = 'Nouvelle tentative de connexion…';
        send('requestState', {});
        if (retryTimer) window.clearTimeout(retryTimer);
        retryTimer = window.setTimeout(function () {
          if (!state) {
            retry.classList.remove('hidden');
            if (status) status.textContent = "L'interface n'a pas reçu d'état.";
          }
        }, 5000);
      });
    }

    buildBadge();
    send('ready', {});
    startSyncWatch();
    bootFallback = window.setTimeout(function () {
      if (state) return;
      var status = $('#boot-status');
      if (status) status.textContent = "Toujours en attente de l'état du lobby…";
      if (retry) retry.classList.remove('hidden');
    }, 8000);
  }

  window.addEventListener('message', handleMessage);

  window.Lobby = {
    send: send,
    on: on,
    el: el,
    icon: icon,
    toast: toast,
    showTransition: showTransition,
    hideTransition: hideTransition,
    get state() {
      return state;
    },
    get ready() {
      return ready;
    },
  };

  document.addEventListener('DOMContentLoaded', boot);
})();
