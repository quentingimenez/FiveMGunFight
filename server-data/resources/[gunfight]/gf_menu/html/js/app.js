/* Menu pause : rendu du profil, panneaux du rail et protocole NUI.
   Toutes les valeurs viennent de l'état via textContent/createElement. */
(function () {
  'use strict';

  var DASH = '—';
  var SOON_KEYS = {
    loadout: 1, crosshair: 1, shop: 1, crates: 1,
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

  function chatPanel() {
    var panel = basePanel('SERVEUR', 'CHAT');
    addText(panel, "Le chat s'ouvre avec T en jeu. Appuie sur T pour écrire un message à tous les joueurs connectés.");
    return panel;
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
    if (SOON_KEYS[key]) panel = soonPanel(label);
    else if (key === 'chat') panel = chatPanel();
    else if (key === 'rules') panel = rulesPanel();
    else if (key === 'discord') panel = discordPanel();
    else if (key === 'quit') panel = quitPanel();
    else panel = soonPanel(label);
    stage.appendChild(panel);
  }

  function hide() {
    visible = false;
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
      var stage = $('stage');
      if (stage && event.target && stage.contains(event.target)) return;
      event.preventDefault();
      if (items[current]) activate(items[current]);
    }
  }

  function onMessage(event) {
    var message = event && event.data;
    if (!message || typeof message !== 'object' || typeof message.type !== 'string') return;
    var data = message.data && typeof message.data === 'object' ? message.data : {};
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
