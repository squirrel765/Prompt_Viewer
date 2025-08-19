// lib/services/metadata_parser_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;

class MetadataParserService {

  /// 이미지 파일에서 A1111, ComfyUI, NAI의 원본 메타데이터를 모두 추출합니다.
  Future<Map<String, String?>> extractRawMetadata(String filePath) async {
    final result = <String, String?>{
      'a1111_parameters': null,
      'comfyui_workflow': null,
      'nai_comment': null,
    };
    final bytes = await File(filePath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return result;

    // 1. ComfyUI 워크플로우 추출 ('prompt' 또는 'workflow' 키 확인)
    result['comfyui_workflow'] = image.textData?['prompt'] ?? image.textData?['workflow'];

    // 2. A1111 파라미터 추출 ('parameters' 키 또는 EXIF 태그 확인)
    if (filePath.toLowerCase().endsWith('.png')) {
      result['a1111_parameters'] = image.textData?['parameters'];
    } else {
      // JPG/JPEG 등 다른 형식의 경우 Exif 데이터 확인
      final userComment = image.exif.getTag(37510);
      if (userComment != null) {
        result['a1111_parameters'] = userComment.toString();
      }
    }

    // 3. NAI Comment 추출 ('Comment' 키 확인, NovelAI 이미지의 가장 큰 특징)
    result['nai_comment'] = image.textData?['Comment'];

    if (result['a1111_parameters'] == null && result['nai_comment'] != null) {
      try {
        final Map<String, dynamic> naiJson = jsonDecode(result['nai_comment']!);
        if (naiJson.containsKey('parameters')) {
          result['a1111_parameters'] = naiJson['parameters'];
        }
      } catch (_) {
        // JSON 파싱에 실패하면 무시
      }
    }

    return result;
  }

  /// A1111 파라미터 문자열을 Positive, Negative, Others로 파싱합니다.
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

  /// NAI Comment JSON 문자열을 파싱하여 Positive, Negative, Options로 분리합니다.
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

  /// ComfyUI 워크플로우 JSON 문자열을 보기 좋게 포맷팅합니다.
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