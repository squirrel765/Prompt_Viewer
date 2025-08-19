// lib/screens/preset_editor_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/models/prompt_preset.dart';
import 'package:prompt_viewer/providers/preset_provider.dart';
import 'package:prompt_viewer/screens/image_selection_screen.dart';
import 'package:uuid/uuid.dart';

class PresetEditorScreen extends ConsumerStatefulWidget {
  final PromptPreset? preset; // 기존 프리셋 편집용
  final String? initialImagePath; // 새로 만들 때 시작 이미지

  const PresetEditorScreen({super.key, this.preset, this.initialImagePath});

  @override
  ConsumerState<PresetEditorScreen> createState() => _PresetEditorScreenState();
}

class _PresetEditorScreenState extends ConsumerState<PresetEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _promptController;
  late List<String> _imagePaths;
  late String? _thumbnailPath;
  late double _rating;
  late bool _isNsfw; // NSFW 상태 변수 추가

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    _titleController = TextEditingController(text: p?.title ?? '');
    _promptController = TextEditingController(text: p?.prompt ?? '');
    _imagePaths = p?.imagePaths ?? (widget.initialImagePath != null ? [widget.initialImagePath!] : []);
    _thumbnailPath = p?.thumbnailPath ?? widget.initialImagePath;
    _rating = p?.rating ?? 3.0;
    _isNsfw = p?.isNsfw ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _selectImages() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => ImageSelectionScreen(initialSelection: _imagePaths.toSet()),
      ),
    );

    if (result != null) {
      setState(() {
        _imagePaths = result;
        if (!_imagePaths.contains(_thumbnailPath)) {
          _thumbnailPath = _imagePaths.isNotEmpty ? _imagePaths.first : null;
        }
      });
    }
  }

  void _savePreset() {
    if (_formKey.currentState!.validate()) {
      if (_thumbnailPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('대표 이미지를 1개 이상 선택해주세요.')));
        return;
      }

      final newPreset = PromptPreset(
        id: widget.preset?.id ?? const Uuid().v4(),
        title: _titleController.text,
        prompt: _promptController.text,
        thumbnailPath: _thumbnailPath!,
        imagePaths: _imagePaths,
        rating: _rating,
        isNsfw: _isNsfw, // 저장할 때 NSFW 상태 포함
      );

      ref.read(presetProvider.notifier).addOrUpdatePreset(newPreset).then((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // [핵심] 현재 테마 정보를 가져와 UI 전반에 사용합니다.
    final theme = Theme.of(context);

    return Scaffold(
      // [수정] backgroundColor를 제거하여 main.dart의 테마 설정을 따릅니다.
      appBar: AppBar(
        // [수정] 모든 스타일 관련 속성을 제거하여 main.dart의 AppBarTheme을 따릅니다.
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.preset != null ? '프리셋 편집' : '프리셋 생성',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      // --- 제목 입력 필드 ---
                      TextFormField(
                        controller: _titleController,
                        // [수정] decoration을 제거하여 main.dart의 inputDecorationTheme을 따릅니다.
                        decoration: const InputDecoration(hintText: '제목'),
                        validator: (value) => (value == null || value.isEmpty) ? '제목을 입력해주세요.' : null,
                      ),
                      const SizedBox(height: 12),
                      // --- 프롬프트 입력 필드 ---
                      TextFormField(
                        controller: _promptController,
                        decoration: const InputDecoration(hintText: '프롬프트 입력'),
                        minLines: 5,
                        maxLines: 10,
                        validator: (value) => (value == null || value.isEmpty) ? '프롬프트를 입력해주세요.' : null,
                      ),
                      const SizedBox(height: 20),
                      // --- 이미지 선택 버튼 ---
                      ElevatedButton(
                        onPressed: _selectImages,
                        // [수정] 버튼 스타일을 테마에 맞게 변경합니다.
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.surfaceVariant,
                          foregroundColor: theme.colorScheme.onSurfaceVariant,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('이미지 선택'),
                      ),
                      const SizedBox(height: 12),
                      _buildImagePicker(),
                      const SizedBox(height: 24),
                      _buildRatingSlider(),
                      const SizedBox(height: 12),
                      _buildNsfwSwitch(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // --- 하단 저장 버튼 ---
          _buildSaveButton(),
        ],
      ),
    );
  }

  /// NSFW 스위치 위젯
  Widget _buildNsfwSwitch() {
    return SwitchListTile(
      title: const Text('NSFW', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      subtitle: const Text('이 프리셋에 민감한 콘텐츠가 포함되어 있습니다.'),
      value: _isNsfw,
      onChanged: (bool value) {
        setState(() {
          _isNsfw = value;
        });
      },
      contentPadding: EdgeInsets.zero,
    );
  }

  /// 선택된 이미지 목록을 보여주는 위젯
  Widget _buildImagePicker() {
    if (_imagePaths.isEmpty) {
      return const SizedBox(height: 150, child: Center(child: Text('선택된 이미지가 없습니다.')));
    }
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _imagePaths.length,
        itemBuilder: (context, index) {
          final path = _imagePaths[index];
          final isSelectedAsThumbnail = path == _thumbnailPath;
          return Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: GestureDetector(
              onTap: () => setState(() => _thumbnailPath = path),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(
                      // [수정] 선택 테두리 색상을 테마의 primary 색상으로 지정합니다.
                      color: isSelectedAsThumbnail ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      width: 3.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9.0),
                    child: Image.file(File(path), fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 평점 슬라이더 위젯
  Widget _buildRatingSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('평점', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              _rating.toStringAsFixed(1),
              // [수정] 글자색을 테마에 맞게 변경합니다.
              style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        Slider(
          value: _rating,
          min: 0.0,
          max: 5.0,
          divisions: 10,
          label: _rating.toStringAsFixed(1),
          onChanged: (value) => setState(() => _rating = value),
        ),
      ],
    );
  }

  /// 하단 저장 버튼 위젯
  Widget _buildSaveButton() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 24.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _savePreset,
          // [수정] 저장 버튼의 색상을 테마의 primary 색상 체계에 맞게 변경합니다.
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
          child: const Text('저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}