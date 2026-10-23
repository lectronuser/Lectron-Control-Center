import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// What the firmware's parameter documentation says about one parameter.
class ParamMeta {
  const ParamMeta({
    required this.name,
    this.title = '',
    this.description = '',
    this.units = '',
    this.values = const {},
    this.bitmask = const {},
    this.min,
    this.max,
    this.increment,
    this.defaultValue,
    this.rebootRequired = false,
    this.readOnly = false,
    this.advanced = false,
    this.group = '',
  });

  final String name;
  final String title;
  final String description;
  final String units;

  /// value -> label for enumerations.
  final Map<int, String> values;

  /// bit -> label for bit masks.
  final Map<int, String> bitmask;
  final double? min;
  final double? max;
  final double? increment;
  final double? defaultValue;
  final bool rebootRequired;
  final bool readOnly;
  final bool advanced;
  final String group;

  /// Text used by the search.
  String get searchText => '$name $title $description'.toLowerCase();

  /// Range problem of [value] or null when it is allowed.
  String? check(num value) {
    if (min != null && value < min! - 1e-6) return 'below the minimum $min';
    if (max != null && value > max! + 1e-6) return 'above the maximum $max';
    if (values.isNotEmpty && bitmask.isEmpty && !values.containsKey(value.round())) return 'not a listed value';
    return null;
  }
}

/// Which documentation set belongs to a vehicle.
String? metaSetFor({required int autopilot, required int mavType}) {
  if (autopilot == 12) return 'PX4';
  if (autopilot != 3) return null;
  return switch (mavType) {
    1 || 16 || 19 || 20 || 21 || 22 || 23 || 24 || 25 || 28 => 'ArduPlane',
    10 || 11 => 'Rover',
    12 => 'ArduSub',
    5 => 'AntennaTracker',
    7 => 'Blimp',
    _ => 'ArduCopter',
  };
}

String metaUrl(String set) => set == 'PX4'
    ? 'https://px4-travis.s3.amazonaws.com/Firmware/master/parameters.json.xz'
    : 'https://autotest.ardupilot.org/Parameters/$set/apm.pdef.json';

double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'.trim()));

Map<int, String> _intKeys(Object? raw) {
  if (raw is! Map) return const {};
  final out = <int, String>{};
  raw.forEach((k, v) {
    final key = int.tryParse('$k'.trim()) ?? _num(k)?.round();
    if (key != null) out[key] = '$v';
  });
  return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

/// ArduPilot apm.pdef.json: {"GROUP_": {"NAME": {"DisplayName", "Description", "Values", ...}}}.
Map<String, ParamMeta> parseArdupilotMeta(String text) {
  final root = jsonDecode(text) as Map<String, dynamic>;
  final out = <String, ParamMeta>{};
  root.forEach((group, params) {
    if (params is! Map) return;
    params.forEach((name, raw) {
      if (raw is! Map) return;
      final range = raw['Range'];
      out['$name'] = ParamMeta(
        name: '$name',
        title: '${raw['DisplayName'] ?? ''}',
        description: '${raw['Description'] ?? ''}'.trim(),
        units: '${raw['Units'] ?? ''}',
        values: _intKeys(raw['Values']),
        bitmask: _intKeys(raw['Bitmask']),
        min: range is Map ? _num(range['low']) : null,
        max: range is Map ? _num(range['high']) : null,
        increment: _num(raw['Increment']),
        rebootRequired: '${raw['RebootRequired']}'.toLowerCase() == 'true',
        readOnly: '${raw['ReadOnly']}'.toLowerCase() == 'true',
        advanced: raw['User'] == 'Advanced',
        group: group.isEmpty ? '' : group.replaceAll(RegExp(r'_$'), ''),
      );
    });
  });
  return out;
}

/// PX4 parameters.json: {"parameters": [{"name", "shortDesc", "longDesc", "values": [...], ...}]}.
Map<String, ParamMeta> parsePx4Meta(String text) {
  final root = jsonDecode(text) as Map<String, dynamic>;
  final out = <String, ParamMeta>{};
  for (final raw in (root['parameters'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final name = '${raw['name']}';
    final values = <int, String>{
      for (final v in (raw['values'] as List? ?? const []))
        if (v is Map && _num(v['value']) != null) _num(v['value'])!.round(): '${v['description']}',
    };
    final bits = <int, String>{
      for (final v in (raw['bitmask'] as List? ?? const []))
        if (v is Map && _num(v['index']) != null) _num(v['index'])!.round(): '${v['description']}',
    };
    final short = '${raw['shortDesc'] ?? ''}'.trim();
    final long = '${raw['longDesc'] ?? ''}'.trim();
    out[name] = ParamMeta(
      name: name,
      title: short,
      description: long.isEmpty ? short : long,
      units: '${raw['units'] ?? ''}',
      values: values,
      bitmask: bits,
      min: _num(raw['min']),
      max: _num(raw['max']),
      increment: _num(raw['increment']),
      defaultValue: _num(raw['default']),
      rebootRequired: raw['rebootRequired'] == true,
      advanced: raw['category'] == 'Developer',
      group: '${raw['group'] ?? ''}',
    );
  }
  return out;
}

/// Downloads the parameter documentation once and keeps a copy for offline use.
class ParamMetaStore {
  ParamMetaStore(this.cacheDir, {this.download = _httpGet});

  final Directory? cacheDir;
  final Future<List<int>> Function(String url) download;

  final Map<String, Map<String, ParamMeta>> _sets = {};
  final Map<String, Future<Map<String, ParamMeta>>> _loading = {};

  Map<String, ParamMeta>? loaded(String set) => _sets[set];

  File? _cacheFile(String set) =>
      cacheDir == null ? null : File('${cacheDir!.path}${Platform.pathSeparator}params_$set.json');

  Future<Map<String, ParamMeta>> _parse(String set, String text) {
    final parse = set == 'PX4' ? parsePx4Meta : parseArdupilotMeta;
    return Isolate.run(() => parse(text));
  }

  /// The cached copy right away, then a fresh download when the cache is older than [maxAge].
  Future<Map<String, ParamMeta>> load(String set, {Duration maxAge = const Duration(days: 7)}) {
    final have = _sets[set];
    if (have != null) return Future.value(have);
    // a block body: returning the removed future would make whenComplete wait for itself
    return _loading[set] ??= _load(set, maxAge).whenComplete(() {
      _loading.remove(set);
    });
  }

  Future<Map<String, ParamMeta>> _load(String set, Duration maxAge) async {
    final file = _cacheFile(set);
    String? cached;
    try {
      if (file != null && file.existsSync()) {
        cached = await file.readAsString();
        if (DateTime.now().difference(file.lastModifiedSync()) < maxAge) {
          return _sets[set] = await _parse(set, cached);
        }
      }
    } catch (_) {
      cached = null; // a broken cache is downloaded again
    }
    try {
      var bytes = await download(metaUrl(set));
      if (set == 'PX4') bytes = XZDecoder().decodeBytes(bytes);
      final text = utf8.decode(bytes);
      final parsed = await _parse(set, text);
      try {
        file?.parent.createSync(recursive: true);
        await file?.writeAsString(text);
      } catch (_) {
        // documentation still works for this session
      }
      return _sets[set] = parsed;
    } catch (e) {
      if (cached != null) return _sets[set] = await _parse(set, cached);
      rethrow;
    }
  }
}

Future<List<int>> _httpGet(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}

/// Plain HTTP GET with timeouts, shared by the firmware and map downloads.
