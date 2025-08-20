// lib/services/manager_isolate.dart

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:prompt_viewer/services/worker_isolate.dart';
import 'dart:collection'; // Queue를 사용하기 위해 import

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

    // 2. 변경된 파일만 필터링 (증분 동기화)
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
    final fileQueue = Queue<File>.from(filesToProcess); // 처리할 파일 큐
    int resultsReceived = 0;
    final totalTasks = filesToProcess.length;

    // 초기 작업자들을 실행
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
        // 결과를 메인 스레드로 즉시 전달
        mainSendPort.send(ParsingResultMessage(message));
        resultsReceived++;

        // 처리할 파일이 더 남아있다면, 일을 마친 워커 대신 새로운 작업을 시작
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

        // 모든 파일 처리가 완료되었는지 확인
        if (resultsReceived == totalTasks) {
          mainSendPort.send(SyncCompleteMessage(allPaths.length));
          receivePort.close(); // 모든 작업이 끝났으므로 포트를 닫음
        }
      }
    });

  } catch (e) {
    mainSendPort.send(SyncErrorMessage(e.toString()));
    receivePort.close();
  }
}