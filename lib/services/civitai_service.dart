// lib/services/civitai_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Civitai API로부터 받은 "개별 이미지"의 상세 정보를 담는 데이터 클래스
class CivitaiInfo {
  final int id;
  final String imageUrl;
  final String? prompt;
  final String? negativePrompt;
  final Map<String, dynamic> otherDetails;

  CivitaiInfo({
    required this.id,
    required this.imageUrl,
    this.prompt,
    this.negativePrompt,
    this.otherDetails = const {},
  });
}

/// Civitai API와의 통신을 담당하는 서비스 클래스
class CivitaiService {
  final String? apiKey;
  CivitaiService({this.apiKey});

  final String _baseUrl = 'https://civitai.com/api/v1';

  /// API 요청 시 사용할 헤더를 생성합니다.
  Map<String, String> get _headers {
    final trimmedApiKey = apiKey?.trim();
    if (trimmedApiKey != null && trimmedApiKey.isNotEmpty) {
      return {'Authorization': 'Bearer $trimmedApiKey'};
    }
    return {};
  }

  /// 사용자가 입력한 URL에서 모델 ID만 추출합니다.
  String? _parseModelIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.contains('models') && segments.indexOf('models') + 1 < segments.length) {
        return segments[segments.indexOf('models') + 1];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// URL로부터 Civitai 이미지 정보 리스트를 가져오는 메인 메서드
  Future<List<CivitaiInfo>> fetchImagesFromModelUrl(String url) async {
    final modelId = _parseModelIdFromUrl(url);
    if (modelId == null) {
      throw Exception('유효한 Model URL이 아닙니다. (civitai.com/models/... 형식이어야 합니다)');
    }

    // 1단계: 모델 정보를 가져와서 최신 버전의 ID(modelVersionId)를 얻습니다.
    final modelResponse = await http.get(Uri.parse('$_baseUrl/models/$modelId'), headers: _headers);

    if (modelResponse.statusCode != 200) {
      if (modelResponse.statusCode == 401) throw Exception('인증 실패. API 키를 확인해주세요.');
      if (modelResponse.statusCode == 404) throw Exception('해당 ID의 모델을 찾을 수 없습니다.');
      throw Exception('모델 정보 로딩 실패 (HTTP ${modelResponse.statusCode})');
    }

    final modelJson = jsonDecode(utf8.decode(modelResponse.bodyBytes));
    if (modelJson['modelVersions'] == null || (modelJson['modelVersions'] as List).isEmpty) {
      throw Exception('모델에 버전 정보가 없습니다.');
    }
    final modelVersionId = modelJson['modelVersions'][0]['id'];
    if (modelVersionId == null) {
      throw Exception('모델 버전 ID를 찾을 수 없습니다.');
    }

    // 2단계: 얻어낸 modelVersionId를 사용하여 이미지 목록 API를 호출합니다.
    final imagesResponse = await http.get(
        Uri.parse('$_baseUrl/images?modelVersionId=$modelVersionId'),
        headers: _headers
    );

    if (imagesResponse.statusCode != 200) {
      throw Exception('이미지 목록 로딩 실패 (HTTP ${imagesResponse.statusCode})');
    }

    // [핵심 수정] 여기서 imagesJson 변수를 선언합니다.
    final imagesJson = jsonDecode(utf8.decode(imagesResponse.bodyBytes));
    final List<dynamic>? imageItems = imagesJson['items']; // 안정성을 위해 nullable로 받습니다.

    if (imageItems == null || imageItems.isEmpty) {
      throw Exception('모델 버전에 이미지 정보가 없습니다.');
    }

    // 3단계: `meta` 정보가 포함된 이미지 목록을 CivitaiInfo 객체 리스트로 변환하여 반환합니다.
    return imageItems.map((imageData) {
      final meta = imageData['meta'];
      final int imageId = imageData['id'];

      if (meta == null) {
        return CivitaiInfo(
          id: imageId,
          imageUrl: imageData['url'],
          prompt: '(이 이미지에는 프롬프트 정보가 없습니다.)',
        );
      }
      return _parseMeta(imageId, imageData['url'], meta);
    }).toList();
  }

  /// API 응답의 'meta' 필드를 파싱하여 CivitaiInfo 객체로 변환합니다.
  CivitaiInfo _parseMeta(int id, String imageUrl, Map<String, dynamic> meta) {
    final prompt = meta['prompt'] as String?;
    final negativePrompt = meta['negativePrompt'] as String?;

    meta.remove('prompt');
    meta.remove('negativePrompt');
    meta.remove('hashes');

    return CivitaiInfo(
      id: id,
      imageUrl: imageUrl,
      prompt: prompt,
      negativePrompt: negativePrompt,
      otherDetails: meta,
    );
  }

  /// 이미지를 다운로드하고 메타데이터를 주입하여 저장하는 메서드
  Future<void> downloadImageWithMetadata(CivitaiInfo info, String filePath) async {
    final response = await http.get(Uri.parse(info.imageUrl));
    if (response.statusCode != 200) {
      throw Exception('이미지 다운로드 실패 (HTTP ${response.statusCode})');
    }
    final imageBytes = response.bodyBytes;

    final image = img.decodeImage(imageBytes);
    if (image == null) {
      throw Exception('다운로드한 이미지의 형식을 알 수 없습니다.');
    }

    final buffer = StringBuffer();
    if (info.prompt != null && info.prompt!.isNotEmpty) {
      buffer.writeln(info.prompt);
    }
    if (info.negativePrompt != null && info.negativePrompt!.isNotEmpty) {
      buffer.writeln("Negative prompt: ${info.negativePrompt}");
    }
    final otherMetaString = info.otherDetails.entries
        .map((e) => "${e.key}: ${e.value}")
        .join(", ");
    if (otherMetaString.isNotEmpty) {
      buffer.writeln(otherMetaString);
    }
    final metadataString = buffer.toString();

    image.textData = {'parameters': metadataString};

    final newBytes = img.encodePng(image);

    final directory = Directory(p.dirname(filePath));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File(filePath);
    await file.writeAsBytes(newBytes);
  }
}