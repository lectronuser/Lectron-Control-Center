import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lectron_control/core/app_storage.dart';
import 'package:lectron_control/core/recipes.dart';
import 'package:lectron_control/core/zones.dart';
import 'package:lectron_control/ui/map_tiles.dart';

void main() {
  test('zones: polygon, circle, allowed areas and the airport list', () async {
    final square = Zone(
      name: 'square',
      allowed: false,
      polygon: const [(40.0, 29.0), (40.0, 29.01), (40.01, 29.01), (40.01, 29.0)],
    );
    expect(square.contains(40.005, 29.005), isTrue);
    expect(square.contains(40.02, 29.005), isFalse);
    final circle = Zone(name: 'c', allowed: false, center: (41.0, 28.0), radius: 1000);
    expect(circle.contains(41.005, 28.0), isTrue); // ~556 m north
    expect(circle.contains(41.02, 28.0), isFalse);

    final dir = await Directory.systemTemp.createTemp('lectron_zones');
    final store = ZoneStore(AppStorage(dir)..load());
    store.airports = true;
    // inside the Esenboğa circle
    expect(store.restrictedAt(40.1281, 32.9951)?.name, contains('ESB'));
    store.own.add(Zone(name: 'permit', allowed: true, center: (40.1281, 32.9951), radius: 500));
    expect(store.restrictedAt(40.1281, 32.9951), isNull);
    store.save();
    final reloaded = ZoneStore(AppStorage(dir)..load());
    expect(reloaded.own.single.name, 'permit');
    expect(reloaded.own.single.allowed, isTrue);
  });

  test('GeoJSON and KML import', () {
    const geo =
        '{"type":"FeatureCollection","features":['
        '{"type":"Feature","properties":{"name":"Park"},"geometry":{"type":"Polygon","coordinates":[[[29,40],[29.01,40],[29.01,40.01],[29,40.01],[29,40]]]}},'
        '{"type":"Feature","properties":{"name":"Tower","radius":300},"geometry":{"type":"Point","coordinates":[28.5,41.1]}}]}';
    final zones = parseGeoJson(geo, allowed: false);
    expect(zones.map((z) => z.name), ['Park', 'Tower']);
    expect(zones.first.contains(40.005, 29.005), isTrue);
    expect(zones.last.radius, 300);
    const kml =
        '<kml><Document><Placemark><name>Field</name><Polygon><outerBoundaryIs><LinearRing><coordinates>'
        '29,40,0 29.01,40,0 29.01,40.01,0 29,40.01,0</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark></Document></kml>';
    final k = parseKml(kml, allowed: true);
    expect(k.single.name, 'Field');
    expect(k.single.contains(40.005, 29.005), isTrue);
  });

  test('recipes: serial port substitution and saved recipes', () {
    final gps = builtinRecipes.firstWhere((r) => r.id == 'ap_gps_serial');
    expect(gps.resolve(port: 4)['SERIAL4_PROTOCOL'], 5);
    final mine = Recipe(id: 'x', title: 'Mine', description: '', values: const {'RTL_ALT': 3000}, custom: true);
    final back = decodeRecipes(encodeRecipes([mine]));
    expect(back.single.values['RTL_ALT'], 3000);
    expect(back.single.custom, isTrue);
    expect(decodeRecipes('broken'), isEmpty);
  });

  test('offline map tiles cover an area and refuse too many', () {
    final bounds = LatLngBounds(const LatLng(40.0, 29.0), const LatLng(40.01, 29.01));
    final tiles = tilesIn(bounds, 15, 16);
    expect(tiles.length, greaterThan(2));
    expect(tiles.every((t) => t.$1 == 15 || t.$1 == 16), isTrue);
    expect(downloadArea(MapStyle.streets, bounds, 15, 16), throwsStateError);
  });
}
