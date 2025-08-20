// lib/screens/image_selection_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/models/image_metadata.dart';

/// [최종] galleryProvider의 비동기 상태를 처리하는 메인 위젯
class ImageSelectionScreen extends ConsumerWidget {
  final Set<String> initialSelection;
  const ImageSelectionScreen({super.key, required this.initialSelection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // galleryProvider의 AsyncValue 상태를 watch
    final galleryAsyncValue = ref.watch(galleryProvider);

    // AsyncValue의 상태에 따라 다른 UI를 보여줌 (when 사용)
    return Scaffold(
      body: galleryAsyncValue.when(
        // 데이터 로딩 중
        loading: () => const Center(child: CircularProgressIndicator()),
        // 에러 발생
        error: (err, stack) => Center(child: Text('이미지를 불러올 수 없습니다: $err')),
        // 데이터 로딩 성공
        data: (galleryState) {
          // 실제 UI는 별도의 위젯으로 분리하여 상태(state)를 전달
          return _ImageSelectionContent(
            galleryState: galleryState,
            initialSelection: initialSelection,
          );
        },
      ),
    );
  }
}

/// 실제 이미지 선택 UI를 표시하는 위젯
class _ImageSelectionContent extends ConsumerStatefulWidget {
  final GalleryState galleryState;
  final Set<String> initialSelection;

  const _ImageSelectionContent({
    required this.galleryState,
    required this.initialSelection,
  });

  @override
  ConsumerState<_ImageSelectionContent> createState() => _ImageSelectionContentState();
}

class _ImageSelectionContentState extends ConsumerState<_ImageSelectionContent> {
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
    // 이제 galleryState는 상위 위젯에서 안전하게 받아옵니다.
    // 이 화면은 파싱이 완료된 이미지만을 선택 대상으로 하므로, FullImageItem만 필터링합니다.
    final List<ImageMetadata> allImages = widget.galleryState.items
        .whereType<FullImageItem>()
        .map((item) => item.metadata)
        .toList();

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
                  ? const GridTileBar(
                  backgroundColor: Colors.black54,
                  leading: Icon(Icons.check_circle, color: Colors.white))
                  : null,
              child: Image.file(
                File(image.thumbnailPath), // 썸네일 사용
                fit: BoxFit.cover,
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