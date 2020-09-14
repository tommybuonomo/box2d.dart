part of box2d;

/// A convex polygon shape. Polygons have a maximum number of vertices equal to _maxPolygonVertices.
/// In most cases you should not need many vertices for a convex polygon.
class PolygonShape extends Shape {
  /// Dump lots of debug information.
  static const bool _debug = false;

  /// Local position of the shape centroid in parent body frame.
  final Vector2 centroid = Vector2.zero();

  /// The vertices of the shape. Note: use getVertexCount(), not _vertices.length, to get number of
  /// active vertices.
  final List<Vector2> vertices = List<Vector2>.generate(
      Settings.maxPolygonVertices, (i) => Vector2.zero());

  /// The normals of the shape. Note: use getVertexCount(), not _normals.length, to get number of
  /// active normals.
  final List<Vector2> normals = List<Vector2>.generate(
      Settings.maxPolygonVertices, (i) => Vector2.zero());

  /// Number of active vertices in the shape.
  int count = 0;

  PolygonShape() : super(ShapeType.POLYGON) {
    radius = Settings.polygonRadius;
  }

  Shape clone() {
    PolygonShape shape = PolygonShape();
    shape.centroid.setFrom(centroid);
    for (int i = 0; i < shape.normals.length; i++) {
      shape.normals[i].setFrom(normals[i]);
      shape.vertices[i].setFrom(vertices[i]);
    }
    shape.radius = radius;
    shape.count = count;
    return shape;
  }

  /// Create a convex hull from the given array of points. The count must be in the range [3,
  /// Settings.maxPolygonVertices].
  /// @warning the points may be re-ordered, even if they form a convex polygon.
  /// @warning collinear points are removed.
  void set(final List<Vector2> updatedVertices, final int updatedCount) {
    assert(3 <= updatedCount && updatedCount <= Settings.maxPolygonVertices);
    if (updatedCount < 3) {
      setAsBoxXY(1.0, 1.0);
      return;
    }

    int n = Math.min(updatedCount, Settings.maxPolygonVertices);

    // Perform welding and copy vertices into local buffer.
    List<Vector2> ps = List<Vector2>(Settings.maxPolygonVertices);
    int tempCount = 0;
    for (int i = 0; i < n; ++i) {
      Vector2 v = updatedVertices[i];
      bool unique = true;
      for (int j = 0; j < tempCount; ++j) {
        if (MathUtils.distanceSquared(v, ps[j]) < 0.5 * Settings.linearSlop) {
          unique = false;
          break;
        }
      }

      if (unique) {
        ps[tempCount++] = v;
      }
    }

    n = tempCount;
    if (n < 3) {
      // Polygon is degenerate.
      assert(false);
      setAsBoxXY(1.0, 1.0);
      return;
    }

    // Create the convex hull using the Gift wrapping algorithm
    // http://en.wikipedia.org/wiki/Gift_wrapping_algorithm

    // Find the right most point on the hull
    int i0 = 0;
    double x0 = ps[0].x;
    for (int i = 1; i < n; ++i) {
      double x = ps[i].x;
      if (x > x0 || (x == x0 && ps[i].y < ps[i0].y)) {
        i0 = i;
        x0 = x;
      }
    }

    List<int> hull = List<int>(Settings.maxPolygonVertices);
    int m = 0;
    int ih = i0;

    while (true) {
      hull[m] = ih;

      int ie = 0;
      for (int j = 1; j < n; ++j) {
        if (ie == ih) {
          ie = j;
          continue;
        }

        Vector2 r = Vector2.copy(ps[ie])..sub(ps[hull[m]]);
        Vector2 v = Vector2.copy(ps[j])..sub(ps[hull[m]]);
        double c = r.cross(v);
        if (c < 0.0) {
          ie = j;
        }

        // Collinearity check
        if (c == 0.0 && v.length2 > r.length2) {
          ie = j;
        }
      }

      ++m;
      ih = ie;

      if (ie == i0) {
        break;
      }
    }

    this.count = m;

    // Copy vertices.
    for (int i = 0; i < count; ++i) {
      if (vertices[i] == null) {
        vertices[i] = Vector2.zero();
      }
      vertices[i].setFrom(ps[hull[i]]);
    }

    final Vector2 edge = Vector2.zero();

    // Compute normals. Ensure the edges have non-zero length.
    for (int i = 0; i < count; ++i) {
      final int i1 = i;
      final int i2 = i + 1 < count ? i + 1 : 0;
      edge
        ..setFrom(vertices[i2])
        ..sub(vertices[i1]);

      assert(edge.length2 > Settings.EPSILON * Settings.EPSILON);
      edge.scaleOrthogonalInto(-1.0, normals[i]);
      normals[i].normalize();
    }

    // Compute the polygon centroid.
    computeCentroid(vertices, count);
  }

