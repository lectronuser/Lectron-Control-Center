import 'dart:convert';
import 'dart:io';

import 'param_meta.dart';

/// A Lua applet from ArduPilot's repository (libraries/AP_Scripting/applets).
class Applet {
  const Applet(this.name, this.size, this.url, {this.docUrl});
  final String name;
  final int size;
  final String url;
  final String? docUrl;
}

const String _api = 'https://api.github.com/repos/ArduPilot/ardupilot/contents/libraries/AP_Scripting/applets';

/// Git refs to try for a firmware, most specific first: release tag, release branch, master.
List<String> appletRefs(String vehicle, String version) {
  final prefix = switch (vehicle) {
    'ArduPlane' => 'Plane',
    'Rover' => 'Rover',
    'ArduSub' => 'Sub',
    'Tracker' => 'AntennaTracker',
    'Blimp' => 'Blimp',
    _ => 'Copter',
  };
  final v = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(version);
  return [if (v != null) '$prefix-${v.group(0)}', if (v != null) '$prefix-${v.group(1)}.${v.group(2)}', 'master'];
}

/// Lists the applets of the first ref that exists; listings are cached on disk because the API is rate limited.
Future<(String ref, List<Applet>)> fetchApplets(
  List<String> refs, {
  Directory? cache,
  Future<List<int>> Function(String) get = httpGet,
}) async {
  Object? lastError;
  for (final ref in refs) {
    final file = cache == null ? null : File('${cache.path}${Platform.pathSeparator}applets_$ref.json');
    try {
      String text;
      if (file != null && file.existsSync() && DateTime.now().difference(file.lastModifiedSync()).inDays < 7) {
        text = await file.readAsString();
      } else {
        text = utf8.decode(await get('$_api?ref=$ref'));
        try {
          file?.parent.createSync(recursive: true);
          await file?.writeAsString(text);
        } catch (_) {
          // the listing still works for this session
        }
      }
      final items = jsonDecode(text) as List;
      final docs = {
        for (final i in items)
          if (i is Map && '${i['name']}'.endsWith('.md')) '${i['name']}'.replaceAll('.md', ''): '${i['download_url']}',
      };
      final applets = [
        for (final i in items)
          if (i is Map && '${i['name']}'.endsWith('.lua'))
            Applet(
              '${i['name']}',
              (i['size'] as num?)?.toInt() ?? 0,
              '${i['download_url']}',
              docUrl: docs['${i['name']}'.replaceAll('.lua', '')],
            ),
      ];
      return (ref, applets);
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError ?? const HttpException('no applet listing');
}

/// Starting point for a new script.
const String luaTemplate = '''-- My script: runs update() every 1000 ms
-- Docs: https://ardupilot.org/copter/docs/common-lua-scripts.html

local MAV_SEVERITY_INFO = 6

local function update()
  if arming:is_armed() then
    -- do something while armed
  end
  return update, 1000
end

gcs:send_text(MAV_SEVERITY_INFO, "my script loaded")
return update()
''';
