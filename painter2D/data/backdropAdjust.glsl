// backdropAdjust.glsl - the backdrop as drawn (the Backdrop tab): its colours changed by the
// BACKDROP box - a hue shift, and the saturation and brightness multiplied - then faded towards
// white by SETUP 3's "strength".

#ifdef GL_ES
precision highp float;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;
varying vec4 vertColor;
varying vec4 vertTexCoord;

uniform float hueShift;         // in turns: 0.5 = half way round
uniform float sat;              // saturation multiplied by this
uniform float bri;              // brightness multiplied by this
uniform float strength;         // 0 = white, 1 = the backdrop as it is

vec3 rgb2hsv(vec3 c) {
  vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
  vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
  vec3 c = texture2D(texture, vertTexCoord.st).rgb;
  vec3 h = rgb2hsv(c);
  h.x = fract(h.x + hueShift);
  h.y = clamp(h.y * sat, 0.0, 1.0);
  h.z = clamp(h.z * bri, 0.0, 1.0);
  c = mix(vec3(1.0), hsv2rgb(h), strength);
  gl_FragColor = vec4(c, 1.0);
}
