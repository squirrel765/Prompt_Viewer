// lib/services/gemini_api_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:prompt_viewer/providers/preset_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart';

// [수정] 첨부된 이미지 정보를 함께 담을 수 있도록 모델 확장
class ChatMessage {
  final String text;
  final bool isFromUser;
  final String? attachedImagePath;

  ChatMessage({required this.text, required this.isFromUser, this.attachedImagePath});
}

class GeminiApiService {
  final String? apiKey;
  final String modelName;
  final int maxOutputTokens; // [추가]
  final double temperature; // [추가]
  final Ref ref;

  GeminiApiService({
    required this.apiKey,
    required this.modelName,
    required this.maxOutputTokens,
    required this.temperature,
    required this.ref,
  });

  Future<String> getResponse(String prompt, {bool useTags = false, String? imagePath}) async {
    if (apiKey == null || apiKey!.isEmpty) {
      throw Exception('Gemini API 키가 설정되지 않았습니다.');
    }

    // --- START: 핵심 수정 부분 ---
    final model = GenerativeModel(
      model: modelName,
      apiKey: apiKey!,
      systemInstruction: useTags ? await _buildSystemInstruction() : null,
      // [추가] 생성 관련 설정을 GenerationConfig에 담아 전달합니다.
      generationConfig: GenerationConfig(
        maxOutputTokens: maxOutputTokens,
        temperature: temperature,
      ),
    );
    // --- END: 핵심 수정 부분 ---

    final content = await _buildContent(prompt, imagePath);
    final response = await model.generateContent(content);
    return response.text ?? "응답을 받지 못했습니다.";
  }

  /// [신규] 태그 라이브러리 정보를 시스템 명령어로 만드는 함수
  Future<Content> _buildSystemInstruction() async {
    final tags = await ref.read(tagsProvider.future);
    final jsonTags = jsonEncode(tags);
    final instruction =
        "You are a helpful AI assistant that specializes in creating prompts for image generation. "
        "When the user asks for a prompt, use the following JSON data of available tags to create a rich and descriptive prompt. "
        "Combine tags in a comma-separated list. Your answer should be the prompt string only.\n\n"
        "Available Tags (JSON):\n$jsonTags";
    return Content.text(instruction);
  }

  /// [신규] 사용자 프롬프트와 이미지를 API가 요구하는 Content 형태로 만드는 함수
  Future<List<Content>> _buildContent(String prompt, String? imagePath) async {
    if (imagePath != null) {
      final imageBytes = await File(imagePath).readAsBytes();
      return [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ])
      ];
    } else {
      return [Content.text(prompt)];
    }
  }
}

final geminiApiServiceProvider = Provider<GeminiApiService>((ref) {
  final config = ref.watch(configProvider);
  return GeminiApiService(
    apiKey: config.geminiApiKey,
    modelName: config.selectedGeminiModel,
    maxOutputTokens: config.maxOutputTokens, // [추가]
    temperature: config.temperature,       // [추가]
    ref: ref,
  );
});