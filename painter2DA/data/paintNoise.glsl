// paintNoise.glsl - draws the paint-by-number picture, with each paint's own noise texture.
//
// It's drawn by putting the "paint map" on screen through this shader. The paint map is a picture
// where every pixel's red channel says which paint that pixel is (paint number * 8 + 4). For each
// pixel the shader looks up that paint's colour and its texture settings, and works out a noise
// value at the pixel's place in the picture - layered noise (fBm) with domain warping, the same
// idea as InfiniteTextureGenerator.java. The noise only makes the paint a little lighter or
// darker and drifts its colour slightly, so every paint stays recognisably its own colour.
//
// Each paint's settings (set from the Paints tab):
//   look1: x = scale (how big the features are), y = warp (how swirly), z = contrast, w = seed
//   look2: x = stretch direction, y = stretch amount (1 = none, more = streaky, like grain or
//          brush strokes), z = persistence (how much fine detail), w = colour drift
//
// The 2D simplex noise is Ian McEwan / Stefan Gustavson's (Ashima Arts, MIT licence).

#ifdef GL_ES
precision highp float;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;      // the paint map
varying vec4 vertTexCoord;

uniform vec2 resolution;        // the picture's size in pixels
uniform vec3 paintColour[32];
uniform vec4 look1[32];
uniform vec4 look2[32];
uniform float textured;         // 1 = paint with its texture, 0 = flat paint

vec3 permute(vec3 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }

float snoise(vec2 v) {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
  vec2 i  = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
  m = m * m;
  m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x  = a0.x  * x0.x   + h.x  * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

// five layers of noise, each twice as fine and `persistence` times as strong as the last
float fbm(vec2 p, float persistence) {
  float total = 0.0, amp = 1.0, sum = 0.0;
  for (int i = 0; i < 5; i++) {
    total += snoise(p) * amp;
    sum += amp;
    p *= 2.0;
    amp *= persistence;
  }
  return total / sum;
}

void main() {
  vec2 uv = vertTexCoord.st;
  int k = int(floor(texture2D(texture, uv).r * 255.0 / 8.0));   // which paint
  vec3 base = paintColour[k];
  if (textured < 0.5) {
    gl_FragColor = vec4(base, 1.0);
    return;
  }
  vec4 a = look1[k];
  vec4 b = look2[k];

  // the pixel's place in the picture, stretched along this paint's direction, scaled and seeded
  vec2 px = uv * resolution;
  vec2 dir = vec2(cos(b.x), sin(b.x));
  vec2 q = vec2(dot(px, dir) / b.y, dot(px, vec2(-dir.y, dir.x))) * a.x + a.w;

  // domain warp: push the place around with two smoother noises, then read the detailed noise there
  vec2 w = vec2(fbm(q + 11.3, 0.5), fbm(q + vec2(5.2, 1.3) + 23.7, 0.5));
  float n = fbm(q + w * a.y, b.z);
  float drift = fbm(q * 0.5 + 41.7, 0.5);

  vec3 c = base * (1.0 + a.z * n);                          // a little lighter or darker
  c = mix(c, c.gbr, b.w * clamp(drift, 0.0, 1.0));          // and a little colour drift
  gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
}