  /// Build vertices to represent an axis-aligned box.
  ///
  /// @param hx the half-width.
  /// @param hy the half-height.
  void setAsBoxXY(final double hx, final double hy) {
    count = 4;
    vertices[0].setValues(-hx, -hy);
    vertices[1].setValues(hx, -hy);
    vertices[2].setValues(hx, hy);
    vertices[3].setValues(-hx, hy);
    normals[0].setValues(0.0, -1.0);
    normals[1].setValues(1.0, 0.0);
    normals[2].setValues(0.0, 1.0);
    normals[3].setValues(-1.0, 0.0);
    centroid.setZero();
  }

  /// Build vertices to represent an oriented box.
  ///
  /// @param hx the half-width.
  /// @param hy the half-height.
  /// @param center the center of the box in local coordinates.
  /// @param angle the rotation of the box in local coordinates.
  void setAsBox(final double hx, final double hy, final Vector2 center,
      final double angle) {
    setAsBoxXY(hx, hy);
    centroid.setFrom(center);

    final Transform xf = Transform.zero();
    xf.p.setFrom(center);
    xf.q.setAngle(angle);

    // Transform vertices and normals.
    for (int i = 0; i < count; ++i) {
      vertices[i].setFrom(Transform.mulVec2(xf, vertices[i]));
      normals[i].setFrom(Rot.mulVec2(xf.q, normals[i]));
    }
  }

  /// Set this as a single edge.
  void setAsEdge(Vector2 v1, Vector2 v2) {
    count = 2;
    vertices[0].setFrom(v1);
    vertices[1].setFrom(v2);
    centroid
      ..setFrom(v1)
      ..add(v2)
      ..scale(0.5);
    normals[0]
      ..setFrom(v2)
      ..sub(v1);
    normals[0].scaleOrthogonalInto(-1.0, normals[0]);
    normals[0].normalize();
    normals[1]
      ..setFrom(normals[0])
      ..negate();
  }

  int getChildCount() {
    return 1;
  }

  bool testPoint(final Transform xf, final Vector2 p) {
    final Rot xfq = xf.q;

    double tempX = p.x - xf.p.x;
    double tempY = p.y - xf.p.y;
    final double pLocalx = xfq.c * tempX + xfq.s * tempY;
    final double pLocaly = -xfq.s * tempX + xfq.c * tempY;

    if (_debug) {
      print("--testPoint debug--");
      print("Vertices: ");
      for (int i = 0; i < count; ++i) {
        print(vertices[i]);
      }
      print("pLocal: $pLocalx, $pLocaly");
    }

    for (int i = 0; i < count; ++i) {
      Vector2 vertex = vertices[i];
      Vector2 normal = normals[i];
      tempX = pLocalx - vertex.x;
      tempY = pLocaly - vertex.y;
      final double dot = normal.x * tempX + normal.y * tempY;
      if (dot > 0.0) {
        return false;
      }
    }

    return true;
  }

  void computeAABB(final AABB aabb, final Transform xf, int childIndex) {
    final Vector2 lower = aabb.lowerBound;
    final Vector2 upper = aabb.upperBound;
    final Vector2 v1 = vertices[0];
    final double xfqc = xf.q.c;
    final double xfqs = xf.q.s;
    final double xfpx = xf.p.x;
    final double xfpy = xf.p.y;
    lower.x = (xfqc * v1.x - xfqs * v1.y) + xfpx;
    lower.y = (xfqs * v1.x + xfqc * v1.y) + xfpy;
    upper.x = lower.x;
    upper.y = lower.y;

    for (int i = 1; i < count; ++i) {
      Vector2 v2 = vertices[i];
      // Vec2 v = Mul(xf, _vertices[i]);
      double vx = (xfqc * v2.x - xfqs * v2.y) + xfpx;
      double vy = (xfqs * v2.x + xfqc * v2.y) + xfpy;
      lower.x = lower.x < vx ? lower.x : vx;
      lower.y = lower.y < vy ? lower.y : vy;
      upper.x = upper.x > vx ? upper.x : vx;
      upper.y = upper.y > vy ? upper.y : vy;
    }

    lower.x -= radius;
    lower.y -= radius;
    upper.x += radius;
    upper.y += radius;
  }

  /// Get the vertex count.
  int getVertexCount() {
    return count;
  }

  /// Get a vertex by index.
  Vector2 getVertex(final int index) {
    assert(0 <= index && index < count);
    return vertices[index];
  }

