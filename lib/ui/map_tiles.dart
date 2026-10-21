import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

enum MapStyle { satellite, streets, topo }

const Map<MapStyle, String> mapStyleNames = {
  MapStyle.satellite: 'Satellite',
  MapStyle.streets: 'Streets',
  MapStyle.topo: 'Topo',
};

const Map<MapStyle, String> _urls = {
  MapStyle.satellite: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  MapStyle.streets: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  MapStyle.topo: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
};

const Map<MapStyle, int> mapMaxZoom = {MapStyle.satellite: 19, MapStyle.streets: 19, MapStyle.topo: 17};

const String _userAgent = 'LectronControlCenter/1.0 (ground control station)';

/// Folder of the tile cache; set once at start.
Directory? tileCacheDir;

String _url(MapStyle style, int z, int x, int y) =>
    _urls[style]!.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y');

File? _file(MapStyle style, int z, int x, int y) {
  final dir = tileCacheDir;
  if (dir == null) return null;
  final sep = Platform.pathSeparator;
  return File('${dir.path}$sep${style.name}$sep$z$sep$x$sep$y.tile');
}

Future<Uint8List?> _fetch(MapStyle style, int z, int x, int y) async {
  final file = _file(style, z, x, y);
  try {
    if (file != null && file.existsSync()) return await file.readAsBytes();
  } catch (_) {
    // a broken cache entry is downloaded again
  }
  try {
    final request = await _client.getUrl(Uri.parse(_url(style, z, x, y)));
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    final bytes = await consolidateHttpClientResponseBytes(response);
    try {
      file?.parent.createSync(recursive: true);
      await file?.writeAsBytes(bytes);
    } catch (_) {
      // shown, just not kept
    }
    return bytes;
  } catch (_) {
    return null;
  }
}

/// One client for every tile, with a few connections per server, instead of a new socket per tile.
final HttpClient _client = HttpClient()
  ..connectionTimeout = const Duration(seconds: 10)
  ..maxConnectionsPerHost = 6
  ..idleTimeout = const Duration(seconds: 30);

/// Tiles from the disk cache first; downloaded ones are stored, so places seen once work offline.
class CachedTileProvider extends TileProvider {
  CachedTileProvider(this.style);
  final MapStyle style;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _TileImage(style, coordinates.z, coordinates.x, coordinates.y);
}

TileLayer tileLayer(MapStyle style) => TileLayer(
  urlTemplate: _urls[style],
  maxNativeZoom: mapMaxZoom[style]!,
  maxZoom: 21,
  userAgentPackageName: 'com.lectron.lectron_control',
  tileProvider: CachedTileProvider(style),
);

class _TileImage extends ImageProvider<_TileImage> {
  const _TileImage(this.style, this.z, this.x, this.y);
  final MapStyle style;
  final int z, x, y;

  @override
  Future<_TileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_TileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await _fetch(style, z, x, y);
    if (bytes == null) throw StateError('tile $z/$x/$y not available');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is _TileImage && other.style == style && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(style, z, x, y);
}

(int, int) tileOf(LatLng p, int z) {
  final n = 1 << z;
  final x = ((p.longitude + 180) / 360 * n).floor().clamp(0, n - 1);
  final lat = p.latitude * math.pi / 180;
  final y = ((1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n).floor().clamp(0, n - 1);
  return (x, y);
}

/// Tiles covering [bounds] from [minZoom] to [maxZoom].
List<(int, int, int)> tilesIn(LatLngBounds bounds, int minZoom, int maxZoom) => [
  for (var z = minZoom; z <= maxZoom; z++)
    for (var x = tileOf(bounds.northWest, z).$1; x <= tileOf(bounds.southEast, z).$1; x++)
      for (var y = tileOf(bounds.northWest, z).$2; y <= tileOf(bounds.southEast, z).$2; y++) (z, x, y),
];

/// Downloads every tile of an area for offline use; streets are not allowed by the OpenStreetMap policy.
Future<int> downloadArea(
  MapStyle style,
  LatLngBounds bounds,
  int minZoom,
  int maxZoom, {
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  if (style == MapStyle.streets) throw StateError('OpenStreetMap does not allow bulk downloads');
  final tiles = tilesIn(bounds, minZoom, math.min(maxZoom, mapMaxZoom[style]!));
  if (tiles.length > 6000) throw StateError('${tiles.length} tiles: zoom in or lower the maximum zoom (limit 6000)');
  var done = 0, ok = 0;
  for (final (z, x, y) in tiles) {
    if (cancelled?.call() ?? false) break;
    if (await _fetch(style, z, x, y) != null) ok++;
    onProgress?.call(++done, tiles.length);
  }
  return ok;
}

/// Size of the tile cache in bytes.
Future<int> tileCacheSize() async {
  final dir = tileCacheDir;
  if (dir == null || !dir.existsSync()) return 0;
  var total = 0;
  await for (final e in dir.list(recursive: true)) {
    if (e is File) total += await e.length();
  }
  return total;
}

Future<void> clearTileCache() async {
  final dir = tileCacheDir;
  if (dir != null && dir.existsSync()) await dir.delete(recursive: true);
}
