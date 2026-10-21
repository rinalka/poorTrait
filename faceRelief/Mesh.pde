// Reads the map maker's .obj files and turns them into a PShape.
//
// An .obj file is plain text: "v x y z" lines are the points, "vt u v" where each point is on the
// photo, "vn x y z" which way the surface faces there, and "f ..." lines list the three corners of
// each triangle. The map maker gives every point the same number in all three lists, which keeps
// this simple.

class Mesh {
  float[] xyz, uv, nrm;      // three / two / three numbers per point
  int[] tris;                // three point numbers per triangle, counting from 0
  int points, triangles;
  float aspect = 1;          // height / width
  float depthMid = 0;        // halfway between the nearest and farthest point

  Mesh(String path) {
    String[] lines = loadStrings(path);
    FloatList v = new FloatList(), t = new FloatList(), n = new FloatList();
    IntList f = new IntList();
    for (String line : lines) {
      if (line.length() < 3) continue;
      char a = line.charAt(0), b = line.charAt(1);
      if (a == 'v' && b == ' ') addFloats(v, line, 3);
      else if (a == 'v' && b == 't') addFloats(t, line, 2);
      else if (a == 'v' && b == 'n') addFloats(n, line, 3);
      else if (a == 'f' && b == ' ') {
        String[] parts = splitTokens(line.substring(2), " ");
        // corners in reverse order: turning y over (below) flips which side counts as the front,
        // and Processing lights the back of a triangle as if it faced away from the light
        for (int k = 2; k >= 0; k--) f.append(int(parts[k].substring(0, parts[k].indexOf('/'))) - 1);
      }
    }
    xyz = v.array();
    uv = t.array();
    nrm = n.array();
    tris = f.array();
    points = xyz.length / 3;
    triangles = tris.length / 3;

    // .obj has y going up, Processing has y going down - turn it over (and its normals with it)
    float minY = 1e9, maxY = -1e9, minZ = 1e9, maxZ = -1e9;
    for (int i = 0; i < points; i++) {
      xyz[i * 3 + 1] = -xyz[i * 3 + 1];
      nrm[i * 3 + 1] = -nrm[i * 3 + 1];
      minY = min(minY, xyz[i * 3 + 1]);
      maxY = max(maxY, xyz[i * 3 + 1]);
      minZ = min(minZ, xyz[i * 3 + 2]);
      maxZ = max(maxZ, xyz[i * 3 + 2]);
    }
    aspect = maxY - minY;          // the photo is 1 wide
    depthMid = (minZ + maxZ) / 2;
  }

  void addFloats(FloatList list, String line, int count) {
    String[] parts = splitTokens(line, " ");
    for (int k = 1; k <= count; k++) list.append(float(parts[k]));
  }

  // the model as one shape - with `tex` on it, or plain clay if tex is null
  PShape toShape(PImage tex) {
    PShape s = createShape();
    s.beginShape(TRIANGLES);
    s.noStroke();
    if (tex != null) {
      s.textureMode(NORMAL);
      s.texture(tex);
      s.fill(255);
    } else {
      s.fill(clay);
    }
    for (int i = 0; i < tris.length; i++) {
      int p = tris[i];
      s.normal(nrm[p * 3], nrm[p * 3 + 1], nrm[p * 3 + 2]);
      if (tex != null) s.vertex(xyz[p * 3], xyz[p * 3 + 1], xyz[p * 3 + 2], uv[p * 2], 1 - uv[p * 2 + 1]);
      else s.vertex(xyz[p * 3], xyz[p * 3 + 1], xyz[p * 3 + 2]);
    }
    s.endShape();
    return s;
  }
}