  double computeDistanceToOut(
      Transform xf, Vector2 p, int childIndex, Vector2 normalOut) {
    double xfqc = xf.q.c;
    double xfqs = xf.q.s;
    double tx = p.x - xf.p.x;
    double ty = p.y - xf.p.y;
    double pLocalx = xfqc * tx + xfqs * ty;
    double pLocaly = -xfqs * tx + xfqc * ty;

    double maxDistance = -double.maxFinite;
    double normalForMaxDistanceX = pLocalx;
    double normalForMaxDistanceY = pLocaly;

    for (int i = 0; i < count; ++i) {
      Vector2 vertex = vertices[i];
      Vector2 normal = normals[i];
      tx = pLocalx - vertex.x;
      ty = pLocaly - vertex.y;
      double dot = normal.x * tx + normal.y * ty;
      if (dot > maxDistance) {
        maxDistance = dot;
        normalForMaxDistanceX = normal.x;
        normalForMaxDistanceY = normal.y;
      }
    }

    double distance;
    if (maxDistance > 0) {
      double minDistanceX = normalForMaxDistanceX;
      double minDistanceY = normalForMaxDistanceY;
      double minDistance2 = maxDistance * maxDistance;
      for (int i = 0; i < count; ++i) {
        Vector2 vertex = vertices[i];
        double distanceVecX = pLocalx - vertex.x;
        double distanceVecY = pLocaly - vertex.y;
        double distance2 =
            (distanceVecX * distanceVecX + distanceVecY * distanceVecY);
        if (minDistance2 > distance2) {
          minDistanceX = distanceVecX;
          minDistanceY = distanceVecY;
          minDistance2 = distance2;
        }
      }
      distance = Math.sqrt(minDistance2);
      normalOut.x = xfqc * minDistanceX - xfqs * minDistanceY;
      normalOut.y = xfqs * minDistanceX + xfqc * minDistanceY;
      normalOut.normalize();
    } else {
      distance = maxDistance;
      normalOut.x = xfqc * normalForMaxDistanceX - xfqs * normalForMaxDistanceY;
      normalOut.y = xfqs * normalForMaxDistanceX + xfqc * normalForMaxDistanceY;
    }

    return distance;
  }

  bool raycast(
      RayCastOutput output, RayCastInput input, Transform xf, int childIndex) {
    final double xfqc = xf.q.c;
    final double xfqs = xf.q.s;
    final Vector2 xfp = xf.p;
    double tempX = input.p1.x - xfp.x;
    double tempY = input.p1.y - xfp.y;
    final double p1x = xfqc * tempX + xfqs * tempY;
    final double p1y = -xfqs * tempX + xfqc * tempY;

    tempX = input.p2.x - xfp.x;
    tempY = input.p2.y - xfp.y;
    final double p2x = xfqc * tempX + xfqs * tempY;
    final double p2y = -xfqs * tempX + xfqc * tempY;

    final double dx = p2x - p1x;
    final double dy = p2y - p1y;

    double lower = 0.0, upper = input.maxFraction;

    int index = -1;

    for (int i = 0; i < count; ++i) {
      Vector2 normal = normals[i];
      Vector2 vertex = vertices[i];
      double tempxn = vertex.x - p1x;
      double tempyn = vertex.y - p1y;
      final double numerator = normal.x * tempxn + normal.y * tempyn;
      final double denominator = normal.x * dx + normal.y * dy;

      if (denominator == 0.0) {
        if (numerator < 0.0) {
          return false;
        }
      } else {
        // Note: we want this predicate without division:
        // lower < numerator / denominator, where denominator < 0
        // Since denominator < 0, we have to flip the inequality:
        // lower < numerator / denominator <==> denominator * lower >
        // numerator.
        if (denominator < 0.0 && numerator < lower * denominator) {
          // Increase lower.
          // The segment enters this half-space.
          lower = numerator / denominator;
          index = i;
        } else if (denominator > 0.0 && numerator < upper * denominator) {
          // Decrease upper.
          // The segment exits this half-space.
          upper = numerator / denominator;
        }
      }

      if (upper < lower) {
        return false;
      }
    }

    assert(0.0 <= lower && lower <= input.maxFraction);

    if (index >= 0) {
      output.fraction = lower;
      Vector2 normal = normals[index];
      Vector2 out = output.normal;
      out.x = xfqc * normal.x - xfqs * normal.y;
      out.y = xfqs * normal.x + xfqc * normal.y;
      return true;
    }
    return false;
  }

