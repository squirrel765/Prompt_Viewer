// lib/screens/metadata_embedding_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/services/metadata_parser_service.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart'; // folderPathProvider를 위해 추가

class MetadataEmbeddingScreen extends ConsumerStatefulWidget {
  final String imagePath;
  final String? initialPositive;
  final String? initialNegative;
  final String? initialOther;

  const MetadataEmbeddingScreen({
    super.key,
    required this.imagePath,
    this.initialPositive,
    this.initialNegative,
    this.initialOther,
  });

  @override
  ConsumerState<MetadataEmbeddingScreen> createState() =>
      _MetadataEmbeddingScreenState();
}

class _MetadataEmbeddingScreenState extends ConsumerState<MetadataEmbeddingScreen> {
  late final TextEditingController _positiveController;
  late final TextEditingController _negativeController;
  late final TextEditingController _otherParamsController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _positiveController = TextEditingController(text: widget.initialPositive ?? '');
    _negativeController = TextEditingController(text: widget.initialNegative ?? '');

    // --- START: 핵심 수정 부분 ---
    // 기존 other 파라미터가 비어있을 경우, 기본 양식을 채워줍니다.
    final initialOtherText = widget.initialOther ?? '';
    _otherParamsController = TextEditingController(
      text: initialOtherText.trim().isEmpty
          ? 'Steps: 20, Sampler: DPM++ 2M Karras, CFG scale: 7, Seed: -1, Size: 512x512'
          : initialOtherText,
    );
    // --- END: 핵심 수정 부분 ---
  }

  @override
  void dispose() {
    _positiveController.dispose();
    _negativeController.dispose();
    _otherParamsController.dispose();
    super.dispose();
  }

  Future<void> _saveMetadata() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final parserService = ref.read(metadataParserProvider);
      // 입력된 프롬프트들을 A1111 형식의 단일 문자열로 조합
      final newMetadataString = parserService.buildA1111Parameters(
        positivePrompt: _positiveController.text,
        negativePrompt: _negativeController.text,
        otherParams: _otherParamsController.text,
      );

      // 조합된 문자열을 이미지 파일에 메타데이터로 주입
      await parserService.embedMetadataInImage(widget.imagePath, newMetadataString);

      // 현재 동기화된 폴더를 다시 스캔하여 변경사항 즉시 반영
      final currentFolder = ref.read(folderPathProvider);
      if (currentFolder != null && currentFolder.isNotEmpty) {
        // syncFolder가 완료될 때까지 기다립니다.
        await ref.read(galleryProvider.notifier).syncFolder(currentFolder);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메타데이터 저장 완료!')),
        );
        Navigator.of(context).pop();
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메타데이터 저장에 실패했습니다: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('메타데이터 편집'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt_outlined),
            tooltip: '저장',
            onPressed: _saveMetadata,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12.0),
              child: Image.file(File(widget.imagePath)),
            ),
            const SizedBox(height: 24),
            _buildTextField(controller: _positiveController, label: 'Positive Prompt'),
            const SizedBox(height: 16),
            _buildTextField(controller: _negativeController, label: 'Negative Prompt'),
            const SizedBox(height: 16),
            // [수정] 라벨을 간결하게 변경
            _buildTextField(controller: _otherParamsController, label: 'Other Parameters'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_isSaving ? '저장 중...' : '이미지에 메타데이터 저장'),
                onPressed: _isSaving ? null : _saveMetadata,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      maxLines: null,
      keyboardType: TextInputType.multiline,
    );
  }
}