/* Curfew landing — the living sky.
 *
 * A faithful, dependency-free Canvas2D port of the app's SundownSky. The
 * constants here are transcribed verbatim from the Swift sources so the web
 * renders the *same* sky, not a lookalike:
 *
 *   Curfew/UI/Sundown/SkyMoment.swift     — the moment model + time-of-day curve
 *   Curfew/UI/Sundown/SundownPalette.swift — the gradient keyframes + glow colour
 *   Curfew/UI/Sundown/SundownSky.swift    — the glow / sun / star / vignette layers
 *
 * On the web the moment is driven by two things: the visitor's real local time
 * (the hero reads as the actual time of day) and scroll progress (scrolling
 * carries the sky down toward dusk → night, the ember kindling near the CTAs).
 *
 * Honours Reduce Motion (freezes to a single correct still frame at real time,
 * no scroll-driven descent) and pauses when the tab is hidden. A `?t=<hour>`
 * query param overrides the clock for spot-checking day/golden/dusk/night.
 */
(function () {
  "use strict";

  // ── Palette (SundownPalette + SkyRGB) ──────────────────────────────────────
  // RGB triples in 0…1, matching the Swift Color initialisers exactly.

  function lerp3(a, b, t) {
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  }
  function clamp01(x) {
    return x < 0 ? 0 : x > 1 ? 1 : x;
  }
  function rgba(c, alpha) {
    return (
      "rgba(" +
      Math.round(c[0] * 255) +
      "," +
      Math.round(c[1] * 255) +
      "," +
      Math.round(c[2] * 255) +
      "," +
      alpha +
      ")"
    );
  }

  // Glow endpoints (SkyRGB.glowWarm / .glowEmber), warmed toward ember as the
  // lock time nears.
  var GLOW_WARM = [1.0, 0.85, 0.62];
  var GLOW_EMBER = [0.97, 0.46, 0.26];
  function glowColor(proximity) {
    return lerp3(GLOW_WARM, GLOW_EMBER, clamp01(proximity));
  }

  // Sky keyframes: (light level, four stops dark-crown → warm-horizon). `light`
  // selects and blends the two bracketing frames (SundownPalette.keyframes).
  var STOP_LOCATIONS = [0, 0.45, 0.8, 1.0];
  var KEYFRAMES = [
    { level: 0.1, stops: [[0.06, 0.07, 0.15], [0.13, 0.13, 0.23], [0.26, 0.17, 0.27], [0.42, 0.23, 0.22]] },
    { level: 0.46, stops: [[0.22, 0.23, 0.34], [0.42, 0.34, 0.42], [0.66, 0.42, 0.4], [0.92, 0.56, 0.34]] },
    { level: 0.66, stops: [[0.3, 0.32, 0.42], [0.5, 0.44, 0.48], [0.78, 0.62, 0.5], [0.95, 0.82, 0.64]] },
    { level: 0.95, stops: [[0.4, 0.52, 0.7], [0.62, 0.62, 0.64], [0.82, 0.74, 0.62], [0.95, 0.86, 0.7]] },
  ];

  // SundownPalette.blendedKeyframe(for:)
  function blendedKeyframe(light) {
    if (light <= KEYFRAMES[0].level) return KEYFRAMES[0].stops;
    var last = KEYFRAMES.length - 1;
    if (light >= KEYFRAMES[last].level) return KEYFRAMES[last].stops;
    for (var i = 1; i < KEYFRAMES.length; i++) {
      if (light <= KEYFRAMES[i].level) {
        var lower = KEYFRAMES[i - 1];
        var upper = KEYFRAMES[i];
        var frac = (light - lower.level) / (upper.level - lower.level);
        var out = [];
        for (var s = 0; s < 4; s++) out.push(lerp3(lower.stops[s], upper.stops[s], frac));
        return out;
      }
    }
    return KEYFRAMES[last].stops;
  }

  // ── Moment (SkyMoment) ─────────────────────────────────────────────────────

  // SkyMoment.starOpacity — fades in only after dusk, full in deep night.
  function starOpacity(light) {
    return clamp01((0.42 - light) / 0.42);
  }

  // SundownSky.glowStrength — strongest at the horizon, lifted by proximity.
  function glowStrength(light, proximity) {
    var horizonPeak = 1 - Math.min(Math.abs(light - 0.5) / 0.5, 1);
    return 0.18 + 0.3 * horizonPeak + 0.22 * proximity;
  }

  // SkyMoment.timeOfDay(_:) — literal clock → smooth day/night curve. Deep night
  // around 1am, midday peak around 1pm.
  function timeOfDayMoment(hour) {
    var light = 0.5 - 0.5 * Math.cos((2 * Math.PI * (hour - 1)) / 24);
    return { light: light, rising: hour >= 1 && hour < 13, proximity: 0 };
  }

  // True when the OS is in dark mode. The whole site honours dark mode, so the
  // sky stays dark too — otherwise a daytime visit in dark mode would show a
  // bright hero above a dark page.
  var darkMql = window.matchMedia("(prefers-color-scheme: dark)");

  // The `?t=<hour>` debug override is fixed for the session — parse it once.
  var T_OVERRIDE = (function () {
    var v = new URLSearchParams(window.location.search).get("t");
    return v !== null && v !== "" && !isNaN(parseFloat(v)) ? parseFloat(v) : null;
  })();

  // The visitor's base moment. In OS dark mode the brightness is capped so the
  // sky reads dark at any hour (deep night overnight, dusk by day) rather than
  // sitting bright above the dark content.
  function baseMoment() {
    var moment;
    if (T_OVERRIDE !== null) {
      moment = timeOfDayMoment(T_OVERRIDE);
    } else {
      var now = new Date();
      moment = timeOfDayMoment(now.getHours() + now.getMinutes() / 60);
    }
    if (darkMql.matches && moment.light > 0.32) {
      moment = { light: 0.32, rising: moment.rising, proximity: moment.proximity };
    }
    return moment;
  }

  // Smoothstep for easing the scroll ramps.
  function smoothstep(edge0, edge1, x) {
    var t = clamp01((x - edge0) / (edge1 - edge0));
    return t * t * (3 - 2 * t);
  }

  // Fold scroll progress `s` (0 at top → 1 at footer) into the base moment:
  // the sky descends toward night and the ember kindles across the lower
  // (CTA / Pro / Download) band. Under Reduce Motion the page passes s = 0 so
  // the sky simply reflects real time, still and correct.
  function momentForScroll(base, s) {
    var light = base.light * (1 - s);
    var proximity = smoothstep(0.55, 1.0, s);
    // Keep the hero anchored to the real time-of-day direction; once we begin
    // descending, the sun sets at the horizon (falling / dusk side).
    var rising = s < 0.12 ? base.rising : false;
    return { light: clamp01(light), rising: rising, proximity: clamp01(proximity) };
  }

  // ── Deterministic star field (SundownSky star data) ────────────────────────
  // Same hash as Swift; low 16 bits are identical, so the constellation matches
  // the app pixel-for-pixel at a given size.
  var STAR_COUNT = 60;
  function hashed(index, salt) {
    var v = (Math.imul(index, 2654435761) + salt * 40503) & 0xffff;
    return v / 0xffff;
  }

  // ── Renderer ───────────────────────────────────────────────────────────────

  var canvas = document.getElementById("sky");
  if (!canvas) return;
  var ctx = canvas.getContext("2d");
  if (!ctx) return; // CSS gradient fallback in style.css covers this.

  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  var width = 0;
  var height = 0;
  var scrollMax = 0; // cached in resize() so draw() needn't read scrollHeight (a layout flush) per frame
  var starData = []; // star geometry, rebuilt only on resize
  var gradCache = { light: -1, grad: null }; // base sky gradient, memoised on `light`

  // Star geometry depends only on the hash and the canvas size, so build it on
  // resize and let the draw loop vary only each star's twinkle.
  function buildStars() {
    starData.length = 0;
    for (var n = 0; n < STAR_COUNT; n++) {
      starData.push({
        x: hashed(n, 17) * width,
        y: hashed(n, 53) * height * 0.62,
        r: 0.6 + 1.1 * hashed(n, 91),
        base: 0.35 + 0.55 * hashed(n, 7),
        phase: hashed(n, 131) * 2 * Math.PI,
      });
    }
  }

  function resize() {
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    canvas.style.width = width + "px";
    canvas.style.height = height + "px";
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    scrollMax = document.documentElement.scrollHeight - height;
    buildStars();
    gradCache.light = -1; // size changed → invalidate the cached gradient
  }

  function scrollProgress() {
    if (reduceMotion.matches) return 0; // no scroll-driven descent under Reduce Motion
    return scrollMax > 0 ? clamp01(window.scrollY / scrollMax) : 0;
  }

  function draw(seconds) {
    var moment = momentForScroll(baseMoment(), scrollProgress());
    var light = moment.light;
    var still = reduceMotion.matches;
    var breath = still ? 1 : 0.92 + 0.08 * Math.sin(seconds * 0.4);

    ctx.globalCompositeOperation = "source-over";
    ctx.clearRect(0, 0, width, height);

    // 1 — sky gradient (vertical, four blended stops). Depends only on `light`,
    // so reuse the cached gradient on idle frames (size changes reset the cache).
    if (gradCache.light !== light) {
      var frame = blendedKeyframe(light);
      var g = ctx.createLinearGradient(0, 0, 0, height);
      for (var i = 0; i < 4; i++) g.addColorStop(STOP_LOCATIONS[i], rgba(frame[i], 1));
      gradCache.light = light;
      gradCache.grad = g;
    }
    ctx.fillStyle = gradCache.grad;
    ctx.fillRect(0, 0, width, height);

    var sun = glowColor(moment.proximity);

    // 2 — sun glow (radial bloom from the horizon, screen-blended, breathing)
    ctx.globalCompositeOperation = "screen";
    var glowCenterY = moment.rising ? 0 : height;
    var glowRadius = Math.max(width, height) * 0.85;
    var glowGrad = ctx.createRadialGradient(width / 2, glowCenterY, 0, width / 2, glowCenterY, glowRadius);
    glowGrad.addColorStop(0, rgba(sun, glowStrength(light, moment.proximity) * breath));
    glowGrad.addColorStop(1, rgba(sun, 0));
    ctx.fillStyle = glowGrad;
    ctx.fillRect(0, 0, width, height);

    // 3 — the sun disc, riding the sky by `light`, fading out into night
    var visible = clamp01((light - 0.32) / 0.4);
    if (visible > 0.01) {
      var bob = still ? 0 : Math.sin(seconds * 0.3) * 3;
      var verticalFraction = 1.02 - light * 0.92;
      var cx = width * 0.72;
      var cy = height * verticalFraction + bob;
      var radius = Math.min(width, height) * 0.085;
      // Soft outer bloom + a brighter core, approximating the app's blurred discs.
      var outer = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius * 2.2);
      outer.addColorStop(0, rgba(sun, 0.9 * visible));
      outer.addColorStop(1, rgba(sun, 0));
      ctx.fillStyle = outer;
      ctx.fillRect(0, 0, width, height);
      var core = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius * 1.25);
      core.addColorStop(0, rgba(sun, 0.95 * visible));
      core.addColorStop(0.6, rgba(sun, 0.9 * visible));
      core.addColorStop(1, rgba(sun, 0));
      ctx.fillStyle = core;
      ctx.fillRect(0, 0, width, height);
    }

    // 4 — star field, drawn once the sky has darkened past dusk. Geometry is
    // precomputed (buildStars); only each star's twinkle varies per frame.
    var starsAlpha = starOpacity(light);
    if (starsAlpha > 0.01) {
      ctx.globalCompositeOperation = "source-over";
      for (var n = 0; n < starData.length; n++) {
        var s = starData[n];
        var twinkle = still ? 1 : 0.65 + 0.35 * Math.sin(seconds * 0.8 + s.phase);
        ctx.fillStyle = "rgba(255,255,255," + s.base * twinkle * starsAlpha + ")";
        ctx.beginPath();
        ctx.arc(s.x, s.y, s.r, 0, 2 * Math.PI);
        ctx.fill();
      }
    }

    // 5 — depth vignette
    ctx.globalCompositeOperation = "multiply";
    var vin = Math.min(width, height) * 0.33;
    var vout = Math.max(width, height) * 0.9;
    var vig = ctx.createRadialGradient(width / 2, height / 2, vin, width / 2, height / 2, vout);
    vig.addColorStop(0, "rgba(0,0,0,0)");
    vig.addColorStop(1, "rgba(0,0,0,0.18)");
    ctx.fillStyle = vig;
    ctx.fillRect(0, 0, width, height);
    ctx.globalCompositeOperation = "source-over";
  }

  // ── Loop ────────────────────────────────────────────────────────────────────

  var rafId = null;

  function animate(ts) {
    draw(ts / 1000);
    rafId = window.requestAnimationFrame(animate);
  }

  function stopLoop() {
    if (rafId !== null) {
      window.cancelAnimationFrame(rafId);
      rafId = null;
    }
  }

  // Still surfaces (Reduce Motion, or a hidden tab) draw exactly one correct
  // frame; the live sky runs a single rAF.
  function refresh() {
    stopLoop();
    resize();
    if (reduceMotion.matches || document.hidden) {
      draw(0);
    } else {
      rafId = window.requestAnimationFrame(animate);
    }
  }

  window.addEventListener("resize", refresh);
  document.addEventListener("visibilitychange", refresh);
  if (reduceMotion.addEventListener) reduceMotion.addEventListener("change", refresh);
  if (darkMql.addEventListener) darkMql.addEventListener("change", refresh);
  // Scrolling changes the moment. While the rAF loop runs it already redraws;
  // only when paused (a hidden tab) do we redraw a single frame. Under Reduce
  // Motion the sky doesn't track scroll, so skip. Canvas size is unchanged by
  // scroll, so no resize() here.
  window.addEventListener(
    "scroll",
    function () {
      if (rafId === null && !reduceMotion.matches) draw(0);
    },
    { passive: true }
  );

  refresh();
})();
