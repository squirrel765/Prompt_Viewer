// lib/screens/gallery_screen.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart';
import 'package:prompt_viewer/screens/detail_screen.dart';
import 'package:path/path.dart' as p;
import 'package:prompt_viewer/screens/preset_editor_screen.dart';
import 'package:prompt_viewer/screens/full_screen_viewer.dart';

/// galleryProvider의 비동기 상태를 처리하는 메인 위젯
class GalleryScreen extends ConsumerWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final galleryAsyncValue = ref.watch(galleryProvider);

    return galleryAsyncValue.when(
      data: (galleryState) => _GalleryScreenContent(galleryState: galleryState),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('갤러리를 불러오는 중 오류 발생:\n$err')),
    );
  }
}

/// 실제 갤러리 UI를 표시하는 위젯
class _GalleryScreenContent extends ConsumerStatefulWidget {
  final GalleryState galleryState;
  const _GalleryScreenContent({required this.galleryState});

  @override
  ConsumerState<_GalleryScreenContent> createState() => _GalleryScreenContentState();
}

class _GalleryScreenContentState extends ConsumerState<_GalleryScreenContent> {
  String? _selectedFolder;
  // [수정] 페이지네이션을 사용하지 않으므로 ScrollController 제거
  // final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // [수정] ScrollController 리스너 제거
  }

  @override
  void dispose() {
    // [수정] ScrollController dispose 제거
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final notificationStatus = await Permission.notification.request();
    if (mounted && !notificationStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림 권한이 없어 진행 상태를 표시할 수 없습니다.')),
      );
    }

    if (await Permission.storage.request().isGranted || await Permission.manageExternalStorage.request().isGranted) {
      final folderPath = await FilePicker.platform.getDirectoryPath();
      if (folderPath != null && mounted) {
        ref.read(galleryProvider.notifier).syncFolder(folderPath);
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('파일 접근 권한이 거부되어 폴더를 열 수 없습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final galleryState = widget.galleryState;
    final showNsfw = ref.watch(configProvider).showNsfw;

    final itemsToDisplay = galleryState.items.where((item) {
      if (showNsfw) return true;
      if (item is FullImageItem) return !item.metadata.isNsfw;
      return true; // TemporaryItem은 일단 보여줌
    }).toList();

    if (itemsToDisplay.isEmpty && !galleryState.isSyncing) {
      return _buildInitialView();
    }

    return _buildGalleryView(itemsToDisplay, galleryState);
  }

  Widget _buildInitialView() {
    return Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.folder_open_outlined, size: 120, color: Colors.grey.shade400),
      const SizedBox(height: 24),
      const Text('이미지 폴더를 선택하세요', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('AI 생성 이미지가 포함된 폴더를 선택하여 갤러리를 시작하세요.\n외부 이미지는 좌측 메뉴의 Import 기능을 이용해주세요.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton(onPressed: _pickFolder, child: const Text('폴더 선택하기')),
    ],),),);
  }

  Widget _buildGalleryView(List<GalleryItem> galleryItems, GalleryState galleryState) {
    final folderPaths = galleryItems.whereType<FullImageItem>().map((item) => p.dirname(item.metadata.path)).toSet().toList();
    final filteredItems = _selectedFolder == null ? galleryItems : galleryItems.where((item) {
      if (item is FullImageItem) {
        return p.dirname(item.metadata.path) == _selectedFolder;
      }
      return false; // TemporaryItem은 폴더 정보가 없으므로 필터링 시 제외
    }).toList();

    return Column(
      children: [
        _buildFolderTabsAndCount(folderPaths, filteredItems.length),
        Expanded(
          child: GridView.builder(
            // [수정] ScrollController 제거
            padding: const EdgeInsets.all(16.0),
            // [수정] itemCount를 간단하게 변경
            itemCount: filteredItems.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12.0, mainAxisSpacing: 12.0),
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: _buildGalleryItem(context, item, galleryItems),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryItem(BuildContext context, GalleryItem item, List<GalleryItem> allItems) {
    if (item is FullImageItem) {
      // image_cache_service를 사용하지 않고 직접 Image.file을 사용하여 OS 캐싱에 의존
      return InkWell(
        onTap: () => _navigateToFullScreen(context, item.path, allItems),
        onLongPress: () => _showContextMenu(context, ref, item.metadata),
        child: Hero(
          tag: item.path,
          child: Image.file(
            File(item.metadata.thumbnailPath),
            fit: BoxFit.cover,
            gaplessPlayback: true, // 이미지 로딩 중 깜빡임 방지
            errorBuilder: (context, error, stackTrace) {
              // 썸네일 로딩 실패 시 아이콘 표시
              return Container(
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: const Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey)),
              );
            },
          ),
        ),
      );
    }

    // TemporaryImageItem의 경우 로딩 인디케이터 표시
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.0))),
    );
  }


  void _navigateToFullScreen(BuildContext context, String currentPath, List<GalleryItem> allItems) {
    // FullScreenViewer에는 FullImageItem의 경로만 전달
    final imagePaths = allItems.whereType<FullImageItem>().map((e) => e.path).toList();
    final initialIndex = imagePaths.indexOf(currentPath);
    if (initialIndex == -1) return;

    Navigator.push(context, MaterialPageRoute(
      builder: (context) => FullScreenViewer(
        imagePaths: imagePaths,
        initialIndex: initialIndex,
        onPageChanged: (viewedIndex) {
          final viewedPath = imagePaths[viewedIndex];
          ref.read(galleryProvider.notifier).viewImage(viewedPath);
        },
      ),
    ),
    );
  }

  Widget _buildFolderTabsAndCount(List<String> folderPaths, int imageCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildTab('전체', null, _selectedFolder == null),
                  const SizedBox(width: 8),
                  ...folderPaths.map((path) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: _buildTab(p.basename(path), path, _selectedFolder == path))),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '$imageCount 개',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTab(String title, String? path, bool isSelected) {
    final theme = Theme.of(context);
    return ActionChip(
      label: Text(title),
      onPressed: () => setState(() => _selectedFolder = path),
      avatar: isSelected ? Icon(Icons.check, size: 18, color: theme.colorScheme.primary) : null,
      backgroundColor: isSelected ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
      side: isSelected ? BorderSide(color: theme.colorScheme.primary) : BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      labelStyle: TextStyle(color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref, ImageMetadata image) {
    showModalBottomSheet(context: context, builder: (context) => Wrap(children: <Widget>[
      ListTile(leading: const Icon(Icons.info_outline), title: const Text('자세히 보기 (프롬프트)'),
        onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => DetailScreen(metadata: image))); },
      ),
      ListTile(
        leading: const Icon(Icons.share_outlined),
        title: const Text('이미지 공유'),
        onTap: () async {
          Navigator.pop(context);
          final withMetadata = ref.read(configProvider).shareWithMetadata;
          await ref.read(sharingServiceProvider).shareImageFile(image.path, withMetadata: withMetadata);
        },
      ),
      const Divider(),
      ListTile(leading: Icon(image.isFavorite ? Icons.star : Icons.star_border), title: Text(image.isFavorite ? '즐겨찾기에서 제거' : '즐겨찾기에 추가'),
        onTap: () { ref.read(galleryProvider.notifier).toggleFavorite(image); Navigator.pop(context); },
      ),
      ListTile(leading: const Icon(Icons.star_half_outlined), title: const Text('별점 매기기'),
        onTap: () { Navigator.pop(context); _showRatingDialog(context, ref, image); },
      ),
      ListTile(leading: const Icon(Icons.add_photo_alternate_outlined), title: const Text('프리셋 만들기'),
        onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => PresetEditorScreen(initialImagePath: image.path), fullscreenDialog: true)); },
      ),
      ListTile(leading: Icon(image.isNsfw ? Icons.visibility_off_outlined : Icons.visibility_outlined), title: Text(image.isNsfw ? 'NSFW 해제' : 'NSFW로 표시'),
        onTap: () { ref.read(galleryProvider.notifier).toggleNsfw(image); Navigator.pop(context); },
      ),
      const Divider(),
      ListTile(leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error), title: Text('삭제', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        onTap: () { ref.read(galleryProvider.notifier).deleteImage(image); Navigator.pop(context); },
      ),
    ],
    ));
  }

  Future<void> _showRatingDialog(BuildContext context, WidgetRef ref, ImageMetadata image) async {
    double currentRating = image.rating;
    return showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('별점 매기기'),
      content: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (index) => IconButton(
        icon: Icon(index < currentRating ? Icons.star : Icons.star_border, color: Colors.amber),
        onPressed: () => setDialogState(() => currentRating = index + 1.0),
      ))),
      actions: [
        TextButton(child: const Text('취소'), onPressed: () => Navigator.pop(context)),
        TextButton(child: const Text('저장'), onPressed: () { ref.read(galleryProvider.notifier).rateImage(image.path, currentRating); Navigator.pop(context); }),
      ],
    )));
  }
}