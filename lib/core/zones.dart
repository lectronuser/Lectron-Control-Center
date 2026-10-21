import 'dart:convert';
import 'dart:math' as math;

import 'app_storage.dart';

/// A flight-restriction zone: a polygon, or a circle around [center].
class Zone {
  Zone({
    required this.name,
    required this.allowed,
    this.polygon = const [],
    this.center,
    this.radius = 0,
    this.builtin = false,
  });

  final String name;

  /// True for an area where the user has permission; false for a no-fly area.
  final bool allowed;
  final List<(double, double)> polygon;
  final (double, double)? center;
  final double radius;
  final bool builtin;

  bool contains(double lat, double lon) {
    final c = center;
    if (c != null) return distanceM(lat, lon, c.$1, c.$2) <= radius;
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final (yi, xi) = polygon[i];
      final (yj, xj) = polygon[j];
      if ((yi > lat) != (yj > lat) && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'allowed': allowed,
    if (center != null) 'center': [center!.$1, center!.$2],
    'radius': radius,
    'polygon': [
      for (final p in polygon) [p.$1, p.$2],
    ],
  };

  static Zone fromJson(Map<String, dynamic> j) => Zone(
    name: '${j['name']}',
    allowed: j['allowed'] == true,
    center: j['center'] is List ? ((j['center'][0] as num).toDouble(), (j['center'][1] as num).toDouble()) : null,
    radius: (j['radius'] as num?)?.toDouble() ?? 0,
    polygon: [
      for (final p in (j['polygon'] as List? ?? const [])) ((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ],
  );
}

double distanceM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = (lat2 - lat1) * math.pi / 180, dl = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Main airports of Türkiye with an approximate 9 km circle. NOT official: check the SHGM / DHMİ rules and map.
final List<Zone> airportZones = [
  for (final (name, lat, lon) in const [
    ('İstanbul Havalimanı (IST)', 41.2753, 28.7519),
    ('Sabiha Gökçen (SAW)', 40.8986, 29.3092),
    ('Ankara Esenboğa (ESB)', 40.1281, 32.9951),
    ('İzmir Adnan Menderes (ADB)', 38.2924, 27.1570),
    ('Antalya (AYT)', 36.8987, 30.8005),
    ('Dalaman (DLM)', 36.7131, 28.7925),
    ('Milas-Bodrum (BJV)', 37.2506, 27.6643),
    ('Trabzon (TZX)', 40.9951, 39.7897),
    ('Gaziantep (GZT)', 36.9472, 37.4787),
    ('Kayseri (ASR)', 38.7704, 35.4954),
    ('Diyarbakır (DIY)', 37.8939, 40.2010),
    ('Erzurum (ERZ)', 39.9565, 41.1702),
    ('Van Ferit Melen (VAN)', 38.4682, 43.3323),
    ('Samsun Çarşamba (SZF)', 41.2545, 36.5671),
    ('Konya (KYA)', 37.9790, 32.5619),
    ('Denizli Çardak (DNZ)', 37.7856, 29.7013),
    ('Bursa Yenişehir (YEI)', 40.2552, 29.5626),
    ('Eskişehir Hasan Polatkan (AOE)', 39.8121, 30.5194),
    ('Malatya (MLX)', 38.4353, 38.0910),
    ('Hatay (HTY)', 36.3628, 36.2823),
    ('Adana Çukurova (COV)', 36.8875, 35.0000),
    ('Kapadokya (NAV)', 38.7719, 34.5345),
    ('Çorlu (TEQ)', 41.1382, 27.9191),
  ])
    Zone(name: name, allowed: false, center: (lat, lon), radius: 9000, builtin: true),
];

/// GeoJSON Polygon / MultiPolygon features, and Points with a "radius" property (metres).
List<Zone> parseGeoJson(String text, {required bool allowed}) {
  final root = jsonDecode(text);
  final features = root is Map && root['type'] == 'FeatureCollection' ? root['features'] as List : [root];
  final out = <Zone>[];
  for (final f in features) {
    if (f is! Map) continue;
    final geom = (f['geometry'] ?? f) as Map;
    final props = (f['properties'] as Map?) ?? const {};
    final name = '${props['name'] ?? props['Name'] ?? 'Zone ${out.length + 1}'}';
    List<(double, double)> ring(List coords) => [
      for (final p in coords) ((p[1] as num).toDouble(), (p[0] as num).toDouble()),
    ];
    switch (geom['type']) {
      case 'Polygon':
        out.add(Zone(name: name, allowed: allowed, polygon: ring((geom['coordinates'] as List).first as List)));
      case 'MultiPolygon':
        for (final poly in geom['coordinates'] as List) {
          out.add(Zone(name: name, allowed: allowed, polygon: ring((poly as List).first as List)));
        }
      case 'Point':
        final c = geom['coordinates'] as List;
        final r = (props['radius'] as num?)?.toDouble() ?? 500;
        out.add(
          Zone(name: name, allowed: allowed, center: ((c[1] as num).toDouble(), (c[0] as num).toDouble()), radius: r),
        );
    }
  }
  return out;
}

/// KML polygons (`<coordinates>lon,lat[,alt] ...</coordinates>`).
List<Zone> parseKml(String text, {required bool allowed}) {
  final out = <Zone>[];
  final placemarks = RegExp(r'<Placemark>(.*?)</Placemark>', dotAll: true).allMatches(text);
  for (final pm in placemarks) {
    final body = pm.group(1)!;
    final name =
        RegExp(r'<name>(.*?)</name>', dotAll: true).firstMatch(body)?.group(1)?.trim() ?? 'Zone ${out.length + 1}';
    final coords = RegExp(r'<coordinates>(.*?)</coordinates>', dotAll: true).firstMatch(body)?.group(1);
    if (coords == null) continue;
    final pts = [
      for (final t in coords.trim().split(RegExp(r'\s+')))
        if (t.split(',').length >= 2) (double.parse(t.split(',')[1]), double.parse(t.split(',')[0])),
    ];
    if (pts.length >= 3) out.add(Zone(name: name, allowed: allowed, polygon: pts));
  }
  return out;
}

/// The user's zones and whether the airport circles are shown; kept in the app settings.
class ZoneStore {
  ZoneStore(this.storage) {
    try {
      final text = storage.getString('zones');
      if (text != null) {
        own.addAll([for (final z in jsonDecode(text) as List) Zone.fromJson(Map<String, dynamic>.from(z as Map))]);
      }
    } catch (_) {
      // a damaged list starts empty
    }
  }

  final AppStorage storage;
  final List<Zone> own = [];

  bool get airports => storage.getBool('zonesAirports') ?? true;
  set airports(bool on) => storage.put('zonesAirports', on);

  List<Zone> get all => [if (airports) ...airportZones, ...own];

  void save() => storage.put('zones', jsonEncode([for (final z in own) z.toJson()]));

  /// The no-fly zone at a position, unless an allowed zone covers it too.
  Zone? restrictedAt(double lat, double lon) {
    final zones = all;
    if (zones.any((z) => z.allowed && z.contains(lat, lon))) return null;
    for (final z in zones) {
      if (!z.allowed && z.contains(lat, lon)) return z;
    }
    return null;
  }
}
