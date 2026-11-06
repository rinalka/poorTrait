// boxRim.glsl - a layer with its edges that face the light lit up (SHADOW BOX, the Layers tab).
//
// Used in place of the plain drawing of a layer onto the canvas. A pixel is on a lit edge when the
// layer is solid there but not a little way towards the light - the edge of a sheet of cut paper
// catching the light. Colours are premultiplied, like the layers' (see Layers), and the tint
// (the layer's opacity) still applies.

#ifdef GL_ES
precision highp float;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;      // the layer
uniform vec2 texOffset;         // one pixel, in texture coordinates
varying vec4 vertColor;
varying vec4 vertTexCoord;

uniform vec2 toLight;           // which way the light is, in pixels (y down the picture)
uniform float width;            // how wide the lit edge is, in pixels
uniform float amount;           // how bright, 0 - 1
uniform float flipY;            // 1, or -1 where the texture is upside down

void main() {
  vec2 px = texOffset * vec2(1.0, flipY);
  vec4 c = texture2D(texture, vertTexCoord.st);
  float beyond = 0.0;
  // a few steps towards the light, so a thin gap doesn't hide the edge
  for (int k = 1; k <= 3; k++) {
    beyond = max(beyond, c.a - texture2D(texture, vertTexCoord.st + toLight * width * float(k) / 3.0 * px).a);
  }
  float rim = clamp(beyond, 0.0, 1.0) * amount;
  c.rgb = min(c.rgb + vec3(rim), vec3(c.a));
  gl_FragColor = c * vertColor;
}
