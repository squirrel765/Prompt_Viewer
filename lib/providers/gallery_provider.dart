// lib/providers/gallery_provider.dart

import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/main.dart';
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/providers/settings_provider.dart';
// [수정] 이제 매니저 Isolate를 사용합니다.
import 'package:prompt_viewer/services/manager_isolate.dart';
import 'package:prompt_viewer/services/database_service.dart';
import 'package:prompt_viewer/services/metadata_parser_service.dart';
import 'package:prompt_viewer/services/sharing_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';


// --- (GalleryItem, GalleryState, Provider 정의는 이전과 동일) ---
abstract class GalleryItem {
  final String path;
  GalleryItem(this.path);
}
class TemporaryImageItem extends GalleryItem {
  TemporaryImageItem(String path) : super(path);
}
class FullImageItem extends GalleryItem {
  final ImageMetadata metadata;
  FullImageItem(this.metadata) : super(metadata.path);
}
@immutable
class GalleryState {
  final List<GalleryItem> items;
  final bool isLoading;
  final bool hasMore;
  final bool isLoadingMore;

  const GalleryState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  GalleryState copyWith({
    List<GalleryItem>? items,
    bool? isLoading,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return GalleryState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

final databaseServiceProvider = Provider<DatabaseService>((ref) => DatabaseService.instance);
final folderPathProvider = Provider<String?>((ref) {
  return ref.watch(configProvider).lastSyncedFolderPath;
});
final sharingServiceProvider = Provider<SharingService>((ref) => SharingService());
final metadataParserProvider = Provider<MetadataParserService>((ref) => MetadataParserService());
final galleryProvider = StateNotifierProvider<GalleryNotifier, GalleryState>((ref) => GalleryNotifier(ref));


class GalleryNotifier extends StateNotifier<GalleryState> {
  final Ref _ref;
  GalleryNotifier(this._ref) : super(const GalleryState());

  bool _isSyncing = false;
  Isolate? _managerIsolate; // [이름 변경] syncIsolate -> managerIsolate
  ReceivePort? _mainReceivePort;
  static const _pageSize = 30;

  final Map<String, int> _itemIndexMap = {};
  final List<ImageMetadata> _metadataBatch = [];
  static const _batchSize = 50;

  Future<void> initialLoad() async {
    state = state.copyWith(isLoading: true, items: [], hasMore: true);
    final dbService = _ref.read(databaseServiceProvider);
    final initialMetadata = await dbService.getImagesPaginated(_pageSize, 0);
    final initialItems = initialMetadata.map((meta) => FullImageItem(meta)).toList();

    _itemIndexMap.clear();
    for (int i = 0; i < initialItems.length; i++) {
      _itemIndexMap[initialItems[i].path] = i;
    }

    state = state.copyWith(
      items: initialItems,
      isLoading: false,
      hasMore: initialItems.length == _pageSize,
    );
  }

  Future<void> loadMoreImages() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);

    final dbService = _ref.read(databaseServiceProvider);
    final currentOffset = state.items.whereType<FullImageItem>().length;
    final newMetadata = await dbService.getImagesPaginated(_pageSize, currentOffset);
    final newItems = newMetadata.map((meta) => FullImageItem(meta)).toList();

    final currentLength = state.items.length;
    for (int i = 0; i < newItems.length; i++) {
      _itemIndexMap[newItems[i].path] = currentLength + i;
    }

    state = state.copyWith(
      items: [...state.items, ...newItems],
      isLoadingMore: false,
      hasMore: newItems.length == _pageSize,
    );
  }

  Future<void> syncFolder(String folderPath) async {
    if (_isSyncing) {
      _cleanupIsolate();
    }
    _isSyncing = true;
    _metadataBatch.clear();

    _ref.read(configProvider.notifier).setLastSyncedFolderPath(folderPath);
    state = state.copyWith(isLoading: true);

    final dbService = _ref.read(databaseServiceProvider);
    final existingFiles = await dbService.getAllImagePathsAndTimestamps();

    _mainReceivePort = ReceivePort();
    final thumbsDir = await getApplicationDocumentsDirectory();
    final thumbPathRoot = p.join(thumbsDir.path, 'thumbnails');

    try {
      final request = SyncRequest(
        folderPath: folderPath,
        thumbPathRoot: thumbPathRoot,
        mainSendPort: _mainReceivePort!.sendPort,
        existingFiles: existingFiles,
      );
      // [수정] 이제 manager_isolate.dart의 manageSyncProcess 함수를 호출
      _managerIsolate = await Isolate.spawn(manageSyncProcess, request);

      int totalFound = 0;
      int parsedCount = 0;
      await notificationService.showProgressNotification(1, 0, "파일 목록을 스캔하는 중...");

      _mainReceivePort!.listen((message) async {
        if (!mounted) {
          _cleanupIsolate();
          return;
        }

        if (message is FileFoundMessage) {
          totalFound = message.paths.length;
          final currentItems = List<GalleryItem>.from(state.items);
          final foundPathsSet = message.paths.toSet();

          // 삭제된 파일 처리
          final deletedPaths = state.items
              .where((item) => !foundPathsSet.contains(item.path))
              .map((item) => item.path)
              .toList();
          if (deletedPaths.isNotEmpty) {
            for (final path in deletedPaths) {
              await dbService.deleteImage(path);
              final itemToDelete = state.items.firstWhere((item) => item.path == path, orElse: () => TemporaryImageItem(''));
              if (itemToDelete is FullImageItem && itemToDelete.metadata.thumbnailPath.isNotEmpty) {
                final thumbFile = File(itemToDelete.metadata.thumbnailPath);
                if (await thumbFile.exists()) {
                  await thumbFile.delete();
                }
              }
            }
          }
          currentItems.removeWhere((item) => !foundPathsSet.contains(item.path));

          // 새로 추가된 파일 처리
          final existingPaths = _itemIndexMap.keys.toSet();
          final newPaths = message.paths.where((p) => !existingPaths.contains(p));
          for (final path in newPaths) {
            currentItems.add(TemporaryImageItem(path));
          }

          _itemIndexMap.clear();
          for (int i = 0; i < currentItems.length; i++) {
            _itemIndexMap[currentItems[i].path] = i;
          }

          state = state.copyWith(items: currentItems);
          await notificationService.showProgressNotification(totalFound, parsedCount, "$parsedCount / $totalFound 개 처리 중...");
        }
        else if (message is ParsingResultMessage) {
          parsedCount++;
          // [수정] message의 타입이 변경되었으므로, 내부 result 객체에 접근
          final result = message.result;
          final index = _itemIndexMap[result.path];
          if (index == null || index >= state.items.length) return;

          final currentItem = state.items[index];
          ImageMetadata existingMetadata;

          if (currentItem is FullImageItem) {
            existingMetadata = currentItem.metadata;
          } else {
            existingMetadata = ImageMetadata(
                path: result.path,
                thumbnailPath: result.thumbnailPath,
                timestamp: result.timestamp);
          }

          final finalMetadata = existingMetadata.copyWith(
            thumbnailPath: result.thumbnailPath,
            timestamp: result.timestamp,
            a1111Parameters: result.a1111Parameters,
            comfyUIWorkflow: result.comfyUIWorkflow,
            naiComment: result.naiComment,
          );

          _metadataBatch.add(finalMetadata);

          final newItems = List<GalleryItem>.from(state.items);
          newItems[index] = FullImageItem(finalMetadata);
          state = state.copyWith(items: newItems);

          if (_metadataBatch.length >= _batchSize) {
            await _flushMetadataBatch();
          }

          await notificationService.showProgressNotification(totalFound, parsedCount, "$parsedCount / $totalFound 개 처리 중...");
        }
        else if (message is SyncCompleteMessage) {
          await _flushMetadataBatch();
          state = state.copyWith(isLoading: false);

          await notificationService.showCompletionNotification("${message.totalCount}개 이미지 동기화 완료!");
          _cleanupIsolate();

          Future.delayed(const Duration(seconds: 2), () async {
            await notificationService.cancelNotification();
          });
        }
        else if (message is SyncErrorMessage) {
          debugPrint("Error from sync isolate: ${message.error}");
          await notificationService.showCompletionNotification("오류 발생: ${message.error}");
          state = state.copyWith(isLoading: false);
          _cleanupIsolate();
        }
      });
    } catch (e) {
      debugPrint("Error spawning isolate: $e");
      state = state.copyWith(isLoading: false);
      _cleanupIsolate();
    }
  }

  // --- 나머지 함수들은 변경 없음 ---
  Future<void> _flushMetadataBatch() async {
    if (_metadataBatch.isEmpty) return;
    final dbService = _ref.read(databaseServiceProvider);
    await dbService.insertOrUpdateImagesBatch(List.from(_metadataBatch));
    _metadataBatch.clear();
  }
  void _cleanupIsolate() {
    _isSyncing = false;
    _mainReceivePort?.close();
    if (_managerIsolate != null) {
      _managerIsolate!.kill(priority: Isolate.immediate);
      _managerIsolate = null;
    }
  }
  Future<void> toggleFavorite(ImageMetadata image) async {
    final dbService = _ref.read(databaseServiceProvider);
    final newFavoriteState = !image.isFavorite;
    await dbService.updateFavoriteStatus(image.path, newFavoriteState);

    final index = _itemIndexMap[image.path];
    if (index != null && index < state.items.length) {
      final item = state.items[index];
      if (item is FullImageItem) {
        final newItems = List<GalleryItem>.from(state.items);
        item.metadata.isFavorite = newFavoriteState;
        newItems[index] = FullImageItem(item.metadata.copyWith());
        state = state.copyWith(items: newItems);
      }
    }
  }
  Future<void> toggleNsfw(ImageMetadata image) async {
    final dbService = _ref.read(databaseServiceProvider);
    final newNsfwState = !image.isNsfw;
    await dbService.updateImageNsfwStatus(image.path, newNsfwState);
    final index = _itemIndexMap[image.path];
    if (index != null && index < state.items.length) {
      final item = state.items[index];
      if (item is FullImageItem) {
        final newItems = List<GalleryItem>.from(state.items);
        item.metadata.isNsfw = newNsfwState;
        newItems[index] = FullImageItem(item.metadata.copyWith());
        state = state.copyWith(items: newItems);
      }
    }
  }
  Future<void> rateImage(String path, double rating) async {
    final dbService = _ref.read(databaseServiceProvider);
    await dbService.updateImageRating(path, rating);
    final index = _itemIndexMap[path];
    if (index != null && index < state.items.length) {
      final item = state.items[index];
      if (item is FullImageItem) {
        final newItems = List<GalleryItem>.from(state.items);
        item.metadata.rating = rating;
        newItems[index] = FullImageItem(item.metadata.copyWith());
        state = state.copyWith(items: newItems);
      }
    }
  }
  Future<void> viewImage(String path) async {
    final dbService = _ref.read(databaseServiceProvider);
    await dbService.incrementImageViewCount(path);
    final index = _itemIndexMap[path];
    if (index != null && index < state.items.length) {
      final item = state.items[index];
      if (item is FullImageItem) {
        item.metadata.viewCount++;
      }
    }
  }
  Future<bool> deleteImage(ImageMetadata image) async {
    final dbService = _ref.read(databaseServiceProvider);
    try {
      final originalFile = File(image.path);
      if (await originalFile.exists()) {
        await originalFile.delete();
      }
      if (image.thumbnailPath.isNotEmpty) {
        final thumbFile = File(image.thumbnailPath);
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      }
      await dbService.deleteImage(image.path);
      final newItems = state.items.where((item) => item.path != image.path).toList();
      state = state.copyWith(items: newItems);
      _rebuildIndexMap();
      return true;
    } catch (e) {
      debugPrint("Error deleting file: $e");
      return false;
    }
  }
  void _rebuildIndexMap() {
    _itemIndexMap.clear();
    for(int i = 0; i < state.items.length; i++) {
      _itemIndexMap[state.items[i].path] = i;
    }
  }
  @override
  void dispose() {
    _cleanupIsolate();
    super.dispose();
  }
}