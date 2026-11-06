// heightAdd.glsl - the paint a tool has just put on a layer, added to that layer's height
// (IMPASTO, the Impasto tab).
//
// Drawn over the layer's height with the layer as it is now as `texture` and as it was before the
// tool painted as `prev`. Wherever they differ, paint went on: the height there is squashed a
// little (a new mark flattens what's under it) and the new paint's thickness put on top. Lighter
// paint stands a little higher than dark, so a mark's own colours give it some texture.
// Blended with (ONE, ONE_MINUS_SRC_ALPHA): new height = rgb + old height * (1 - alpha).

#ifdef GL_ES
precision highp float;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;      // the layer now
uniform sampler2D prev;         // the layer before the tool painted
varying vec4 vertTexCoord;

uniform float thickness;        // how thick a solid mark is, as height (0 - 1)
uniform float squash;           // how much of the height under a solid mark it flattens

void main() {
  vec4 c = texture2D(texture, vertTexCoord.st);
  vec4 d = abs(c - texture2D(prev, vertTexCoord.st));
  float laid = clamp(max(max(d.r, d.g), max(d.b, d.a)) * 1.5, 0.0, 1.0);
  float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11)) / max(c.a, 0.01);
  float h = laid * thickness * (0.6 + 0.8 * lum);
  gl_FragColor = vec4(h, h, h, laid * squash);
}
