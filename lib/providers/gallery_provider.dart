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
import 'package:prompt_viewer/services/image_cache_service.dart';

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

/// [최종] 비동기 초기화와 상태 관리를 통합한 AsyncNotifierProvider
final galleryProvider = AsyncNotifierProvider<GalleryNotifier, GalleryState>(() {
  return GalleryNotifier();
});

/// [최종] Gallery State Notifier
class GalleryNotifier extends AsyncNotifier<GalleryState> {
  Isolate? _managerIsolate;
  ReceivePort? _mainReceivePort;
  static const _pageSize = 30;
  final Map<String, int> _itemIndexMap = {};
  final List<ImageMetadata> _metadataBatch = [];
  static const _batchSize = 50;

  /// Provider가 처음 생성될 때 비동기 초기화를 수행합니다.
  @override
  Future<GalleryState> build() async {
    final folderPath = ref.watch(folderPathProvider);
    if (folderPath == null) {
      // 선택된 폴더가 없으면 빈 상태로 즉시 완료.
      return const GalleryState();
    }
    // 선택된 폴더가 있으면 DB에서 첫 페이지를 로드하여 초기 상태를 구성합니다.
    return await _initialLoad();
  }

  /// DB에서 첫 페이지 데이터를 가져와 초기 상태를 생성하는 헬퍼 함수
  Future<GalleryState> _initialLoad() async {
    final dbService = ref.read(databaseServiceProvider);
    final initialMetadata = await dbService.getImagesPaginated(_pageSize, 0);
    final initialItems = initialMetadata.map((meta) => FullImageItem(meta)).toList();

    _itemIndexMap.clear();
    for (int i = 0; i < initialItems.length; i++) {
      _itemIndexMap[initialItems[i].path] = i;
    }

    return GalleryState(
      items: initialItems,
      hasMore: initialItems.length == _pageSize,
    );
  }

  /// 스크롤을 내렸을 때 다음 페이지 이미지를 로드합니다.
  Future<void> loadMoreImages() async {
    // state.value는 현재 로드된 GalleryState 데이터입니다.
    final currentState = state.value;
    if (currentState == null || currentState.isLoadingMore || !currentState.hasMore) return;

    // 로딩 시작 상태로 업데이트
    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    final dbService = ref.read(databaseServiceProvider);
    final currentOffset = currentState.items.whereType<FullImageItem>().length;
    final newMetadata = await dbService.getImagesPaginated(_pageSize, currentOffset);
    final newItems = newMetadata.map((meta) => FullImageItem(meta)).toList();

    final currentLength = currentState.items.length;
    for (int i = 0; i < newItems.length; i++) {
      _itemIndexMap[newItems[i].path] = currentLength + i;
    }

    // 로딩 완료 및 데이터 추가 상태로 업데이트
    state = AsyncData(currentState.copyWith(
      items: [...currentState.items, ...newItems],
      isLoadingMore: false,
      hasMore: newItems.length == _pageSize,
    ));
  }

  /// 폴더 동기화를 시작합니다. (멀티코어 워커 풀 사용)
  Future<void> syncFolder(String folderPath) async {
    final currentState = state.value;
    if (currentState == null || currentState.isSyncing) return;

    _metadataBatch.clear();
    ref.read(imageCacheProvider).clear();
    ref.read(configProvider.notifier).setLastSyncedFolderPath(folderPath);

    // 동기화 시작 상태로 UI 즉시 업데이트
    state = AsyncData(currentState.copyWith(isSyncing: true));

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

      _mainReceivePort!.listen((message) {
        // listen 콜백 안에서는 항상 최신 상태를 다시 읽어와야 합니다.
        final currentListenState = state.value;
        if (currentListenState == null) return;

        if (message is FileFoundMessage) {
          totalFound = message.paths.length;
          final currentItems = List<GalleryItem>.from(currentListenState.items);
          final foundPathsSet = message.paths.toSet();

          // 삭제된 파일 처리
          final deletedPaths = currentListenState.items
              .where((item) => !foundPathsSet.contains(item.path))
              .map((item) => item.path)
              .toList();
          if (deletedPaths.isNotEmpty) {
            // DB에서 삭제하는 작업은 비동기로 처리 (UI를 막지 않음)
            Future(() async {
              for (final path in deletedPaths) {
                await dbService.deleteImage(path);
              }
            });
          }
          currentItems.removeWhere((item) => deletedPaths.contains(item.path));

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
            _flushMetadataBatch();
          }

          notificationService.showProgressNotification(totalFound, parsedCount, "$parsedCount / $totalFound 개 처리 중...");
        }
        else if (message is SyncCompleteMessage) {
          _flushMetadataBatch();
          state = AsyncData(currentListenState.copyWith(isSyncing: false));

          notificationService.showCompletionNotification("${message.totalCount}개 이미지 동기화 완료!");
          _cleanupIsolate();

          Future.delayed(const Duration(seconds: 2), () async {
            await notificationService.cancelNotification();
          });
        }
        else if (message is SyncErrorMessage) {
          debugPrint("Error from sync isolate: ${message.error}");
          notificationService.showCompletionNotification("오류 발생: ${message.error}");
          state = AsyncData(currentListenState.copyWith(isSyncing: false));
          _cleanupIsolate();
        }
      });
    } catch (e) {
      if (state.value != null) {
        state = AsyncData(state.value!.copyWith(isSyncing: false));
      }
      debugPrint("Error spawning isolate: $e");
      _cleanupIsolate();
    }
  }

  // --- 이하 사용자 인터랙션 및 헬퍼 함수들 ---

  Future<void> _flushMetadataBatch() async {
    if (_metadataBatch.isEmpty) return;
    final dbService = ref.read(databaseServiceProvider);
    await dbService.insertOrUpdateImagesBatch(List.from(_metadataBatch));
    _metadataBatch.clear();
  }

  void _cleanupIsolate() {
    _mainReceivePort?.close();
    if (_managerIsolate != null) {
      _managerIsolate!.kill(priority: Isolate.immediate);
      _managerIsolate = null;
    }
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
    // 조회수는 UI에 직접적인 영향을 주지 않으므로 상태 업데이트 생략
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
}