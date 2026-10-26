import 'strings_tr.dart';

/// Language of the interface: 'en' or 'tr'. Parameter names and the firmware's own messages stay in English.
String appLanguage = 'en';

const Map<String, String> languages = {'en': 'English', 'tr': 'Türkçe'};

/// The interface text for [en] in the current language; English when there is no translation.
String tr(String en) => appLanguage == 'tr' ? (trStrings[en] ?? en) : en;

/// [tr] with `{name}` placeholders filled in after the translation.
String trf(String en, Map<String, Object> args) {
  var text = tr(en);
  args.forEach((k, v) => text = text.replaceAll('{$k}', '$v'));
  return text;
}
