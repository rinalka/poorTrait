// impasto.glsl - the finished painting with the light catching the thick paint (the Impasto tab).
//
// Run over the combined canvas. The height of the paint (every layer's added up) gives each pixel
// a slope; a raking light from one side brightens slopes that face it and darkens those that face
// away, with a little shine on the steepest lit ones.

#ifdef GL_ES
precision highp float;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;      // the canvas
uniform vec2 texOffset;         // one pixel, in texture coordinates
varying vec4 vertColor;
varying vec4 vertTexCoord;

uniform sampler2D heights;      // the paint's height (red)
uniform float relief;           // how steep the height looks (0 = no light effect)
uniform float gloss;            // shine
uniform vec3 toLight;           // which way the light is: x, y in pixels (y down the picture), z up
uniform float flipY;            // 1, or -1 where the texture is upside down

float heightAt(vec2 st) {
  return texture2D(heights, st).r;
}

void main() {
  vec2 st = vertTexCoord.st;
  vec4 c = texture2D(texture, st);

  vec2 px = texOffset * vec2(1.0, flipY) * 1.5;
  float dx = heightAt(st + vec2(px.x, 0.0)) - heightAt(st - vec2(px.x, 0.0));
  float dy = heightAt(st + vec2(0.0, px.y)) - heightAt(st - vec2(0.0, px.y));
  float k = relief * 14.0;
  vec3 n = normalize(vec3(-dx * k, -dy * k, 1.0));
  vec3 l = normalize(toLight);
  float shade = dot(n, l) - l.z;             // 0 on flat paint
  c.rgb *= 1.0 + shade * 1.4;
  vec3 r = reflect(-l, n);
  c.rgb += vec3(pow(max(r.z, 0.0), 30.0) * gloss * min(1.0, length(vec2(dx, dy)) * k * 3.0));
  gl_FragColor = vec4(clamp(c.rgb, 0.0, 1.0), c.a) * vertColor;
}
