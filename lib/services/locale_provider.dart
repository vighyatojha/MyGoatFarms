import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { en, hi, gu }

extension AppLanguageX on AppLanguage {
  String get code {
    switch (this) {
      case AppLanguage.en:
        return 'en';
      case AppLanguage.hi:
        return 'hi';
      case AppLanguage.gu:
        return 'gu';
    }
  }

  /// Label shown on the toggle itself — always in its own script, so a
  /// user who can't read English can still recognise their language.
  String get label {
    switch (this) {
      case AppLanguage.en:
        return 'English';
      case AppLanguage.hi:
        return 'हिंदी';
      case AppLanguage.gu:
        return 'ગુજરાતી';
    }
  }

  static AppLanguage fromCode(String? code) {
    switch (code) {
      case 'hi':
        return AppLanguage.hi;
      case 'gu':
        return AppLanguage.gu;
      default:
        return AppLanguage.en;
    }
  }
}

/// Holds the app's current display language.
///
/// Persisted two ways so it's never lost:
///  - locally, in [SharedPreferences], so it applies instantly next time
///    the app opens, even before Firestore has loaded;
///  - on the farm document (`preferredLanguage`), so the same choice
///    follows this farm profile to another device.
///
/// Only the Profile screen exposes the toggle for changing it, but any
/// screen can read the current language via `context.watch<LocaleProvider>()`.
class LocaleProvider extends ChangeNotifier {
  static const _prefsKey = 'app_language';

  AppLanguage _language = AppLanguage.en;
  AppLanguage get language => _language;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _language = AppLanguageX.fromCode(prefs.getString(_prefsKey));
  }

  /// Called once the farm profile has loaded, so a language chosen on a
  /// different device takes effect here too — without overwriting a
  /// choice the person just made locally.
  void syncFromFarm(String? code) {
    if (code == null) return;
    final farmLanguage = AppLanguageX.fromCode(code);
    if (farmLanguage != _language) {
      _language = farmLanguage;
      notifyListeners();
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (language == _language) return;
    _language = language;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, language.code);
  }
}
