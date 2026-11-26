/* Transport NUI → callbacks Lua. Aucun échec ne remonte : la page doit
   continuer à fonctionner quand elle est ouverte hors du jeu (file://). */
(function () {
  'use strict';

  var resource = 'gf_menu';
  try {
    if (typeof GetParentResourceName === 'function') {
      resource = GetParentResourceName();
    }
  } catch (err) {
    resource = 'gf_menu';
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

  window.NUI = Object.freeze({ post: post, resource: resource });
})();
