// lib/providers/gallery_provider.dart

import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/main.dart';
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/providers/settings_provider.dart';
import 'package:prompt_viewer/services/manager_isolate.dart';
import 'package:prompt_viewer/services/database_service.dart';
import 'package:prompt_viewer/services/sharing_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:prompt_viewer/services/metadata_parser_service.dart';
import 'package:prompt_viewer/services/image_cache_service.dart';
import 'package:prompt_viewer/services/worker_isolate.dart'; // WorkerResult를 사용하기 위해 import 추가

// --- 데이터 모델 ---

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
  final bool isSyncing;
  final bool hasMore;
  final bool isLoadingMore;

  const GalleryState({
    this.items = const [],
    this.isSyncing = false,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  GalleryState copyWith({
    List<GalleryItem>? items,
    bool? isSyncing,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return GalleryState(
      items: items ?? this.items,
      isSyncing: isSyncing ?? this.isSyncing,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

// --- Provider 정의 ---

final databaseServiceProvider = Provider<DatabaseService>((ref) => DatabaseService.instance);
final folderPathProvider = Provider<String?>((ref) {
  return ref.watch(configProvider).lastSyncedFolderPath;
});
final sharingServiceProvider = Provider<SharingService>((ref) => SharingService());
final imageCacheProvider = ChangeNotifierProvider((ref) => ImageCacheService(maxSize: 150));

final galleryProvider = AsyncNotifierProvider<GalleryNotifier, GalleryState>(() {
  return GalleryNotifier();
});


class GalleryNotifier extends AsyncNotifier<GalleryState> {
  Isolate? _managerIsolate;
  ReceivePort? _mainReceivePort;
  static const _pageSize = 30;
  final Map<String, int> _itemIndexMap = {};
  final List<ImageMetadata> _metadataBatch = [];
  static const _batchSize = 50;

  @override
  Future<GalleryState> build() async {
    ref.onDispose(() {
      _cleanupIsolate();
    });

    final folderPath = ref.watch(folderPathProvider);
    if (folderPath == null) {
      return const GalleryState();
    }

    final initialState = await _initialLoad();

    // [수정] 백그라운드에서 모든 이미지 정보를 미리 로드하도록 활성화
    _loadAllImagesInBackground();

    return initialState;
  }

  Future<GalleryState> _initialLoad() async {
    final dbService = ref.read(databaseServiceProvider);
    final initialMetadata = await dbService.getImagesPaginated(_pageSize, 0);
    final initialItems = initialMetadata.map((meta) => FullImageItem(meta)).toList();

    _rebuildIndexMap(initialItems);

    return GalleryState(
      items: initialItems,
      hasMore: initialItems.length == _pageSize,
    );
  }

  Future<void> _loadAllImagesInBackground() async {
    final dbService = ref.read(databaseServiceProvider);
    final allMetadata = await dbService.getAllImages();
    final allItems = allMetadata.map((meta) => FullImageItem(meta)).toList();

    _rebuildIndexMap(allItems);

    if (state.hasValue) {
      state = AsyncData(state.value!.copyWith(
        items: allItems,
        hasMore: false,
      ));
    }
  }

  Future<void> loadMoreImages() async {
    final currentState = state.value;
    if (currentState == null || currentState.isLoadingMore || !currentState.hasMore) return;

    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    final dbService = ref.read(databaseServiceProvider);
    final currentOffset = currentState.items.whereType<FullImageItem>().length;
    final newMetadata = await dbService.getImagesPaginated(_pageSize, currentOffset);
    final newItems = newMetadata.map((meta) => FullImageItem(meta)).toList();

    final newCombinedItems = [...currentState.items, ...newItems];
    _rebuildIndexMap(newCombinedItems);

    state = AsyncData(currentState.copyWith(
      items: newCombinedItems,
      isLoadingMore: false,
      hasMore: newItems.length == _pageSize,
    ));
  }

  // [수정] 2번 코드의 효율적인 동기화 및 새로고침 로직으로 교체
  Future<void> syncFolder(String folderPath) async {
    if (state.value?.isSyncing == true) return;

    _metadataBatch.clear();
    ref.read(imageCacheProvider).clear();
    ref.read(configProvider.notifier).setLastSyncedFolderPath(folderPath);

    final initialState = state.value ?? const GalleryState();
    state = AsyncData(initialState.copyWith(isSyncing: true));

    final dbService = ref.read(databaseServiceProvider);
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
      _managerIsolate = await Isolate.spawn(manageSyncProcess, request);

      int totalFound = 0;
      int parsedCount = 0;
      await notificationService.showProgressNotification(1, 0, "파일 목록을 스캔하는 중...");

      _mainReceivePort!.listen((message) async {
        if (!state.hasValue) {
          _cleanupIsolate();
          return;
        }
        final currentListenState = state.value!;

        if (message is FileFoundMessage) {
          totalFound = message.paths.length;
          final currentItems = List<GalleryItem>.from(currentListenState.items);
          final foundPathsSet = message.paths.toSet();

          final deletedPaths = currentListenState.items
              .where((item) => !foundPathsSet.contains(item.path))
              .map((item) => item.path)
              .toList();
          if (deletedPaths.isNotEmpty) {
            Future(() async {
              for (final path in deletedPaths) {
                await dbService.deleteImage(path);
              }
            });
          }
          currentItems.removeWhere((item) => deletedPaths.contains(item.path));

          final existingPaths = _itemIndexMap.keys.toSet();
          final newPaths = message.paths.where((p) => !existingPaths.contains(p));
          for (final path in newPaths) {
            currentItems.add(TemporaryImageItem(path));
          }

          _rebuildIndexMap(currentItems);
          state = AsyncData(currentListenState.copyWith(items: currentItems));
          notificationService.showProgressNotification(totalFound, parsedCount, "$parsedCount / $totalFound 개 처리 중...");
        }
        else if (message is ParsingResultMessage) {
          parsedCount++;
          final result = message.result;
          final index = _itemIndexMap[result.path];
          if (index == null || index >= currentListenState.items.length) return;

          final currentItem = currentListenState.items[index];
          ImageMetadata existingMetadata = (currentItem is FullImageItem)
              ? currentItem.metadata
              : ImageMetadata(path: result.path, thumbnailPath: result.thumbnailPath, timestamp: result.timestamp);

          final finalMetadata = existingMetadata.copyWith(
            thumbnailPath: result.thumbnailPath,
            timestamp: result.timestamp,
            a1111Parameters: result.a1111Parameters,
            comfyUIWorkflow: result.comfyUIWorkflow,
            naiComment: result.naiComment,
          );

          _metadataBatch.add(finalMetadata);

          final newItems = List<GalleryItem>.from(currentListenState.items);
          newItems[index] = FullImageItem(finalMetadata);
          state = AsyncData(currentListenState.copyWith(items: newItems));

          if (_metadataBatch.length >= _batchSize) {
            await _flushMetadataBatch();
          }

          notificationService.showProgressNotification(totalFound, parsedCount, "$parsedCount / $totalFound 개 처리 중...");
        }
        else if (message is SyncCompleteMessage) {
          await _flushMetadataBatch();
          await _loadAllImagesInBackground();
          if (state.hasValue) {
            state = AsyncData(state.value!.copyWith(isSyncing: false));
          }

          notificationService.showCompletionNotification("${message.totalCount}개 이미지 동기화 완료!");
          _cleanupIsolate();

          Future.delayed(const Duration(seconds: 2), () async {
            await notificationService.cancelNotification();
          });
        }
        else if (message is SyncErrorMessage) {
          notificationService.showCompletionNotification("오류 발생: ${message.error}");
          if (state.hasValue) {
            state = AsyncData(state.value!.copyWith(isSyncing: false));
          }
          _cleanupIsolate();
        }
      });
    } catch (e) {
      if (state.hasValue) {
        state = AsyncData(state.value!.copyWith(isSyncing: false));
      }
      debugPrint("Error spawning isolate: $e");
      _cleanupIsolate();
    }
  }

  Future<void> _flushMetadataBatch() async {
    if (_metadataBatch.isEmpty) return;
    final dbService = ref.read(databaseServiceProvider);
    await dbService.insertOrUpdateImagesBatch(List.from(_metadataBatch));
    _metadataBatch.clear();
  }

  void _cleanupIsolate() {
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _managerIsolate?.kill(priority: Isolate.immediate);
    _managerIsolate = null;
  }

  Future<void> toggleFavorite(ImageMetadata image) async {
    final currentState = state.value;
    if (currentState == null) return;

    final dbService = ref.read(databaseServiceProvider);
    final newFavoriteState = !image.isFavorite;
    await dbService.updateFavoriteStatus(image.path, newFavoriteState);

    final index = _itemIndexMap[image.path];
    if (index != null && index < currentState.items.length) {
      final item = currentState.items[index];
      if (item is FullImageItem) {
        final newItems = List<GalleryItem>.from(currentState.items);
        newItems[index] = FullImageItem(item.metadata.copyWith(isFavorite: newFavoriteState));
        state = AsyncData(currentState.copyWith(items: newItems));
      }
    }
  }

  Future<void> toggleNsfw(ImageMetadata image) async {
    final currentState = state.value;
    if (currentState == null) return;

    final dbService = ref.read(databaseServiceProvider);
    final newNsfwState = !image.isNsfw;
    await dbService.updateImageNsfwStatus(image.path, newNsfwState);

    final index = _itemIndexMap[image.path];
    if (index != null && index < currentState.items.length) {
      final item = currentState.items[index];
      if (item is FullImageItem) {
        final newItems = List<GalleryItem>.from(currentState.items);
        newItems[index] = FullImageItem(item.metadata.copyWith(isNsfw: newNsfwState));
        state = AsyncData(currentState.copyWith(items: newItems));
      }
    }
  }

  Future<void> rateImage(String path, double rating) async {
    final currentState = state.value;
    if (currentState == null) return;

    final dbService = ref.read(databaseServiceProvider);
    await dbService.updateImageRating(path, rating);

    final index = _itemIndexMap[path];
    if (index != null && index < currentState.items.length) {
      final item = currentState.items[index];
      if (item is FullImageItem) {
        final newItems = List<GalleryItem>.from(currentState.items);
        newItems[index] = FullImageItem(item.metadata.copyWith(rating: rating));
        state = AsyncData(currentState.copyWith(items: newItems));
      }
    }
  }

  Future<void> viewImage(String path) async {
    final dbService = ref.read(databaseServiceProvider);
    await dbService.incrementImageViewCount(path);
  }

  Future<bool> deleteImage(ImageMetadata image) async {
    final currentState = state.value;
    if (currentState == null) return false;

    final dbService = ref.read(databaseServiceProvider);
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
      final newItems = currentState.items.where((item) => item.path != image.path).toList();
      _rebuildIndexMap(newItems);
      state = AsyncData(currentState.copyWith(items: newItems));
      return true;
    } catch (e) {
      debugPrint("Error deleting file: $e");
      return false;
    }
  }

  void _rebuildIndexMap(List<GalleryItem> items) {
    _itemIndexMap.clear();
    for(int i = 0; i < items.length; i++) {
      _itemIndexMap[items[i].path] = i;
    }
  }

  Future<List<String>> importAndProcessImages() async {
    final rootFolder = ref.read(folderPathProvider);
    if (rootFolder == null || rootFolder.isEmpty) {
      throw Exception("먼저 이미지를 저장할 갤러리 폴더를 선택해주세요.");
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    final List<String> needsMetadataPaths = [];

    if (result != null && result.files.isNotEmpty) {
      for (final file in result.files) {
        if (file.path == null) continue;

        final sourceFile = File(file.path!);
        final newPath = p.join(rootFolder, p.basename(sourceFile.path));
        await sourceFile.copy(newPath);

        final parser = ref.read(metadataParserProvider);
        final metadata = await parser.extractRawMetadata(newPath);

        if (metadata['a1111_parameters'] == null || metadata['a1111_parameters']!.isEmpty) {
          needsMetadataPaths.add(newPath);
        }
      }
      await syncFolder(rootFolder);
    }

    return needsMetadataPaths;
  }
}