// lib/screens/gallery_screen.dart

import 'dart:io';
import 'dart:typed_data';
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
import 'package:image/image.dart' as img;

// [신규] 실시간 썸네일 생성을 compute를 통해 백그라운드에서 처리하기 위한 최상위 함수
Future<Uint8List?> _generateThumbnailIsolate(String path) async {
  try {
    // 원본 파일을 읽어 썸네일 생성 후 JPG 바이트 데이터로 반환
    final fileBytes = await File(path).readAsBytes();
    final image = img.decodeImage(fileBytes);
    if (image == null) return null;
    final thumbnail = img.copyResizeCropSquare(image, size: 256);
    return Uint8List.fromList(img.encodeJpg(thumbnail, quality: 80));
  } catch (e) {
    debugPrint("On-the-fly thumbnail generation failed for $path: $e");
    return null;
  }
}

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
    // 위젯이 빌드된 후 첫 데이터 로드를 요청
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(galleryProvider.notifier).initialLoad();
    });

    // 스크롤 리스너 추가하여 페이지네이션 구현
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

  Future<void> _pickFolder() async {
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

    // DB에서 첫 페이지를 불러오는 동안 로딩 인디케이터 표시
    if (galleryState.isLoading && galleryState.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // NSFW 필터링 (FullImageItem에만 적용 가능)
    final itemsToDisplay = galleryState.items.where((item) {
      if (showNsfw) return true;
      if (item is FullImageItem) return !item.metadata.isNsfw;
      return true; // 임시 아이템은 필터링하지 않고 일단 보여줌
    }).toList();

    return itemsToDisplay.isEmpty && galleryState.items.isNotEmpty
        ? const Center(child: Text('NSFW 설정으로 인해 표시할 이미지가 없습니다.'))
        : itemsToDisplay.isEmpty
        ? _buildInitialView()
        : _buildGalleryView(itemsToDisplay, galleryState);
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
        _buildFolderTabs(folderPaths),
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
                child: _buildGalleryItem(context, item, filteredItems),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryItem(BuildContext context, GalleryItem item, List<GalleryItem> allItems) {
    // 1. 파싱 완료된 아이템: 저장된 썸네일 파일을 즉시 보여줌 (빠름)
    if (item is FullImageItem) {
      return InkWell(
        onTap: () => _navigateToFullScreen(context, item.path, allItems),
        onLongPress: () => _showContextMenu(context, ref, item.metadata),
        child: Hero(tag: item.path, child: Image.file(File(item.metadata.thumbnailPath), fit: BoxFit.cover)),
      );
    }
    // 2. 파싱 전 임시 아이템: 실시간으로 썸네일을 생성해서 보여줌
    else if (item is TemporaryImageItem) {
      return FutureBuilder<Uint8List?>(
        future: compute(_generateThumbnailIsolate, item.path),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
            return InkWell(
              onTap: () => _navigateToFullScreen(context, item.path, allItems),
              // 임시 아이템은 메타데이터가 없으므로 롱클릭 메뉴 비활성화
              child: Hero(tag: item.path, child: Image.memory(snapshot.data!, fit: BoxFit.cover)),
            );
          }
          // 썸네일 생성 중에는 회색 배경 표시
          return Container(color: Theme.of(context).colorScheme.surfaceContainer);
        },
      );
    }
    return const SizedBox.shrink();
  }

  void _navigateToFullScreen(BuildContext context, String currentPath, List<GalleryItem> allItems) {
    final allPaths = allItems.map((e) => e.path).toList();
    final initialIndex = allPaths.indexOf(currentPath);
    if (initialIndex == -1) return; // 안전장치

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

  Widget _buildFolderTabs(List<String> folderPaths) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0), child: SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, children: [
      _buildTab('전체', null, _selectedFolder == null),
      const SizedBox(width: 8),
      ...folderPaths.map((path) => Padding(padding: const EdgeInsets.only(right: 8.0), child: _buildTab(p.basename(path), path, _selectedFolder == path))),
    ],
    )),
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