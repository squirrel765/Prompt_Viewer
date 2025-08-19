// lib/services/sharing_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img; // 메타데이터 제거를 위해 image 패키지 사용

class SharingService {
  SharingService();

  /// 이미지 파일을 메타데이터 포함 여부에 따라 공유하는 핵심 메서드
  /// [imagePath]: 공유할 원본 이미지의 경로
  /// [withMetadata]: true이면 원본 파일 공유, false이면 메타데이터를 제거한 사본 공유
  Future<void> shareImageFile(String imagePath, {required bool withMetadata}) async {
    try {
      if (withMetadata) {
        // 옵션이 켜져 있으면, 원본 파일을 그대로 공유합니다.
        await Share.shareXFiles([XFile(imagePath)], text: 'AI Generated Image (with metadata)');
      } else {
        // 옵션이 꺼져 있으면, 메타데이터를 제거한 사본을 만들어 공유합니다.

        // 1. 원본 이미지 파일의 바이트 데이터를 읽어옵니다.
        final originalFile = File(imagePath);
        final Uint8List imageBytes = await originalFile.readAsBytes();

        // 2. 'image' 패키지를 사용해 이미지를 디코딩합니다.
        final image = img.decodeImage(imageBytes);
        if (image == null) {
          throw Exception("이미지 파일을 디코딩할 수 없습니다.");
        }

        // 3. 이미지를 다시 JPG로 인코딩합니다. 이 과정에서 대부분의 메타데이터가 제거됩니다.
        // PNG 원본이라도 JPG로 변환하여 공유하면 메타데이터가 남지 않습니다.
        final strippedBytes = img.encodeJpg(image, quality: 95);

        // 4. 임시 디렉토리에 메타데이터가 제거된 새 파일(사본)을 저장합니다.
        final tempDir = await getTemporaryDirectory();
        // 파일 이름이 겹치지 않도록 타임스탬프를 사용합니다.
        final tempPath = '${tempDir.path}/share_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(strippedBytes);

        // 5. 생성된 임시 파일을 공유합니다.
        await Share.shareXFiles([XFile(tempPath)], text: 'AI Generated Image');
      }
    } catch (e) {
      debugPrint("이미지 공유 중 오류 발생: $e");
      // UI 레이어에서 오류를 처리할 수 있도록 다시 던집니다.
      rethrow;
    }
  }

  /// 위젯을 이미지로 캡처하여 공유하는 메서드 (기존 기능)
  Future<void> captureAndShareWidget(GlobalKey boundaryKey) async {
    try {
      final RenderRepaintBoundary boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      // 해상도를 위해 pixelRatio를 조절할 수 있습니다.
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