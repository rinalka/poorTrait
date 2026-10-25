// impasto.glsl - the finished painting with the ground showing through and the light catching
// the thick paint (GROUND and IMPASTO, the Ground and Impasto tabs).
//
// Run over the combined canvas. The height of the paint (every layer's added up) gives each pixel
// a slope; a raking light from one side brightens slopes that face it and darkens those that face
// away, with a little shine on the steepest lit ones. The ground texture is multiplied in as much
// as "shows through the paint" says, and a canvas weave or paper adds its own bumps to the height.

#ifdef GL_ES
precision highp float;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;      // the canvas
uniform vec2 texOffset;         // one pixel, in texture coordinates
varying vec4 vertColor;
varying vec4 vertTexCoord;

uniform sampler2D heights;      // the paint's height (red)
uniform sampler2D groundTex;    // the ground texture: white where it changes nothing
uniform float relief;           // how steep the height looks (0 = no light effect)
uniform float gloss;            // shine
uniform vec3 toLight;           // which way the light is: x, y in pixels (y down the picture), z up
uniform float through;          // how much the ground's texture shows through the paint
uniform float groundBumps;      // how much the ground's texture adds to the height
uniform float flipY;            // 1, or -1 where the texture is upside down

float heightAt(vec2 st) {
  float g = dot(texture2D(groundTex, st).rgb, vec3(0.333));
  return texture2D(heights, st).r + (1.0 - g) * groundBumps * 0.08;
}

void main() {
  vec2 st = vertTexCoord.st;
  vec4 c = texture2D(texture, st);
  c.rgb *= mix(vec3(1.0), texture2D(groundTex, st).rgb, through);

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
