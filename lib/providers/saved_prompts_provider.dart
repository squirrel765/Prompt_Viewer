// lib/providers/saved_prompts_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final savedPromptsProvider = StateNotifierProvider<SavedPromptsNotifier, List<String>>((ref) {
  return SavedPromptsNotifier();
});

class SavedPromptsNotifier extends StateNotifier<List<String>> {
  static const _storageKey = 'saved_prompts_list';

  SavedPromptsNotifier() : super([]) {
    _loadPrompts();
  }

  Future<void> _loadPrompts() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getStringList(_storageKey) ?? [];
  }

  Future<void> _savePrompts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, state);
  }

  Future<void> addPrompt(String prompt) async {
    if (prompt.isNotEmpty && !state.contains(prompt)) {
      state = [...state, prompt];
      await _savePrompts();
    }
  }

  Future<void> deletePrompt(int index) async {
    final newList = List<String>.from(state);
    newList.removeAt(index);
    state = newList;
    await _savePrompts();
  }

  /// *** 새로 추가된 프롬프트 수정 메서드 ***
  Future<void> editPrompt(int index, String newPrompt) async {
    // 수정된 내용이 비어있지 않은지 확인
    if (newPrompt.isNotEmpty) {
      // state는 불변이므로, 복사본을 만들어 수정합니다.
      final newList = List<String>.from(state);
      // 해당 인덱스의 값을 새로운 프롬프트로 교체
      newList[index] = newPrompt;
      // 상태를 새로운 리스트로 업데이트
      state = newList;
      // 변경사항을 영구 저장
      await _savePrompts();
    }
  }
}