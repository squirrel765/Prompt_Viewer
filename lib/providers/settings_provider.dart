// lib/providers/settings_provider.dart

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/models/parsing_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- 데이터 모델 ---

/// 앱의 모든 설정을 담고 있는 데이터 클래스
class AppConfig {
  final List<ParsingPreset> presets;
  final List<String> parsingStrategy;
  final bool showNsfw;
  final bool shareWithMetadata;
  final String? civitaiApiKey; // Civitai API 키
  final String? geminiApiKey; // Gemini API 키
  final String selectedGeminiModel; // 선택된 Gemini 모델
  final int maxOutputTokens; // [추가] Gemini 최대 출력 토큰
  final double temperature; // [추가] Gemini Temperature
  final String? lastSyncedFolderPath;

  AppConfig({
    required this.presets,
    required this.parsingStrategy,
    required this.showNsfw,
    required this.shareWithMetadata,
    this.civitaiApiKey,
    this.geminiApiKey,
    required this.selectedGeminiModel,
    required this.maxOutputTokens,
    required this.temperature,
    this.lastSyncedFolderPath,
  });

  /// 앱의 기본 설정을 정의합니다.
  factory AppConfig.defaultConfig() {
    return AppConfig(
      presets: [
        ParsingPreset(id: 'default-a1111', name: 'A1111 (기본)', type: PresetType.a1111),
      ],
      parsingStrategy: ['default-a1111'],
      showNsfw: true,
      shareWithMetadata: true,
      civitaiApiKey: null,
      geminiApiKey: null,
      selectedGeminiModel: 'gemini-1.5-flash', // 기본 모델
      maxOutputTokens: 2048, // [추가] 기본값
      temperature: 0.9, // [추가] 기본값
      lastSyncedFolderPath: null,
    );
  }

  /// 기존 설정을 유지한 채 일부 값만 변경하여 새로운 AppConfig 객체를 생성합니다.
  AppConfig copyWith({
    List<ParsingPreset>? presets,
    List<String>? parsingStrategy,
    bool? showNsfw,
    bool? shareWithMetadata,
    String? civitaiApiKey,
    String? geminiApiKey,
    String? selectedGeminiModel,
    int? maxOutputTokens,
    double? temperature,
    String? lastSyncedFolderPath,
  }) {
    return AppConfig(
      presets: presets ?? this.presets,
      parsingStrategy: parsingStrategy ?? this.parsingStrategy,
      showNsfw: showNsfw ?? this.showNsfw,
      shareWithMetadata: shareWithMetadata ?? this.shareWithMetadata,
      civitaiApiKey: civitaiApiKey ?? this.civitaiApiKey,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      selectedGeminiModel: selectedGeminiModel ?? this.selectedGeminiModel,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      temperature: temperature ?? this.temperature,
      lastSyncedFolderPath: lastSyncedFolderPath ?? this.lastSyncedFolderPath,
    );
  }

  /// SharedPreferences에 저장하기 위해 객체를 JSON 맵으로 변환합니다.
  Map<String, dynamic> toJson() => {
    'presets': presets.map((p) => p.toJson()).toList(),
    'parsingStrategy': parsingStrategy,
    'showNsfw': showNsfw,
    'shareWithMetadata': shareWithMetadata,
    'civitaiApiKey': civitaiApiKey,
    'geminiApiKey': geminiApiKey,
    'selectedGeminiModel': selectedGeminiModel,
    'maxOutputTokens': maxOutputTokens,
    'temperature': temperature,
    'lastSyncedFolderPath': lastSyncedFolderPath,
  };

  /// JSON 맵으로부터 AppConfig 객체를 생성합니다.
  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    presets: (json['presets'] as List).map((p) => ParsingPreset.fromJson(p)).toList(),
    parsingStrategy: List<String>.from(json['parsingStrategy']),
    showNsfw: json['showNsfw'] ?? true,
    shareWithMetadata: json['shareWithMetadata'] ?? true,
    civitaiApiKey: json['civitaiApiKey'],
    geminiApiKey: json['geminiApiKey'],
    selectedGeminiModel: json['selectedGeminiModel'] ?? 'gemini-1.5-flash',
    maxOutputTokens: json['maxOutputTokens'] ?? 2048,
    temperature: json['temperature'] ?? 0.9,
    lastSyncedFolderPath: json['lastSyncedFolderPath'],
  );
}


