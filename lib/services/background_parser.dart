// lib/services/background_parser.dart

import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/services/metadata_parser_service.dart';

// --- Isolate 간 통신을 위한 데이터 모델 ---

/// 메인 Isolate에서 백그라운드 Isolate로 보낼 초기 데이터
class SyncRequest {
  final String folderPath;
  final String thumbPathRoot;
  final SendPort mainSendPort; // 메인 Isolate로 메시지를 보낼 포트

  SyncRequest({
    required this.folderPath,
    required this.thumbPathRoot,
    required this.mainSendPort,
  });
}

/// 백그라운드 Isolate에서 메인 Isolate로 보낼 메시지의 기본 타입
/// Isolate 간에는 클래스의 메서드가 아닌 데이터만 전달할 수 있습니다.
abstract class SyncMessage {}

/// [타입 1] 파일 경로를 찾았을 때 보내는 메시지
/// 찾은 파일 경로 목록을 담습니다.
class FileFoundMessage extends SyncMessage {
  final List<String> paths;
  FileFoundMessage(this.paths);
}

/// [타입 2] 파일 하나를 파싱 완료했을 때 보내는 메시지
/// 완성된 메타데이터 객체 하나를 담습니다.
class ParsingResultMessage extends SyncMessage {
  final ImageMetadata metadata;
  ParsingResultMessage(this.metadata);
}

/// [타입 3] 모든 작업이 완료되었을 때 보내는 메시지
/// 최종적으로 처리된 파일의 총 개수를 담습니다.
class SyncCompleteMessage extends SyncMessage {
  final int totalCount;
  SyncCompleteMessage(this.totalCount);
}

/// [타입 4] 오류가 발생했을 때 보내는 메시지
/// 오류 메시지 문자열을 담습니다.
class SyncErrorMessage extends SyncMessage {
  final String error;
  SyncErrorMessage(this.error);
}


/// Isolate.spawn()에 의해 독립적으로 실행될 최상위 함수
/// 이 함수는 메인 스레드와 메모리를 공유하지 않으므로, UI를 절대 방해하지 않습니다.
Future<void> backgroundSyncAndParse(SyncRequest request) async {
  try {
    final parserService = MetadataParserService();
    final directory = Directory(request.folderPath);

    if (!await directory.exists()) {
      throw Exception("Directory not found at ${request.folderPath}");
    }

    // --- 1단계: 디렉토리에서 모든 이미지 파일을 빠르게 스캔 ---
    final List<File> imageFiles = [];
    final stream = directory.list(recursive: true);
    await for (final entity in stream) {
      if (entity is File) {
        final path = entity.path.toLowerCase();
        if (path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg')) {
          imageFiles.add(entity);

          // 성능을 위해 20개씩 묶어서 찾은 파일 경로 목록을 메인 스레드로 전송
          if (imageFiles.length % 20 == 0) {
            final paths = imageFiles.map((f) => f.path).toList();
            request.mainSendPort.send(FileFoundMessage(paths));
          }
        }
      }
    }
    // 스캔이 끝난 후, 최종 파일 목록을 한 번 더 전송하여 누락 방지
    final finalPaths = imageFiles.map((f) => f.path).toList();
    request.mainSendPort.send(FileFoundMessage(finalPaths));


    // --- 2단계: 찾은 파일들을 순회하며 파싱 및 썸네일 생성 진행 ---
    for (final file in imageFiles) {
      try {
        final fileBytes = await file.readAsBytes();
        final fileStat = await file.stat();

        // 메타데이터 파싱
        final rawData = await parserService.extractRawMetadata(file.path, bytes: fileBytes);

        // 썸네일 생성 및 저장
        final image = img.decodeImage(fileBytes);
        if (image == null) continue; // 이미지를 디코딩할 수 없으면 건너뜀

        final thumbnail = img.copyResizeCropSquare(image, size: 256);
        final thumbFileName = p.basename(file.path);
        final thumbPath = p.join(request.thumbPathRoot, '$thumbFileName.jpg');
        final thumbFile = File(thumbPath);

        await thumbFile.parent.create(recursive: true);
        await thumbFile.writeAsBytes(img.encodeJpg(thumbnail, quality: 85));

        final metadata = ImageMetadata(
          path: file.path,
          thumbnailPath: thumbPath,
          timestamp: fileStat.modified.millisecondsSinceEpoch,
          a1111Parameters: rawData['a1111_parameters'],
          comfyUIWorkflow: rawData['comfyui_workflow'],
          naiComment: rawData['nai_comment'],
        );

        // 파싱이 완료된 메타데이터를 메인 스레드로 즉시 전송
        request.mainSendPort.send(ParsingResultMessage(metadata));

      } catch (e) {
        // 파일 하나가 실패하더라도 전체 작업이 중단되지 않도록 함
        debugPrint("Background parsing failed for ${file.path}: $e");
      }
    }

    // --- 3단계: 모든 작업 완료 메시지 전송 ---
    request.mainSendPort.send(SyncCompleteMessage(imageFiles.length));

  } catch(e) {
    // --- 4단계: 스캔 중 심각한 오류 발생 시 오류 메시지 전송 ---
    request.mainSendPort.send(SyncErrorMessage(e.toString()));
  }
}