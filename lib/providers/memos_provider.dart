// lib/providers/memos_provider.dart

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 메모 데이터 하나를 나타내는 모델 클래스
class Memo {
  final String id;
  String content;
  final int createdAt;
  int updatedAt;

  Memo({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'content': content, 'createdAt': createdAt, 'updatedAt': updatedAt};
  }

  factory Memo.fromMap(Map<String, dynamic> map) {
    return Memo(
      id: map['id'],
      content: map['content'],
      createdAt: map['createdAt'],
      updatedAt: map['updatedAt'],
    );
  }
}

/// 앱 전역에서 메모 목록에 접근할 수 있도록 하는 Provider
final memosProvider = StateNotifierProvider<MemosNotifier, List<Memo>>((ref) {
  return MemosNotifier();
});

/// 메모 목록의 상태를 관리하는 Notifier
class MemosNotifier extends StateNotifier<List<Memo>> {
  static const _storageKey = 'saved_memos_list';
  final _uuid = const Uuid();

  // [수정] 생성자에서는 더 이상 load 함수를 호출하지 않습니다.
  MemosNotifier() : super([]);

  /// [수정] SharedPreferences에서 메모 목록을 불러오는 public 메소드
  Future<void> loadMemos() async {
    final prefs = await SharedPreferences.getInstance();
    final memoListString = prefs.getStringList(_storageKey) ?? [];
    state = memoListString
        .map((s) => Memo.fromMap(jsonDecode(s)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// 현재 메모 목록 상태를 SharedPreferences에 저장합니다.
  Future<void> _saveMemos() async {
    final prefs = await SharedPreferences.getInstance();
    final memoListString = state.map((memo) => jsonEncode(memo.toMap())).toList();
    await prefs.setStringList(_storageKey, memoListString);
  }

  /// 새 메모를 추가합니다.
  Future<void> addMemo(String content) async {
    if (content.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final newMemo = Memo(id: _uuid.v4(), content: content, createdAt: now, updatedAt: now);
      state = [newMemo, ...state];
      await _saveMemos();
    }
  }

  /// 기존 메모의 내용을 수정합니다.
  Future<void> editMemo(String id, String newContent) async {
    state = [
      for (final memo in state)
        if (memo.id == id)
          Memo(
              id: memo.id,
              content: newContent,
              createdAt: memo.createdAt,
              updatedAt: DateTime.now().millisecondsSinceEpoch)
        else
          memo,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _saveMemos();
  }

  /// 특정 ID의 메모를 삭제합니다.
  Future<void> deleteMemo(String id) async {
    state = state.where((memo) => memo.id != id).toList();
    await _saveMemos();
  }
}