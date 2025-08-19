// lib/providers/gallery_provider.dart

import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/main.dart'; // notificationService를 사용하기 위해 import
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/services/background_parser.dart';
import 'package:prompt_viewer/services/database_service.dart';
import 'package:prompt_viewer/services/metadata_parser_service.dart';
import 'package:prompt_viewer/services/sharing_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// --- 갤러리 아이템의 상태를 표현하기 위한 클래스들 ---

/// 모든 갤러리 아이템의 기본이 되는 추상 클래스
abstract class GalleryItem {
  final String path;
  GalleryItem(this.path);
}

/// 파싱 전, 경로만 아는 상태의 임시 아이템
class TemporaryImageItem extends GalleryItem {
  TemporaryImageItem(String path) : super(path);
}

/// 파싱 완료 후, 모든 메타데이터를 가진 완전한 아이템
class FullImageItem extends GalleryItem {
  final ImageMetadata metadata;
  FullImageItem(this.metadata) : super(metadata.path);
}

/// GalleryProvider의 상태를 관리하는 클래스
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

// --- Provider 정의 ---
final databaseServiceProvider = Provider<DatabaseService>((ref) => DatabaseService.instance);
final folderPathProvider = StateProvider<String?>((ref) => null);
final sharingServiceProvider = Provider<SharingService>((ref) => SharingService());
final metadataParserProvider = Provider<MetadataParserService>((ref) => MetadataParserService());
final galleryProvider = StateNotifierProvider<GalleryNotifier, GalleryState>((ref) => GalleryNotifier(ref));

// --- State Notifier 클래스 ---
class GalleryNotifier extends StateNotifier<GalleryState> {
  final Ref _ref;
  GalleryNotifier(this._ref) : super(const GalleryState());

  bool _isSyncing = false;
  Isolate? _syncIsolate;
  ReceivePort? _mainReceivePort;
  static const _pageSize = 30;

  // [최적화] 경로를 키로 사용하여 아이템의 인덱스를 빠르게 찾기 위한 Map
  final Map<String, int> _itemIndexMap = {};

  /// 앱 시작 시 또는 새로고침 시 DB에서 첫 페이지만 불러옵니다.
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

  /// DB에서 다음 페이지를 불러와 기존 목록에 추가합니다.
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

  /// [핵심 최종 수정] 상태 업데이트를 최소화하여 성능을 극대화한 동기화 메서드
  Future<void> syncFolder(String folderPath) async {
    if (_isSyncing) {
      _cleanupIsolate();
    }
    _isSyncing = true;
    _itemIndexMap.clear();

    _ref.read(folderPathProvider.notifier).state = folderPath;
    state = state.copyWith(isLoading: true, items: []);

    _mainReceivePort = ReceivePort();
    final dbService = _ref.read(databaseServiceProvider);
    final thumbsDir = await getApplicationDocumentsDirectory();
    final thumbPathRoot = p.join(thumbsDir.path, 'thumbnails');

    try {
      final request = SyncRequest(
        folderPath: folderPath,
        thumbPathRoot: thumbPathRoot,
        mainSendPort: _mainReceivePort!.sendPort,
      );
      _syncIsolate = await Isolate.spawn(backgroundSyncAndParse, request);

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
          final currentItems = state.items;
          final newPaths = message.paths.where((path) => !_itemIndexMap.containsKey(path));

          for (final path in newPaths) {
            currentItems.add(TemporaryImageItem(path));
            _itemIndexMap[path] = currentItems.length - 1;
          }
          state = state.copyWith(items: currentItems, isLoading: false);
          await notificationService.showProgressNotification(totalFound, parsedCount, "$parsedCount / $totalFound 개 처리 중...");
        }
        else if (message is ParsingResultMessage) {
          parsedCount++;
          await dbService.insertOrUpdateImage(message.metadata);

          final index = _itemIndexMap[message.metadata.path];
          if (index != null && index < state.items.length) {
            state.items[index] = FullImageItem(message.metadata);

            if (parsedCount % 20 == 0 || parsedCount == totalFound) {
              state = state.copyWith(); // UI 갱신을 위해 호출
            }
          }
          await notificationService.showProgressNotification(totalFound, parsedCount, "$parsedCount / $totalFound 개 처리 중...");
        }
        else if (message is SyncCompleteMessage) {
          await notificationService.showCompletionNotification("${message.totalCount}개 이미지 동기화 완료!");
          state = state.copyWith(); // 마지막 변경사항 반영
          _cleanupIsolate();
          Future.delayed(const Duration(seconds: 2), () async {
            await notificationService.cancelNotification();
            await initialLoad();
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

  void _cleanupIsolate() {
    _isSyncing = false;
    _mainReceivePort?.close();
    _syncIsolate?.kill(priority: Isolate.immediate);
    _mainReceivePort = null;
    _syncIsolate = null;
  }

  Future<void> toggleFavorite(ImageMetadata image) async {
    final dbService = _ref.read(databaseServiceProvider);
    final newFavoriteState = !image.isFavorite;
    await dbService.updateFavoriteStatus(image.path, newFavoriteState);

    final newItems = state.items.map((item) {
      if (item is FullImageItem && item.path == image.path) {
        item.metadata.isFavorite = newFavoriteState;
      }
      return item;
    }).toList();
    state = state.copyWith(items: newItems);
  }

  Future<void> toggleNsfw(ImageMetadata image) async {
    final dbService = _ref.read(databaseServiceProvider);
    final newNsfwState = !image.isNsfw;
    await dbService.updateImageNsfwStatus(image.path, newNsfwState);
    final newItems = state.items.map((item) {
      if (item is FullImageItem && item.path == image.path) {
        item.metadata.isNsfw = newNsfwState;
      }
      return item;
    }).toList();
    state = state.copyWith(items: newItems);
  }

  Future<void> rateImage(String path, double rating) async {
    final dbService = _ref.read(databaseServiceProvider);
    await dbService.updateImageRating(path, rating);
    final newItems = state.items.map((item) {
      if (item is FullImageItem && item.path == path) {
        item.metadata.rating = rating;
      }
      return item;
    }).toList();
    state = state.copyWith(items: newItems);
  }

  Future<void> viewImage(String path) async {
    final dbService = _ref.read(databaseServiceProvider);
    await dbService.incrementImageViewCount(path);
    final newItems = state.items.map((item) {
      if (item is FullImageItem && item.path == path) {
        item.metadata.viewCount++;
      }
      return item;
    }).toList();
    state = state.copyWith(items: newItems);
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

      _itemIndexMap.remove(image.path);
      state = state.copyWith(items: state.items.where((item) => item.path != image.path).toList());
      // Rebuild index map after deletion
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