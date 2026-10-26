import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Shaded vehicle model drawn from roll / pitch / yaw (degrees), seen from behind and above.
/// [highlight] colours one face ('top', 'bottom', 'left', 'right', 'front', 'back') for calibration steps.
class Vehicle3D extends StatelessWidget {
  const Vehicle3D({
    super.key,
    required this.roll,
    required this.pitch,
    required this.yaw,
    this.size = 220,
    this.plane = false,
    this.highlight,
    this.motorLabels = const [],
    this.motors,
  });
  final double roll;
  final double pitch;
  final double yaw;
  final double size;
  final bool plane;
  final String? highlight;

  /// Labels drawn at the arm tips of a multicopter, clockwise from front right.
  final List<String> motorLabels;

  /// Multicopter motors as (x forward, y right, clockwise propeller), any scale; null draws a quad X.
  final List<(double, double, bool)>? motors;

  @override
  // its own layer: the page around it rebuilds with every update, the model is only redrawn when it moves
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _VehiclePainter(roll, pitch, yaw, plane, highlight, motorLabels, motors)),
    ),
  );
}

typedef _V3 = (double x, double y, double z);

/// One flat polygon of the model; a line when it has two points.
class _Face {
  _Face(this.points, this.color, {this.edge, this.width = 1});
  final List<_V3> points;
  final Color color;
  final Color? edge;
  final double width;
}

/// Faces drawn together in their own order, sorted against the other parts by [key].
class _Part {
  _Part(this.key, this.faces);
  final _V3 key;
  final List<_Face> faces;
}

// palette of the model: dark carbon frame, slate canopy, metal motors
const Color _frameDark = Color(0xFF23252F);
const Color _frameLight = Color(0xFF545A70);
const Color _canopyDark = Color(0xFF1B2540);
const Color _canopyLight = Color(0xFF3D5C99);
const Color _motorDark = Color(0xFF2E2E38);
const Color _motorLight = Color(0xFF8A8A9E);
const Color _edge = Color(0x33000000);

class _VehiclePainter extends CustomPainter {
  _VehiclePainter(this.roll, this.pitch, this.yaw, this.plane, this.highlight, this.labels, this.motors);
  final double roll, pitch, yaw;
  final bool plane;
  final String? highlight;
  final List<String> labels;
  final List<(double, double, bool)>? motors;

  static const List<(double, double, bool)> _quadX = [
    (0.7071, 0.7071, false),
    (-0.7071, 0.7071, true),
    (-0.7071, -0.7071, false),
    (0.7071, -0.7071, true),
  ];

  static const double _elev = 28 * math.pi / 180;

  // body frame: x forward, y right, z down (NED)
  _V3 _rotate(_V3 p) {
    final r = roll * math.pi / 180, pt = pitch * math.pi / 180, y = yaw * math.pi / 180;
    var (x0, y0, z0) = p;
    // roll about x
    final y1 = y0 * math.cos(r) - z0 * math.sin(r);
    final z1 = y0 * math.sin(r) + z0 * math.cos(r);
    // pitch about y
    final x2 = x0 * math.cos(pt) + z1 * math.sin(pt);
    final z2 = -x0 * math.sin(pt) + z1 * math.cos(pt);
    // yaw about z
    final x3 = x2 * math.cos(y) - y1 * math.sin(y);
    final y3 = x2 * math.sin(y) + y1 * math.cos(y);
    return (x3, y3, z2);
  }

  // distance from the camera, which is behind and above the vehicle looking forward and down
  static double _depth(_V3 p) => p.$1 * math.cos(_elev) + p.$3 * math.sin(_elev);

  Offset _project(_V3 p, Size size) {
    final (x, y, z) = p;
    final up = x * math.sin(_elev) - z * math.cos(_elev);
    final scale = size.shortestSide * 0.34 * (3.2 / (3.2 + _depth(p) * 0.6));
    return Offset(size.width / 2 + y * scale, size.height * 0.46 - up * scale);
  }

  /// Fill between [dark] and [light] by how much the face looks up or down, after the rotation.
  static Color _shade(List<_V3> pts, Color dark, Color light) {
    if (pts.length < 3) return light;
    final (ax, ay, az) = pts[0];
    final (bx, by, bz) = pts[1];
    final (cx, cy, cz) = pts[2];
    final (ux, uy, uz) = (bx - ax, by - ay, bz - az);
    final (vx, vy, vz) = (cx - ax, cy - ay, cz - az);
    final nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    final len = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (len == 0) return dark;
    // light from above, a little from the front left
    final k = ((nx * 0.3 - ny * 0.35 - nz * 0.89) / len).abs();
    return Color.lerp(dark, light, 0.15 + 0.85 * k)!;
  }

