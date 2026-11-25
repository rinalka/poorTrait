// depthAdd.glsl - the shapes of the marks a tool has just made, added to its layer's height (the
// Impasto tab).
//
// Drawn over the layer's height with the marks' shapes as `texture`: how thick the paint is in its
// colour (premultiplied), how solid in its alpha. Where a mark is, most of the height under it is pressed
// flat and its own put on top.
// Blended with (ONE, ONE_MINUS_SRC_ALPHA): new height = rgb + old height * (1 - alpha).

#ifdef GL_ES
precision highp float;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;      // the marks' shapes
varying vec4 vertTexCoord;

uniform float thickness;        // how high the thickest paint is
uniform float pressed;          // how much of the height under a solid mark is flattened

void main() {
  vec4 c = texture2D(texture, vertTexCoord.st);
  gl_FragColor = vec4(c.rgb * thickness, c.a * pressed);
}
