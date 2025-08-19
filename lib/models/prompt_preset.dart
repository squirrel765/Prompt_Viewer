// lib/models/prompt_preset.dart

import 'dart:convert';

class PromptPreset {
  final String id;
  String title;
  String prompt;
  String thumbnailPath; // 대표 이미지 경로
  List<String> imagePaths; // 연관된 모든 이미지 경로 리스트
  double rating; // 0.0 ~ 5.0
  bool isNsfw; // NSFW 여부

  PromptPreset({
    required this.id,
    required this.title,
    required this.prompt,
    required this.thumbnailPath,
    required this.imagePaths,
    this.rating = 0.0,
    this.isNsfw = false, // 기본값 false
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'prompt': prompt,
      'thumbnail_path': thumbnailPath,
      // List<String>은 JSON 문자열로 변환하여 저장
      'image_paths': jsonEncode(imagePaths),
      'rating': rating,
      'is_nsfw': isNsfw ? 1 : 0, // toMap에 추가
    };
  }

  factory PromptPreset.fromMap(Map<String, dynamic> map) {
    return PromptPreset(
      id: map['id'],
      title: map['title'],
      prompt: map['prompt'],
      thumbnailPath: map['thumbnail_path'],
      // DB에 저장된 JSON 문자열을 List<String>으로 다시 변환
      imagePaths: List<String>.from(jsonDecode(map['image_paths'])),
      rating: map['rating'],
      isNsfw: map['is_nsfw'] == 1, // fromMap에 추가
    );
  }
}