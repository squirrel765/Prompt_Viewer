// lib/screens/gallery_screen.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart'; // 설정 provider 임포트
import 'package:prompt_viewer/screens/detail_screen.dart';
import 'package:path/path.dart' as p;
import 'package:prompt_viewer/screens/preset_editor_screen.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  String? _selectedFolder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(galleryProvider.notifier).initialLoad();
    });
  }

  Future<void> _pickFolder() async {
    if (await Permission.storage.request().isGranted || await Permission.manageExternalStorage.request().isGranted) {
      final folderPath = await FilePicker.platform.getDirectoryPath();
      if (folderPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지를 불러오고 동기화하는 중...'), duration: Duration(days: 1)),
        );
        await ref.read(galleryProvider.notifier).syncFolder(folderPath);
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('동기화 완료!'), duration: Duration(seconds: 2)),
          );
        }
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('파일 접근 권한이 거부되어 폴더를 열 수 없습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allImages = ref.watch(galleryProvider);
    final showNsfw = ref.watch(configProvider).showNsfw;

    // NSFW 설정에 따라 이미지 필터링
    final imagesToDisplay = showNsfw ? allImages : allImages.where((img) => !img.isNsfw).toList();

    return imagesToDisplay.isEmpty && allImages.isNotEmpty
        ? const Center(child: Text('NSFW 설정으로 인해 표시할 이미지가 없습니다.'))
        : imagesToDisplay.isEmpty
        ? _buildInitialView()
        : _buildGalleryView(imagesToDisplay);
  }

  Widget _buildInitialView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_outlined, size: 120, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            const Text(
              'Select an image folder',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap here to choose a folder containing your AI-generated images.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _pickFolder,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Select Folder'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryView(List<ImageMetadata> allImages) {
    final folderPaths = allImages.map((img) => p.dirname(img.path)).toSet().toList();
    final filteredImages = _selectedFolder == null
        ? allImages
        : allImages.where((img) => p.dirname(img.path) == _selectedFolder).toList();

    return Column(
      children: [
        _buildFolderTabs(folderPaths),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: filteredImages.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12.0,
              mainAxisSpacing: 12.0,
            ),
            itemBuilder: (context, index) {
              final image = filteredImages[index];
              return InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => DetailScreen(metadata: image)),
                ),
                // 이미지를 길게 누르면 컨텍스트 메뉴 표시
                onLongPress: () => _showContextMenu(context, ref, image),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Image.file(
                    File(image.path),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.broken_image_outlined, color: Colors.grey);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFolderTabs(List<String> folderPaths) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildTab('All Images', null, _selectedFolder == null),
            const SizedBox(width: 8),
            ...folderPaths.map((path) {
              final folderName = p.basename(path);
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _buildTab(folderName, path, _selectedFolder == path),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String title, String? path, bool isSelected) {
    final theme = Theme.of(context);
    return ActionChip(
      label: Text(title),
      onPressed: () {
        setState(() {
          _selectedFolder = path;
        });
      },
      avatar: isSelected ? Icon(Icons.check, size: 18, color: theme.colorScheme.primary) : null,
      backgroundColor: isSelected ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceVariant,
      side: isSelected ? BorderSide(color: theme.colorScheme.primary) : BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      labelStyle: TextStyle(
        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  /// 이미지를 길게 눌렀을 때 표시될 컨텍스트 메뉴
  void _showContextMenu(BuildContext context, WidgetRef ref, ImageMetadata image) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: Icon(image.isFavorite ? Icons.star : Icons.star_border),
              title: Text(image.isFavorite ? '즐겨찾기에서 제거' : '즐겨찾기에 추가'),
              onTap: () {
                ref.read(galleryProvider.notifier).toggleFavorite(image);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_half_outlined),
              title: const Text('별점 매기기'),
              onTap: () {
                Navigator.pop(context);
                _showRatingDialog(context, ref, image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('프리셋 만들기'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PresetEditorScreen(initialImagePath: image.path),
                    fullscreenDialog: true,
                  ),
                );
              },
            ),
            // *** 새로 추가된 NSFW 토글 메뉴 ***
            ListTile(
              leading: Icon(image.isNsfw ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              title: Text(image.isNsfw ? 'NSFW 해제' : 'NSFW로 표시'),
              onTap: () {
                ref.read(galleryProvider.notifier).toggleNsfw(image);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
              title: Text('삭제', style: TextStyle(color: Colors.red.shade400)),
              onTap: () {
                Navigator.pop(context);
                // TODO: 삭제 확인 다이얼로그 추가
                ref.read(galleryProvider.notifier).deleteImage(image);
              },
            ),
          ],
        );
      },
    );
  }

  /// 별점 선택 팝업(Dialog)을 띄우는 함수
  Future<void> _showRatingDialog(BuildContext context, WidgetRef ref, ImageMetadata image) async {
    double currentRating = image.rating;
    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('별점 매기기'),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < currentRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        // 별점을 0.5 단위로 매길 수 있도록 로직 수정 (선택사항)
                        // currentRating = index + 1.0;
                        // 아래는 0.5 단위 로직 예시
                        if (currentRating == index + 0.5) {
                          currentRating = index + 1.0;
                        } else if(currentRating == index + 1.0){
                          currentRating = index + 0.5;
                        }
                        else{
                          currentRating = index + 1.0;
                        }
                      });
                    },
                  );
                }),
              ),
              actions: [
                TextButton(child: const Text('취소'), onPressed: () => Navigator.pop(context)),
                TextButton(
                  child: const Text('저장'),
                  onPressed: () {
                    ref.read(galleryProvider.notifier).rateImage(image.path, currentRating);
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}