/* Onglets de personnalisation (placeholders premium).
   Aucun appel serveur : deux boutons dans #main-nav, une modale « bientôt ».
   ES5 strict, chargé après app.js (window.Lobby disponible). */
(function () {
  'use strict';

  var Lobby = window.Lobby;
  if (!Lobby || typeof Lobby.el !== 'function') return;

  var el = Lobby.el;
  var icon = Lobby.icon;

  var TABS = [
    {
      id: 'weapons',
      label: 'ARMES',
      icon: 'weapon',
      ariaLabel: 'Personnalisation des armes — bientôt disponible',
      title: 'Personnalisation des armes',
      description: 'Bientôt, personnalise chaque arme : skins, teintes, accessoires et marqueurs pour composer un style qui te ressemble avant chaque déploiement.',
      art: 'weapon',
      detail: 'SKINS · ACCESSOIRES · FINITIONS'
    },
    {
      id: 'character',
      label: 'PERSONNAGE',
      icon: 'spark',
      ariaLabel: 'Personnalisation du personnage — bientôt disponible',
      title: 'Personnalisation du personnage',
      description: 'Bientôt, va plus loin que le créateur : vêtements, silhouettes et apparence avancée pour affirmer ton identité sur le terrain.',
      art: 'character',
      detail: 'TENUES · APPARENCE · STYLE'
    }
  ];

  var byId = {};
  var modal = null;
  var dialog = null;
  var closeButton = null;
  var backdrop = null;
  var lastTrigger = null;
  var titleNode = null;
  var descNode = null;
  var eyebrowNode = null;
  var artNode = null;
  var detailNode = null;

  function $(selector, root) {
    return (root || document).querySelector(selector);
  }

  function makeArt(kind) {
    var host = el('div', 'cust-art');
    host.setAttribute('aria-hidden', 'true');
    if (kind === 'character') {
      host.appendChild(el('div', 'cust-art-character'));
    } else {
      host.appendChild(el('div', 'cust-art-weapon'));
    }
    host.appendChild(el('div', 'cust-art-scan'));
    return host;
  }

  function buildModal() {
    if (modal) return;

    var host = $('#lobby-chrome') || document.body;

    backdrop = el('div', 'cust-backdrop');
    dialog = el('div', 'cust-dialog');
    dialog.setAttribute('role', 'dialog');
    dialog.setAttribute('aria-modal', 'true');
    dialog.setAttribute('aria-labelledby', 'cust-dialog-title');
    dialog.setAttribute('aria-describedby', 'cust-dialog-desc');
    dialog.classList.add('hidden');

    var head = el('div', 'cust-dialog-head');
    eyebrowNode = el('p', 'eyebrow cust-eyebrow', 'BIENTÔT DISPONIBLE');
    head.appendChild(eyebrowNode);
    closeButton = el('button', 'icon-btn cust-close');
    closeButton.type = 'button';
    closeButton.setAttribute('aria-label', 'Fermer la fenêtre');
    closeButton.appendChild(icon('close'));
    head.appendChild(closeButton);
    dialog.appendChild(head);

    var body = el('div', 'cust-dialog-body');
    titleNode = el('h2', 'cust-title', '');
    titleNode.id = 'cust-dialog-title';
    descNode = el('p', 'cust-desc', '');
    descNode.id = 'cust-dialog-desc';
    body.appendChild(titleNode);
    body.appendChild(descNode);
    dialog.appendChild(body);

    artNode = el('div', 'cust-art-wrap');
    dialog.appendChild(artNode);

    detailNode = el('p', 'cust-detail', '');
    dialog.appendChild(detailNode);

    var foot = el('div', 'cust-dialog-foot');
    var ok = el('button', 'btn primary cust-ok', 'Compris');
    ok.type = 'button';
    ok.appendChild(icon('check', 'cust-ok-icon'));
    foot.appendChild(ok);
    dialog.appendChild(foot);

    backdrop.appendChild(dialog);
    backdrop.classList.add('hidden');
    host.appendChild(backdrop);

    modal = backdrop;

    closeButton.addEventListener('click', closeModal);
    ok.addEventListener('click', closeModal);
    backdrop.addEventListener('mousedown', function (event) {
      if (event.target === backdrop) closeModal();
    });
    backdrop.addEventListener('touchstart', function (event) {
      if (event.target === backdrop) closeModal();
    }, { passive: true });
    dialog.addEventListener('keydown', trapTab);
    document.addEventListener('keydown', onKeyDown);
  }

  function focusables() {
    if (!dialog) return [];
    var nodes = dialog.querySelectorAll('button:not([disabled]), [href], input:not([disabled]), [tabindex]:not([tabindex="-1"])');
    var list = [];
    for (var i = 0; i < nodes.length; i += 1) {
      if (nodes[i].getAttribute('aria-hidden') !== 'true') list.push(nodes[i]);
    }
    return list;
  }

  function trapTab(event) {
    if (event.key !== 'Tab') return;
    var list = focusables();
    if (!list.length) return;
    var first = list[0];
    var last = list[list.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  function onKeyDown(event) {
    if (!modal || modal.classList.contains('hidden')) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      closeModal();
    } else if (event.key === 'Tab') {
      trapTab(event);
    }
  }

  function openModal(tab, trigger) {
    buildModal();
    if (!modal) return;
    lastTrigger = trigger || null;

    eyebrowNode.textContent = 'BIENTÔT DISPONIBLE';
    titleNode.textContent = tab.title;
    descNode.textContent = tab.description;
    detailNode.textContent = tab.detail;
    dialog.setAttribute('aria-labelledby', 'cust-dialog-title');
    dialog.setAttribute('aria-describedby', 'cust-dialog-desc');

    while (artNode.firstChild) artNode.removeChild(artNode.firstChild);
    artNode.appendChild(makeArt(tab.art));

    modal.classList.remove('hidden');
    dialog.classList.remove('hidden');
    closeButton.focus();
  }

  function closeModal() {
    if (!modal || modal.classList.contains('hidden')) return;
    modal.classList.add('hidden');
    dialog.classList.add('hidden');
    var trigger = lastTrigger;
    lastTrigger = null;
    if (trigger && trigger.focus && document.contains(trigger)) trigger.focus();
  }

  function makeTab(config) {
    var button = el('button', 'cust-tab');
    button.type = 'button';
    button.setAttribute('aria-label', config.ariaLabel);
    button.setAttribute('aria-haspopup', 'dialog');
    button.appendChild(icon(config.icon, 'cust-tab-icon'));
    button.appendChild(el('span', 'cust-tab-label', config.label));
    var lock = icon('lock', 'cust-tab-lock');
    lock.setAttribute('aria-hidden', 'true');
    button.appendChild(lock);
    button.addEventListener('click', function () {
      openModal(config, button);
    });
    return button;
  }

  function mount() {
    var nav = $('#main-nav');
    if (!nav) return;
    if (nav.childElementCount > 0) return;

    for (var i = 0; i < TABS.length; i += 1) {
      var config = TABS[i];
      var button = makeTab(config);
      byId[config.id] = button;
      nav.appendChild(button);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mount);
  } else {
    mount();
  }

  window.Customization = {
    open: function (id) {
      var config = null;
      for (var i = 0; i < TABS.length; i += 1) {
        if (TABS[i].id === id) config = TABS[i];
      }
      if (config) openModal(config, byId[id]);
    },
    close: closeModal
  };
})();
