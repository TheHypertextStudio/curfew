/* One landscape language for the opening and closing scenes.
   CSS is the complete fallback; the GPU layer contains no page content. */
const vertex = `attribute vec2 position;
void main() { gl_Position = vec4(position, 0.0, 1.0); }`;
const fragment = `precision highp float;
uniform vec2 size;
uniform float time, closing, motion, edge, glow, density, scroll;
uniform vec3 depth;
uniform vec3 sky, ground, distant, sun, lower;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
  return mix(mix(hash(i), hash(i+vec2(1.,0.)), f.x),
    mix(hash(i+vec2(0.,1.)), hash(i+vec2(1.,1.)), f.x), f.y);
}
float contour(float d, vec2 p) {
  float fibers = (noise(p*.65)-.5)*edge + (noise(p*.12)-.5)*edge*1.5;
  return 1.0-smoothstep(-.65, .65, d+fibers);
}
void main() {
  vec2 p = vec2(gl_FragCoord.x/density, size.y-gl_FragCoord.y/density);
  vec2 uv = p/size;
  float mobile = 1.0-step(700.,size.x);
  float drift = sin(time*.08)*motion;
  vec2 center = mix(vec2(.82, .96), vec2(.80,.70), closing);
  center.y = mix(center.y, .84, mobile*(1.-closing));
  center.y += drift*.006 - scroll*depth.x;
  float radius = mix(min(size.x*.20, 300.), clamp(size.x*.10,60.,145.), closing);
  radius = mix(radius, 150., mobile*(1.-closing));
  vec2 fromSun = p-center*size;
  float light = exp(-dot(fromSun/size.y,fromSun/size.y)*3.8);
  float horizon = smoothstep(.2,1.,uv.y);
  vec3 color = mix(sky, lower, closing*horizon);
  color = mix(color, sun, light*glow*(1.-closing*.4)*smoothstep(0.,.18,uv.y));
  float disc = contour(length(fromSun)-radius,p);
  vec3 discColor = mix(sun, mix(sun,sky,.16), smoothstep(-radius,radius,fromSun.y));
  color = mix(color, discColor, disc);
  float farY = mix(.88,.65,closing) - .10*uv.x + .035*sin(uv.x*4.5+1.3);
  float nearY = mix(.82,.88,closing) + mix(.10,-.11,closing)*uv.x + .03*sin(uv.x*5.5-.8);
  farY -= scroll*depth.y;
  nearY -= scroll*depth.z;
  float farMask = contour((farY-uv.y)*size.y,p+vec2(41.,0.));
  float nearMask = contour((nearY-uv.y)*size.y,p+vec2(0.,71.));
  color = mix(color, distant, farMask);
  color = mix(color, ground, nearMask);
  gl_FragColor = vec4(color,1.);
}`;
const root = document.documentElement;
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const forced = matchMedia("(forced-colors: active)");

