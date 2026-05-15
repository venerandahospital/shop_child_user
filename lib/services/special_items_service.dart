import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Extra product names treated as special roll items (in addition to built-in patterns).
class SpecialItemsService {
  SpecialItemsService._();
  static final SpecialItemsService instance = SpecialItemsService._();

  static const _prefsKey = 'special_item_name_patterns_v1';

  List<String> _extraPatterns = const [];
  bool _loaded = false;

  List<String> get extraPatterns => List.unmodifiable(_extraPatterns);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      _extraPatterns = const [];
    } else {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _extraPatterns = decoded
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } catch (_) {
        _extraPatterns = const [];
      }
    }
    _loaded = true;
  }

  bool matchesExtraName(String rawName) {
    final lower = rawName.trim().toLowerCase();
    if (lower.isEmpty) return false;
    for (final pattern in _extraPatterns) {
      final p = pattern.trim().toLowerCase();
      if (p.isNotEmpty && lower.contains(p)) return true;
    }
    return false;
  }

  Future<void> setExtraPatterns(List<String> patterns) async {
    final normalized = <String>[];
    final seen = <String>{};
    for (final raw in patterns) {
      final p = raw.trim();
      if (p.isEmpty) continue;
      final key = p.toLowerCase();
      if (seen.add(key)) normalized.add(p);
    }
    _extraPatterns = normalized;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_extraPatterns));
  }

  Future<void> addPattern(String pattern) async {
    await ensureLoaded();
    final p = pattern.trim();
    if (p.isEmpty) return;
    await setExtraPatterns([..._extraPatterns, p]);
  }

  Future<void> removePattern(String pattern) async {
    await ensureLoaded();
    final key = pattern.trim().toLowerCase();
    await setExtraPatterns(
      _extraPatterns.where((e) => e.trim().toLowerCase() != key).toList(),
    );
  }
}
