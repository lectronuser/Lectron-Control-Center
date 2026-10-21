import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Wireframe vehicle drawn from roll / pitch / yaw (degrees), seen from behind and above.
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
  });
  final double roll;
  final double pitch;
  final double yaw;
  final double size;
  final bool plane;
  final String? highlight;

  /// Labels drawn at the arm tips of a multicopter, clockwise from front right.
  final List<String> motorLabels;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _VehiclePainter(roll, pitch, yaw, plane, highlight, motorLabels)),
  );
}

typedef _V3 = (double x, double y, double z);

class _VehiclePainter extends CustomPainter {
  _VehiclePainter(this.roll, this.pitch, this.yaw, this.plane, this.highlight, this.labels);
  final double roll, pitch, yaw;
  final bool plane;
  final String? highlight;
  final List<String> labels;

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

  // camera behind and above the vehicle, looking forward and down
  Offset _project(_V3 p, Size size) {
    final (x, y, z) = p;
    const elev = 25 * math.pi / 180;
    final depth = x * math.cos(elev) - z * math.sin(elev);
    final up = -z * math.cos(elev) - x * math.sin(elev);
    final scale = size.shortestSide * 0.36 * (3.2 / (3.2 + depth * 0.6));
    return Offset(size.width / 2 + y * scale, size.height / 2 - up * scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.muted
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    Offset pr(_V3 p) => _project(_rotate(p), size);

    // ground reference
    final ground = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = -2; i <= 2; i++) {
      canvas.drawLine(_project((i * 0.5, -1.2, 0.9), size), _project((i * 0.5, 1.2, 0.9), size), ground);
      canvas.drawLine(_project((-1.0, i * 0.6, 0.9), size), _project((1.0, i * 0.6, 0.9), size), ground);
    }

    // body box faces
    const hx = 0.45, hy = 0.3, hz = 0.12;
    final corners = <_V3>[
      for (final x in [hx, -hx])
        for (final y in [-hy, hy])
          for (final z in [-hz, hz]) (x, y, z),
    ];
    // index: x(+/-) * 4 + y(-/+) * 2 + z(-/+)
    const faces = {
      'top': [0, 2, 6, 4],
      'bottom': [1, 3, 7, 5],
      'left': [0, 1, 5, 4],
      'right': [2, 3, 7, 6],
      'front': [0, 1, 3, 2],
      'back': [4, 5, 7, 6],
    };
    faces.forEach((name, idx) {
      final path = Path()..addPolygon([for (final i in idx) pr(corners[i])], true);
      final fill = Paint()
        ..color = name == highlight
            ? AppColors.accent.withValues(alpha: 0.55)
            : (name == 'top' ? AppColors.surface2.withValues(alpha: 0.9) : AppColors.surface2.withValues(alpha: 0.45));
      canvas.drawPath(path, fill);
      canvas.drawPath(path, line..color = name == highlight ? AppColors.accent : AppColors.muted);
    });

    if (plane) {
      final wing = Paint()
        ..color = AppColors.text
        ..strokeWidth = 3;
      canvas.drawLine(pr((0.1, -1.3, -0.05)), pr((0.1, 1.3, -0.05)), wing);
      canvas.drawLine(pr((-0.9, -0.45, -0.05)), pr((-0.9, 0.45, -0.05)), wing);
      canvas.drawLine(pr((-0.9, 0, -0.05)), pr((-0.9, 0, -0.45)), wing);
      canvas.drawLine(pr((0.6, 0, 0)), pr((-0.9, 0, 0)), wing);
    } else {
      // X frame arms and rotors, clockwise from front right
      const arms = [(0.75, 0.75), (-0.75, 0.75), (-0.75, -0.75), (0.75, -0.75)];
      final arm = Paint()
        ..color = AppColors.text
        ..strokeWidth = 3;
      for (var i = 0; i < arms.length; i++) {
        final (x, y) = arms[i];
        final tip = pr((x, y, -0.05));
        canvas.drawLine(pr((0, 0, -0.05)), tip, arm);
        final ring = Path();
        for (var k = 0; k <= 24; k++) {
          final a = k / 24 * 2 * math.pi;
          final p = pr((x + 0.32 * math.cos(a), y + 0.32 * math.sin(a), -0.12));
          k == 0 ? ring.moveTo(p.dx, p.dy) : ring.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(ring, line..color = (x > 0 ? AppColors.accent : AppColors.muted));
        if (i < labels.length) {
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
          tp.paint(canvas, tip - Offset(tp.width / 2, tp.height + 8));
        }
      }
    }
    // nose arrow
    final nose = Paint()
      ..color = AppColors.ok
      ..strokeWidth = 3;
    canvas.drawLine(pr((0.45, 0, -0.13)), pr((0.95, 0, -0.13)), nose);
  }

  @override
  bool shouldRepaint(_VehiclePainter old) =>
      old.roll != roll || old.pitch != pitch || old.yaw != yaw || old.highlight != highlight || old.plane != plane;
}

/// Artificial horizon with the heading underneath.
class Horizon extends StatelessWidget {
  const Horizon({super.key, required this.roll, required this.pitch, required this.yaw, this.size = 180});
  final double roll;
  final double pitch;
  final double yaw;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _HorizonPainter(roll, pitch, yaw)),
  );
}

class _HorizonPainter extends CustomPainter {
  _HorizonPainter(this.roll, this.pitch, this.yaw);
  final double roll, pitch, yaw;

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
  bool shouldRepaint(_HorizonPainter old) => old.roll != roll || old.pitch != pitch || old.yaw != yaw;
}
