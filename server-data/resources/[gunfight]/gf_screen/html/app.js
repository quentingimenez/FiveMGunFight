(function () {
  'use strict';

  var resourceName = 'gf_screen';
  try {
    if (typeof GetParentResourceName === 'function') {
      var name = GetParentResourceName();
      if (typeof name === 'string' && name.length > 0) resourceName = name;
    }
  } catch (e) { /* NUI indisponible : on garde le nom par défaut. */ }

  function post(endpoint, payload) {
    try {
      return fetch('https://' + resourceName + '/' + endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(payload || {})
      }).catch(function () { return null; });
    } catch (e) {
      return Promise.resolve(null);
    }
  }

  /* --- Utilitaires ------------------------------------------------------- */
  var DASH = '\u2014'; /* « — » */

  function isNum(value) {
    return typeof value === 'number' && isFinite(value);
  }

  function truncate(text, max) {
    var s = String(text);
    return s.length > max ? s.slice(0, max) : s;
  }

  function numOrDash(value) {
    return isNum(value) ? String(Math.round(value * 100) / 100) : DASH;
  }

  /* --- Visionneuse ------------------------------------------------------- */
  var viewer = document.getElementById('viewer');
  var viewerTitle = document.getElementById('viewer-title');
  var viewerImage = document.getElementById('viewer-image');
  var viewerHint = document.getElementById('viewer-hint');
  var viewerFps = document.getElementById('viewer-fps');
  var info = document.getElementById('viewer-info');
  var infoStream = document.getElementById('info-stream');
  var infoPlayer = document.getElementById('info-player');

  var frameTimes = [];      /* horodatages des images reçues (fenêtre glissante 2 s) */
  var previewTimes = [];    /* horodatages des changements d'image (écart entre images) */
  var totalBytes = 0;       /* somme des poids estimés en Ko */
  var totalCount = 0;
  var startMs = 0;          /* début de la session de visionnage */
  var streamPreset = '';    /* preset reçu avec viewStart */
  var fpsTimer = null;

  function setViewerVisible(visible) {
    if (!viewer) return;
    viewer.classList.toggle('hidden', !visible);
    viewer.setAttribute('aria-hidden', visible ? 'false' : 'true');
  }

  function resetStats() {
    frameTimes.length = 0;
    previewTimes.length = 0;
    totalBytes = 0;
    totalCount = 0;
    startMs = Date.now();
    streamPreset = '';
    if (viewerFps) viewerFps.textContent = '0 i/s';
    if (infoStream) infoStream.textContent = '';
    if (infoPlayer) infoPlayer.textContent = '';
  }

  function stopFpsTimer() {
    if (fpsTimer !== null) {
      clearInterval(fpsTimer);
      fpsTimer = null;
    }
  }

  function startFpsTimer() {
    stopFpsTimer();
    fpsTimer = setInterval(refreshStats, 500);
  }

  function refreshStats() {
    var now = Date.now();
    while (frameTimes.length > 0 && now - frameTimes[0] > 2000) frameTimes.shift();
    while (previewTimes.length > 0 && now - previewTimes[0] > 2000) previewTimes.shift();
    if (viewerFps) {
      viewerFps.textContent = (frameTimes.length / 2).toFixed(1) + ' i/s';
    }
    if (infoStream) {
      var fps = frameTimes.length / 2;
      var seconds = Math.max(0.001, (now - startMs) / 1000);
      var avgKb = totalCount > 0 ? totalBytes / totalCount : 0;
      var bitrate = totalBytes / seconds;
      var gap = DASH;
      if (previewTimes.length > 1) {
        var gapSum = 0;
        for (var i = 1; i < previewTimes.length; i++) gapSum += previewTimes[i] - previewTimes[i - 1];
        gap = Math.round(gapSum / (previewTimes.length - 1)) + ' ms';
      }
      infoStream.textContent =
        'Flux : ' + fps.toFixed(1) + ' i/s' +
        ' | ' + streamResolution() +
        ' | Préréglage : ' + (streamPreset || DASH) +
        ' | Poids : ' + (totalCount > 0 ? avgKb.toFixed(1) : DASH) + ' Ko' +
        ' | Débit : ' + bitrate.toFixed(1) + ' Ko/s' +
        ' | Écart : ' + gap;
    }
  }

  var lastMeta = null;

  function streamResolution() {
    if (lastMeta && isNum(lastMeta.w) && isNum(lastMeta.h)) {
      return Math.round(lastMeta.w) + ' \u00d7 ' + Math.round(lastMeta.h);
    }
    return DASH + ' \u00d7 ' + DASH;
  }

  function modeLabel(mode) {
    if (mode === 'attack') return 'Attaque';
    if (mode === 'redzone') return 'Redzone';
    if (mode === 'lobby') return 'Lobby';
    return mode;
  }

  function renderPlayer(meta) {
    if (!infoPlayer) return;
    if (!meta || typeof meta !== 'object') {
      infoPlayer.textContent = '';
      return;
    }
    var weapon = typeof meta.weapon === 'string' && meta.weapon.length > 0
      ? truncate(meta.weapon, 32)
      : 'Mains nues';
    var ammo = numOrDash(meta.clip) + ' / ' + numOrDash(meta.ammo);
    var mode = typeof meta.mode === 'string' && meta.mode.length > 0
      ? truncate(modeLabel(meta.mode), 32)
      : DASH;
    var state = meta.vehicle
      ? 'V\u00e9hicule' + (isNum(meta.speed) ? ' ' + Math.round(meta.speed) + ' km/h' : ' ' + DASH + ' km/h')
      : '\u00c0 pied';

    infoPlayer.textContent =
      'Joueur : Vie ' + numOrDash(meta.hp) +
      ' | Kevlar ' + numOrDash(meta.armour) +
      ' | Arme ' + weapon + ' (' + ammo + ')' +
      ' | Mode : ' + mode +
      ' | ' + state;
  }

  function onViewStart(data) {
    if (viewerImage) viewerImage.removeAttribute('src');
    if (viewerTitle) viewerTitle.textContent = 'ÉCRAN DE ' + (typeof data.name === 'string' ? data.name : DASH);
    if (viewerHint) viewerHint.textContent = "screen (F8) ou F10 > Arrêter l'écran";
    resetStats();
    streamPreset = typeof data.preset === 'string' ? truncate(data.preset, 32) : '';
    lastMeta = null;
    if (infoStream) infoStream.textContent = '';
    if (infoPlayer) infoPlayer.textContent = '';
    setViewerVisible(true);
    startFpsTimer();
    refreshStats();
  }

  function onFrame(data) {
    var image = data.data;
    if (typeof image !== 'string') return;
    if (image.indexOf('data:image/webp;base64,') !== 0 &&
        image.indexOf('data:image/jpeg;base64,') !== 0) return;
    if (!viewerImage) return;

    var now = Date.now();
    frameTimes.push(now);
    previewTimes.push(now);
    var b64length = image.length - image.indexOf(',') - 1;
    totalBytes += b64length * 3 / 4 / 1024;
    totalCount++;

    /* Meta strictement courante : une frame sans meta ne conserve rien de la précédente. */
    lastMeta = (data.meta && typeof data.meta === 'object') ? data.meta : null;
    if (typeof data.preset === 'string' && data.preset.length > 0) {
      streamPreset = truncate(data.preset, 32);
    }

    viewerImage.src = image;
    renderPlayer(lastMeta);
    refreshStats();
  }

  function onViewStop() {
    setViewerVisible(false);
    if (viewerImage) viewerImage.removeAttribute('src');
    if (viewerTitle) viewerTitle.textContent = '';
    if (viewerHint) viewerHint.textContent = '';
    stopFpsTimer();
    lastMeta = null;
    resetStats();
  }

  /* --- Capture ---------------------------------------------------------- */
  var capture = null; /* { renderer, scene, camera, rt, texture, material, geometry,
                           canvas, frameCanvas, frameCtx, imageData, pixels,
                           width, height, quality, format, timer, pending } */

  var VERTEX_SHADER = [
    'varying vec2 vUv;',
    'void main() {',
    '  vUv = vec2(uv.x, 1.0 - uv.y);',
    '  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);',
    '}'
  ].join('\n');

  var FRAGMENT_SHADER = [
    'uniform sampler2D tDiffuse;',
    'varying vec2 vUv;',
    'void main() {',
    '  gl_FragColor = texture2D(tDiffuse, vUv);',
    '}'
  ].join('\n');

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function cleanup() {
    if (!capture) return;
    var c = capture;
    capture = null; /* libéré en premier : toute frame en vol ne republie rien. */

    if (c.timer !== null) {
      clearInterval(c.timer);
      c.timer = null;
    }
    try {
      if (c.geometry) c.geometry.dispose();
      if (c.material) c.material.dispose();
      if (c.texture) c.texture.dispose();
      if (c.rt) c.rt.dispose();
      if (c.renderer) {
        c.renderer.dispose();
        var canvas = c.renderer.domElement;
        if (canvas && canvas.parentNode) canvas.parentNode.removeChild(canvas);
      }
      if (c.frameCanvas) c.frameCanvas.width = c.frameCanvas.height = 1;
      c.imageData = null;
      c.pixels = null;
      c.frameCtx = null;
      c.frameCanvas = null;
    } catch (e) {
      console.warn('gf_screen: erreur pendant le nettoyage de la capture', e);
    }
  }

  function startCapture(data) {
    if (capture) return; /* une seule capture à la fois */
    if (typeof THREE === 'undefined' || !THREE.CfxTexture) {
      console.warn('gf_screen: THREE.CfxTexture indisponible, capture ignorée');
      cleanup();
      return;
    }

    var width = Number(data.width);
    if (!isFinite(width) || width <= 0) width = 1280;
    width = clamp(Math.round(width), 320, 1920);
    var height = Math.round(width * window.innerHeight / window.innerWidth);
    if (!isFinite(height) || height <= 0) height = 1;
    height = Math.max(1, height);

    var quality = Number(data.quality);
    if (!isFinite(quality)) quality = 0.8;
    quality = clamp(quality, 0.05, 1);

    var fps = Number(data.fps);
    if (!isFinite(fps) || fps <= 0) fps = 8;
    fps = clamp(Math.round(fps), 1, 30);

    var format = data.format === 'webp' ? 'webp' : 'jpeg';

    try {
      var texture = new THREE.CfxTexture();
      texture.needsUpdate = true;

      var material = new THREE.ShaderMaterial({
        uniforms: { tDiffuse: { value: texture } },
        vertexShader: VERTEX_SHADER,
        fragmentShader: FRAGMENT_SHADER
      });
      var geometry = new THREE.PlaneBufferGeometry(2, 2);
      var scene = new THREE.Scene();
      scene.add(new THREE.Mesh(geometry, material));

      var camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
      var rt = new THREE.WebGLRenderTarget(width, height, {
        minFilter: THREE.LinearFilter,
        magFilter: THREE.LinearFilter,
        format: THREE.RGBAFormat,
        depthBuffer: false,
        stencilBuffer: false
      });

      var renderer = new THREE.WebGLRenderer({ antialias: false, alpha: false, preserveDrawingBuffer: false });
      renderer.autoClear = false;
      renderer.setSize(width, height, false);
      var canvas = renderer.domElement;
      canvas.style.display = 'none';
      canvas.style.pointerEvents = 'none';
      document.body.appendChild(canvas);

      var frameCanvas = document.createElement('canvas');
      frameCanvas.width = width;
      frameCanvas.height = height;
      var frameCtx = frameCanvas.getContext('2d');
      if (!frameCtx) throw new Error('contexte 2D indisponible');

      /* Un seul ImageData alloué au démarrage, réutilisé à chaque frame. */
      var imageData = frameCtx.createImageData(width, height);
      var pixels = new Uint8Array(width * height * 4);

      capture = {
        renderer: renderer,
        scene: scene,
        camera: camera,
        rt: rt,
        texture: texture,
        material: material,
        geometry: geometry,
        canvas: canvas,
        frameCanvas: frameCanvas,
        frameCtx: frameCtx,
        imageData: imageData,
        pixels: pixels,
        width: width,
        height: height,
        quality: quality,
        format: format,
        timer: null,
        pending: false
      };

      capture.timer = setInterval(captureFrame, Math.max(1, Math.round(1000 / fps)));
      captureFrame();
    } catch (e) {
      console.warn('gf_screen: capture indisponible (WebGL ou CfxTexture)', e);
      cleanup();
    }
  }

  function captureFrame() {
    var c = capture;
    if (!c || c.pending) return;

    c.pending = true;
    var encoded = null;
    try {
      c.renderer.clear();
      c.renderer.render(c.scene, c.camera, c.rt, true);
      c.renderer.readRenderTargetPixels(c.rt, 0, 0, c.width, c.height, c.pixels);

      var bytes = c.imageData.data;
      var pixels = c.pixels;
      for (var i = 0, j = 0; i < pixels.length; i += 4, j += 4) {
        bytes[j] = pixels[i];
        bytes[j + 1] = pixels[i + 1];
        bytes[j + 2] = pixels[i + 2];
        bytes[j + 3] = 255;
      }
      c.frameCtx.putImageData(c.imageData, 0, 0);

      if (c.format === 'webp') {
        encoded = c.frameCanvas.toDataURL('image/webp', c.quality);
        if (encoded.indexOf('data:image/webp;base64,') !== 0) {
          encoded = c.frameCanvas.toDataURL('image/jpeg', c.quality);
        }
      } else {
        encoded = c.frameCanvas.toDataURL('image/jpeg', c.quality);
      }
    } catch (e) {
      console.warn('gf_screen: échec de lecture d’une frame', e);
    }

    var valid = typeof encoded === 'string' &&
      (encoded.indexOf('data:image/webp;base64,') === 0 ||
       encoded.indexOf('data:image/jpeg;base64,') === 0);
    var next = valid ? post('frame', {
      data: encoded,
      w: c.width,
      h: c.height
    }) : Promise.resolve(null);

    next.then(function () {
      if (capture === c) c.pending = false;
    }).catch(function () {
      if (capture === c) c.pending = false;
    });
  }

  /* --- Messages NUI ----------------------------------------------------- */
  window.addEventListener('message', function (event) {
    var data = event && event.data;
    if (!data || typeof data !== 'object') return;
    try {
      switch (data.type) {
        case 'captureStart': startCapture(data); break;
        case 'captureStop': cleanup(); break;
        case 'viewStart': onViewStart(data); break;
        case 'frame': onFrame(data); break;
        case 'viewStop': onViewStop(); break;
        default: break;
      }
    } catch (e) {
      console.warn('gf_screen: message ignoré', e);
    }
  });

  window.addEventListener('pagehide', function () {
    stopFpsTimer();
    cleanup();
  });

  post('ready', {});
})();
