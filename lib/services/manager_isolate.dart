// lib/services/manager_isolate.dart

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:prompt_viewer/services/worker_isolate.dart';
import 'dart:collection';

// --- 데이터 모델 (변경 없음) ---
class SyncRequest {
  final String folderPath;
  final String thumbPathRoot;
  final SendPort mainSendPort;
  final Map<String, int> existingFiles;

  SyncRequest({
    required this.folderPath,
    required this.thumbPathRoot,
    required this.mainSendPort,
    required this.existingFiles,
  });
}

abstract class SyncMessage {}
class FileFoundMessage extends SyncMessage {
  final List<String> paths;
  FileFoundMessage(this.paths);
}
class ParsingResultMessage extends SyncMessage {
  final WorkerResult result;
  ParsingResultMessage(this.result);
}
class SyncCompleteMessage extends SyncMessage {
  final int totalCount;
  SyncCompleteMessage(this.totalCount);
}
class SyncErrorMessage extends SyncMessage {
  final String error;
  SyncErrorMessage(this.error);
}

/// [핵심 수정] 워커 풀을 안정적으로 관리하는 최종 매니저 Isolate
Future<void> manageSyncProcess(SyncRequest request) async {
  final mainSendPort = request.mainSendPort;
  final receivePort = ReceivePort(); // 워커들의 보고를 받을 포트

  try {
    // 1. 파일 시스템 스캔
    final directory = Directory(request.folderPath);
    if (!await directory.exists()) throw Exception("Directory not found");

    final allFiles = <File>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        final path = entity.path.toLowerCase();
        if (path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg')) {
          allFiles.add(entity);
        }
      }
    }

    final allPaths = allFiles.map((f) => f.path).toList();
    mainSendPort.send(FileFoundMessage(allPaths));

    // 2. 변경된 파일만 필터링
    final filesToProcess = <File>[];
    for (final file in allFiles) {
      final stat = await file.stat();
      final lastModified = stat.modified.millisecondsSinceEpoch;
      if (request.existingFiles[file.path] != lastModified) {
        filesToProcess.add(file);
      }
    }

    if (filesToProcess.isEmpty) {
      mainSendPort.send(SyncCompleteMessage(allPaths.length));
      receivePort.close();
      return;
    }

    // 3. 워커 풀 생성 및 작업 분배
    final numberOfWorkers = max(1, Platform.numberOfProcessors - 1);
    final fileQueue = Queue<File>.from(filesToProcess);
    int resultsReceived = 0;
    final totalTasks = filesToProcess.length;

    // 초기 작업자들 실행
    for (int i = 0; i < numberOfWorkers; i++) {
      if (fileQueue.isNotEmpty) {
        final file = fileQueue.removeFirst();
        Isolate.spawn(
          processSingleFile,
          WorkerRequest(
            filePath: file.path,
            thumbPathRoot: request.thumbPathRoot,
            managerSendPort: receivePort.sendPort,
          ),
        );
      }
    }

    // 4. 워커들의 작업 결과 수신 및 다음 작업 할당
    receivePort.listen((message) {
      if (message is WorkerResult) {
        mainSendPort.send(ParsingResultMessage(message));
        resultsReceived++;

        if (fileQueue.isNotEmpty) {
          final file = fileQueue.removeFirst();
          Isolate.spawn(
            processSingleFile,
            WorkerRequest(
              filePath: file.path,
              thumbPathRoot: request.thumbPathRoot,
              managerSendPort: receivePort.sendPort,
            ),
          );
        }

        if (resultsReceived == totalTasks) {
          mainSendPort.send(SyncCompleteMessage(allPaths.length));
          receivePort.close();
        }
      }
    });

  } catch (e) {
    mainSendPort.send(SyncErrorMessage(e.toString()));
    receivePort.close();
  }
}