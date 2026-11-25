/* Panneau escouade, modale d'invitation et cartes d'invitation reçue.
   ES5, IIFE, aucun innerHTML avec des données serveur. */
(function () {
  'use strict';

  var Lobby = window.Lobby;
  if (!Lobby) return;

  var panel = null;
  var inviteRoot = null;
  var modalHost = null;
  var cardHost = null;

  /* État de la modale */
  var modalOpen = false;
  var modalDialog = null;
  var modalList = null;
  var modalFocusBefore = null;
  var modalPlayers = [];
  var modalFilter = '';
  var modalPhase = 'idle'; /* idle | loading | ready | error */
  var modalRequest = 0;
  var modalTimer = null;

  /* Invitations envoyées : la promesse 'invite' n'est qu'un accusé, la
     confirmation finale vient par l'événement 'inviteResult'. */
  var pendingInvites = {};      /* id joueur -> bouton */
  var inviteTimeout = null;

  /* État de l'invitation reçue */
  var currentInvite = null;
  var inviteCard = null;
  var inviteTimer = null;
  var inviteSeconds = 0;
  var inviteResponding = false;

  function el(tag, className, text) {
    return Lobby.el(tag, className, text);
  }

  function icon(name, className) {
    return Lobby.icon(name, className);
  }

  function firstName(value) {
    var text = String(value == null ? '' : value).trim();
    return text.charAt(0).toUpperCase() || '?';
  }

  function label(value) {
    var text = String(value == null ? '' : value).trim();
    return text || 'Joueur';
  }

  function maxSize(party) {
    var n = party && Number(party.maxSize);
    if (!isFinite(n) || n < 1) n = 4;
    return Math.min(Math.floor(n), 12);
  }

  function sizeOf(party) {
    var members = party && Array.isArray(party.members) ? party.members : [];
    var n = party && Number(party.size);
    if (!isFinite(n) || n < members.length) n = members.length;
    if (!isFinite(n) || n < 1) n = 1;
    return Math.floor(n);
  }

  function resultOk(response) {
    return !!(response && response.ok === true);
  }

  function resultError(response, fallback) {
    if (!response) return fallback;
    if (response.error) return String(response.error);
    if (response.message) return String(response.message);
    return fallback;
  }

  function toastResult(response, successText, fallbackError) {
    if (resultOk(response)) {
      Lobby.toast(successText, 'success');
      return true;
    }
    Lobby.toast(resultError(response, fallbackError), 'error');
    return false;
  }

  /* ------------------------------------------------------------------ */
  /* Panneau escouade                                                     */
  /* ------------------------------------------------------------------ */

  function memberCard(member, isLeader, isSelf, canKick) {
    var row = el('div', 'squad-member' + (isSelf ? ' is-self' : ''));
    var avatar = el('div', 'squad-avatar', firstName(member.displayName || member.name));
    avatar.setAttribute('aria-hidden', 'true');
    var id = Number(member.id) || 0;
    var hue = (id * 47 + 18) % 360;
    avatar.style.setProperty('--avatar-hue', String(hue));
    row.appendChild(avatar);

    var identity = el('div', 'squad-member-identity');
    var nameLine = el('div', 'squad-member-name');
    nameLine.appendChild(el('span', 'squad-member-name-text', label(member.displayName || member.name)));
    if (isLeader) {
      var leaderBadge = el('span', 'squad-badge squad-badge-leader');
      leaderBadge.appendChild(icon('crown', 'squad-badge-icon'));
      leaderBadge.appendChild(el('span', '', 'CHEF'));
      nameLine.appendChild(leaderBadge);
    }
    if (isSelf) {
      nameLine.appendChild(el('span', 'squad-badge squad-badge-self', 'VOUS'));
    }
    identity.appendChild(nameLine);
    identity.appendChild(el('p', 'squad-member-sub', label(member.name)));
    row.appendChild(identity);

    if (canKick && !isSelf) {
      var kick = el('button', 'icon-btn squad-kick');
      kick.type = 'button';
      kick.setAttribute('aria-label', 'Exclure ' + label(member.displayName || member.name) + " de l'escouade");
      kick.title = 'Exclure';
      kick.appendChild(icon('close'));
      kick.addEventListener('click', function () {
        kick.disabled = true;
        Lobby.send('kickMember', { id: member.id }).then(function (response) {
          if (!resultOk(response)) kick.disabled = false;
          toastResult(response, 'Membre exclu de l\'escouade.', "Impossible d'exclure ce membre.");
        });
      });
      row.appendChild(kick);
    }
    return row;
  }

  function emptySlot(slot, openModal) {
    var row = el('div', 'squad-slot');
    var dot = el('div', 'squad-slot-dot');
    dot.appendChild(icon('plus'));
    dot.setAttribute('aria-hidden', 'true');
    row.appendChild(dot);
    row.appendChild(el('span', 'squad-slot-label', 'Emplacement libre ' + slot));
    var btn = el('button', 'btn ghost squad-slot-invite');
    btn.type = 'button';
    btn.appendChild(icon('plus'));
    btn.appendChild(el('span', '', 'Inviter'));
    btn.setAttribute('aria-label', "Inviter un joueur dans l'emplacement " + slot);
    btn.addEventListener('click', openModal);
    row.appendChild(btn);
    return row;
  }

  function renderPanel(state) {
    if (!panel) return;
    var party = (state && state.party) || {};
    var me = (state && state.me) || {};
    var members = Array.isArray(party.members) ? party.members.slice() : [];
    members.sort(function (a, b) {
      var sa = Number(a && a.slot) || 0;
      var sb = Number(b && b.slot) || 0;
      return sa - sb;
    });

    var total = maxSize(party);
    var used = sizeOf(party);
    var selfIsLeader = !!me.isLeader;

    panel.replaceChildren();

    var head = el('div', 'squad-head');
    var titleWrap = el('div', 'squad-title-wrap');
    titleWrap.appendChild(icon('users', 'squad-title-icon'));
    titleWrap.appendChild(el('h2', 'squad-title', 'ESCOUADE'));
    head.appendChild(titleWrap);
    var counter = el('span', 'squad-counter', used + '/' + total);
    counter.setAttribute('aria-label', used + ' joueur' + (used > 1 ? 's' : '') + ' sur ' + total);
    head.appendChild(counter);
    panel.appendChild(head);

    var intro = el('p', 'squad-subtitle');
    intro.textContent = selfIsLeader ? "Vous êtes chef d'escouade." : "Le chef choisit le mode de jeu.";
    panel.appendChild(intro);

    var list = el('div', 'squad-list');
    for (var i = 0; i < total; i += 1) {
      var member = members[i];
      if (member) {
        list.appendChild(memberCard(
          member,
          !!member.isLeader || Number(member.id) === Number(party.leaderId),
          !!member.isSelf || Number(member.id) === Number(me.id),
          selfIsLeader
        ));
      } else {
        list.appendChild(emptySlot(i + 1, openModal));
      }
    }
    panel.appendChild(list);

    var foot = el('div', 'squad-foot');
    var inviteBtn = el('button', 'btn primary squad-invite-btn');
    inviteBtn.type = 'button';
    inviteBtn.appendChild(icon('plus'));
    inviteBtn.appendChild(el('span', '', 'Inviter'));
    inviteBtn.setAttribute('aria-label', used >= total ? 'Escouade complète' : 'Ouvrir la liste des joueurs à inviter');
    if (used >= total) {
      inviteBtn.disabled = true;
      inviteBtn.title = 'Escouade complète';
    }
    inviteBtn.addEventListener('click', openModal);
    foot.appendChild(inviteBtn);

    if (used > 1) {
      var leaveBtn = el('button', 'btn ghost squad-leave-btn');
      leaveBtn.type = 'button';
      leaveBtn.setAttribute('aria-label', "Quitter l'escouade");
      leaveBtn.appendChild(icon('logout'));
      leaveBtn.appendChild(el('span', '', "Quitter l'escouade"));
      leaveBtn.addEventListener('click', function () {
        leaveBtn.disabled = true;
        Lobby.send('leaveParty', {}).then(function (response) {
          if (!resultOk(response)) leaveBtn.disabled = false;
          toastResult(response, "Vous avez quitté l'escouade.", "Impossible de quitter l'escouade.");
        });
      });
      foot.appendChild(leaveBtn);
    }
    panel.appendChild(foot);
  }

  /* ------------------------------------------------------------------ */
  /* Modale d'invitation                                                  */
  /* ------------------------------------------------------------------ */

  function modalBodyText() {
    if (modalPhase === 'loading') return 'Recherche des joueurs…';
    if (modalPhase === 'error') return 'Impossible de charger les joueurs.';
    if (!modalPlayers.length) return 'Aucun joueur invitable pour le moment.';
    return modalPlayers.length + ' joueur' + (modalPlayers.length > 1 ? 's' : '') + ' invitable' + (modalPlayers.length > 1 ? 's' : '');
  }

  function renderModalList() {
    if (!modalList) return;
    modalList.replaceChildren();
    var status = el('p', 'invite-list-status');
    status.textContent = modalBodyText();
    status.setAttribute('role', modalPhase === 'error' ? 'alert' : 'status');
    modalList.appendChild(status);

    if (modalPhase === 'loading') {
      var loader = el('div', 'invite-loading');
      loader.appendChild(el('span', 'spinner'));
      loader.appendChild(el('span', '', 'Chargement de la liste…'));
      modalList.appendChild(loader);
      return;
    }
    if (modalPhase === 'error') {
      var retry = el('button', 'btn ghost invite-retry');
      retry.type = 'button';
      retry.setAttribute('aria-label', 'Recharger la liste des joueurs');
      retry.appendChild(icon('repeat'));
      retry.appendChild(el('span', '', 'Réessayer'));
      retry.addEventListener('click', requestPlayers);
      modalList.appendChild(retry);
      return;
    }

    var needle = modalFilter.toLowerCase();
    var found = 0;
    for (var i = 0; i < modalPlayers.length; i += 1) {
      var player = modalPlayers[i];
      var name = label(player && player.name);
      if (needle && name.toLowerCase().indexOf(needle) < 0) continue;
      found += 1;

      var row = el('div', 'invite-player');
      var avatar = el('div', 'invite-player-avatar', firstName(name));
      avatar.setAttribute('aria-hidden', 'true');
      var pid = Number(player && player.id) || 0;
      avatar.style.setProperty('--avatar-hue', String((pid * 47 + 18) % 360));
      row.appendChild(avatar);

      var info = el('div', 'invite-player-info');
      info.appendChild(el('p', 'invite-player-name', name));
      var teamSize = Number(player && player.partySize);
      if (!isFinite(teamSize) || teamSize < 1) teamSize = 1;
      info.appendChild(el('p', 'invite-player-meta', 'Escouade ' + teamSize + '/4'));
      row.appendChild(info);

      var btn = el('button', 'btn primary invite-player-btn');
      btn.type = 'button';
      btn.setAttribute('aria-label', 'Inviter ' + name + ' dans l\'escouade');
      btn.appendChild(icon('plus'));
      btn.appendChild(el('span', '', 'Inviter'));
      btn.addEventListener('click', function (playerId, playerName, button) {
        button.disabled = true;
        pendingInvites[String(playerId)] = button;
        armInviteTimeout();
        Lobby.send('invite', { id: playerId }).then(function (response) {
          /* Le serveur confirme l'envoi par inviteResult (événement), pas par
             cette promesse : ne pas afficher de succès ici pour éviter le
             double toast. La promesse ne sert qu'à réactiver en cas d'erreur. */
          if (!resultOk(response)) {
            enableInviteButton(playerId);
            Lobby.toast(resultError(response, "Impossible d'envoyer l'invitation."), 'error');
          }
        });
      }.bind(null, player.id, name, btn));
      row.appendChild(btn);
      modalList.appendChild(row);
    }

    if (!found) {
      var empty = el('p', 'invite-empty', 'Aucun joueur ne correspond à « ' + modalFilter + ' ».');
      modalList.appendChild(empty);
    }
  }

  function clearPendingInvite(id) {
    if (Object.prototype.hasOwnProperty.call(pendingInvites, String(id))) {
      delete pendingInvites[String(id)];
    }
  }

  function enableInviteButton(id) {
    var button = pendingInvites[String(id)];
    if (!button) return;
    clearPendingInvite(id);
    if (document.body.contains(button)) button.disabled = false;
  }

  function clearInviteTimeout() {
    if (inviteTimeout !== null) {
      window.clearTimeout(inviteTimeout);
      inviteTimeout = null;
    }
  }

  function armInviteTimeout() {
    if (inviteTimeout !== null) return;
    inviteTimeout = window.setTimeout(function () {
      inviteTimeout = null;
      var ids = [];
      for (var key in pendingInvites) {
        if (Object.prototype.hasOwnProperty.call(pendingInvites, key)) ids.push(key);
      }
      for (var i = 0; i < ids.length; i += 1) enableInviteButton(ids[i]);
      Lobby.toast("Invitation non confirmée par le serveur. Réessaie.", 'info');
    }, 5000);
  }

  function modalLoadingTimeout(request) {
    if (!modalOpen || request !== modalRequest || modalPhase !== 'loading') return;
    modalPhase = 'error';
    modalPlayers = [];
    renderModalList();
  }

  function requestPlayers() {
    if (!modalOpen) return;
    var request = ++modalRequest;
    modalPhase = 'loading';
    modalPlayers = [];
    renderModalList();
    if (modalTimer !== null) window.clearTimeout(modalTimer);
    modalTimer = window.setTimeout(function () {
      modalTimer = null;
      modalLoadingTimeout(request);
    }, 5000);
    Lobby.send('requestPlayers', {}).then(function (response) {
      if (!modalOpen || request !== modalRequest) return;
      /* requestPlayers ne renvoie que {ok:true} : la liste arrive ensuite par
         l'événement 'players'. Ne jamais passer en 'ready' ici. */
      if (!resultOk(response)) {
        if (modalTimer !== null) {
          window.clearTimeout(modalTimer);
          modalTimer = null;
        }
        modalPhase = 'error';
        modalPlayers = [];
        renderModalList();
      }
    });
  }

  function closeModal() {
    if (!modalOpen) return;
    modalOpen = false;
    modalRequest += 1;
    if (modalTimer !== null) {
      window.clearTimeout(modalTimer);
      modalTimer = null;
    }
    clearInviteTimeout();
    pendingInvites = {};
    modalPhase = 'idle';
    modalPlayers = [];
    modalFilter = '';
    modalDialog = null;
    modalList = null;
    if (modalHost) modalHost.replaceChildren();
    var focus = modalFocusBefore;
    modalFocusBefore = null;
    if (focus && document.body.contains(focus) && typeof focus.focus === 'function') {
      try { focus.focus(); } catch (e) { /* focus indisponible */ }
    }
  }

  function trapFocus(event) {
    if (!modalOpen || !modalDialog || event.key !== 'Tab') return;
    var focusables = modalDialog.querySelectorAll('button, input, [href], [tabindex]:not([tabindex="-1"])');
    var available = [];
    for (var i = 0; i < focusables.length; i += 1) {
      var node = focusables[i];
      if (!node.disabled && node.offsetParent !== null) available.push(node);
    }
    if (!available.length) return;
    var first = available[0];
    var last = available[available.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  function openModal() {
    if (!inviteRoot || modalOpen) return;
    modalFocusBefore = document.activeElement;
    modalOpen = true;
    modalFilter = '';
    modalPlayers = [];

    var backdrop = el('div', 'invite-backdrop');
    var dialog = el('div', 'invite-dialog');
    modalDialog = dialog;
    dialog.setAttribute('role', 'dialog');
    dialog.setAttribute('aria-modal', 'true');
    dialog.setAttribute('aria-labelledby', 'invite-dialog-title');

    var head = el('div', 'invite-dialog-head');
    var titleWrap = el('div', 'squad-title-wrap');
    titleWrap.appendChild(icon('users', 'squad-title-icon'));
    var heading = el('h2', 'squad-title', 'INVITER UN JOUEUR');
    heading.id = 'invite-dialog-title';
    titleWrap.appendChild(heading);
    head.appendChild(titleWrap);

    var close = el('button', 'icon-btn invite-close');
    close.type = 'button';
    close.setAttribute('aria-label', 'Fermer la fenêtre d\'invitation');
    close.appendChild(icon('close'));
    close.addEventListener('click', closeModal);
    head.appendChild(close);
    dialog.appendChild(head);

    var subtitle = el('p', 'invite-dialog-sub', 'Joueurs présents dans le lobby, hors de votre escouade.');
    dialog.appendChild(subtitle);

    var searchWrap = el('div', 'invite-search');
    searchWrap.appendChild(icon('search', 'invite-search-icon'));
    var search = el('input', 'invite-search-input');
    search.type = 'text';
    search.placeholder = 'Rechercher un joueur…';
    search.setAttribute('aria-label', 'Rechercher un joueur par son nom');
    search.setAttribute('autocomplete', 'off');
    search.addEventListener('input', function () {
      modalFilter = search.value || '';
      renderModalList();
    });
    searchWrap.appendChild(search);
    dialog.appendChild(searchWrap);

    var list = el('div', 'invite-list');
    modalList = list;
    dialog.appendChild(list);

    var foot = el('div', 'invite-dialog-foot');
    foot.appendChild(el('span', 'invite-foot-hint', 'Les invitations expirent après 30 secondes.'));
    dialog.appendChild(foot);

    backdrop.appendChild(dialog);
    backdrop.addEventListener('mousedown', function (event) {
      if (event.target === backdrop) closeModal();
    });
    modalHost.replaceChildren();
    modalHost.appendChild(backdrop);

    requestPlayers();
    try { search.focus(); } catch (e) { /* focus indisponible */ }
  }

  /* ------------------------------------------------------------------ */
  /* Invitation reçue                                                     */
  /* ------------------------------------------------------------------ */

  function clearInviteTimer() {
    if (inviteTimer !== null) {
      window.clearInterval(inviteTimer);
      inviteTimer = null;
    }
  }

  function respondInvite(accept) {
    if (!currentInvite || inviteResponding) return;
    inviteResponding = true;
    var data = { partyId: currentInvite.partyId, accept: accept };
    clearInviteTimer();
    var card = inviteCard;
    var join = card && card.querySelector('.invite-join');
    var decline = card && card.querySelector('.invite-decline');
    if (join) join.disabled = true;
    if (decline) decline.disabled = true;
    Lobby.send('respondInvite', data).then(function (response) {
      inviteResponding = false;
      if (resultOk(response)) {
        /* Carte retirée seulement après confirmation : en cas d'erreur elle
           reste affichée avec ses boutons réactivés. */
        if (card && card.parentNode) card.parentNode.removeChild(card);
        if (inviteCard === card) {
          inviteCard = null;
          currentInvite = null;
        }
        return;
      }
      if (join) join.disabled = false;
      if (decline) decline.disabled = false;
      Lobby.toast(resultError(response, "Impossible de répondre à l'invitation."), 'error');
    });
  }

  function renderInviteCard() {
    if (!inviteRoot || !currentInvite) return;
    clearInviteTimer();
    if (inviteCard && inviteCard.parentNode) inviteCard.parentNode.removeChild(inviteCard);

    var from = currentInvite.from || {};
    var leader = currentInvite.leader || {};
    var card = el('div', 'invite-card');
    card.setAttribute('role', 'group');
    card.setAttribute('aria-label', 'Invitation reçue');

    var top = el('div', 'invite-card-top');
    top.appendChild(icon('users', 'invite-card-icon'));
    var lines = el('div', 'invite-card-lines');
    lines.appendChild(el('p', 'invite-card-title', 'Invitation reçue'));
    lines.appendChild(el('p', 'invite-card-text',
      label(from.name) + " vous invite à rejoindre l'escouade de " + label(leader.name) + '.'));
    top.appendChild(lines);

    var countdown = el('span', 'invite-countdown', inviteSeconds + ' s');
    countdown.setAttribute('aria-live', 'off');
    top.appendChild(countdown);
    card.appendChild(top);

    var bar = el('div', 'invite-card-bar');
    var fill = el('div', 'invite-card-bar-fill');
    bar.appendChild(fill);
    card.appendChild(bar);

    var actions = el('div', 'invite-card-actions');
    var join = el('button', 'btn primary invite-join');
    join.type = 'button';
    join.setAttribute('aria-label', "Rejoindre l'escouade");
    join.appendChild(icon('check'));
    join.appendChild(el('span', '', 'Rejoindre'));
    join.addEventListener('click', function () { respondInvite(true); });
    actions.appendChild(join);

    var decline = el('button', 'btn ghost invite-decline');
    decline.type = 'button';
    decline.setAttribute('aria-label', 'Refuser l\'invitation');
    decline.appendChild(icon('close'));
    decline.appendChild(el('span', '', 'Refuser'));
    decline.addEventListener('click', function () { respondInvite(false); });
    actions.appendChild(decline);
    card.appendChild(actions);

    cardHost.replaceChildren();
    cardHost.appendChild(card);
    inviteCard = card;

    inviteTimer = window.setInterval(function () {
      inviteSeconds -= 1;
      if (inviteSeconds <= 0) {
        clearInviteTimer();
        if (inviteCard && inviteCard.parentNode) inviteCard.parentNode.removeChild(inviteCard);
        inviteCard = null;
        currentInvite = null;
        inviteResponding = false;
        return;
      }
      countdown.textContent = inviteSeconds + ' s';
      fill.style.width = (inviteSeconds / Math.max(1, currentInvite.duration || 30) * 100) + '%';
    }, 1000);
  }

  function showInvite(data) {
    if (!data) return;
    var expires = Number(data.expiresIn);
    if (!isFinite(expires) || expires <= 0) expires = 30000;
    currentInvite = {
      partyId: data.partyId,
      from: data.from || {},
      leader: data.leader || {},
      duration: Math.ceil(expires / 1000)
    };
    inviteSeconds = currentInvite.duration;
    renderInviteCard();
  }

  /* ------------------------------------------------------------------ */
  /* Protocole NUI                                                        */
  /* ------------------------------------------------------------------ */

  Lobby.on('state', function (state) {
    renderPanel(state);
  });

  Lobby.on('players', function (data) {
    if (!modalOpen) return;
    modalRequest += 1;
    if (modalTimer !== null) {
      window.clearTimeout(modalTimer);
      modalTimer = null;
    }
    modalPhase = 'ready';
    modalPlayers = data && Array.isArray(data.players) ? data.players : [];
    if (modalList) renderModalList();
    else requestPlayers();
  });

  Lobby.on('invite', showInvite);

  Lobby.on('inviteResult', function (data) {
    /* Confirmation par relay : erreur -> réactiver le bouton du joueur
       concerné ; succès -> fermeture de la modale (cf. closeModal). */
    if (!resultOk(data)) {
      var id = data && (data.id != null ? data.id : data.targetId);
      if (id != null) enableInviteButton(id);
    }
    var message = data && (data.message || data.error);
    if (!message) return;
    Lobby.toast(message, resultOk(data) ? 'success' : 'error');
    if (resultOk(data)) closeModal();
  });

  document.addEventListener('keydown', function (event) {
    if (!modalOpen) return;
    if (event.key === 'Escape' || event.keyCode === 27) {
      event.preventDefault();
      closeModal();
      return;
    }
    trapFocus(event);
  });

  Lobby.on('close', function () {
    closeModal();
    clearInviteTimer();
    currentInvite = null;
    inviteCard = null;
    inviteResponding = false;
    if (cardHost) cardHost.replaceChildren();
  });

  function boot() {
    panel = document.getElementById('squad-panel');
    inviteRoot = document.getElementById('invite-root');
    if (inviteRoot) {
      cardHost = el('div', 'invite-card-host');
      modalHost = el('div', 'invite-modal-host');
      inviteRoot.appendChild(cardHost);
      inviteRoot.appendChild(modalHost);
    }
    if (Lobby.state) renderPanel(Lobby.state);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