  /// Prism over a 2D outline from [z0] to [z1]; [map] places (u, v, z) in the body frame.
  List<List<_V3>> _slab(List<(double, double)> outline, double z0, double z1, [_V3 Function(_V3)? map]) {
    _V3 m(double u, double v, double z) => map == null ? (u, v, z) : map((u, v, z));
    return [
      [for (final (u, v) in outline) m(u, v, z0)],
      [for (final (u, v) in outline.reversed) m(u, v, z1)],
      for (var i = 0; i < outline.length; i++)
        [
          m(outline[i].$1, outline[i].$2, z0),
          m(outline[(i + 1) % outline.length].$1, outline[(i + 1) % outline.length].$2, z0),
          m(outline[(i + 1) % outline.length].$1, outline[(i + 1) % outline.length].$2, z1),
          m(outline[i].$1, outline[i].$2, z1),
        ],
    ];
  }

  /// Box faces by name; 'bottom' is the face the calibration asks to put on the table.
  Map<String, List<_V3>> _box(double x0, double x1, double y0, double y1, double z0, double z1) => {
    'top': [(x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z0)],
    'bottom': [(x1, y0, z1), (x0, y0, z1), (x0, y1, z1), (x1, y1, z1)],
    'left': [(x1, y0, z0), (x0, y0, z0), (x0, y0, z1), (x1, y0, z1)],
    'right': [(x1, y1, z0), (x1, y1, z1), (x0, y1, z1), (x0, y1, z0)],
    'front': [(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)],
    'back': [(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)],
  };

  static _V3 _mean(List<_V3> pts) {
    var x = 0.0, y = 0.0, z = 0.0;
    for (final (a, b, c) in pts) {
      x += a;
      y += b;
      z += c;
    }
    return (x / pts.length, y / pts.length, z / pts.length);
  }

  List<(double, double)> _circle(double cx, double cy, double r, [int n = 28]) => [
    for (var k = 0; k < n; k++) (cx + r * math.cos(k / n * 2 * math.pi), cy + r * math.sin(k / n * 2 * math.pi)),
  ];

  /// Adds every face of a solid as its own part, shaded by its direction.
  void _solid(List<_Part> parts, List<List<_V3>> faces, Color dark, Color light) {
    for (final f in faces) {
      final w = [for (final p in f) _rotate(p)];
      parts.add(_Part(_mean(w), [_Face(w, _shade(w, dark, light), edge: _edge)]));
    }
  }

  /// Body box, highlighted face kept aside so it can be drawn over everything.
  List<_V3>? _body(List<_Part> parts, Map<String, List<_V3>> box, Color dark, Color light) {
    List<_V3>? marked;
    box.forEach((name, f) {
      final w = [for (final p in f) _rotate(p)];
      if (name == highlight) marked = w;
      parts.add(_Part(_mean(w), [_Face(w, _shade(w, dark, light), edge: _edge)]));
    });
    return marked;
  }

