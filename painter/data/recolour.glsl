// recolour.glsl - RECOLOUR's pass over each layer as they're combined (the Recolour tab). The
// layers are premultiplied, so the colour is divided by the alpha first and multiplied back after.
//
// Each pixel finds how near it is to each of the palette's colours, and takes their changes -
// a hue shift (degrees), and how much to multiply the saturation and brightness by - each
// counting as much as that colour is near, compared with the nearest one. `reach` is how near
// counts: small, and a pixel takes only its nearest colour's changes; bigger, and they blend.

#ifdef GL_ES
precision highp float;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;
varying vec4 vertColor;
varying vec4 vertTexCoord;

uniform vec3 pal[40];           // the palette, 0 - 1
uniform vec3 adj[40];           // each colour's hue shift, saturation and brightness
uniform int count;
uniform float reach;

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
  vec4 t = texture2D(texture, vertTexCoord.st);
  if (t.a <= 0.0) {
    gl_FragColor = vec4(0.0);
    return;
  }
  vec4 c = vec4(min(t.rgb / t.a, 1.0), t.a);
  float nearest = 100.0;
  for (int k = 0; k < 40; k++) {
    if (k >= count) break;
    vec3 d = c.rgb - pal[k];
    nearest = min(nearest, dot(d, d));
  }
  vec3 sum = vec3(0.0);
  float total = 0.0;
  for (int k = 0; k < 40; k++) {
    if (k >= count) break;
    vec3 d = c.rgb - pal[k];
    float w = exp(-(dot(d, d) - nearest) / (2.0 * reach * reach));
    sum += w * adj[k];
    total += w;
  }
  vec3 a = sum / total;
  vec3 hsv = rgb2hsv(c.rgb);
  hsv.x = fract(hsv.x + a.x / 360.0);
  hsv.y = clamp(hsv.y * a.y, 0.0, 1.0);
  hsv.z = clamp(hsv.z * a.z, 0.0, 1.0);
  gl_FragColor = vec4(hsv2rgb(hsv) * c.a, c.a);
}
