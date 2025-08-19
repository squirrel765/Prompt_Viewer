// lib/providers/help_provider.dart

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 1. 데이터 모델 클래스 생성
class HelpTerm {
  final String name;
  final String description;

  HelpTerm({required this.name, required this.description});

  factory HelpTerm.fromJson(Map<String, dynamic> json) {
    return HelpTerm(
      name: json['name'] as String,
      description: json['description'] as String,
    );
  }
}

// 2. JSON 파일을 읽고 파싱하는 FutureProvider 생성
final helpTermsProvider = FutureProvider<List<HelpTerm>>((ref) async {
  // assets 폴더의 JSON 파일을 문자열로 읽어옵니다.
  final jsonString = await rootBundle.loadString('assets/prompt_viewer_help.json');
  // 문자열을 JSON 객체로 디코딩합니다.
  final jsonResponse = jsonDecode(jsonString) as Map<String, dynamic>;
  // 'terms' 키에 해당하는 리스트를 가져옵니다.
  final termsList = jsonResponse['terms'] as List;
  // 리스트의 각 아이템을 HelpTerm 객체로 변환합니다.
  return termsList.map((termJson) => HelpTerm.fromJson(termJson as Map<String, dynamic>)).toList();
});