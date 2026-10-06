/// The page `previewPage` fills in (see `preview.dart`).
library;

const previewTemplate = r'''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{{TITLE}} Figma Export</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Schibsted+Grotesk:wght@500;700&family=Source+Sans+3:wght@400;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
/* Layout: a proof sheet. Summary up top, then one row per screen: Flutter's
   render beside the export, same scale, so differences read at a glance. */
:root {
  --bg: #f3f2ee;
  --surface: #fbfaf7;
  --ink: #1d2320;
  --muted: #5d655f;
  --line: #d9d8d1;
  --accent: #2b5d4f;
  --vec: #0f8a6b;
  --txt: #2f63c7;
  --img: #c27c0e;
  --display: 'Schibsted Grotesk', 'Helvetica Neue', Arial, sans-serif;
  --body: 'Source Sans 3', 'Segoe UI', system-ui, sans-serif;
  --mono: 'IBM Plex Mono', ui-monospace, Menlo, monospace;
  --s: 0.62;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #161a18; --surface: #1d2220; --ink: #e8ebe7; --muted: #a2aaa4; --line: #343b37;
    --accent: #8fc9b5; --vec: #3fcf9f; --txt: #7ea6ff; --img: #f0b44c; color-scheme: dark;
  }
}
:root[data-theme="dark"] {
  --bg: #161a18; --surface: #1d2220; --ink: #e8ebe7; --muted: #a2aaa4; --line: #343b37;
  --accent: #8fc9b5; --vec: #3fcf9f; --txt: #7ea6ff; --img: #f0b44c; color-scheme: dark;
}
/*FACES*/
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.5 var(--body); }
[hidden] { display: none !important; }
.wrap { max-width: 1120px; margin: 0 auto; padding-inline: 24px; padding-block: 40px 80px; }
h1, h2 { font-family: var(--display); text-wrap: balance; margin: 0; }
h1 { font-size: clamp(30px, 5vw, 44px); line-height: 1.05; letter-spacing: -0.01em; }
.lede { max-width: 62ch; color: var(--muted); margin: 12px 0 0; }
.lede code, .note code { font-family: var(--mono); font-size: 0.88em; }

.summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 1px;
  background: var(--line); border: 1px solid var(--line); border-radius: 10px; overflow: hidden; margin-top: 28px; }
.stat { background: var(--surface); padding: 14px 16px; }
.stat b { display: block; font: 600 26px/1.1 var(--mono); font-variant-numeric: tabular-nums; }
.stat span { font-size: 13px; color: var(--muted); letter-spacing: 0.02em; }
.stat.v b { color: var(--vec); } .stat.t b { color: var(--txt); } .stat.i b { color: var(--img); }

.toolbar { position: sticky; top: env(safe-area-inset-top, 0px); z-index: 5; display: flex; flex-wrap: wrap; gap: 12px 20px;
  align-items: center; margin-top: 28px; padding: 12px 0; background: var(--bg); border-bottom: 1px solid var(--line); }
.seg { display: inline-flex; border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
.seg input { position: absolute; opacity: 0; pointer-events: none; }
.seg label { padding: 6px 14px; font-size: 14px; cursor: pointer; background: var(--surface); }
.seg input:checked + label { background: var(--accent); color: var(--surface); }
.seg input:focus-visible + label { outline: 2px solid var(--accent); outline-offset: 2px; }
.toggle { display: inline-flex; align-items: center; gap: 8px; font-size: 14px; cursor: pointer; }
.toggle input { accent-color: var(--accent); width: 16px; height: 16px; }
.legend { display: flex; gap: 14px; font-size: 13px; color: var(--muted); }
.legend i { display: inline-block; width: 10px; height: 10px; border: 2px solid; border-radius: 2px; margin-right: 6px; vertical-align: -1px; }
.legend .lv i { border-color: var(--vec); } .legend .lt i { border-color: var(--txt); } .legend .li i { border-color: var(--img); }
.jump { display: flex; flex-wrap: wrap; gap: 6px 14px; margin-top: 16px; font-size: 14px; }
.jump a { color: var(--accent); text-decoration: none; border-bottom: 1px solid transparent; }
.jump a:hover, .jump a:focus-visible { border-bottom-color: currentColor; }

.screen { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 24px 40px; padding-block: 36px; border-bottom: 1px solid var(--line); scroll-margin-top: 72px; }
.screen-head { min-width: 0; }
.screen h2 { font-size: 22px; letter-spacing: -0.005em; }
.chips { list-style: none; padding: 0; margin: 10px 0 0; display: flex; flex-wrap: wrap; gap: 8px; }
.chip { font: 500 13px/1 var(--mono); padding: 6px 9px; border-radius: 6px; border: 1px solid var(--line); background: var(--surface); }
.chip b { font-weight: 600; font-variant-numeric: tabular-nums; }
.chip-v b { color: var(--vec); } .chip-t b { color: var(--txt); } .chip-i b { color: var(--img); }
.chip-s { color: var(--img); border-color: currentColor; }
.note { margin: 14px 0 0; color: var(--muted); max-width: 46ch; font-size: 15px; }

.pair { display: flex; gap: 20px; flex-wrap: wrap; }
.phone-col { margin: 0; display: grid; gap: 8px; }
.phone-col figcaption { font: 600 12px/1 var(--display); letter-spacing: 0.08em; text-transform: uppercase; }
.phone-col figcaption span { font: 400 12px var(--mono); letter-spacing: 0; text-transform: none; color: var(--muted); margin-left: 6px; }
.phone { position: relative; width: calc(390px * var(--s)); height: calc(844px * var(--s)); max-width: 100%;
  border-radius: calc(28px * var(--s)); overflow: hidden; background: #fff; box-shadow: 0 0 0 1px var(--line), 0 10px 30px -18px rgba(0,0,0,.35); }
.shot { display: block; width: 100%; height: 100%; }
.canvas { position: absolute; top: 0; left: 0; width: 390px; height: 844px; transform: scale(var(--s)); transform-origin: 0 0; }
.noshot { display: grid; place-items: center; height: 100%; padding: 20px; text-align: center; color: var(--muted); background: var(--surface); font-size: 14px; }

/* Wipe: the export sits over Flutter's render, revealed up to the slider. */
.wipe-control { display: none; align-items: center; gap: 10px; font-size: 13px; color: var(--muted); grid-column: 2; }
.wipe-control input { accent-color: var(--accent); width: calc(390px * var(--s)); max-width: 100%; }
body.wiping .pair { display: grid; }
body.wiping .phone-col { grid-area: 1 / 1; }
body.wiping .export-col figcaption { visibility: hidden; }
body.wiping .export-col .phone { background: transparent; box-shadow: none; clip-path: inset(0 0 0 var(--x, 50%)); }
body.wiping .export-col .phone::before { content: ''; position: absolute; z-index: 2; top: 0; bottom: 0; left: var(--x, 50%); width: 2px; margin-left: -1px; background: var(--accent); }
body.wiping .wipe-control { display: flex; }

/* Layer outlines: what each export node is in Figma. */
.outlines .canvas .nv { outline: 2px solid var(--vec); outline-offset: -1px; }
.outlines .canvas .nt { outline: 2px solid var(--txt); outline-offset: -1px; }
.outlines .canvas .nf.ni { outline: 2px solid var(--img); outline-offset: -1px; }

.foot { margin-top: 40px; color: var(--muted); font-size: 14px; max-width: 70ch; }

@media (max-width: 760px) {
  .screen { grid-template-columns: minmax(0, 1fr); }
  .wipe-control { grid-column: 1; }
}
@media (max-width: 520px) {
  :root { --s: 0.42; }
  .wrap { padding-inline: 16px; }
  .pair { gap: 12px; }
}
@media (prefers-reduced-motion: reduce) { * { scroll-behavior: auto !important; } }
</style>
</head>
<body>

<div class="wrap">
  <h1>{{TITLE}}, exported to Figma</h1>
  <p class="lede">{{FLUTTER}}The export is drawn from <code>design.json</code>, the file the Figma plugin imports: its frames, auto layout, text, vectors and images, with the app’s own fonts. It is a browser rendering of that file, not Figma itself.</p>

  <div class="summary" role="list">
    <div class="stat" {{WIPE}} role="listitem"><b>{{RENDERED}}/{{SCREENS}}</b><span>screens rendered by Flutter</span></div>
    <div class="stat v" role="listitem"><b>{{VECTORS}}</b><span>vector layers</span></div>
    <div class="stat t" role="listitem"><b>{{TEXTS}}</b><span>editable text layers</span></div>
    <div class="stat i" role="listitem"><b>{{IMAGES}}</b><span>image layers</span></div>
  </div>

  <div class="toolbar">
    <div class="seg" role="radiogroup" aria-label="View" {{WIPE}}>
      <input type="radio" name="view" id="view-side" value="side" checked><label for="view-side">Side by side</label>
      <input type="radio" name="view" id="view-wipe" value="wipe"><label for="view-wipe">Wipe</label>
    </div>
    <label class="toggle" for="outlines"><input type="checkbox" id="outlines"> Show layers</label>
    <div class="legend" aria-hidden="true"><span class="lv"><i></i>Vector</span><span class="lt"><i></i>Text</span><span class="li"><i></i>Image</span></div>
  </div>
  <nav class="jump" id="jump" aria-label="Screens"></nav>

  <!--SECTIONS-->

  <p class="foot">Generated by flutter2figma. Browsers and Figma draw some things differently: check angular gradients, blurs and rotated layers in a real Figma import.</p>
</div>

<script>
// Gradients depend on their box's size, known only after layout. A Figma
// gradientTransform maps the box's unit square to gradient space; its
// inverse places the gradient's handles in pixels.
function f2fRgba(c) {
  return 'rgba(' + Math.round(c.r * 255) + ',' + Math.round(c.g * 255) + ',' +
    Math.round(c.b * 255) + ',' + (c.a == null ? 1 : c.a) + ')';
}
function f2fGradient(p, w, h) {
  var t = p.gradientTransform;
  var a = t[0][0], b = t[0][1], c = t[0][2], d = t[1][0], e = t[1][1], g = t[1][2];
  var det = a * e - b * d;
  if (Math.abs(det) < 1e-12) return null;
  function px(x, y) {
    return [(e * (x - c) - b * (y - g)) / det * w, (-d * (x - c) + a * (y - g)) / det * h];
  }
  var stops = p.gradientStops;
  if (p.type === 'GRADIENT_LINEAR') {
    var p0 = px(0, 0.5), p1 = px(1, 0.5);
    var dx = p1[0] - p0[0], dy = p1[1] - p0[1], len = Math.hypot(dx, dy);
    if (!len) return null;
    var ux = dx / len, uy = dy / len, theta = Math.atan2(dx, -dy);
    var line = Math.abs(w * Math.sin(theta)) + Math.abs(h * Math.cos(theta)) || 1;
    var sx = w / 2 - ux * line / 2, sy = h / 2 - uy * line / 2;
    return 'linear-gradient(' + theta * 180 / Math.PI + 'deg, ' + stops.map(function (s) {
      var qx = p0[0] + s.position * dx, qy = p0[1] + s.position * dy;
      return f2fRgba(s.color) + ' ' + ((qx - sx) * ux + (qy - sy) * uy) / line * 100 + '%';
    }).join(', ') + ')';
  }
  var ctr = px(0.5, 0.5);
  if (p.type === 'GRADIENT_RADIAL') {
    var rx = px(1, 0.5), ry = px(0.5, 1);
    return 'radial-gradient(' + Math.hypot(rx[0] - ctr[0], rx[1] - ctr[1]) + 'px ' +
      Math.hypot(ry[0] - ctr[0], ry[1] - ctr[1]) + 'px at ' + ctr[0] + 'px ' + ctr[1] + 'px, ' +
      stops.map(function (s) { return f2fRgba(s.color) + ' ' + s.position * 100 + '%'; }).join(', ') + ')';
  }
  if (p.type === 'GRADIENT_ANGULAR') {
    // Figma starts toward +x (3 o'clock); CSS conic gradients at 12.
    var st = px(1, 0.5);
    var from = Math.atan2(st[1] - ctr[1], st[0] - ctr[0]) * 180 / Math.PI + 90;
    return 'conic-gradient(from ' + from + 'deg at ' + ctr[0] + 'px ' + ctr[1] + 'px, ' +
      stops.map(function (s) { return f2fRgba(s.color) + ' ' + s.position * 360 + 'deg'; }).join(', ') + ')';
  }
  return null;
}
function f2fBackgrounds() {
  document.querySelectorAll('[data-bg]').forEach(function (el) {
    var w = el.offsetWidth || 1, h = el.offsetHeight || 1, images = [], sizes = [];
    JSON.parse(el.getAttribute('data-bg')).forEach(function (l) {
      var css = l.gradient ? f2fGradient(l.gradient, w, h) : l.css;
      if (css) { images.push(css); sizes.push(l.size); }
    });
    el.style.backgroundImage = images.join(',');
    el.style.backgroundSize = sizes.join(',');
    el.style.backgroundPosition = 'center';
    el.style.backgroundRepeat = 'no-repeat';
  });
}
f2fBackgrounds();
if (document.fonts && document.fonts.ready) document.fonts.ready.then(f2fBackgrounds);
(function () {
  var body = document.body;
  var nav = document.getElementById('jump');
  document.querySelectorAll('.screen').forEach(function (s) {
    var a = document.createElement('a');
    a.href = '#' + s.id;
    a.textContent = s.querySelector('h2').textContent;
    nav.appendChild(a);
    // Screens Flutter didn't render have nothing to wipe against.
    var range = s.querySelector('.wipe-range');
    var col = s.querySelector('.export-col .phone');
    if (range) range.addEventListener('input', function () { col.style.setProperty('--x', range.value + '%'); });
  });
  function setView(v) {
    body.classList.toggle('wiping', v === 'wipe');
    try { localStorage.setItem('f2f-view', v); } catch (e) {}
  }
  document.querySelectorAll('input[name="view"]').forEach(function (r) {
    r.addEventListener('change', function () { if (r.checked) setView(r.value); });
  });
  var outlines = document.getElementById('outlines');
  outlines.addEventListener('change', function () {
    body.classList.toggle('outlines', outlines.checked);
    try { localStorage.setItem('f2f-outlines', outlines.checked ? '1' : ''); } catch (e) {}
  });
  try {
    var v = localStorage.getItem('f2f-view');
    if (v === 'wipe') { document.getElementById('view-wipe').checked = true; setView('wipe'); }
    if (localStorage.getItem('f2f-outlines')) { outlines.checked = true; body.classList.add('outlines'); }
  } catch (e) {}
})();
</script>
</body>
</html>
''';
