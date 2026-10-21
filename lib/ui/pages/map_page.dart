import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/board_controller.dart';
import '../../core/mission.dart';
import '../../core/models.dart';
import '../../core/zones.dart';
import '../i18n.dart';
import '../map_tiles.dart';
import '../theme.dart';
import '../widgets.dart';

enum _Tool { none, waypoints, fencePolygon, fenceCircle, rally, zonePolygon, zoneCircle }

/// What is drawn on the map; kept while other pages are shown.
class MapSession {
  final List<MissionItem> mission = [];
  MissionItem? home;
  final List<MissionItem> fence = [];
  final List<MissionItem> rally = [];
  final List<LatLng> drawing = [];
  MapStyle style = MapStyle.satellite;
  bool follow = true;
  int tab = 0;
  double defaultAlt = 30;
  double circleRadius = 100;
  bool zoneAllowed = false;
  String status = '';
  bool busy = false;
}

final Expando<MapSession> _sessions = Expando();
MapSession mapSessionFor(BoardController c) => _sessions[c] ??= MapSession();

const _wpFiles = XTypeGroup(label: 'Waypoints', extensions: ['waypoints', 'txt']);
const _zoneFiles = XTypeGroup(label: 'GeoJSON / KML', extensions: ['geojson', 'json', 'kml']);

/// Vehicle on the map, missions, geofence, rally points, flight-restriction zones and offline maps.
class MapPage extends StatefulWidget {
  const MapPage(this.c, {super.key});
  final BoardController c;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _map = MapController();
  final GlobalKey _mapKey = GlobalKey();
  _Tool _tool = _Tool.none;
  int? _dragging;
  String _cacheSize = '';
  double? _progress;
  bool _cancelDownload = false;
  int _maxZoom = 17;

  BoardController get c => widget.c;
  MapSession get s => mapSessionFor(c);

  @override
  void initState() {
    super.initState();
    if (c.home == null && c.target != null) c.requestHome();
    unawaited(_refreshCache());
  }

  Future<void> _refreshCache() async {
    final size = await tileCacheSize();
    if (mounted) setState(() => _cacheSize = '${(size / (1 << 20)).toStringAsFixed(1)} MB');
  }

  LatLng get _center {
    final p = c.position;
    if (p != null) return LatLng(p.$1, p.$2);
    final h = c.home;
    if (h != null) return LatLng(h.$1, h.$2);
    return const LatLng(39.92, 32.85);
  }

  LatLng _latLngAt(Offset global) {
    final box = _mapKey.currentContext!.findRenderObject()! as RenderBox;
    return _map.camera.screenOffsetToLatLng(box.globalToLocal(global));
  }

  Future<void> _run(String what, Future<void> Function(MissionClient mc) op) async {
    if (c.target == null) {
      setState(() => s.status = tr('Connect a vehicle first'));
      return;
    }
    final mc = MissionClient(c);
    setState(() {
      s.busy = true;
      s.status = what;
    });
    try {
      await op(mc);
    } catch (e) {
      s.status = '$what: $e';
    } finally {
      mc.dispose();
      if (mounted) setState(() => s.busy = false);
    }
  }

  void _onTap(LatLng p) {
    setState(() {
      switch (_tool) {
        case _Tool.waypoints:
          s.mission.add(MissionItem(command: MavCmd.waypoint, lat: p.latitude, lon: p.longitude, alt: s.defaultAlt));
        case _Tool.fencePolygon || _Tool.zonePolygon:
          s.drawing.add(p);
        case _Tool.fenceCircle:
          s.fence.add(
            MissionItem(
              command: MavCmd.fenceCircleInclusion,
              frame: frameGlobal,
              p1: s.circleRadius,
              lat: p.latitude,
              lon: p.longitude,
            ),
          );
          _tool = _Tool.none;
        case _Tool.rally:
          s.rally.add(MissionItem(command: MavCmd.rallyPoint, lat: p.latitude, lon: p.longitude, alt: s.defaultAlt));
        case _Tool.zoneCircle:
          c.zones.own.add(
            Zone(
              name: '${s.zoneAllowed ? tr('Allowed') : tr('No-fly')} ${c.zones.own.length + 1}',
              allowed: s.zoneAllowed,
              center: (p.latitude, p.longitude),
              radius: s.circleRadius,
            ),
          );
          c.zones.save();
          _tool = _Tool.none;
        case _Tool.none:
          break;
      }
    });
  }

