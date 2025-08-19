// lib/providers/theme_provider.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1. StateNotifierProvider를 정의하여 앱 어디서든 접근할 수 있게 합니다.
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  // SharedPreferences에서 테마 설정을 저장할 때 사용할 키
  static const _themePrefKey = 'theme_mode_preference';

  // Notifier가 생성될 때 저장된 테마를 불러옵니다. 기본값은 라이트 모드.
  ThemeNotifier() : super(ThemeMode.light) {
    _loadTheme();
  }

  /// 기기에 저장된 테마 설정을 불러와 상태를 업데이트합니다.
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    // 저장된 문자열을 기반으로 ThemeMode를 결정합니다.
    switch (prefs.getString(_themePrefKey)) {
      case 'dark':
        state = ThemeMode.dark;
        break;
      case 'light':
      default:
        state = ThemeMode.light;
        break;
    }
  }

  /// 새로운 테마 모드를 설정하고 기기에 저장합니다.
  Future<void> setTheme(ThemeMode themeMode) async {
    // 1. 상태를 즉시 업데이트하여 UI에 반영합니다.
    state = themeMode;

    // 2. 선택된 테마를 기기에 영구적으로 저장합니다.
    try {
      final prefs = await SharedPreferences.getInstance();
      // ThemeMode를 문자열로 변환하여 저장
      final themeString = themeMode == ThemeMode.dark ? 'dark' : 'light';
      await prefs.setString(_themePrefKey, themeString);
    } catch (e) {
      // 에러 처리
      debugPrint('Failed to save theme preference: $e');
    }
  }
}