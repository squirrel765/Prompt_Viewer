// lib/services/background_parser.dart

import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:prompt_viewer/services/metadata_parser_service.dart';

// --- Isolate 간 통신을 위한 데이터 모델 ---

/// 메인 Isolate에서 백그라운드 Isolate로 보낼 초기 데이터
/// [수정] 증분 동기화를 위해 existingFiles 맵을 포함합니다.
class SyncRequest {
  final String folderPath;
  final String thumbPathRoot;
  final SendPort mainSendPort;
  final Map<String, int> existingFiles; // { "path": timestamp }

  SyncRequest({
    required this.folderPath,
    required this.thumbPathRoot,
    required this.mainSendPort,
    required this.existingFiles,
  });
}

/// 백그라운드 Isolate에서 메인 Isolate로 보낼 메시지의 기본 타입
abstract class SyncMessage {}

/// [타입 1] 파일 경로를 찾았을 때 보내는 메시지
class FileFoundMessage extends SyncMessage {
  final List<String> paths;
  FileFoundMessage(this.paths);
}

/// [타입 2] 파일 하나를 파싱 완료했을 때 보내는 메시지 (원시 데이터)
class ParsingResultMessage extends SyncMessage {
  final String path;
  final String thumbnailPath;
  final int timestamp;
  final String? a1111Parameters;
  final String? comfyUIWorkflow;
  final String? naiComment;

  ParsingResultMessage({
    required this.path,
    required this.thumbnailPath,
    required this.timestamp,
    this.a1111Parameters,
    this.comfyUIWorkflow,
    this.naiComment,
  });
}

/// [타입 3] 모든 작업이 완료되었을 때 보내는 메시지
class SyncCompleteMessage extends SyncMessage {
  final int totalCount;
  SyncCompleteMessage(this.totalCount);
}

/// [타입 4] 오류가 발생했을 때 보내는 메시지
class SyncErrorMessage extends SyncMessage {
  final String error;
  SyncErrorMessage(this.error);
}


/// Isolate.spawn()에 의해 독립적으로 실행될 최상위 함수
/// [핵심] 증분 동기화 로직이 적용되어 있습니다.
Future<void> backgroundSyncAndParse(SyncRequest request) async {
  try {
    final parserService = MetadataParserService();
    final directory = Directory(request.folderPath);
    final existingFiles = request.existingFiles;

    if (!await directory.exists()) {
      throw Exception("Directory not found at ${request.folderPath}");
    }

    // 1단계: 디렉토리에서 모든 이미지 파일을 빠르게 스캔
    final List<File> imageFiles = [];
    final stream = directory.list(recursive: true);
    await for (final entity in stream) {
      if (entity is File) {
        final path = entity.path.toLowerCase();
        if (path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg')) {
          imageFiles.add(entity);
        }
      }
    }
    // 스캔이 끝난 후, 최종 파일 목록을 메인 스레드로 한 번에 전송
    final finalPaths = imageFiles.map((f) => f.path).toList();
    request.mainSendPort.send(FileFoundMessage(finalPaths));


    // 2단계: 찾은 파일들을 순회하며 파싱 및 썸네일 생성 진행
    for (final file in imageFiles) {
      try {
        final fileStat = await file.stat();
        final lastModified = fileStat.modified.millisecondsSinceEpoch;

        // [핵심 최적화] 기존 파일의 수정 시간과 현재 파일의 수정 시간을 비교
        if (existingFiles.containsKey(file.path) && existingFiles[file.path] == lastModified) {
          // 타임스탬프가 동일하면 변경되지 않은 파일이므로, 모든 무거운 작업을 건너뜁니다 (Continue).
          continue;
        }

        // 파일이 변경되었거나 새로 추가된 경우에만 아래 로직을 실행합니다.
        final fileBytes = await file.readAsBytes();
        final rawData = await parserService.extractRawMetadata(file.path, bytes: fileBytes);
        final image = img.decodeImage(fileBytes);
        if (image == null) continue;

        final thumbnail = img.copyResizeCropSquare(image, size: 256);
        final thumbFileName = p.basename(file.path);
        final thumbPath = p.join(request.thumbPathRoot, '$thumbFileName.jpg');
        final thumbFile = File(thumbPath);

        // 썸네일 저장
        await thumbFile.parent.create(recursive: true);
        await thumbFile.writeAsBytes(img.encodeJpg(thumbnail, quality: 85));

        // 파싱된 결과 데이터를 메인 스레드로 전송
        request.mainSendPort.send(ParsingResultMessage(
          path: file.path,
          thumbnailPath: thumbPath,
          timestamp: lastModified, // DB에 저장할 타임스탬프는 현재 파일의 수정 시간
          a1111Parameters: rawData['a1111_parameters'],
          comfyUIWorkflow: rawData['comfyui_workflow'],
          naiComment: rawData['nai_comment'],
        ));

      } catch (e) {
        // 파일 하나가 실패하더라도 전체 작업이 중단되지 않도록 함
        debugPrint("Background parsing failed for ${file.path}: $e");
      }
    }

    // 3단계: 모든 작업 완료 메시지 전송
    request.mainSendPort.send(SyncCompleteMessage(imageFiles.length));

  } catch(e) {
    // 4단계: 스캔 중 심각한 오류 발생 시 오류 메시지 전송
    request.mainSendPort.send(SyncErrorMessage(e.toString()));
  }
}