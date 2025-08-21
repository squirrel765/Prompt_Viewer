// lib/providers/preset_provider.dart

import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/models/prompt_preset.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/services/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- Preset State Notifier ---
class PresetNotifier extends StateNotifier<List<PromptPreset>> {
  final DatabaseService _dbService;

  PresetNotifier(this._dbService) : super([]);

  Future<void> loadPresets() async {
    state = await _dbService.getAllPresets();
  }

  Future<void> addOrUpdatePreset(PromptPreset preset) async {
    await _dbService.insertOrUpdatePreset(preset);
    await loadPresets();
  }

  Future<void> deletePreset(String id) async {
    await _dbService.deletePreset(id);
    await loadPresets();
  }

  /// [추가] 프리셋에서 특정 이미지를 제거합니다.
  Future<void> removeImageFromPreset(String presetId, String imagePath) async {
    final presetIndex = state.indexWhere((p) => p.id == presetId);
    if (presetIndex == -1) return;

    final preset = state[presetIndex];
    // 이미지 목록이 2개 이상일 때만 제거 가능
    if (preset.imagePaths.length > 1) {
      preset.imagePaths.remove(imagePath);

      // 만약 대표 이미지가 삭제되었다면, 목록의 첫 번째 이미지를 새 대표 이미지로 지정
      if (preset.thumbnailPath == imagePath) {
        preset.thumbnailPath = preset.imagePaths.first;
      }

      await addOrUpdatePreset(preset);
    }
  }
}

// --- Custom Tags State Notifier (구조 변경) ---

/// 두 맵을 재귀적으로 병합하는 헬퍼 함수
Map<String, dynamic> _deepMerge(Map<String, dynamic> map1, Map<String, dynamic> map2) {
  final result = Map<String, dynamic>.from(map1);
  for (final key in map2.keys) {
    if (map2[key] is Map<String, dynamic> &&
        result.containsKey(key) &&
        result[key] is Map<String, dynamic>) {
      result[key] = _deepMerge(result[key] as Map<String, dynamic>, map2[key] as Map<String, dynamic>);
    } else {
      result[key] = map2[key];
    }
  }
  return result;
}

/// 사용자가 추가한 커스텀 태그의 상태를 관리하는 Notifier
class CustomTagsNotifier extends StateNotifier<Map<String, Map<String, dynamic>>> {
  CustomTagsNotifier() : super({}) {
    _load();
  }

  static const _prefsKey = 'custom_tags_json_v2'; // 버전 변경으로 이전 데이터와 충돌 방지

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      try {
        // SharedPreferences에서 읽은 문자열을 Map<String, dynamic>으로 변환
        final decodedMap = jsonDecode(jsonString) as Map<String, dynamic>;
        // 최종적으로 Map<String, Map<String, dynamic>> 형태로 변환
        state = decodedMap.map((key, value) => MapEntry(key, value as Map<String, dynamic>));
      } catch (e) {
        state = {};
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state));
  }

  /// [수정] JSON 문자열을 'sourceName' 키와 함께 저장합니다.
  Future<void> importFromJson(String jsonString, String sourceName) async {
    try {
      final newTags = jsonDecode(jsonString) as Map<String, dynamic>;
      // 기존 state 복사 후 새로운 소스 추가/덮어쓰기
      final newState = Map<String, Map<String, dynamic>>.from(state);
      newState[sourceName] = newTags;
      state = newState;
      await _save();
    } catch (e) {
      rethrow;
    }
  }

  /// [신규] 특정 소스(파일명)의 태그를 삭제합니다.
  Future<void> removeSource(String sourceName) async {
    if (state.containsKey(sourceName)) {
      final newState = Map<String, Map<String, dynamic>>.from(state);
      newState.remove(sourceName);
      state = newState;
      await _save();
    }
  }

  /// 모든 커스텀 태그를 삭제하고 저장합니다.
  Future<void> clear() async {
    state = {};
    await _save();
  }
}

// --- Providers ---

final presetProvider = StateNotifierProvider<PresetNotifier, List<PromptPreset>>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return PresetNotifier(dbService);
});

final customTagsProvider = StateNotifierProvider<CustomTagsNotifier, Map<String, Map<String, dynamic>>>((ref) {
  return CustomTagsNotifier();
});

/// [수정] 에셋 태그와 모든 커스텀 태그 소스를 병합하여 제공하는 Provider
final tagsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  // 1. 에셋 폴더의 기본 태그들을 읽어옵니다.
  final manifestContent = await rootBundle.loadString('AssetManifest.json');
  final Map<String, dynamic> manifestMap = json.decode(manifestContent);
  final tagFiles = manifestMap.keys.where((String key) => key.startsWith('assets/tags/')).toList();

  final Map<String, dynamic> assetTags = {};
  for (final file in tagFiles) {
    final jsonString = await rootBundle.loadString(file);
    final Map<String, dynamic> jsonMap = json.decode(jsonString);
    final fileName = file.split('/').last.replaceAll('.json', '');
    assetTags[fileName] = jsonMap;
  }

  // 2. 사용자가 추가한 모든 커스텀 태그 소스를 읽어옵니다.
  final customTagSources = ref.watch(customTagsProvider);

  // 3. 기본 태그 맵을 시작으로, 모든 커스텀 태그 소스를 순차적으로 병합합니다.
  Map<String, dynamic> combinedTags = Map.from(assetTags);
  for (final customTagMap in customTagSources.values) {
    combinedTags = _deepMerge(combinedTags, customTagMap);
  }

  return combinedTags;
});