  void _finishPolygon() {
    if (s.drawing.length < 3) return;
    setState(() {
      if (_tool == _Tool.fencePolygon) {
        for (final p in s.drawing) {
          s.fence.add(
            MissionItem(
              command: MavCmd.fencePolygonInclusion,
              frame: frameGlobal,
              p1: s.drawing.length.toDouble(),
              lat: p.latitude,
              lon: p.longitude,
            ),
          );
        }
      } else {
        c.zones.own.add(
          Zone(
            name: '${s.zoneAllowed ? tr('Allowed') : tr('No-fly')} ${c.zones.own.length + 1}',
            allowed: s.zoneAllowed,
            polygon: [for (final p in s.drawing) (p.latitude, p.longitude)],
          ),
        );
        c.zones.save();
      }
      s.drawing.clear();
      _tool = _Tool.none;
    });
  }

  double _missionDistance() {
    var total = 0.0;
    LatLng? last = s.home == null ? null : LatLng(s.home!.lat, s.home!.lon);
    for (final it in s.mission) {
      if (!it.hasPosition || (it.lat == 0 && it.lon == 0)) continue;
      final p = LatLng(it.lat, it.lon);
      if (last != null && last.latitude != 0) {
        total += distanceM(last.latitude, last.longitude, p.latitude, p.longitude);
      }
      last = p;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final pos = c.position;
    if (s.follow && pos != null && _tool == _Tool.none && _dragging == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _map.move(LatLng(pos.$1, pos.$2), _map.camera.zoom);
        } catch (_) {
          // the map is not laid out yet
        }
      });
    }
    final restricted = pos == null ? null : c.zones.restrictedAt(pos.$1, pos.$2);
    return PageFrame(
      title: tr('Map'),
      subtitle: tr('Vehicle, missions, geofence, rally points, flight-restriction zones and offline maps'),
      scroll: false,
      actions: [
        SegmentedButton<MapStyle>(
          showSelectedIcon: false,
          segments: [for (final st in MapStyle.values) ButtonSegment(value: st, label: Text(tr(mapStyleNames[st]!)))],
          selected: {s.style},
          onSelectionChanged: (v) => setState(() => s.style = v.first),
        ),
        FilterChip(label: Text(tr('Follow')), selected: s.follow, onSelected: (v) => setState(() => s.follow = v)),
        OutlinedButton.icon(
          onPressed: c.target == null
              ? null
              : () async {
                  if (await confirm(
                    context,
                    tr('Return to launch'),
                    tr('Switch the vehicle to RTL now?'),
                    action: 'RTL',
                  )) {
                    c.returnToLaunch();
                  }
                },
          icon: const Icon(Icons.home, size: 16),
          label: Text(tr('Return to launch')),
        ),
        OutlinedButton.icon(
          onPressed: c.target == null
              ? null
              : () async {
                  final center = _map.camera.center;
                  if (await confirm(
                    context,
                    tr('Set home'),
                    '${tr('Set home at the map centre?')}\n${center.latitude.toStringAsFixed(6)}, ${center.longitude.toStringAsFixed(6)}',
                  )) {
                    c.setHome(center.latitude, center.longitude, c.home?.$3 ?? 0);
                    Timer(const Duration(seconds: 1), () => c.requestHome());
                  }
                },
          icon: const Icon(Icons.add_home_outlined, size: 16),
          label: Text(tr('Set home here')),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (restricted != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.err.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${tr('The vehicle is inside a restricted area:')} ${restricted.name}',
                style: const TextStyle(color: AppColors.err),
              ),
            ),
          if (s.status.isNotEmpty || s.busy)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  if (s.busy) ...[
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Muted(s.status, size: 12.5)),
                ],
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(borderRadius: BorderRadius.circular(12), child: _mapView()),
                ),
                const SizedBox(width: 12),
                SizedBox(width: 370, child: _panel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapView() {
    final pos = c.position;
    final home = c.home;
    final missionPoints = [
      if (home != null) LatLng(home.$1, home.$2),
      for (final it in s.mission)
        if (it.hasPosition && !(it.lat == 0 && it.lon == 0)) LatLng(it.lat, it.lon),
    ];
    final polygons = <Polygon>[];
    final circles = <CircleMarker>[];
    // fence: consecutive polygon vertices form one polygon
    var i = 0;
    while (i < s.fence.length) {
      final it = s.fence[i];
      if (it.command == MavCmd.fencePolygonInclusion || it.command == MavCmd.fencePolygonExclusion) {
        final n = math.max(3, it.p1.round());
        final pts = [for (var k = i; k < math.min(i + n, s.fence.length); k++) LatLng(s.fence[k].lat, s.fence[k].lon)];
        final incl = it.command == MavCmd.fencePolygonInclusion;
        polygons.add(
          Polygon(
            points: pts,
            color: (incl ? AppColors.ok : AppColors.err).withValues(alpha: 0.10),
            borderColor: incl ? AppColors.ok : AppColors.err,
            borderStrokeWidth: 2,
          ),
        );
        i += n;
      } else {
        if (it.command == MavCmd.fenceCircleInclusion || it.command == MavCmd.fenceCircleExclusion) {
          final incl = it.command == MavCmd.fenceCircleInclusion;
          circles.add(
            CircleMarker(
              point: LatLng(it.lat, it.lon),
              radius: it.p1,
              useRadiusInMeter: true,
              color: (incl ? AppColors.ok : AppColors.err).withValues(alpha: 0.10),
              borderColor: incl ? AppColors.ok : AppColors.err,
              borderStrokeWidth: 2,
            ),
          );
        }
        i++;
      }
    }
    for (final z in c.zones.all) {
      final color = z.allowed ? const Color(0xFF22C55E) : const Color(0xFFDC2626);
      if (z.center != null) {
        circles.add(
          CircleMarker(
            point: LatLng(z.center!.$1, z.center!.$2),
            radius: z.radius,
            useRadiusInMeter: true,
            color: color.withValues(alpha: 0.12),
            borderColor: color.withValues(alpha: 0.6),
            borderStrokeWidth: 1.5,
          ),
        );
      } else {
        polygons.add(
          Polygon(
            points: [for (final p in z.polygon) LatLng(p.$1, p.$2)],
            color: color.withValues(alpha: 0.12),
            borderColor: color.withValues(alpha: 0.6),
            borderStrokeWidth: 1.5,
          ),
        );
      }
    }
    final hud = c.msgStats['VFR_HUD']?.last;
    final dist = pos != null && home != null ? distanceM(pos.$1, pos.$2, home.$1, home.$2) : null;
    return Stack(
      children: [
        FlutterMap(
          key: _mapKey,
          mapController: _map,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 17,
            maxZoom: 21,
            onTap: (_, p) => _onTap(p),
            onPositionChanged: (_, gesture) {
              if (gesture && s.follow) setState(() => s.follow = false);
            },
          ),
          children: [
            tileLayer(s.style),
            CircleLayer(circles: circles),
            PolygonLayer(polygons: polygons),
            if (c.track.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [for (final p in c.track) LatLng(p.$1, p.$2)],
                    color: AppColors.warn.withValues(alpha: 0.8),
                    strokeWidth: 2,
                  ),
                ],
              ),
            if (missionPoints.length > 1)
              PolylineLayer(
                polylines: [Polyline(points: missionPoints, color: Colors.white, strokeWidth: 2.5)],
              ),
            if (s.drawing.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [...s.drawing, if (s.drawing.length > 2) s.drawing.first],
                    color: AppColors.accent,
                    strokeWidth: 2,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (home != null)
                  Marker(
                    point: LatLng(home.$1, home.$2),
                    width: 30,
                    height: 30,
                    child: const Icon(Icons.home, color: AppColors.ok, size: 26),
                  ),
                for (var k = 0; k < s.mission.length; k++)
                  if (s.mission[k].hasPosition && !(s.mission[k].lat == 0 && s.mission[k].lon == 0))
                    Marker(
                      point: LatLng(s.mission[k].lat, s.mission[k].lon),
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        onPanStart: (_) => setState(() => _dragging = k),
                        onPanUpdate: (d) {
                          final p = _latLngAt(d.globalPosition);
                          setState(() {
                            s.mission[k].lat = p.latitude;
                            s.mission[k].lon = p.longitude;
                          });
                        },
                        onPanEnd: (_) => setState(() => _dragging = null),
                        child: Container(
                          decoration: BoxDecoration(
                            color: s.mission[k].command == MavCmd.land ? AppColors.err : AppColors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${k + 1}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                for (final r in s.rally)
                  Marker(
                    point: LatLng(r.lat, r.lon),
                    width: 26,
                    height: 26,
                    child: const Icon(Icons.flag_circle, color: AppColors.warn, size: 24),
                  ),
                for (final p in s.drawing)
                  Marker(
                    point: p,
                    width: 10,
                    height: 10,
                    child: Container(
                      decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                    ),
                  ),
                if (pos != null)
                  Marker(
                    point: LatLng(pos.$1, pos.$2),
                    width: 40,
                    height: 40,
                    child: Transform.rotate(
                      angle: (pos.$4 ?? c.attitude?.$3 ?? 0) * math.pi / 180,
                      child: Icon(
                        Icons.navigation,
                        color: c.hb?.armed == true ? AppColors.err : AppColors.warn,
                        size: 36,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DefaultTextStyle.merge(
              style: monoStyle.copyWith(fontSize: 12, color: Colors.white),
              child: Wrap(
                spacing: 14,
                children: [
                  Text(c.hb?.mode ?? '-'),
                  Text(c.hb?.armed == true ? tr('ARMED') : tr('Disarmed')),
                  if (hud != null) Text('${hud.d('groundspeed').toStringAsFixed(1)} m/s'),
                  if (hud != null) Text('${hud.i('heading')}°'),
                  if (pos != null) Text('${pos.$3.toStringAsFixed(1)} m'),
                  if (dist != null) Text('${tr('home')} ${dist.toStringAsFixed(0)} m'),
                ],
              ),
            ),
          ),
        ),
        if (_tool != _Tool.none)
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(switch (_tool) {
                _Tool.waypoints => tr('Click the map to add waypoints'),
                _Tool.fencePolygon || _Tool.zonePolygon => tr('Click the corners, then Finish polygon'),
                _Tool.fenceCircle || _Tool.zoneCircle => tr('Click the centre of the circle'),
                _Tool.rally => tr('Click the map to add rally points'),
                _Tool.none => '',
              }, style: const TextStyle(color: Colors.white)),
            ),
          ),
      ],
    );
  }

  Widget _toolButton(_Tool tool, String label, IconData icon) => FilterChip(
    avatar: Icon(icon, size: 16),
    label: Text(tr(label), style: const TextStyle(fontSize: 12)),
    selected: _tool == tool,
    onSelected: (on) => setState(() {
      _tool = on ? tool : _Tool.none;
      s.drawing.clear();
    }),
  );

  Widget _panel() {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity(horizontal: -3, vertical: -2)),
                segments: [
                  for (final (i, t) in const ['Mission', 'Fence', 'Rally', 'Zones', 'Offline'].indexed)
                    ButtonSegment(
                      value: i,
                      label: Text(tr(t), style: const TextStyle(fontSize: 12)),
                    ),
                ],
                selected: {s.tab},
                onSelectionChanged: (v) => setState(() {
                  s.tab = v.first;
                  _tool = _Tool.none;
                  s.drawing.clear();
                }),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  switch (s.tab) {
                    0 => _missionPanel(),
                    1 => _fencePanel(),
                    2 => _rallyPanel(),
                    3 => _zonesPanel(),
                    _ => _offlinePanel(),
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(double value, ValueChanged<double> onChanged, {double width = 70, String? suffix}) => SizedBox(
    width: width,
    child: SyncedField(
      value: formatG(value),
      onChanged: (t) {
        final v = double.tryParse(t.replaceAll(',', '.'));
        if (v != null) onChanged(v);
      },
      hint: suffix,
    ),
  );

  Widget _missionPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _toolButton(_Tool.waypoints, 'Add waypoints on map', Icons.add_location_alt_outlined),
            OutlinedButton(
              onPressed: () =>
                  setState(() => s.mission.insert(0, MissionItem(command: MavCmd.takeoff, alt: s.defaultAlt))),
              child: Text('+ ${tr('Takeoff')}'),
            ),
            OutlinedButton(
              onPressed: () => setState(() => s.mission.add(MissionItem(command: MavCmd.rtl))),
              child: const Text('+ RTL'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Muted(tr('Default altitude')),
            const SizedBox(width: 8),
            _numberField(s.defaultAlt, (v) => s.defaultAlt = v),
            const SizedBox(width: 4),
            const Muted('m'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${s.mission.length} ${tr('items')}  ·  ${(_missionDistance() / 1000).toStringAsFixed(2)} km',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        for (var k = 0; k < s.mission.length; k++) _missionRow(k),
        const Divider(height: 20),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilledButton(
              onPressed: s.busy || s.mission.isEmpty
                  ? null
                  : () => _run(tr('Uploading mission…'), (mc) async {
                      final home = c.home;
                      await mc.upload(
                        s.mission,
                        home: home == null
                            ? null
                            : MissionItem(
                                command: MavCmd.waypoint,
                                frame: frameGlobal,
                                lat: home.$1,
                                lon: home.$2,
                                alt: home.$3,
                              ),
                      );
                      s.status = '${tr('Mission uploaded')}: ${s.mission.length} ${tr('items')}';
                    }),
              child: Text(tr('Upload')),
            ),
            OutlinedButton(
              onPressed: s.busy
                  ? null
                  : () => _run(tr('Downloading mission…'), (mc) async {
                      final (items, home) = await mc.download();
                      setState(() {
                        s.mission
                          ..clear()
                          ..addAll(items);
                        s.home = home;
                      });
                      s.status = '${tr('Mission downloaded')}: ${items.length} ${tr('items')}';
                    }),
              child: Text(tr('Download')),
            ),
            OutlinedButton(
              onPressed: s.busy
                  ? null
                  : () async {
                      if (!await confirm(
                        context,
                        tr('Clear mission'),
                        tr('Delete the mission stored on the vehicle?'),
                        danger: true,
                      )) {
                        return;
                      }
                      await _run(tr('Clearing…'), (mc) async {
                        await mc.clear();
                        s.status = tr('Mission cleared on the vehicle');
                      });
                    },
              child: Text(tr('Clear on vehicle')),
            ),
            OutlinedButton(onPressed: s.mission.isEmpty ? null : _saveWaypoints, child: Text(tr('Save…'))),
            OutlinedButton(onPressed: _openWaypoints, child: Text(tr('Open…'))),
            TextButton(onPressed: s.mission.isEmpty ? null : () => setState(s.mission.clear), child: Text(tr('New'))),
          ],
        ),
      ],
    );
  }

  Widget _missionRow(int k) {
    final it = s.mission[k];
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('${k + 1}', style: monoStyle.copyWith(color: AppColors.muted)),
          ),
          Expanded(
            child: EnumDropdown(
              options: {
                ...missionCommands.map((k, v) => MapEntry(k, tr(v))),
                if (!missionCommands.containsKey(it.command)) it.command: 'CMD ${it.command}',
              },
              value: it.command,
              onChanged: (v) => setState(() => it.command = v),
            ),
          ),
          const SizedBox(width: 4),
          if (it.command != MavCmd.rtl) _numberField(it.alt, (v) => it.alt = v, width: 60, suffix: 'm'),
          if (it.command == MavCmd.loiterTime) ...[
            const SizedBox(width: 4),
            _numberField(it.p1, (v) => it.p1 = v, width: 50, suffix: 's'),
          ],
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: k == 0 ? null : () => setState(() => s.mission.insert(k - 1, s.mission.removeAt(k))),
            icon: const Icon(Icons.arrow_upward, size: 15),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: k == s.mission.length - 1
                ? null
                : () => setState(() => s.mission.insert(k + 1, s.mission.removeAt(k))),
            icon: const Icon(Icons.arrow_downward, size: 15),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => s.mission.removeAt(k)),
            icon: const Icon(Icons.close, size: 15),
          ),
        ],
      ),
    );
  }

  Future<void> _saveWaypoints() async {
    final loc = await fileDialog(
      (m) => c.notify(m, sticky: true),
      () => getSaveLocation(suggestedName: 'mission.waypoints', acceptedTypeGroups: const [_wpFiles]),
    );
    if (loc == null) return;
    final home = c.home;
    await saveWaypointsFile(
      loc.path,
      s.mission,
      s.home ??
          (home == null
              ? null
              : MissionItem(command: MavCmd.waypoint, frame: frameGlobal, lat: home.$1, lon: home.$2, alt: home.$3)),
    );
    setState(() => s.status = '${tr('Saved')} ${loc.path}');
  }

  Future<void> _openWaypoints() async {
    final file = await fileDialog(
      (m) => c.notify(m, sticky: true),
      () => openFile(acceptedTypeGroups: const [_wpFiles]),
    );
    if (file == null) return;
    try {
      final (items, home) = readWaypoints(await file.readAsString());
      setState(() {
        s.mission
          ..clear()
          ..addAll(items);
        s.home = home;
        s.status = '${tr('Opened')} ${file.name}: ${items.length} ${tr('items')}';
      });
    } catch (e) {
      setState(() => s.status = '$e');
    }
  }

  Widget _fencePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _toolButton(_Tool.fencePolygon, 'Draw polygon', Icons.pentagon_outlined),
            if (_tool == _Tool.fencePolygon)
              FilledButton(onPressed: s.drawing.length < 3 ? null : _finishPolygon, child: Text(tr('Finish polygon'))),
            _toolButton(_Tool.fenceCircle, 'Place circle', Icons.circle_outlined),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Muted(tr('Circle radius')),
            const SizedBox(width: 8),
            _numberField(s.circleRadius, (v) => s.circleRadius = v),
            const SizedBox(width: 4),
            const Muted('m'),
          ],
        ),
        const SizedBox(height: 8),
        Muted('${s.fence.length} ${tr('fence items')}'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilledButton(
              onPressed: s.busy
                  ? null
                  : () => _run(tr('Uploading fence…'), (mc) async {
                      await mc.upload(s.fence, type: MissionType.fence);
                      s.status = '${tr('Fence uploaded')}: ${s.fence.length}';
                    }),
              child: Text(tr('Upload fence')),
            ),
            OutlinedButton(
              onPressed: s.busy
                  ? null
                  : () => _run(tr('Downloading fence…'), (mc) async {
                      final (items, _) = await mc.download(type: MissionType.fence);
                      setState(
                        () => s.fence
                          ..clear()
                          ..addAll(items),
                      );
                      s.status = '${tr('Fence downloaded')}: ${items.length}';
                    }),
              child: Text(tr('Download')),
            ),
            TextButton(onPressed: () => setState(s.fence.clear), child: Text(tr('Clear'))),
          ],
        ),
        const SizedBox(height: 10),
        Muted(
          tr('Enable the fence on Safety & Failsafes (FENCE_ENABLE, and include "polygon" in FENCE_TYPE).'),
          size: 12,
        ),
      ],
    );
  }

  Widget _rallyPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(spacing: 6, children: [_toolButton(_Tool.rally, 'Add rally points', Icons.flag_outlined)]),
      const SizedBox(height: 8),
      for (var k = 0; k < s.rally.length; k++)
        Row(
          children: [
            Expanded(
              child: Text(
                '${k + 1}.  ${s.rally[k].lat.toStringAsFixed(6)}, ${s.rally[k].lon.toStringAsFixed(6)}',
                style: monoStyle.copyWith(fontSize: 12),
              ),
            ),
            _numberField(s.rally[k].alt, (v) => s.rally[k].alt = v, width: 60, suffix: 'm'),
            IconButton(onPressed: () => setState(() => s.rally.removeAt(k)), icon: const Icon(Icons.close, size: 15)),
          ],
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        children: [
          FilledButton(
            onPressed: s.busy
                ? null
                : () => _run(tr('Uploading rally points…'), (mc) async {
                    await mc.upload(s.rally, type: MissionType.rally);
                    s.status = '${tr('Rally points uploaded')}: ${s.rally.length}';
                  }),
            child: Text(tr('Upload')),
          ),
          OutlinedButton(
            onPressed: s.busy
                ? null
                : () => _run(tr('Downloading rally points…'), (mc) async {
                    final (items, _) = await mc.download(type: MissionType.rally);
                    setState(
                      () => s.rally
                        ..clear()
                        ..addAll(items),
                    );
                    s.status = '${tr('Rally points downloaded')}: ${items.length}';
                  }),
            child: Text(tr('Download')),
          ),
        ],
      ),
    ],
  );

  Future<void> _importZones() async {
    final file = await fileDialog(
      (m) => c.notify(m, sticky: true),
      () => openFile(acceptedTypeGroups: const [_zoneFiles]),
    );
    if (file == null) return;
    try {
      final text = await file.readAsString();
      final zones = file.name.toLowerCase().endsWith('.kml')
          ? parseKml(text, allowed: s.zoneAllowed)
          : parseGeoJson(text, allowed: s.zoneAllowed);
      setState(() {
        c.zones.own.addAll(zones);
        c.zones.save();
        s.status = '${tr('Imported')} ${zones.length} ${tr('zones')}';
      });
    } catch (e) {
      setState(() => s.status = '${tr('Could not import:')} $e');
    }
  }

  Widget _zonesPanel() {
    final zones = c.zones;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckRow(tr('Approximate airport zones (Türkiye)'), zones.airports, (v) => setState(() => zones.airports = v)),
        Muted(
          tr(
            '9 km circles, NOT official. Check the SHGM / DHMİ drone rules and the official map for airports, military and restricted areas.',
          ),
          size: 11.5,
        ),
        const Divider(height: 20),
        Row(
          children: [
            Muted(tr('New zone is')),
            const SizedBox(width: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(tr('No-fly'))),
                ButtonSegment(value: true, label: Text(tr('Allowed'))),
              ],
              selected: {s.zoneAllowed},
              onSelectionChanged: (v) => setState(() => s.zoneAllowed = v.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _toolButton(_Tool.zonePolygon, 'Polygon', Icons.pentagon_outlined),
            if (_tool == _Tool.zonePolygon)
              FilledButton(onPressed: s.drawing.length < 3 ? null : _finishPolygon, child: Text(tr('Finish polygon'))),
            _toolButton(_Tool.zoneCircle, 'Circle', Icons.circle_outlined),
            OutlinedButton(onPressed: _importZones, child: Text(tr('Import GeoJSON / KML…'))),
          ],
        ),
        const SizedBox(height: 10),
        for (var k = 0; k < zones.own.length; k++)
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: zones.own[k].allowed ? AppColors.ok : AppColors.err),
              const SizedBox(width: 8),
              Expanded(child: Text(zones.own[k].name)),
              IconButton(
                onPressed: () => setState(() {
                  zones.own.removeAt(k);
                  zones.save();
                }),
                icon: const Icon(Icons.delete_outline, size: 16),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Muted(
          tr(
            'Arming inside a no-fly zone (and not inside an allowed one) gives a warning. The app cannot stop the vehicle from arming.',
          ),
          size: 11.5,
        ),
      ],
    );
  }

  Widget _offlinePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Muted(
          tr(
            'Every tile you look at is stored, so places you have seen work without internet. For a field without network, zoom to it while online and download the area.',
          ),
          size: 12,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('${tr('Stored')}: $_cacheSize'),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await clearTileCache();
                await _refreshCache();
              },
              child: Text(tr('Delete')),
            ),
          ],
        ),
        const Divider(height: 20),
        Row(
          children: [
            Muted(tr('Down to zoom')),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _maxZoom,
              items: [for (var z = 14; z <= 19; z++) DropdownMenuItem(value: z, child: Text('$z'))],
              onChanged: (v) => setState(() => _maxZoom = v ?? 17),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_progress != null) ...[LinearProgressIndicator(value: _progress), const SizedBox(height: 6)],
        Wrap(
          spacing: 6,
          children: [
            FilledButton(
              onPressed: _progress != null || s.style == MapStyle.streets
                  ? null
                  : () async {
                      final bounds = _map.camera.visibleBounds;
                      final from = _map.camera.zoom.floor().clamp(1, 19);
                      _cancelDownload = false;
                      setState(() => _progress = 0);
                      try {
                        final n = await downloadArea(
                          s.style,
                          bounds,
                          from,
                          _maxZoom,
                          cancelled: () => _cancelDownload,
                          onProgress: (d, t) {
                            if (mounted) setState(() => _progress = d / t);
                          },
                        );
                        s.status = '${tr('Downloaded')} $n ${tr('tiles')}';
                      } catch (e) {
                        s.status = '$e';
                      } finally {
                        if (mounted) setState(() => _progress = null);
                        await _refreshCache();
                      }
                    },
              child: Text(tr('Download this area')),
            ),
            if (_progress != null) OutlinedButton(onPressed: () => _cancelDownload = true, child: Text(tr('Stop'))),
          ],
        ),
        if (s.style == MapStyle.streets)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Muted(tr('OpenStreetMap does not allow bulk downloads: switch to Satellite or Topo.'), size: 11.5),
          ),
      ],
    );
  }
}
