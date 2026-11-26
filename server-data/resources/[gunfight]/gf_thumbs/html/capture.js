// Studio photo : capture l'image du jeu, détoure le fond vert, recadre l'objet.
//
// Capture : technique de screenshot-basic (citizenfx/screenshot-basic, licence MIT).
// Une texture WebGL 1x1 suivie d'une séquence précise de texParameterf est reliée
// par FiveM à l'image du jeu (sans l'interface NUI). On la dessine dans une
// texture hors écran, puis on lit les pixels.

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'gf_thumbs';

const VERT = `
attribute vec2 a_pos;
varying vec2 v_uv;
void main() {
    v_uv = vec2((a_pos.x + 1.0) / 2.0, 1.0 - (a_pos.y + 1.0) / 2.0);
    gl_Position = vec4(a_pos, 0.0, 1.0);
}`;
const FRAG = `
precision mediump float;
varying vec2 v_uv;
uniform sampler2D u_tex;
void main() { gl_FragColor = texture2D(u_tex, v_uv); }`;

let gl = null;
let prog = null;
let gameTex = null;

function setup() {
    const canvas = document.createElement('canvas');
    gl = canvas.getContext('webgl', { preserveDrawingBuffer: true, antialias: false });
    if (!gl) throw new Error('WebGL indisponible');

    const sh = (type, src) => {
        const s = gl.createShader(type);
        gl.shaderSource(s, src);
        gl.compileShader(s);
        return s;
    };
    prog = gl.createProgram();
    gl.attachShader(prog, sh(gl.VERTEX_SHADER, VERT));
    gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(prog);

    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]), gl.STATIC_DRAW);

    // Texture « jeu » : même séquence que CfxTexture de @citizenfx/three
    gameTex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, gameTex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, 1, 1, 0, gl.RGB, gl.UNSIGNED_BYTE, new Uint8Array(3));
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
}

// Image du jeu en RGBA (lignes de haut en bas)
function grabFrame() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    gl.canvas.width = w;
    gl.canvas.height = h;
    gl.viewport(0, 0, w, h);
    gl.useProgram(prog);
    const loc = gl.getAttribLocation(prog, 'a_pos');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, gameTex);
    gl.uniform1i(gl.getUniformLocation(prog, 'u_tex'), 0);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
    const px = new Uint8Array(w * h * 4);
    gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, px);
    return { w, h, px };
}

// Fond vert -> transparent, avec atténuation du reflet vert sur les bords
function keyOut(img) {
    const p = img.px;
    for (let i = 0; i < p.length; i += 4) {
        const r = p[i], g = p[i + 1], b = p[i + 2];
        const other = Math.max(r, b);
        const excess = g - other;
        if (excess > 90) {
            p[i + 3] = 0;
        } else if (excess > 25) {
            // bord : semi-transparent, vert ramené au niveau des autres couleurs
            p[i + 3] = Math.round(255 * (1 - (excess - 25) / 65));
            p[i + 1] = other;
        } else {
            if (excess > 0) p[i + 1] = other;
            p[i + 3] = 255;
        }
    }
}

// Boîte englobante des pixels visibles, cherchée seulement dans la zone de l'objet
// (region en fractions de l'écran, calculée par le client à partir du modèle 3D)
function bounds(img, region) {
    const { w, h, px } = img;
    const r = region || { x0: 0, y0: 0, x1: 1, y1: 1 };
    const rx0 = Math.max(0, Math.floor(r.x0 * w)), rx1 = Math.min(w - 1, Math.ceil(r.x1 * w));
    const ry0 = Math.max(0, Math.floor(r.y0 * h)), ry1 = Math.min(h - 1, Math.ceil(r.y1 * h));
    let x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (let y = ry0; y <= ry1; y++) {
        for (let x = rx0; x <= rx1; x++) {
            if (px[(y * w + x) * 4 + 3] > 20) {
                if (x < x0) x0 = x;
                if (x > x1) x1 = x;
                if (y < y0) y0 = y;
                if (y > y1) y1 = y;
            }
        }
    }
    return x1 < 0 ? null : { x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}

// Objet centré dans une image width x height, marge de 2 %
function compose(img, box, width, height) {
    const src = document.createElement('canvas');
    src.width = img.w;
    src.height = img.h;
    src.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(img.px.buffer), img.w, img.h), 0, 0);

    const out = document.createElement('canvas');
    out.width = width;
    out.height = height;
    const ctx = out.getContext('2d');
    ctx.imageSmoothingQuality = 'high';
    const scale = Math.min(width * 0.98 / box.w, height * 0.98 / box.h);
    const dw = box.w * scale;
    const dh = box.h * scale;
    ctx.drawImage(src, box.x, box.y, box.w, box.h, (width - dw) / 2, (height - dh) / 2, dw, dh);
    return out.toDataURL('image/png');
}

function reply(data) {
    fetch(`https://${RES}/captured`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).catch(() => {});
}

function capture(req) {
    try {
        if (!gl) setup();
        // deux images de rendu pour être sûr que la texture contient l'image actuelle
        requestAnimationFrame(() => requestAnimationFrame(() => {
            try {
                grabFrame();
                const img = grabFrame();
                keyOut(img);
                const box = bounds(img, req.region);
                if (!box) return reply({ error: 'objet introuvable sur l\'image' });
                reply({ url: compose(img, box, req.width || 512, req.height || 288) });
            } catch (e) {
                reply({ error: String(e && e.message || e) });
            }
        }));
    } catch (e) {
        reply({ error: String(e && e.message || e) });
    }
}

window.addEventListener('message', e => {
    const msg = e.data || {};
    if (msg.type === 'capture') capture(msg);
});
