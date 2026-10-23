import 'package:flutter/material.dart';

import '../../board/board_data.dart';
import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../vehicle3d.dart';
import '../widgets.dart';
import 'outputs_page.dart';

/// Motors of a frame layout for [Vehicle3D].
List<(double, double, bool)> frameMotors(FrameLayout layout) => [for (final p in layout.positions) (p.$1, p.$2, p.$4)];

/// Picture of a PX4 airframe: the nearest ArduPilot motor layout, a plane, or nothing.
(FrameLayout?, bool plane) _px4Look(int airframe) => switch (airframe) {
  5001 => (apFrameLayouts[(1, 0)], false),
  4041 => (apFrameLayouts[(1, 3)], false),
  6001 => (apFrameLayouts[(2, 1)], false),
  11001 => (apFrameLayouts[(5, 0)], false),
  8001 => (apFrameLayouts[(3, 1)], false),
  12001 => (apFrameLayouts[(4, 1)], false),
  14001 => (apFrameLayouts[(7, 0)] ?? apFrameLayouts[(7, 1)], false),
  2100 || 3000 || 13000 || 13200 => (null, true),
  50000 || 60000 => (null, false),
  _ => (apFrameLayouts[(1, 1)], false),
};

/// Every frame the firmware knows, as pictures; picking one writes it and reboots the board.
class FramePage extends StatelessWidget {
  const FramePage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Frame',
      subtitle: 'Pick the frame of your vehicle; the board reboots to apply it',
      child: c.target == null ? Muted('Connect a vehicle to choose its frame') : FrameSelector(c),
    );
  }
}

/// The frame picker, also used by the frame step of the calibration.
class FrameSelector extends StatelessWidget {
  const FrameSelector(this.c, {super.key});
  final BoardController c;

  Future<void> _pick(BuildContext context, String name, {int? frameClass, int? frameType, int? airframe}) async {
    final ok = await confirm(
      context,
      'Change frame',
      '$name\n\nThe frame is written to the board, then the board reboots and reconnects. Remove the propellers.',
      action: 'Apply and reboot',
    );
    if (ok) c.applyFrame(frameClass: frameClass, frameType: frameType, airframe: airframe);
  }

  @override
  Widget build(BuildContext context) {
    final busy = c.job != null || c.hb?.armed == true;
    final children = <Widget>[];
    if (c.isPx4) {
      final current = c.paramInt('SYS_AUTOSTART');
      children.add(
        _Grid([
          for (final e in px4Airframes.entries)
            () {
              final (layout, plane) = _px4Look(e.key);
              return _FrameTile(
                name: e.value,
                layout: layout,
                plane: plane,
                selected: e.key == current,
                onTap: busy ? null : () => _pick(context, e.value, airframe: e.key),
              );
            }(),
        ]),
      );
    } else if (c.framePrefix == null) {
      children.add(Muted('This vehicle has no multicopter frame to choose (no FRAME_CLASS parameter).'));
    } else {
      final p = c.framePrefix!;
      final current = (c.paramInt('${p}FRAME_CLASS'), c.paramInt('${p}FRAME_TYPE'));
      final classes = <int>{for (final key in apFrameLayouts.keys) key.$1};
      for (final cls in classes) {
        children
          ..add(
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Text(
                (frameClasses[cls] ?? 'Class $cls').toUpperCase(),
                style: const TextStyle(
                  fontSize: 11.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
            ),
          )
          ..add(
            _Grid([
              for (final e in apFrameLayouts.entries.where((e) => e.key.$1 == cls))
                _FrameTile(
                  name: e.value.name,
                  layout: e.value,
                  selected: e.key == current,
                  onTap: busy ? null : () => _pick(context, e.value.name, frameClass: e.key.$1, frameType: e.key.$2),
                ),
            ]),
          )
          ..add(const SizedBox(height: 16));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.hb?.armed == true) ...[Muted('Disarm the vehicle to change the frame'), const SizedBox(height: 10)],
        if (c.status('frame').text.isNotEmpty) ...[StatusLine(c.status('frame')), const SizedBox(height: 10)],
        ...children,
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid(this.tiles);
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 12, runSpacing: 12, children: tiles);
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({required this.name, required this.layout, required this.selected, this.onTap, this.plane = false});
  final String name;
  final FrameLayout? layout;
  final bool plane;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.12) : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        hoverColor: AppColors.hover,
        onTap: selected ? null : onTap,
        child: Container(
          width: 168,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              if (layout != null || plane)
                Vehicle3D(
                  roll: 0,
                  pitch: 0,
                  yaw: 0,
                  size: 140,
                  plane: plane,
                  motors: layout == null ? null : frameMotors(layout!),
                )
              else
                const SizedBox(height: 140, child: Icon(Icons.directions_car_outlined, size: 48, color: AppColors.off)),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
              if (selected) ...[const SizedBox(height: 4), StatusChip('Current', Tone.accent)],
            ],
          ),
        ),
      ),
    );
  }
}
