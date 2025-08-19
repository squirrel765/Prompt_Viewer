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
                        // --- START: 에러 해결 부분 ---
                        // [수정] FullScreenViewer의 생성자 변경에 따라 호출 방식 수정
                        // 단일 이미지 경로를 리스트로 감싸고, 시작 인덱스를 0으로 전달합니다.
                        builder: (context) => FullScreenViewer(
                          imagePaths: [widget.metadata.path],
                          initialIndex: 0,
                        ),
                        // --- END: 에러 해결 부분 ---
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

  /// 메타데이터 종류를 선택하는 탭 위젯
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

  /// 개별 탭 아이템 위젯
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
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  /// 현재 선택된 탭에 따라 다른 프롬프트 뷰를 보여주는 위젯
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

  /// Stable Diffusion (A1111) 파라미터 뷰 위젯
  Widget _buildStableDiffusionView() {
    if (widget.metadata.a1111Parameters == null || widget.metadata.a1111Parameters!.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('Stable Diffusion 데이터가 없습니다.')));
    }
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

  /// ComfyUI 워크플로우 뷰 위젯
  Widget _buildComfyUIView() {
    final formattedJson = ref.read(metadataParserProvider).formatJson(widget.metadata.comfyUIWorkflow);
    if(formattedJson.contains("데이터가 없습니다")){
      return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('ComfyUI 데이터가 없습니다.')));
    }
    return _buildPromptSection('ComfyUI Workflow', formattedJson);
  }

  /// NovelAI 파라미터 뷰 위젯
  Widget _buildNovelAIView() {
    if (widget.metadata.naiComment == null || widget.metadata.naiComment!.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('NovelAI 데이터가 없습니다.')));
    }
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

  /// 프롬프트 내용을 표시하는 공통 섹션 위젯
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
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
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