  /// Motor can with its propeller disc and two blades on top.
  /// [below] hangs the motor under the arm, for the lower propeller of a coaxial pair.
  void _rotor(
    List<_Part> parts,
    double x,
    double y,
    double z,
    double radius,
    bool front,
    double blade, {
    bool below = false,
  }) {
    // can: sides sorted far to near, then the cap
    final can = below ? _slab(_circle(x, y, 0.075, 16), 0.02, 0.14) : _slab(_circle(x, y, 0.075, 16), z, z + 0.12);
    final sides = [
      for (final f in can.skip(2)) [for (final p in f) _rotate(p)],
    ]..sort((a, b) => _depth(_mean(b)).compareTo(_depth(_mean(a))));
    final cap = [for (final p in can[0]) _rotate(p)];
    parts.add(
      _Part(_rotate((x, y, z + 0.06)), [
        for (final s in sides) _Face(s, _shade(s, _motorDark, _motorLight)),
        _Face(cap, _shade(cap, _motorDark, _motorLight), edge: _edge),
      ]),
    );
    // propeller: tinted disc, blades and hub
    final tint = front ? AppColors.accent : AppColors.muted;
    final pz = below ? 0.17 : z - 0.03;
    final disc = [for (final (u, v) in _circle(x, y, radius, 40)) _rotate((u, v, pz))];
    final (c, s) = (math.cos(blade), math.sin(blade));
    final (bx, by) = (-s * 0.035, c * 0.035);
    _V3 at(double t, double w) => _rotate((x + c * t + bx * w, y + s * t + by * w, pz - 0.005));
    final blades = [at(-radius * 0.95, -0.6), at(-radius * 0.95, 0.6), at(radius * 0.95, 0.6), at(radius * 0.95, -0.6)];
    final hub = [for (final (u, v) in _circle(x, y, 0.03, 12)) _rotate((u, v, pz - 0.01))];
    parts.add(
      _Part(_rotate((x, y, pz)), [
        _Face(disc, tint.withValues(alpha: 0.16), edge: tint.withValues(alpha: 0.75), width: 1.5),
        _Face(blades, const Color(0xFFD8D8E2), edge: _edge),
        _Face(hub, _motorLight),
      ]),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    Offset pj(_V3 p) => _project(p, size);
    Path path(List<_V3> pts) => Path()..addPolygon([for (final p in pts) pj(p)], true);

    // soft shadow on the ground, which does not turn with the vehicle
    final shadow = [for (final (u, v) in _circle(0, 0, plane ? 1.1 : 1.0, 40)) (u * 0.85, v, 0.8)];
    canvas.drawPath(
      path(shadow),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final parts = <_Part>[];
    List<_V3>? marked;
    final tips = <_V3>[];
    if (plane) {
      // fuselage with the named faces, wings, tail and the spinner disc
      marked = _body(parts, _box(-0.85, 0.6, -0.1, 0.1, -0.09, 0.09), _frameDark, _frameLight);
      _solid(
        parts,
        _slab([(0.22, -1.3), (0.22, 1.3), (0.0, 1.3), (-0.1, 0.12), (-0.1, -0.12), (0.0, -1.3)], -0.1, -0.07),
        _canopyDark,
        _canopyLight,
      );
      _solid(
        parts,
        _slab([(-0.66, -0.5), (-0.66, 0.5), (-0.84, 0.5), (-0.84, -0.5)], -0.08, -0.06),
        _canopyDark,
        _canopyLight,
      );
      _solid(
        parts,
        _slab([(-0.6, -0.08), (-0.84, -0.42), (-0.85, -0.08)], -0.012, 0.012, (p) => (p.$1, p.$3, p.$2)),
        _canopyDark,
        _canopyLight,
      );
      // canopy over the nose
      _solid(
        parts,
        _slab([(0.45, -0.07), (0.45, 0.07), (0.15, 0.07), (0.15, -0.07)], -0.16, -0.09),
        _canopyDark,
        _canopyLight,
      );
      final spinner = [for (final (u, v) in _circle(0, 0, 0.26, 32)) _rotate((0.63, u, v))];
      parts.add(
        _Part(_rotate((0.63, 0, 0)), [
          _Face(
            spinner,
            AppColors.accent.withValues(alpha: 0.16),
            edge: AppColors.accent.withValues(alpha: 0.75),
            width: 1.5,
          ),
        ]),
      );
    } else {
      // landing gear: two legs per side and a skid
      for (final side in [-1.0, 1.0]) {
        final skid = <_Face>[];
        for (final x in [-0.16, 0.16]) {
          skid.add(
            _Face([_rotate((x, side * 0.16, 0.08)), _rotate((x * 1.15, side * 0.24, 0.3))], _frameLight, width: 2.5),
          );
        }
        skid.add(_Face([_rotate((-0.3, side * 0.24, 0.3)), _rotate((0.28, side * 0.24, 0.3))], _frameLight, width: 3));
        parts.add(_Part(_rotate((0, side * 0.22, 0.22)), skid));
      }
      marked = _body(parts, _box(-0.32, 0.32, -0.22, 0.22, -0.07, 0.08), _frameDark, _frameLight);
      // canopy with the nose arrow on top
      final canopy = _box(-0.22, 0.24, -0.15, 0.15, -0.15, -0.07);
      _solid(
        parts,
        [
          for (final e in canopy.entries)
            if (e.key != 'top') e.value,
        ],
        _canopyDark,
        _canopyLight,
      );
      final top = [for (final p in canopy['top']!) _rotate(p)];
      final arrow = [
        for (final p in [(0.21, 0.0, -0.152), (0.05, -0.09, -0.152), (0.09, 0.0, -0.152), (0.05, 0.09, -0.152)])
          _rotate(p),
      ];
      parts.add(
        _Part(_mean(top), [
          _Face(top, _shade(top, _canopyDark, _canopyLight), edge: _edge),
          _Face(arrow, AppColors.ok),
        ]),
      );
      // arms scaled to a common reach, propellers as large as the gaps between motors allow
      final list = motors == null || motors!.isEmpty ? _quadX : motors!;
      final reach = list.map((m) => math.sqrt(m.$1 * m.$1 + m.$2 * m.$2)).fold<double>(0.01, math.max);
      final arms = [for (final (x, y, cw) in list) (x / reach * 0.74, y / reach * 0.74, cw)];
      var gap = double.infinity;
      for (var i = 0; i < arms.length; i++) {
        for (var j = i + 1; j < arms.length; j++) {
          final d = math.sqrt(math.pow(arms[i].$1 - arms[j].$1, 2) + math.pow(arms[i].$2 - arms[j].$2, 2));
          if (d > 0.05) gap = math.min(gap, d);
        }
      }
      final radius = math.min(0.34, gap * 0.48);
      for (var i = 0; i < arms.length; i++) {
        final (x, y, cw) = arms[i];
        // the second motor at the same place is the lower one of a coaxial pair
        final below = arms.take(i).any((a) => (a.$1 - x).abs() < 0.05 && (a.$2 - y).abs() < 0.05);
        final len = math.max(math.sqrt(x * x + y * y), 0.01);
        final (dx, dy) = (x / len, y / len);
        final (nx, ny) = (-dy * 0.04, dx * 0.04);
        final (sx, sy) = (dx * 0.2, dy * 0.2);
        _solid(
          parts,
          _slab([(sx + nx, sy + ny), (x + nx, y + ny), (x - nx, y - ny), (sx - nx, sy - ny)], -0.03, 0.02),
          _frameDark,
          _frameLight,
        );
        _rotor(parts, x, y, -0.12, radius, x > 0.05, (cw ? 1 : -1) * math.pi / 5, below: below);
        tips.add((x, y, below ? 0.2 : -0.15));
      }
    }

    parts.sort((a, b) => _depth(b.key).compareTo(_depth(a.key)));
    for (final part in parts) {
      for (final f in part.faces) {
        if (f.points.length == 2) {
          canvas.drawLine(
            pj(f.points[0]),
            pj(f.points[1]),
            Paint()
              ..color = f.color
              ..strokeWidth = f.width * size.shortestSide / 220
              ..strokeCap = StrokeCap.round,
          );
          continue;
        }
        final p = path(f.points);
        canvas.drawPath(p, Paint()..color = f.color);
        if (f.edge != null) {
          canvas.drawPath(
            p,
            Paint()
              ..color = f.edge!
              ..style = PaintingStyle.stroke
              ..strokeWidth = f.width
              ..strokeJoin = StrokeJoin.round,
          );
        }
      }
    }

    // the face to put down stays visible through the model
    if (marked != null) {
      final p = path(marked);
      canvas.drawPath(p, Paint()..color = AppColors.accent.withValues(alpha: 0.5));
      canvas.drawPath(
        p,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (var i = 0; i < tips.length && i < labels.length; i++) {
      final tip = pj(_rotate(tips[i]));
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFamily: 'Roboto',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final r = math.max(tp.width, tp.height) / 2 + 3;
      canvas.drawCircle(tip, r, Paint()..color = AppColors.surface.withValues(alpha: 0.85));
      tp.paint(canvas, tip - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_VehiclePainter old) =>
      old.roll != roll ||
      old.pitch != pitch ||
      old.yaw != yaw ||
      old.highlight != highlight ||
      old.plane != plane ||
      // the lists are rebuilt on every frame, so compare their contents
      !listEquals(old.labels, labels) ||
      !listEquals(old.motors, motors);
}

/// Artificial horizon with the heading underneath.
class Horizon extends StatelessWidget {
  const Horizon({
    super.key,
    required this.roll,
    required this.pitch,
    required this.yaw,
    this.size = 180,
    this.heading = true,
  });
  final double roll;
  final double pitch;
  final double yaw;
  final double size;

  /// Writes the heading at the bottom; off when a compass shows it next to the horizon.
  final bool heading;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _HorizonPainter(roll, pitch, yaw, heading)),
  );
}

class _HorizonPainter extends CustomPainter {
  _HorizonPainter(this.roll, this.pitch, this.yaw, this.heading);
  final double roll, pitch, yaw;
  final bool heading;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-roll * math.pi / 180);
    final shift = pitch * r / 45;
    canvas.drawRect(Rect.fromLTRB(-2 * r, -2 * r, 2 * r, shift), Paint()..color = const Color(0xFF1E4E8C));
    canvas.drawRect(Rect.fromLTRB(-2 * r, shift, 2 * r, 2 * r), Paint()..color = const Color(0xFF6B4423));
    final ladder = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(-2 * r, shift), Offset(2 * r, shift), ladder..strokeWidth = 2);
    for (var p = -30; p <= 30; p += 10) {
      if (p == 0) continue;
      final y = shift - p * r / 45;
      final w = p % 20 == 0 ? r * 0.35 : r * 0.2;
      canvas.drawLine(Offset(-w, y), Offset(w, y), ladder..strokeWidth = 1.2);
    }
    canvas.restore();
    // aircraft symbol
    final symbol = Paint()
      ..color = AppColors.warn
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c - Offset(r * 0.45, 0), c - Offset(r * 0.12, 0), symbol);
    canvas.drawLine(c + Offset(r * 0.12, 0), c + Offset(r * 0.45, 0), symbol);
    canvas.drawCircle(c, 3, symbol);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = AppColors.borderStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (!heading) return;
    final tp = TextPainter(
      text: TextSpan(
        text: '${yaw.round() % 360}°',
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'Roboto'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy + r - tp.height - 8));
  }

