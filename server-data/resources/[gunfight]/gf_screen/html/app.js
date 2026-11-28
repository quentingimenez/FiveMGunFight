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

  /* --- Visionneuse ------------------------------------------------------ */
  var viewer = document.getElementById('viewer');
  var viewerTitle = document.getElementById('viewer-title');
  var viewerImage = document.getElementById('viewer-image');
  var viewerHint = document.getElementById('viewer-hint');
  var viewerFps = document.getElementById('viewer-fps');
  var frameTimes = [];
  var fpsTimer = null;

  function setViewerVisible(visible) {
    if (!viewer) return;
    viewer.classList.toggle('hidden', !visible);
    viewer.setAttribute('aria-hidden', visible ? 'false' : 'true');
  }

  function resetFps() {
    frameTimes.length = 0;
    if (viewerFps) viewerFps.textContent = '0 i/s';
  }

  function refreshFps() {
    if (!viewerFps) return;
    var now = Date.now();
    while (frameTimes.length > 0 && now - frameTimes[0] > 1000) frameTimes.shift();
    viewerFps.textContent = frameTimes.length + ' i/s';
  }

  function noteFrame() {
    if (!viewerFps) return;
    frameTimes.push(Date.now());
    refreshFps();
  }

  function stopFpsTimer() {
    if (fpsTimer !== null) {
      clearInterval(fpsTimer);
      fpsTimer = null;
    }
  }

  function startFpsTimer() {
    stopFpsTimer();
    fpsTimer = setInterval(refreshFps, 500);
  }

  function onViewStart(data) {
    if (viewerImage) viewerImage.removeAttribute('src');
    if (viewerTitle) viewerTitle.textContent = 'ÉCRAN DE ' + data.name;
    if (viewerHint) viewerHint.textContent = "screen (F8) ou F10 > Arrêter l'écran";
    resetFps();
    setViewerVisible(true);
    startFpsTimer();
  }

  function onFrame(data) {
    if (typeof data.data !== 'string') return;
    if (data.data.indexOf('data:image/jpeg;base64,') !== 0) return;
    if (!viewerImage) return;
    viewerImage.src = data.data;
    noteFrame();
  }

  function onViewStop() {
    setViewerVisible(false);
    if (viewerImage) viewerImage.removeAttribute('src');
    if (viewerTitle) viewerTitle.textContent = '';
    if (viewerHint) viewerHint.textContent = '';
    stopFpsTimer();
    resetFps();
  }

  /* --- Capture ---------------------------------------------------------- */
  var capture = null; /* { renderer, scene, camera, rt, texture, material, geometry,
                          canvas, ctx, pixels, width, height, quality, timer, pending } */

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
    if (!isFinite(width) || width <= 0) width = 640;
    width = Math.max(1, Math.round(width));
    var height = Math.round(width * window.innerHeight / window.innerWidth);
    if (!isFinite(height) || height <= 0) height = 1;
    height = Math.max(1, height);

    var quality = Number(data.quality);
    if (!isFinite(quality)) quality = 0.8;
    quality = clamp(quality, 0.05, 1);

    var fps = Number(data.fps);
    if (!isFinite(fps) || fps <= 0) fps = 15;
    fps = clamp(fps, 1, 60);

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
        pixels: pixels,
        width: width,
        height: height,
        quality: quality,
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
    var jpeg = null;
    try {
      c.renderer.clear();
      c.renderer.render(c.scene, c.camera, c.rt, true);
      c.renderer.readRenderTargetPixels(c.rt, 0, 0, c.width, c.height, c.pixels);

      var imageData = c.frameCtx.createImageData(c.width, c.height);
      var bytes = imageData.data;
      var pixels = c.pixels;
      for (var i = 0, j = 0; i < pixels.length; i += 4, j += 4) {
        bytes[j] = pixels[i];
        bytes[j + 1] = pixels[i + 1];
        bytes[j + 2] = pixels[i + 2];
        bytes[j + 3] = 255;
      }
      c.frameCtx.putImageData(imageData, 0, 0);
      jpeg = c.frameCanvas.toDataURL('image/jpeg', c.quality);
    } catch (e) {
      console.warn('gf_screen: échec de lecture d’une frame', e);
    }

    var next = typeof jpeg === 'string' && jpeg.indexOf('data:image/jpeg;base64,') === 0
      ? post('frame', { data: jpeg })
      : Promise.resolve(null);

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
