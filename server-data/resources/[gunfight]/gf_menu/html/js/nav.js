/* Navigation du rail : module pur, testable sous Node et exposé au navigateur.
   nextIndex(count, current, delta) -> index dans [0, count - 1], ou -1 si la
   navigation est impossible. current invalide : +1 -> 0, sinon -> count - 1. */
(function (root, factory) {
  'use strict';
  var api = factory();
  if (typeof module === 'object' && module && module.exports) {
    module.exports = api;
  } else {
    root.GFMenuNav = api;
  }
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  function nextIndex(count, current, delta) {
    if (!Number.isInteger(count) || count < 1) return -1;
    var start = Number.isInteger(current) && current >= 0 && current < count ? current : -1;
    if (!Number.isInteger(delta)) return start;
    if (start === -1) return delta > 0 ? 0 : count - 1;
    return ((start + delta) % count + count) % count;
  }

  return { nextIndex: nextIndex };
});