// --- 상태 관리 로직 (State Notifier) ---

class ConfigNotifier extends StateNotifier<AppConfig> {
  ConfigNotifier() : super(AppConfig.defaultConfig()) {
    _loadConfig();
  }

  /// 앱 시작 시 SharedPreferences에서 설정을 불러옵니다.
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configString = prefs.getString('app_config');
    if (configString != null) {
      state = AppConfig.fromJson(jsonDecode(configString));
    }
  }

  /// 현재 설정 상태를 SharedPreferences에 저장합니다.
  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_config', jsonEncode(state.toJson()));
  }

  /// NSFW 콘텐츠 표시 여부를 변경하고 저장합니다.
  void setShowNsfw(bool isVisible) {
    state = state.copyWith(showNsfw: isVisible);
    _saveConfig();
  }

  /// 메타데이터 공유 여부를 변경하고 저장합니다.
  void setShareWithMetadata(bool value) {
    state = state.copyWith(shareWithMetadata: value);
    _saveConfig();
  }

  /// Civitai API 키를 변경하고 저장합니다.
  void setCivitaiApiKey(String? key) {
    state = state.copyWith(civitaiApiKey: key);
    _saveConfig();
  }

  /// Gemini API 키를 변경하고 저장합니다.
  void setGeminiApiKey(String? key) {
    state = state.copyWith(geminiApiKey: key);
    _saveConfig();
  }

  /// Gemini 모델을 변경하고 저장합니다.
  void setSelectedGeminiModel(String model) {
    state = state.copyWith(selectedGeminiModel: model);
    _saveConfig();
  }

  /// [추가] Gemini 최대 출력 토큰을 변경하고 저장합니다.
  void setMaxOutputTokens(int tokens) {
    state = state.copyWith(maxOutputTokens: tokens);
    _saveConfig();
  }

  /// [추가] Gemini Temperature를 변경하고 저장합니다.
  void setTemperature(double temp) {
    state = state.copyWith(temperature: temp);
    _saveConfig();
  }

  /// 마지막 동기화 폴더 경로를 변경하고 저장합니다.
  void setLastSyncedFolderPath(String path) {
    state = state.copyWith(lastSyncedFolderPath: path);
    _saveConfig();
  }

  /// 파싱 전략 순서를 변경하고 저장합니다.
  void updateStrategy(List<String> newStrategy) {
    state = state.copyWith(parsingStrategy: newStrategy);
    _saveConfig();
  }

  /// 파싱 프리셋을 추가하거나 업데이트하고 저장합니다.
  void addOrUpdatePreset(ParsingPreset preset) {
    final presets = List<ParsingPreset>.from(state.presets);
    final index = presets.indexWhere((p) => p.id == preset.id);

    if (index != -1) {
      presets[index] = preset; // 기존 항목 업데이트
    } else {
      presets.add(preset); // 새 항목 추가
    }

    state = state.copyWith(presets: presets);
    _saveConfig();
  }

  /// 특정 ID의 프리셋을 삭제하고 저장합니다.
  void deletePreset(String presetId) {
    // 기본 프리셋은 삭제할 수 없도록 방어
    if (presetId == 'default-a1111') return;

    final newPresets = state.presets.where((p) => p.id != presetId).toList();
    final newStrategy = state.parsingStrategy.where((id) => id != presetId).toList();

    state = state.copyWith(presets: newPresets, parsingStrategy: newStrategy);
    _saveConfig();
  }
}


// --- Provider 정의 ---

/// 앱 전역에서 설정 상태에 접근할 수 있도록 하는 Provider
final configProvider = StateNotifierProvider<ConfigNotifier, AppConfig>((ref) {
  return ConfigNotifier();
});