function mountLandscape(host) {
  if (forced.matches) return;
  const canvas = document.createElement("canvas");
  canvas.setAttribute("aria-hidden", "true");
  const gl = canvas.getContext("webgl", {
    alpha: false,
    antialias: false,
    depth: false,
    powerPreference: "low-power",
  });
  if (!gl) return;
  const shaders = [];
  const program = gl.createProgram();
  let frame = 0,
    visible = false,
    lost = false,
    last = 0;
  const closing = host.classList.contains("footer-landscape");
  function fallback() {
    lost = true;
    cancelAnimationFrame(frame);
    host.dataset.renderer = "fallback";
    canvas.hidden = true;
  }
  try {
    for (const [type, source] of [
      [gl.VERTEX_SHADER, vertex],
      [gl.FRAGMENT_SHADER, fragment],
    ]) {
      const shader = gl.createShader(type);
      shaders.push(shader);
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS))
        throw new Error("Landscape shader unavailable");
      gl.attachShader(program, shader);
    }
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS))
      throw new Error("Landscape program unavailable");
  } catch {
    for (const shader of shaders) gl.deleteShader(shader);
    gl.deleteProgram(program);
    return;
  }
  for (const shader of shaders) gl.deleteShader(shader);
  gl.useProgram(program);
  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(
    gl.ARRAY_BUFFER,
    new Float32Array([-1, -1, 1, -1, -1, 1, -1, 1, 1, -1, 1, 1]),
    gl.STATIC_DRAW,
  );
  const position = gl.getAttribLocation(program, "position");
  gl.enableVertexAttribArray(position);
  gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
  const locations = Object.fromEntries(
    [
      "scroll",
      "depth",
      "density",
      "size",
      "time",
      "closing",
      "motion",
      "edge",
      "glow",
      "sky",
      "ground",
      "distant",
      "sun",
      "lower",
    ].map((name) => [name, gl.getUniformLocation(program, name)]),
  );
  host.append(canvas);
  let width, height, pixelRatio;
  function palette() {
    const styles = getComputedStyle(root);
    const color = (uniform, token) => {
      const hex = styles.getPropertyValue(token).trim().replace("#", "");
      gl.uniform3f(
        locations[uniform],
        ...[0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255),
      );
    };
    color("sky", closing ? "--evening-surface" : "--surface");
    color("ground", closing ? "--footer-surface" : "--chapter-surface");
    color("distant", closing ? "--footer-hill-far" : "--landscape-distant");
    color("sun", "--landscape-sun");
    color("lower", closing ? "--footer-sky" : "--footer-surface");
    gl.uniform1f(locations.closing, Number(closing));
    gl.uniform3f(
      locations.depth,
      ...["sun", "far", "near"].map((layer) =>
        parseFloat(styles.getPropertyValue(`--scene-depth-${layer}`)),
      ),
    );
    gl.uniform1f(
      locations.edge,
      parseFloat(styles.getPropertyValue("--scene-edge-texture")),
    );
    gl.uniform1f(
      locations.glow,
      parseFloat(styles.getPropertyValue("--scene-light-strength")),
    );
  }
  function draw(timestamp = 0) {
    if (lost) return;
    const progress = reduced.matches
      ? 0
      : Math.max(-1, Math.min(1, -host.getBoundingClientRect().top / height));
    gl.uniform1f(locations.scroll, progress);
    gl.uniform2f(locations.size, width, height);
    gl.uniform1f(locations.density, pixelRatio);
    gl.uniform1f(locations.time, reduced.matches ? 0 : timestamp / 1000);
    gl.uniform1f(locations.motion, reduced.matches ? 0 : 1);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
  }
  function resize() {
    if (lost) return;
    width = host.clientWidth;
    height = host.clientHeight;
    if (!width || !height) return;
    pixelRatio = Math.min(
      devicePixelRatio,
      1.5,
      Math.sqrt(2000000 / (width * height)),
    );
    canvas.width = Math.round(width * pixelRatio);
    canvas.height = Math.round(height * pixelRatio);
    gl.viewport(0, 0, canvas.width, canvas.height);
    draw();
    host.dataset.renderer = "webgl";
  }
  function tick(timestamp) {
    if (
      lost ||
      !visible ||
      document.hidden ||
      reduced.matches ||
      forced.matches
    ) {
      frame = 0;
      return;
    }
    if (timestamp - last >= 1000 / 24) {
      draw(timestamp);
      last = timestamp;
    }
    frame = requestAnimationFrame(tick);
  }
  function sync() {
    if (lost) return;
    cancelAnimationFrame(frame);
    frame = 0;
    canvas.hidden = forced.matches;
    host.dataset.renderer = forced.matches ? "fallback" : "webgl";
    palette();
    draw();
    if (visible && !document.hidden && !reduced.matches && !forced.matches)
      frame = requestAnimationFrame(tick);
  }
  palette();
  resize();
  new ResizeObserver(resize).observe(host);
  new IntersectionObserver((entries) => {
    visible = entries[0].isIntersecting;
    sync();
  }).observe(host);
  new MutationObserver(sync).observe(root, {
    attributes: true,
    attributeFilter: ["data-theme"],
  });
  reduced.addEventListener("change", sync);
  forced.addEventListener("change", sync);
  document.addEventListener("visibilitychange", sync);
  canvas.addEventListener("webglcontextlost", fallback);
}
document.querySelectorAll(".sky, .footer-landscape").forEach(mountLandscape);
