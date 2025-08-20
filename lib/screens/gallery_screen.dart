// lib/screens/gallery_screen.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
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

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  String? _selectedFolder;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // --- START: 핵심 수정 부분 ---
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final galleryState = ref.read(galleryProvider);
      final folderPath = ref.read(folderPathProvider);

      // [수정] 오직 폴더가 선택되어 있고, 갤러리 아이템이 비어 있으며, 로딩 중도 아닐 때만 initialLoad를 호출합니다.
      // 이렇게 하면 다른 탭에 갔다가 돌아왔을 때 상태가 초기화되는 것을 방지할 수 있습니다.
      if (folderPath != null && galleryState.items.isEmpty && !galleryState.isLoading) {
        ref.read(galleryProvider.notifier).initialLoad();
      }
    });
    // --- END: 핵심 수정 부분 ---

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
        ref.read(galleryProvider.notifier).loadMoreImages();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 폴더 선택 및 권한 요청을 처리하는 함수
  Future<void> _pickFolder() async {
    // 1. 알림 권한을 먼저 요청합니다 (Android 13 이상).
    final notificationStatus = await Permission.notification.request();
    if (mounted && !notificationStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알림 권한이 없어 진행 상태를 표시할 수 없습니다.')),
      );
    }

    // 2. 저장소 접근 권한을 요청합니다.
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
    final galleryState = ref.watch(galleryProvider);
    final showNsfw = ref.watch(configProvider).showNsfw;
    final hasInitialFolder = ref.watch(folderPathProvider) != null;

    // 동기화 중(isLoading)이면서 아이템이 비어있을 때
    if (galleryState.isLoading && galleryState.items.isEmpty) {
      // 이전에 선택한 폴더가 있다면 로딩 인디케이터를 보여줌
      return hasInitialFolder
          ? const Center(child: CircularProgressIndicator())
          : _buildInitialView(); // 선택한 폴더가 아예 없다면 초기 폴더 선택 화면
    }

    final itemsToDisplay = galleryState.items.where((item) {
      if (showNsfw) return true;
      if (item is FullImageItem) return !item.metadata.isNsfw;
      // TemporaryImageItem은 일단 보여줌 (NSFW 필터링은 파싱 후에 적용)
      return true;
    }).toList();

    // 동기화가 끝났는데도 아이템이 없는 경우 (또는 필터링으로 인해)
    if (itemsToDisplay.isEmpty) {
      // galleryState.items는 있지만 필터링 후 0개 -> NSFW 필터링 안내
      if (galleryState.items.isNotEmpty) {
        return const Center(child: Text('NSFW 설정으로 인해 표시할 이미지가 없습니다.'));
      }
      // galleryState.items 자체가 0개 -> 초기 폴더 선택 화면
      return _buildInitialView();
    }

    // 정상적으로 갤러리 표시
    return _buildGalleryView(itemsToDisplay, galleryState);
  }

  Widget _buildInitialView() {
    return Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.folder_open_outlined, size: 120, color: Colors.grey.shade400),
      const SizedBox(height: 24),
      const Text('이미지 폴더를 선택하세요', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('AI 생성 이미지가 포함된 폴더를 선택하여 갤러리를 시작하세요.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton(onPressed: _pickFolder, child: const Text('폴더 선택하기')),
    ],),),);
  }

  Widget _buildGalleryView(List<GalleryItem> galleryItems, GalleryState galleryState) {
    final folderPaths = galleryItems.whereType<FullImageItem>().map((item) => p.dirname(item.metadata.path)).toSet().toList();
    final filteredItems = _selectedFolder == null ? galleryItems : galleryItems.where((item) => p.dirname(item.path) == _selectedFolder).toList();

    return Column(
      children: [
        _buildFolderTabsAndCount(folderPaths, filteredItems.length),
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16.0),
            itemCount: filteredItems.length + (galleryState.hasMore ? 1 : 0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12.0, mainAxisSpacing: 12.0),
            itemBuilder: (context, index) {
              if (index == filteredItems.length) {
                return galleryState.isLoadingMore ? const Center(child: CircularProgressIndicator()) : const SizedBox.shrink();
              }

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
      return InkWell(
        onTap: () => _navigateToFullScreen(context, item.path, allItems),
        onLongPress: () => _showContextMenu(context, ref, item.metadata),
        child: Hero(
          tag: item.path,
          child: Image.file(
            File(item.metadata.thumbnailPath),
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => Container(color: Colors.grey.shade300),
          ),
        ),
      );
    }
    else if (item is TemporaryImageItem) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.0),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _navigateToFullScreen(BuildContext context, String currentPath, List<GalleryItem> allItems) {
    final allPaths = allItems.map((e) => e.path).toList();
    final initialIndex = allPaths.indexOf(currentPath);
    if (initialIndex == -1) return;

    Navigator.push(context, MaterialPageRoute(
      builder: (context) => FullScreenViewer(
        imagePaths: allPaths,
        initialIndex: initialIndex,
        onPageChanged: (viewedIndex) {
          final viewedItem = allItems[viewedIndex];
          if(viewedItem is FullImageItem) {
            ref.read(galleryProvider.notifier).viewImage(viewedItem.path);
          }
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
      ), const Divider(),
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
      ), const Divider(),
      ListTile(leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error), title: Text('삭제', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        onTap: () { Navigator.pop(context); ref.read(galleryProvider.notifier).deleteImage(image); },
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