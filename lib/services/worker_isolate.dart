// lib/services/worker_isolate.dart

import 'dart:io';
import 'dart:isolate';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:prompt_viewer/services/metadata_parser_service.dart';

// --- 데이터 모델 ---

/// 매니저 -> 워커에게 보내는 작업 지시서
class WorkerRequest {
  final String filePath;
  final String thumbPathRoot;
  final SendPort managerSendPort; // 결과를 보고할 포트

  WorkerRequest({
    required this.filePath,
    required this.thumbPathRoot,
    required this.managerSendPort,
  });
}

/// 워커 -> 매니저에게 보내는 작업 결과 보고서
class WorkerResult {
  final String path;
  final String thumbnailPath;
  final int timestamp;
  final String? a1111Parameters;
  final String? comfyUIWorkflow;
  final String? naiComment;

  WorkerResult({
    required this.path,
    required this.thumbnailPath,
    required this.timestamp,
    this.a1111Parameters,
    this.comfyUIWorkflow,
    this.naiComment,
  });
}

/// 개별 작업자 Isolate가 실행할 최상위 함수
/// 파일 하나를 받아 파싱하고 썸네일을 생성하는 역할만 수행합니다.
Future<void> processSingleFile(WorkerRequest request) async {
  try {
    final parserService = MetadataParserService();
    final file = File(request.filePath);

    if (!await file.exists()) {
      // 파일이 중간에 삭제된 경우, 아무것도 하지 않고 종료
      return;
    }

    final fileStat = await file.stat();
    final lastModified = fileStat.modified.millisecondsSinceEpoch;

    final fileBytes = await file.readAsBytes();
    final rawData = await parserService.extractRawMetadata(request.filePath, bytes: fileBytes);
    final image = img.decodeImage(fileBytes);

    if (image == null) return;

    final thumbnail = img.copyResizeCropSquare(image, size: 256);
    final thumbFileName = p.basename(request.filePath);
    final thumbPath = p.join(request.thumbPathRoot, '$thumbFileName.jpg');
    final thumbFile = File(thumbPath);

    await thumbFile.parent.create(recursive: true);
    await thumbFile.writeAsBytes(img.encodeJpg(thumbnail, quality: 85));

    // 작업 완료 후 매니저에게 결과 보고
    request.managerSendPort.send(WorkerResult(
      path: request.filePath,
      thumbnailPath: thumbPath,
      timestamp: lastModified,
      a1111Parameters: rawData['a1111_parameters'],
      comfyUIWorkflow: rawData['comfyui_workflow'],
      naiComment: rawData['nai_comment'],
    ));

  } catch (e) {
    // 오류 발생 시에도 다른 워커에 영향을 주지 않도록 Isolate 내에서 처리
    print('Worker failed for ${request.filePath}: $e');
  }
}