// lib/services/metadata_parser_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

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

  /// [수정] A1111 형식의 파라미터를 안정적으로 파싱하는 개선된 로직
  Map<String, String> parseA1111Parameters(String fullParams) {
    final result = <String, String>{
      'positive_prompt': '',
      'negative_prompt': '',
      'other_params': '',
    };
    const negPromptKeyword = "Negative prompt:";
    final paramKeywords = ["Steps:", "Sampler:", "CFG scale:", "Seed:", "Size:", "Model hash:", "Model:", "Denoising strength:", "Clip skip:", "ENSD:"];

    int negPromptIndex = fullParams.indexOf(negPromptKeyword);

    // 1. Negative Prompt가 있는 경우
    if (negPromptIndex != -1) {
      result['positive_prompt'] = fullParams.substring(0, negPromptIndex).trim();
      String afterNegative = fullParams.substring(negPromptIndex + negPromptKeyword.length).trim();

      int paramsStartIndex = -1;
      // 파라미터 키워드들의 가장 빠른 시작 위치를 찾음
      for (String key in paramKeywords) {
        int index = afterNegative.indexOf(key);
        if (index != -1) {
          if (paramsStartIndex == -1 || index < paramsStartIndex) {
            paramsStartIndex = index;
          }
        }
      }

      if (paramsStartIndex != -1) {
        result['negative_prompt'] = afterNegative.substring(0, paramsStartIndex).trim();
        result['other_params'] = afterNegative.substring(paramsStartIndex).trim();
      } else {
        result['negative_prompt'] = afterNegative; // 파라미터가 없으면 나머지는 모두 네거티브
      }
    }
    // 2. Negative Prompt가 없는 경우
    else {
      int paramsStartIndex = -1;
      for (String key in paramKeywords) {
        int index = fullParams.indexOf(key);
        if (index != -1) {
          if (paramsStartIndex == -1 || index < paramsStartIndex) {
            paramsStartIndex = index;
          }
        }
      }

      if (paramsStartIndex != -1) {
        result['positive_prompt'] = fullParams.substring(0, paramsStartIndex).trim();
        result['other_params'] = fullParams.substring(paramsStartIndex).trim();
      } else {
        result['positive_prompt'] = fullParams.trim(); // 파라미터가 없으면 전체가 포지티브
      }
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

  /// [추가] 입력된 프롬프트들을 A1111 형식의 단일 문자열로 조합합니다.
  String buildA1111Parameters({
    required String positivePrompt,
    String negativePrompt = '',
    String otherParams = '',
  }) {
    final buffer = StringBuffer();
    if (positivePrompt.isNotEmpty) {
      buffer.writeln(positivePrompt.trim());
    }
    if (negativePrompt.isNotEmpty) {
      buffer.writeln("Negative prompt: ${negativePrompt.trim()}");
    }
    if (otherParams.isNotEmpty) {
      buffer.writeln(otherParams.trim());
    }
    return buffer.toString();
  }

  /// [추가] 이미지 파일에 A1111 형식의 메타데이터를 주입(embed)합니다.
  Future<void> embedMetadataInImage(String filePath, String metadata) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception("파일을 찾을 수 없습니다: $filePath");
    }

    final imageBytes = await file.readAsBytes();
    final image = img.decodeImage(imageBytes);

    if (image == null) {
      throw Exception("이미지 형식을 디코딩할 수 없습니다.");
    }

    // PNG 파일에만 메타데이터를 쓸 수 있습니다.
    // JPG의 경우 Exif 데이터를 수정해야 하므로 더 복잡한 라이브러리가 필요합니다.
    // 여기서는 PNG로 변환하여 저장하는 방식을 택합니다.
    final originalExtension = filePath.split('.').last.toLowerCase();

    // textData 맵을 새로 만들거나 기존 맵에 'parameters' 키를 추가/업데이트합니다.
    image.textData = {...?image.textData, 'parameters': metadata};

    // PNG 형식으로 인코딩
    final newBytes = img.encodePng(image);

    // 원본 파일 확장자가 png가 아니었다면, 확장자를 .png로 변경하여 저장합니다.
    String newFilePath = filePath;
    if (originalExtension != 'png') {
      newFilePath = '${filePath.substring(0, filePath.length - originalExtension.length)}png';
    }

    final newFile = File(newFilePath);
    await newFile.writeAsBytes(newBytes);

    // 원본 파일이 png가 아니었고, 새 파일이 성공적으로 저장되었다면 원본은 삭제
    if (originalExtension != 'png' && newFilePath != filePath) {
      await file.delete();
    }
  }
}