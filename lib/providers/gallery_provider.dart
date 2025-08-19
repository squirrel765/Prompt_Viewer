// lib/providers/gallery_provider.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/services/background_parser.dart';
import 'package:prompt_viewer/services/database_service.dart';
import 'package:prompt_viewer/services/metadata_parser_service.dart';
import 'package:prompt_viewer/services/sharing_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// --- [핵심 1] 갤러리 아이템의 상태를 표현하기 위한 클래스들 ---

/// 모든 갤러리 아이템의 기본이 되는 추상 클래스
abstract class GalleryItem {
  final String path;
  GalleryItem(this.path);
}

/// 1. 파싱 전, 경로만 아는 상태의 임시 아이템
class TemporaryImageItem extends GalleryItem {
  TemporaryImageItem(String path) : super(path);
}

/// 2. 파싱 완료 후, 모든 메타데이터를 가진 완전한 아이템
class FullImageItem extends GalleryItem {
  final ImageMetadata metadata;
  FullImageItem(this.metadata) : super(metadata.path);
}

/// [핵심 2] GalleryState가 이제 GalleryItem 리스트와 페이지네이션 상태를 관리
@immutable
class GalleryState {
  final List<GalleryItem> items;
  final bool isLoading; // 최초 스캔 또는 DB 첫 페이지 로딩
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
  static const _pageSize = 30; // 점진적 로딩 시 한 번에 불러올 이미지 개수

  /// 앱 시작 시 또는 새로고침 시 DB에서 첫 페이지만 불러옵니다.
  Future<void> initialLoad() async {
    state = state.copyWith(isLoading: true, items: [], hasMore: true);
    final dbService = _ref.read(databaseServiceProvider);
    final initialMetadata = await dbService.getImagesPaginated(_pageSize, 0);
    final initialItems = initialMetadata.map((meta) => FullImageItem(meta)).toList();
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
    final currentOffset = state.items.whereType<FullImageItem>().length; // FullImageItem 기준 offset
    final newMetadata = await dbService.getImagesPaginated(_pageSize, currentOffset);
    final newItems = newMetadata.map((meta) => FullImageItem(meta)).toList();

    state = state.copyWith(
      items: [...state.items, ...newItems],
      isLoadingMore: false,
      hasMore: newItems.length == _pageSize,
    );
  }

  /// "선(先)표시, 후(後)파싱" 전략을 구현한 동기화 메서드
  Future<void> syncFolder(String folderPath) async {
    if (_isSyncing) return;
    _isSyncing = true;
    state = state.copyWith(isLoading: true, items: []);

    try {
      // 1. 디스크에서 파일 경로 목록만 빠르게 스캔
      final directory = Directory(folderPath);
      final diskFiles = <File>[];
      if (await directory.exists()) {
        final stream = directory.list(recursive: true);
        await for (final entity in stream) {
          if (entity is File) {
            final path = entity.path.toLowerCase();
            if (path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg')) {
              diskFiles.add(entity);
            }
          }
        }
      }

      // 2. 임시 아이템으로 변환하여 UI에 즉시 표시
      final tempItems = diskFiles.map((file) => TemporaryImageItem(file.path)).toList();
      state = state.copyWith(isLoading: false, items: tempItems, hasMore: false);

      // --- 사용자 모르게 백그라운드에서 실제 작업 시작 ---
      final dbService = _ref.read(databaseServiceProvider);
      final thumbsDir = await getApplicationDocumentsDirectory();
      final thumbPathRoot = p.join(thumbsDir.path, 'thumbnails');

      // 3. 백그라운드에서 각 파일을 순차적으로 파싱하고 DB에 저장
      for (int i = 0; i < tempItems.length; i++) {
        final item = tempItems[i];
        final request = ParseRequest(filePath: item.path, thumbPathRoot: thumbPathRoot);
        final ImageMetadata? newMetadata = await compute(parseAndCreateThumbnail, request);

        if (newMetadata != null) {
          await dbService.insertOrUpdateImage(newMetadata);

          // 4. 파싱이 완료된 아이템을 FullImageItem으로 교체하고 UI 갱신
          final currentItems = List<GalleryItem>.from(state.items);
          if (i < currentItems.length && currentItems[i] is TemporaryImageItem) {
            currentItems[i] = FullImageItem(newMetadata);
            state = state.copyWith(items: currentItems);
          }
        }
      }

      // 5. 모든 동기화가 끝나면, DB 기준으로 첫 페이지를 다시 로드하여 최종 상태로 전환
      await initialLoad();
      _ref.read(folderPathProvider.notifier).state = folderPath;

    } catch (e) {
      debugPrint("Error during folder sync: $e");
      state = state.copyWith(isLoading: false);
    } finally {
      _isSyncing = false;
    }
  }

  // --- 상태 변경 메서드 (FullImageItem을 찾아 수정) ---
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
      await File(image.path).delete();
      if (image.thumbnailPath.isNotEmpty) {
        final thumbFile = File(image.thumbnailPath);
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      }
      await dbService.deleteImage(image.path);
      state = state.copyWith(items: state.items.where((item) => item.path != image.path).toList());
      return true;
    } catch (e) {
      debugPrint("Error deleting file: $e");
      return false;
    }
  }
}