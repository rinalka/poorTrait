// boxShadow.glsl - the shadow one layer casts on the layers under it (SHADOW BOX, the Layers tab).
//
// It's drawn by putting the layer on the canvas through this shader, just before the layer itself.
// Each pixel looks back towards the light, by `offset`, to see whether the layer is there, and
// averages a disc of samples `radius` across so the shadow's edge is soft - softer the further
// the layer floats above what's under it. The result is a see-through black, as dark as the layer
// is solid there, times `strength`. Colours are premultiplied, like the layers' (see Layers).

#ifdef GL_ES
precision highp float;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;      // the layer
uniform vec2 texOffset;         // one pixel, in texture coordinates
varying vec4 vertTexCoord;

uniform vec2 offset;            // how far the shadow falls, in pixels (y down the picture)
uniform float radius;           // how soft its edge is, in pixels
uniform float strength;         // 0 - 1
uniform float flipY;            // 1, or -1 where the texture is upside down

void main() {
  vec2 px = texOffset * vec2(1.0, flipY);
  vec2 from = vertTexCoord.st - offset * px;
  float a = 0.0;
  // 24 samples spread evenly over a disc (a golden-angle spiral)
  for (int k = 0; k < 24; k++) {
    float r = sqrt((float(k) + 0.5) / 24.0) * radius;
    float t = float(k) * 2.39996;
    a += texture2D(texture, from + vec2(cos(t), sin(t)) * r * px).a;
  }
  gl_FragColor = vec4(0.0, 0.0, 0.0, a / 24.0 * strength);
}
