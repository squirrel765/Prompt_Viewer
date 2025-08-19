// lib/providers/gallery_provider.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/services/database_service.dart';
import 'package:prompt_viewer/services/metadata_parser_service.dart';
import 'package:prompt_viewer/services/sharing_service.dart';
import 'package:path/path.dart' as p;

// --- Provider 정의 ---

/// 데이터베이스 서비스를 제공하는 Provider
final databaseServiceProvider = Provider<DatabaseService>((ref) => DatabaseService.instance);

/// 메타데이터 파싱 로직을 제공하는 Provider
final metadataParserProvider = Provider<MetadataParserService>((ref) => MetadataParserService());

/// 현재 선택된 **루트(root)** 폴더 경로를 저장하는 Provider
final folderPathProvider = StateProvider<String?>((ref) => null);

/// 공유 로직을 담당하는 SharingService를 위한 Provider
final sharingServiceProvider = Provider<SharingService>((ref) {
  return SharingService();
});

/// 갤러리의 이미지 목록 상태를 관리하는 핵심 Provider
final galleryProvider = StateNotifierProvider<GalleryNotifier, List<ImageMetadata>>((ref) {
  return GalleryNotifier(ref);
});

// --- State Notifier 클래스 ---

/// 갤러리 상태 관리를 담당하는 클래스
class GalleryNotifier extends StateNotifier<List<ImageMetadata>> {
  final Ref _ref;
  GalleryNotifier(this._ref) : super([]);

  bool _isLoading = false;

  /// 앱 시작 시 또는 필요할 때 데이터베이스에서 전체 이미지 목록을 비동기적으로 불러옵니다.
  Future<void> initialLoad() async {
    final dbService = _ref.read(databaseServiceProvider);
    state = await dbService.getAllImages();
  }

  /// 지정된 폴더 경로와 그 하위의 모든 내용을 데이터베이스와 동기화합니다.
  Future<void> syncFolder(String folderPath) async {
    if (_isLoading) return;
    _isLoading = true;

    final dbService = _ref.read(databaseServiceProvider);
    final parserService = _ref.read(metadataParserProvider);
    final directory = Directory(folderPath);

    try {
      if (await directory.exists()) {
        final dbImages = await dbService.getImagesByPath(folderPath);
        final dbImageMap = {for (var img in dbImages) img.path: img};
        final diskPathSet = <String>{};

        // *** [핵심 수정] `recursive: true` 옵션으로 하위 폴더의 모든 파일을 가져옵니다. ***
        final stream = directory.list(recursive: true);
        await for (final entity in stream) {
          if (entity is! File) continue;

          final path = entity.path.toLowerCase();
          if (!path.endsWith('.png') && !path.endsWith('.jpg') && !path.endsWith('.jpeg')) {
            continue;
          }

          diskPathSet.add(entity.path);
          final dbEntry = dbImageMap[entity.path];
          final fileStat = await entity.stat();
          final fileTimestamp = fileStat.modified.millisecondsSinceEpoch;

          if (dbEntry == null || fileTimestamp > dbEntry.timestamp) {
            final rawData = await parserService.extractRawMetadata(entity.path);

            final metadata = ImageMetadata(
              path: entity.path,
              timestamp: fileTimestamp,
              a1111Parameters: rawData['a1111_parameters'],
              comfyUIWorkflow: rawData['comfyui_workflow'],
              naiComment: rawData['nai_comment'],
              isFavorite: dbEntry?.isFavorite ?? false,
              rating: dbEntry?.rating ?? 0.0,
              viewCount: dbEntry?.viewCount ?? 0,
              isNsfw: dbEntry?.isNsfw ?? false, // 기존 상태 유지 또는 false로 초기화
            );
            await dbService.insertOrUpdateImage(metadata);
          }
        }

        final pathsToDelete = dbImageMap.keys.where((path) => !diskPathSet.contains(path) && path.startsWith(folderPath));
        for (final path in pathsToDelete) {
          await dbService.deleteImage(path);
        }

        // 동기화 후에는 전체 이미지 목록을 다시 불러옵니다.
        state = await dbService.getAllImages();
        _ref.read(folderPathProvider.notifier).state = folderPath;
      }
    } catch (e) {
      debugPrint("Error during folder sync: $e");
    } finally {
      _isLoading = false;
    }
  }

  /// 즐겨찾기 상태를 토글합니다.
  Future<void> toggleFavorite(ImageMetadata image) async {
    final dbService = _ref.read(databaseServiceProvider);
    final newFavoriteState = !image.isFavorite;
    await dbService.updateFavoriteStatus(image.path, newFavoriteState);

    state = [
      for (final img in state)
        if (img.path == image.path)
          img..isFavorite = newFavoriteState
        else
          img,
    ];
  }

  /// NSFW 상태를 (수동으로) 토글합니다.
  Future<void> toggleNsfw(ImageMetadata image) async {
    final dbService = _ref.read(databaseServiceProvider);
    final newNsfwState = !image.isNsfw;
    await dbService.updateImageNsfwStatus(image.path, newNsfwState);

    state = [
      for (final img in state)
        if (img.path == image.path)
          img..isNsfw = newNsfwState
        else
          img,
    ];
  }

  /// 이미지에 별점을 매깁니다.
  Future<void> rateImage(String path, double rating) async {
    final dbService = _ref.read(databaseServiceProvider);
    await dbService.updateImageRating(path, rating);

    state = [
      for (final img in state)
        if (img.path == path)
          img..rating = rating
        else
          img,
    ];
  }

  /// 이미지 조회수를 1 증가시킵니다.
  Future<void> viewImage(String path) async {
    final dbService = _ref.read(databaseServiceProvider);
    await dbService.incrementImageViewCount(path);

    state = [
      for (final img in state)
        if (img.path == path)
          img..viewCount = img.viewCount + 1
        else
          img,
    ];
  }

  /// 이미지 파일의 이름을 변경하고 DB 경로도 업데이트합니다.
  Future<bool> renameImage(ImageMetadata image, String newName) async {
    final dbService = _ref.read(databaseServiceProvider);
    try {
      final oldFile = File(image.path);
      final newPath = p.join(oldFile.parent.path, '$newName${p.extension(oldFile.path)}');

      if (await File(newPath).exists()) {
        debugPrint("Error: File with the new name already exists.");
        return false;
      }

      await oldFile.rename(newPath);
      await dbService.updateImagePath(image.path, newPath);

      state = [
        for (final img in state)
          if (img.path == image.path)
            ImageMetadata(
              path: newPath,
              timestamp: img.timestamp,
              a1111Parameters: img.a1111Parameters,
              comfyUIWorkflow: img.comfyUIWorkflow,
              naiComment: img.naiComment,
              isFavorite: img.isFavorite,
              rating: img.rating,
              viewCount: img.viewCount,
              isNsfw: img.isNsfw,
            )
          else
            img
      ];
      return true;
    } catch (e) {
      debugPrint("Error renaming file: $e");
      return false;
    }
  }

  /// 이미지 파일을 디스크와 DB에서 모두 삭제합니다.
  Future<bool> deleteImage(ImageMetadata image) async {
    final dbService = _ref.read(databaseServiceProvider);
    try {
      await File(image.path).delete();
      await dbService.deleteImage(image.path);

      state = state.where((img) => img.path != image.path).toList();
      return true;
    } catch (e) {
      debugPrint("Error deleting file: $e");
      return false;
    }
  }
}