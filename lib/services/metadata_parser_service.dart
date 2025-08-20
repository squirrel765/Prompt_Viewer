// lib/services/metadata_parser_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // [추가]
import 'package:image/image.dart' as img;

// [추가] 이제 Provider는 서비스 파일 내부에 정의됩니다.
final metadataParserProvider = Provider<MetadataParserService>((ref) => MetadataParserService());

class MetadataParserService {

  Future<Map<String, String?>> extractRawMetadata(String filePath, {Uint8List? bytes}) async {
    final result = <String, String?>{
      'a1111_parameters': null,
      'comfyui_workflow': null,
      'nai_comment': null,
    };

    final imageBytes = bytes ?? await File(filePath).readAsBytes();
    final image = img.decodeImage(imageBytes);
    if (image == null) return result;

    result['comfyui_workflow'] = image.textData?['prompt'] ?? image.textData?['workflow'];

    if (filePath.toLowerCase().endsWith('.png')) {
      result['a1111_parameters'] = image.textData?['parameters'];
    } else {
      final userComment = image.exif.getTag(37510);
      if (userComment != null) {
        result['a1111_parameters'] = userComment.toString();
      }
    }

    result['nai_comment'] = image.textData?['Comment'];

    if (result['a1111_parameters'] == null && result['nai_comment'] != null) {
      try {
        final Map<String, dynamic> naiJson = jsonDecode(result['nai_comment']!);
        if (naiJson.containsKey('parameters')) {
          result['a1111_parameters'] = naiJson['parameters'];
        }
      } catch (_) {
        // JSON 파싱 실패 무시
      }
    }

    return result;
  }

  Map<String, String> parseA1111Parameters(String fullParams) {
    final result = <String, String>{
      'positive_prompt': '',
      'negative_prompt': '',
      'other_params': '',
    };
    const negPromptKeyword = "Negative prompt:";
    const paramsKeyword = "Steps:";
    int negPromptIndex = fullParams.indexOf(negPromptKeyword);
    int paramsIndex = fullParams.indexOf(paramsKeyword);

    if (negPromptIndex != -1) {
      result['positive_prompt'] = fullParams.substring(0, negPromptIndex).trim();
      if (paramsIndex > negPromptIndex) {
        result['negative_prompt'] =
            fullParams.substring(negPromptIndex + negPromptKeyword.length, paramsIndex).trim();
        result['other_params'] = fullParams.substring(paramsIndex).trim();
      } else {
        result['negative_prompt'] =
            fullParams.substring(negPromptIndex + negPromptKeyword.length).trim();
      }
    } else if (paramsIndex != -1) {
      result['positive_prompt'] = fullParams.substring(0, paramsIndex).trim();
      result['other_params'] = fullParams.substring(paramsIndex).trim();
    } else {
      result['positive_prompt'] = fullParams.trim();
    }
    return result;
  }

  Map<String, String> parseNaiParameters(String naiComment) {
    try {
      final naiJson = jsonDecode(naiComment) as Map<String, dynamic>;
      final positivePrompt = naiJson['prompt'] as String? ?? '';
      final negativePrompt = naiJson['uc'] as String? ?? '';

      final options = <String, dynamic>{};
      naiJson.forEach((key, value) {
        if (key != 'prompt' && key != 'uc') {
          options[key] = value;
        }
      });

      final optionsString = options.isNotEmpty
          ? const JsonEncoder.withIndent('  ').convert(options)
          : '추가 옵션 없음';

      return {
        'positive_prompt': positivePrompt,
        'negative_prompt': negativePrompt,
        'options': optionsString,
      };
    } catch (e) {
      return {
        'positive_prompt': 'NAI 데이터를 파싱하는 데 실패했습니다.',
        'negative_prompt': 'JSON 형식이 아닐 수 있습니다.',
        'options': naiComment,
      };
    }
  }

  String formatJson(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return 'ComfyUI 데이터가 없습니다.';
    try {
      final decoded = jsonDecode(jsonString);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (e) {
      return '잘못된 JSON 형식입니다:\n\n$jsonString';
    }
  }

  Future<String?> extractWorkflowJson(String filePath) async {
    final rawData = await extractRawMetadata(filePath);
    return rawData['comfyui_workflow'];
  }
}