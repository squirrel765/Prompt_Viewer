// lib/screens/image_selection_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/models/image_metadata.dart'; // ImageMetadata를 사용하기 위해 추가

class ImageSelectionScreen extends ConsumerStatefulWidget {
  final Set<String> initialSelection;
  const ImageSelectionScreen({super.key, required this.initialSelection});

  @override
  ConsumerState<ImageSelectionScreen> createState() => _ImageSelectionScreenState();
}

class _ImageSelectionScreenState extends ConsumerState<ImageSelectionScreen> {
  late Set<String> _selectedPaths;

  @override
  void initState() {
    super.initState();
    _selectedPaths = Set.from(widget.initialSelection);
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // --- START: 수정된 부분 ---
    final galleryState = ref.watch(galleryProvider);
    // 이 화면은 파싱이 완료된 이미지만을 선택 대상으로 하므로, FullImageItem만 필터링합니다.
    final List<ImageMetadata> allImages = galleryState.items.whereType<FullImageItem>().map((item) => item.metadata).toList();
    // --- END: 수정된 부분 ---

    return Scaffold(
      appBar: AppBar(
        title: Text('${_selectedPaths.length}개 선택됨'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done),
            onPressed: () {
              Navigator.pop(context, _selectedPaths.toList());
            },
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(4.0),
        itemCount: allImages.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 4.0,
          crossAxisSpacing: 4.0,
        ),
        itemBuilder: (context, index) {
          final image = allImages[index];
          final isSelected = _selectedPaths.contains(image.path);

          return InkWell(
            onTap: () => _toggleSelection(image.path),
            child: GridTile(
              footer: isSelected
                  ? const GridTileBar(backgroundColor: Colors.black54, leading: Icon(Icons.check_circle, color: Colors.white))
                  : null,
              child: Image.file(
                File(image.thumbnailPath), // 썸네일 사용
                fit: BoxFit.cover,
                // [경고 수정] withOpacity -> withAlpha
                color: isSelected ? Colors.white.withAlpha(128) : null,
                colorBlendMode: BlendMode.dstATop,
              ),
            ),
          );
        },
      ),
    );
  }
}