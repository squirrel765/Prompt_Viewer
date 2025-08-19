// lib/services/background_parser.dart

import 'dart:io';
import 'package:flutter/foundation.dart'; // [수정] debugPrint를 사용하기 위해 추가
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/services/metadata_parser_service.dart';

/// compute에 전달할 데이터 묶음 클래스
class ParseRequest {
  final String filePath;
  final String thumbPathRoot;
  ParseRequest({required this.filePath, required this.thumbPathRoot});
}

/// [수정] 함수 이름에서 밑줄(_)을 제거하여 다른 파일에서도 접근할 수 있도록 공개(public)로 변경
Future<ImageMetadata?> parseAndCreateThumbnail(ParseRequest request) async {
  try {
    final file = File(request.filePath);
    if (!await file.exists()) return null;

    final fileBytes = await file.readAsBytes();
    final fileStat = await file.stat();

    // 1. 메타데이터 파싱
    final parserService = MetadataParserService();
    final rawData = await parserService.extractRawMetadata(request.filePath, bytes: fileBytes);

    // 2. 썸네일 생성 및 저장
    final image = img.decodeImage(fileBytes);
    if (image == null) return null;

    final thumbnail = img.copyResizeCropSquare(image, size: 256);
    final thumbFileName = p.basename(request.filePath);
    final thumbPath = p.join(request.thumbPathRoot, '$thumbFileName.jpg');
    final thumbFile = File(thumbPath);

    await thumbFile.parent.create(recursive: true);
    await thumbFile.writeAsBytes(img.encodeJpg(thumbnail, quality: 85));

    // 3. 결과물인 ImageMetadata 객체 반환
    return ImageMetadata(
      path: request.filePath,
      thumbnailPath: thumbPath,
      timestamp: fileStat.modified.millisecondsSinceEpoch,
      a1111Parameters: rawData['a1111_parameters'],
      comfyUIWorkflow: rawData['comfyui_workflow'],
      naiComment: rawData['nai_comment'],
    );
  } catch (e) {
    // 이제 debugPrint가 정상적으로 작동합니다.
    debugPrint("Background parsing failed for ${request.filePath}: $e");
    return null;
  }
}