  void computeCentroid(final List<Vector2> vs, final int count) {
    assert(count >= 3);

    centroid.setZero();
    double area = 0.0;

    // pRef is the reference point for forming triangles.
    // It's location doesn't change the result (except for rounding error).
    final Vector2 pRef = Vector2.zero();

    final Vector2 e1 = Vector2.zero();
    final Vector2 e2 = Vector2.zero();

    final double inv3 = 1.0 / 3.0;

    for (int i = 0; i < count; ++i) {
      // Triangle vertices.
      final Vector2 p1 = pRef;
      final Vector2 p2 = vs[i];
      final Vector2 p3 = i + 1 < count ? vs[i + 1] : vs[0];

      e1
        ..setFrom(p2)
        ..sub(p1);
      e2
        ..setFrom(p3)
        ..sub(p1);

      final double D = e1.cross(e2);

      final double triangleArea = 0.5 * D;
      area += triangleArea;

      // Area weighted centroid
      e1
        ..setFrom(p1)
        ..add(p2)
        ..add(p3)
        ..scale(triangleArea * inv3);
      centroid.add(e1);
    }

    // Centroid
    assert(area > Settings.EPSILON);
    centroid.scale(1.0 / area);
  }

  void computeMass(final MassData massData, double density) {
    // Polygon mass, centroid, and inertia.
    // Let rho be the polygon density in mass per unit area.
    // Then:
    // mass = rho * int(dA)
    // centroid.x = (1/mass) * rho * int(x * dA)
    // centroid.y = (1/mass) * rho * int(y * dA)
    // I = rho * int((x*x + y*y) * dA)
    //
    // We can compute these integrals by summing all the integrals
    // for each triangle of the polygon. To evaluate the integral
    // for a single triangle, we make a change of variables to
    // the (u,v) coordinates of the triangle:
    // x = x0 + e1x * u + e2x * v
    // y = y0 + e1y * u + e2y * v
    // where 0 <= u && 0 <= v && u + v <= 1.
    //
    // We integrate u from [0,1-v] and then v from [0,1].
    // We also need to use the Jacobian of the transformation:
    // D = cross(e1, e2)
    //
    // Simplification: triangle centroid = (1/3) * (p1 + p2 + p3)
    //
    // The rest of the derivation is handled by computer algebra.

    assert(count >= 3);

    final Vector2 center = Vector2.zero();
    double area = 0.0;
    double I = 0.0;

    // pRef is the reference point for forming triangles.
    // It's location doesn't change the result (except for rounding error).
    final Vector2 s = Vector2.zero();
    // This code would put the reference point inside the polygon.
    for (int i = 0; i < count; ++i) {
      s.add(vertices[i]);
    }
    s.scale(1.0 / count.toDouble());

    final double k_inv3 = 1.0 / 3.0;

    final Vector2 e1 = Vector2.zero();
    final Vector2 e2 = Vector2.zero();

    for (int i = 0; i < count; ++i) {
      // Triangle vertices.
      e1
        ..setFrom(vertices[i])
        ..sub(s);
      e2
        ..setFrom(s)
        ..negate()
        ..add(i + 1 < count ? vertices[i + 1] : vertices[0]);

      final double D = e1.cross(e2);

      final double triangleArea = 0.5 * D;
      area += triangleArea;

      // Area weighted centroid
      center.x += triangleArea * k_inv3 * (e1.x + e2.x);
      center.y += triangleArea * k_inv3 * (e1.y + e2.y);

      final double ex1 = e1.x, ey1 = e1.y;
      final double ex2 = e2.x, ey2 = e2.y;

      double intx2 = ex1 * ex1 + ex2 * ex1 + ex2 * ex2;
      double inty2 = ey1 * ey1 + ey2 * ey1 + ey2 * ey2;

      I += (0.25 * k_inv3 * D) * (intx2 + inty2);
    }

    // Total mass
    massData.mass = density * area;

    // Center of mass
    assert(area > Settings.EPSILON);
    center.scale(1.0 / area);
    massData.center
      ..setFrom(center)
      ..add(s);

    // Inertia tensor relative to the local origin (point s)
    massData.I = I * density;

    // Shift to center of mass then to original body origin.
    massData.I += massData.mass * (massData.center.dot(massData.center));
  }

  /// Validate convexity. This is a very time consuming operation.
  bool validate() {
    for (int i = 0; i < count; ++i) {
      int i1 = i;
      int i2 = i < count - 1 ? i1 + 1 : 0;
      Vector2 p = vertices[i1];
      Vector2 e = Vector2.copy(vertices[i2])..sub(p);

      for (int j = 0; j < count; ++j) {
        if (j == i1 || j == i2) {
          continue;
        }

        Vector2 v = Vector2.copy(vertices[j])..sub(p);
        double c = e.cross(v);
        if (c < 0.0) {
          return false;
        }
      }
    }

    return true;
  }

  /// Get the centroid and apply the supplied transform.
  Vector2 applyToCentroid(final Transform xf) {
    return Transform.mulVec2(xf, centroid);
  }
}
