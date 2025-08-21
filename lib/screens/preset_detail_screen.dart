// lib/screens/preset_detail_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:prompt_viewer/models/prompt_preset.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/providers/preset_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart';
import 'package:prompt_viewer/screens/detail_screen.dart';
import 'package:prompt_viewer/screens/preset_editor_screen.dart';
import 'package:prompt_viewer/screens/full_screen_viewer.dart';

class PresetDetailScreen extends ConsumerStatefulWidget {
  final String presetId;
  const PresetDetailScreen({super.key, required this.presetId});

  @override
  ConsumerState<PresetDetailScreen> createState() => _PresetDetailScreenState();
}

class _PresetDetailScreenState extends ConsumerState<PresetDetailScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(() {
      if (_pageController.page?.round() != _currentPage) {
        if (mounted) {
          setState(() {
            _currentPage = _pageController.page!.round();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// [신규] 이미지 롱클릭 시 컨텍스트 메뉴를 표시하는 함수
  void _showImageContextMenu(BuildContext context, PromptPreset preset, String imagePath) {
    final galleryState = ref.read(galleryProvider).value;
    if (galleryState == null) return;

    // [오류 수정] firstWhere 대신 firstWhereOrNull을 사용하여 null 안전성을 확보합니다.
    final imageMetadata = galleryState.items
        .whereType<FullImageItem>()
        .firstWhereOrNull((item) => item.metadata.path == imagePath)
        ?.metadata;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Wrap(children: [
        ListTile(
          leading: const Icon(Icons.share_outlined),
          title: const Text('공유'),
          onTap: () async {
            Navigator.pop(ctx);
            final withMetadata = ref.read(configProvider).shareWithMetadata;
            await ref.read(sharingServiceProvider).shareImageFile(imagePath, withMetadata: withMetadata);
          },
        ),
        if (imageMetadata != null)
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('자세히 보기 (프롬프트)'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (context) => DetailScreen(metadata: imageMetadata)));
            },
          ),
        ListTile(
          leading: Icon(Icons.remove_circle_outline, color: Theme.of(context).colorScheme.error),
          title: Text('프리셋에서 제거', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () {
            Navigator.pop(ctx);
            if (preset.imagePaths.length > 1) {
              ref.read(presetProvider.notifier).removeImageFromPreset(preset.id, imagePath);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('프리셋에는 최소 1개의 이미지가 필요합니다.')),
              );
            }
          },
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final presetList = ref.watch(presetProvider);
    final preset = presetList.firstWhere(
          (p) => p.id == widget.presetId,
      orElse: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).pop();
        });
        return PromptPreset(id: '', title: '', prompt: '', thumbnailPath: '', imagePaths: []);
      },
    );

    if (preset.id.isEmpty) {
      return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: const Center(child: CircularProgressIndicator())
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '프리셋 수정',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PresetEditorScreen(preset: preset),
                  fullscreenDialog: true,
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImageGallery(preset),

          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8.0,
                      children: [
                        Text(
                          preset.title,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onBackground,
                          ),
                        ),
                        if (preset.isNsfw)
                          const Chip(
                            label: Text('NSFW'),
                            backgroundColor: Colors.redAccent,
                            labelStyle: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildRatingSection(preset.rating),
                    const SizedBox(height: 16),
                    SelectableText(
                      preset.prompt,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        label: const Text('프롬프트 복사'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: preset.prompt));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('프롬프트가 클립보드에 복사되었습니다.')),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.colorScheme.onSurfaceVariant,
                          side: BorderSide(color: theme.dividerColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGallery(PromptPreset preset) {
    return AspectRatio(
      aspectRatio: 1 / 1.1,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: preset.imagePaths.length,
            itemBuilder: (context, index) {
              final imagePath = preset.imagePaths[index];
              return GestureDetector(
                onLongPress: () {
                  _showImageContextMenu(context, preset, imagePath);
                },
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FullScreenViewer(
                        imagePaths: preset.imagePaths,
                        initialIndex: index,
                      ),
                    ),
                  );
                },
                child: Hero(
                  tag: imagePath,
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.broken_image)),
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(bottom: 16, top: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withOpacity(0.4)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(preset.imagePaths.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    height: 6,
                    width: 6,
                    decoration: BoxDecoration(
                      color: _currentPage == index ? Colors.white : Colors.white.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSection(double rating) {
    final theme = Theme.of(context);
    List<Widget> stars = [];
    int fullStars = rating.floor();
    bool hasHalfStar = (rating - fullStars) >= 0.5;

    for (int i = 0; i < 5; i++) {
      if (i < fullStars) {
        stars.add(const Icon(Icons.star, color: Colors.amber, size: 24));
      } else if (i == fullStars && hasHalfStar) {
        stars.add(const Icon(Icons.star_half, color: Colors.amber, size: 24));
      } else {
        stars.add(const Icon(Icons.star_border, color: Colors.amber, size: 24));
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              height: 1.0,
              color: theme.colorScheme.onBackground
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: stars),
            Text(
              'My Rating',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}