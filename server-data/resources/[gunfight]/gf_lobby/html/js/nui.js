/* Transport NUI → callbacks Lua. Aucun échec ne remonte : l'interface ne doit
   jamais planter à cause d'un fetch. */
(function () {
  'use strict';

  var resource = 'gf_lobby';
  try {
    if (typeof GetParentResourceName === 'function') {
      resource = GetParentResourceName();
    }
  } catch (err) {
    resource = 'gf_lobby';
  }

  function post(name, data) {
    if (typeof window.fetch !== 'function') {
      return Promise.resolve({ ok: false, error: 'fetch_unavailable' });
    }
    return window
      .fetch('https://' + resource + '/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
      })
      .then(function (response) {
        return response.json().catch(function () {
          return { ok: response.ok };
        });
      })
      .catch(function () {
        return { ok: false, error: 'callback_unreachable' };
      });
  }

  // Player-facing text for the codes returned by post() and the Lua callbacks.
  var ERROR_TEXT = {
    callback_unreachable: 'Le jeu ne répond pas. Réessaie.',
    fetch_unavailable: 'Interface indisponible. Relance le jeu.',
    nui_missing: 'Interface indisponible. Relance le jeu.',
    internal_error: 'Erreur interne. Réessaie.',
    invalid_payload: 'Demande invalide.',
    invalid_character: 'Apparence invalide.',
    invalid_name: 'Nom invalide.',
  };
  var CODE_SHAPE = /^[a-z][a-z0-9_]*$/;

  // Never shows a raw code: a known code gets its message, an unknown one the
  // caller's fallback. A sentence already written for the player is kept.
  function errorText(error, fallback) {
    if (typeof error !== 'string' || error === '') return fallback;
    if (Object.prototype.hasOwnProperty.call(ERROR_TEXT, error)) return ERROR_TEXT[error];
    if (CODE_SHAPE.test(error)) return fallback;
    return error;
  }

  window.NUI = Object.freeze({ post: post, resource: resource, errorText: errorText });
})();
