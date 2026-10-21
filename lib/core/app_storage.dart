import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Everything the app keeps on disk lives in its own data directory: the daily log files and the
/// remembered settings. Nothing is created in the user's home directory.
class AppStorage {
  AppStorage(this.root);

  /// Null when no directory is available; the app then runs without persistence.
  final Directory? root;

  Map<String, Object?> _settings = {};

  Directory? get logDir => root == null ? null : Directory('${root!.path}${Platform.pathSeparator}logs');

  String? get logPath {
    final dir = logDir;
    if (dir == null) return null;
    final now = DateTime.now();
    return '${dir.path}${Platform.pathSeparator}board_test_${now.year}${two(now.month)}${two(now.day)}.log';
  }

  File? get _settingsFile => root == null ? null : File('${root!.path}${Platform.pathSeparator}settings.json');

  void load() {
    try {
      final file = _settingsFile;
      if (file != null && file.existsSync()) {
        _settings = Map<String, Object?>.from(jsonDecode(file.readAsStringSync()) as Map);
      }
    } catch (_) {
      _settings = {};
    }
  }

  // a settings file edited by hand may hold anything
  String? getString(String key) {
    final value = _settings[key];
    return value is String ? value : null;
  }

  int? getInt(String key) {
    final value = _settings[key];
    return value is int ? value : null;
  }

  bool? getBool(String key) {
    final value = _settings[key];
    return value is bool ? value : null;
  }

  void put(String key, Object? value) {
    if (_settings[key] == value) return;
    _settings[key] = value;
    try {
      _settingsFile?.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_settings));
    } catch (_) {
      // settings are a convenience, never an error
    }
  }

  /// Appends one line to today's log file; written straight away so it survives a crash.
  void log(String level, String message) {
    final path = logPath;
    if (path == null) return;
    try {
      logDir!.createSync(recursive: true);
      final now = DateTime.now();
      File(path).writeAsStringSync('${ymd(now)} ${hms(now)} ${level.padRight(7)} $message\n', mode: FileMode.append);
    } catch (_) {
      // a full or read-only disk must not stop the test
    }
  }
}
