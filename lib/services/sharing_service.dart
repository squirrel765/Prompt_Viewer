// lib/services/sharing_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img; // 메타데이터 제거를 위해 image 패키지 사용
import 'package:path/path.dart' as p; // 경로 조작을 위해 추가

class SharingService {
  SharingService();

  /// 이미지 파일을 메타데이터 포함 여부에 따라 공유하는 핵심 메서드
  Future<void> shareImageFile(String imagePath, {required bool withMetadata}) async {
    try {
      if (withMetadata) {
        await Share.shareXFiles([XFile(imagePath)], text: 'AI Generated Image (with metadata)');
      } else {
        final originalFile = File(imagePath);
        final Uint8List imageBytes = await originalFile.readAsBytes();

        final image = img.decodeImage(imageBytes);
        if (image == null) {
          throw Exception("이미지 파일을 디코딩할 수 없습니다.");
        }

        final strippedBytes = img.encodeJpg(image, quality: 95);

        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/share_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(strippedBytes);

        await Share.shareXFiles([XFile(tempPath)], text: 'AI Generated Image');
      }
    } catch (e) {
      debugPrint("이미지 공유 중 오류 발생: $e");
      rethrow;
    }
  }

  /// [신규] 여러 이미지 파일을 메타데이터 포함 여부에 따라 내보내는(공유하는) 메서드
  Future<void> exportImages(List<String> imagePaths, {required bool withMetadata}) async {
    try {
      if (withMetadata) {
        await Share.shareXFiles(imagePaths.map((p) => XFile(p)).toList(), text: 'AI Generated Images (with metadata)');
      } else {
        // 메타데이터가 제거된 임시 파일들의 경로를 담을 리스트
        final List<String> tempPaths = [];
        final tempDir = await getTemporaryDirectory();

        for (final imagePath in imagePaths) {
          final originalFile = File(imagePath);
          final imageBytes = await originalFile.readAsBytes();
          final image = img.decodeImage(imageBytes);

          if (image != null) {
            final strippedBytes = img.encodeJpg(image, quality: 95);
            // 파일 이름이 겹치지 않도록 고유한 이름 생성
            final tempPath = '${tempDir.path}/export_image_${DateTime.now().millisecondsSinceEpoch}_${p.basename(imagePath)}.jpg';
            final tempFile = File(tempPath);
            await tempFile.writeAsBytes(strippedBytes);
            tempPaths.add(tempPath);
          }
        }

        if (tempPaths.isNotEmpty) {
          await Share.shareXFiles(tempPaths.map((p) => XFile(p)).toList(), text: 'AI Generated Images');
        } else {
          throw Exception("내보낼 이미지를 처리할 수 없습니다.");
        }
      }
    } catch (e) {
      debugPrint("이미지 내보내기 중 오류 발생: $e");
      rethrow;
    }
  }

  /// 위젯을 이미지로 캡처하여 공유하는 메서드
  Future<void> captureAndShareWidget(GlobalKey boundaryKey) async {
    try {
      final RenderRepaintBoundary boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);

      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception("위젯을 이미지 데이터로 변환할 수 없습니다.");
      }
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/share_widget_${DateTime.now().millisecondsSinceEpoch}.png').create();
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles([XFile(file.path)], text: 'Generated with Prompt Viewer');
    } catch (e) {
      debugPrint("위젯 캡처 및 공유 중 오류 발생: $e");
      rethrow;
    }
  }
}