  @override
  bool shouldRepaint(_HorizonPainter old) =>
      old.roll != roll || old.pitch != pitch || old.yaw != yaw || old.heading != heading;
}

/// Heading on a compass rose: N, E, S, W fixed, the arrow turns with the yaw (degrees).
class CompassRose extends StatelessWidget {
  const CompassRose({super.key, required this.yaw, this.size = 180});
  final double yaw;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _RosePainter(yaw)),
  );
}

/// Eight-point name of a heading, e.g. 74° -> E.
String headingName(double yaw) {
  const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return names[((yaw % 360 + 360) % 360 / 45).round() % 8];
}

class _RosePainter extends CustomPainter {
  _RosePainter(this.yaw);
  final double yaw;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    canvas.drawCircle(c, r, Paint()..color = AppColors.surface2);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = AppColors.borderStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // ticks every 10°, longer every 30°
    for (var d = 0; d < 360; d += 10) {
      final a = d * math.pi / 180;
      final dir = Offset(math.sin(a), -math.cos(a));
      final major = d % 30 == 0;
      canvas.drawLine(
        c + dir * (r - (major ? 12 : 6)),
        c + dir * (r - 2),
        Paint()
          ..color = major ? AppColors.muted : AppColors.border
          ..strokeWidth = major ? 2 : 1,
      );
    }
    for (final (label, d) in const [('N', 0), ('E', 90), ('S', 180), ('W', 270)]) {
      final a = d * math.pi / 180;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: label == 'N' ? AppColors.err : AppColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'Roboto',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final at = c + Offset(math.sin(a), -math.cos(a)) * (r - 26);
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }
    // needle: bright arrowhead on the nose side, a thin dim tail behind
    final a = yaw * math.pi / 180;
    final dir = Offset(math.sin(a), -math.cos(a));
    final side = Offset(-dir.dy, dir.dx);
    final tip = c + dir * (r - 34);
    final tail = c - dir * (r * 0.42);
    final base = c + dir * (r * 0.18);
    canvas.drawPath(
      Path()
        ..moveTo((c + side * 4).dx, (c + side * 4).dy)
        ..lineTo((tail + side * 2.5).dx, (tail + side * 2.5).dy)
        ..lineTo((tail - side * 2.5).dx, (tail - side * 2.5).dy)
        ..lineTo((c - side * 4).dx, (c - side * 4).dy)
        ..close(),
      Paint()..color = AppColors.off,
    );
    canvas.drawPath(
      Path()
        ..moveTo((c + side * 4).dx, (c + side * 4).dy)
        ..lineTo((base + side * 4).dx, (base + side * 4).dy)
        ..lineTo((base + side * 11).dx, (base + side * 11).dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo((base - side * 11).dx, (base - side * 11).dy)
        ..lineTo((base - side * 4).dx, (base - side * 4).dy)
        ..lineTo((c - side * 4).dx, (c - side * 4).dy)
        ..close(),
      Paint()..color = AppColors.warn,
    );
    canvas.drawCircle(c, 6, Paint()..color = AppColors.text);
    canvas.drawCircle(c, 3, Paint()..color = AppColors.bg);
  }

  @override
  bool shouldRepaint(_RosePainter old) => old.yaw != yaw;
}
