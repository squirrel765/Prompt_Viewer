// lib/screens/detail_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:photo_view/photo_view.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart';
import 'package:prompt_viewer/screens/full_screen_viewer.dart';

enum DisplayMode { stableDiffusion, comfyUI, novelAI }

class DetailScreen extends ConsumerStatefulWidget {
  final ImageMetadata metadata;

  const DetailScreen({super.key, required this.metadata});

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  late DisplayMode _mode;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(galleryProvider.notifier).viewImage(widget.metadata.path);
      }
    });

    if (widget.metadata.naiComment != null && widget.metadata.naiComment!.isNotEmpty) {
      _mode = DisplayMode.novelAI;
    } else if (widget.metadata.comfyUIWorkflow != null && widget.metadata.comfyUIWorkflow!.isNotEmpty) {
      _mode = DisplayMode.comfyUI;
    } else {
      _mode = DisplayMode.stableDiffusion;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: '이미지 공유',
            onPressed: () async {
              try {
                final withMetadata = ref.read(configProvider).shareWithMetadata;
                await ref.read(sharingServiceProvider).shareImageFile(
                  widget.metadata.path,
                  withMetadata: withMetadata,
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('이미지 공유에 실패했습니다: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 3 / 2,
              child: Hero(
                tag: widget.metadata.path,
                child: PhotoView(
                  imageProvider: FileImage(File(widget.metadata.path)),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 2,
                  onTapUp: (context, details, controllerValue) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullScreenViewer(
                          imagePaths: [widget.metadata.path],
                          initialIndex: 0,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            _buildMetadataTabs(),
            _buildPromptView(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataTabs() {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1.0)),
      ),
      child: Row(
        children: [
          _buildTabItem('SD', DisplayMode.stableDiffusion),
          _buildTabItem('ComfyUI', DisplayMode.comfyUI),
          _buildTabItem('NAI', DisplayMode.novelAI),
        ],
      ),
    );
  }

  Widget _buildTabItem(String title, DisplayMode mode) {
    final isSelected = _mode == mode;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        setState(() {
          _mode = mode;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isSelected ? theme.colorScheme.primary : Colors.transparent,
              width: 3.0,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            // [경고 수정] withOpacity -> withAlpha
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withAlpha(179),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildPromptView() {
    switch (_mode) {
      case DisplayMode.stableDiffusion:
        return _buildStableDiffusionView();
      case DisplayMode.comfyUI:
        return _buildComfyUIView();
      case DisplayMode.novelAI:
        return _buildNovelAIView();
    }
  }

  Widget _buildStableDiffusionView() {
    if (widget.metadata.a1111Parameters == null || widget.metadata.a1111Parameters!.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('Stable Diffusion 데이터가 없습니다.')));
    }
    // [오류 수정] 이제 정상적으로 provider를 찾을 수 있습니다.
    final parsedData = ref.read(metadataParserProvider).parseA1111Parameters(widget.metadata.a1111Parameters!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPromptSection('Positive Prompt', parsedData['positive_prompt']),
        _buildPromptSection('Negative Prompt', parsedData['negative_prompt']),
        _buildPromptSection('Other Parameters', parsedData['other_params']),
      ],
    );
  }

  Widget _buildComfyUIView() {
    // [오류 수정] 이제 정상적으로 provider를 찾을 수 있습니다.
    final formattedJson = ref.read(metadataParserProvider).formatJson(widget.metadata.comfyUIWorkflow);
    if(formattedJson.contains("데이터가 없습니다")){
      return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('ComfyUI 데이터가 없습니다.')));
    }
    return _buildPromptSection('ComfyUI Workflow', formattedJson);
  }

  Widget _buildNovelAIView() {
    if (widget.metadata.naiComment == null || widget.metadata.naiComment!.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('NovelAI 데이터가 없습니다.')));
    }
    // [오류 수정] 이제 정상적으로 provider를 찾을 수 있습니다.
    final parsedData = ref.read(metadataParserProvider).parseNaiParameters(widget.metadata.naiComment!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPromptSection('Positive Prompt', parsedData['positive_prompt']),
        _buildPromptSection('Negative Prompt', parsedData['negative_prompt']),
        _buildPromptSection('Options', parsedData['options']),
      ],
    );
  }

  Widget _buildPromptSection(String title, String? content) {
    if (content == null || content.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy_all_outlined, size: 16),
                label: const Text('Copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$title 복사 완료!'), duration: const Duration(seconds: 1)),
                  );
                },
              )
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              // [경고 수정] surfaceVariant -> surfaceContainerHighest
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: SelectableText(
              content,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}