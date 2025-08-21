// lib/screens/preset_list_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/models/prompt_preset.dart';
import 'package:prompt_viewer/providers/preset_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart';
import 'package:prompt_viewer/screens/preset_detail_screen.dart';
import 'package:prompt_viewer/screens/preset_editor_screen.dart';

class PresetListScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const PresetListScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<PresetListScreen> createState() => _PresetListScreenState();
}

class _PresetListScreenState extends ConsumerState<PresetListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(presetProvider.notifier).loadPresets();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<PromptPreset> presets = ref.watch(presetProvider);
    final showNsfw = ref.watch(configProvider).showNsfw;
    final presetsToDisplay = showNsfw
        ? presets
        : presets.where((p) => !p.isNsfw).toList();

    final content = presetsToDisplay.isEmpty
        ? _buildEmptyView(context)
        : _buildPresetGridView(presetsToDisplay);

    if (widget.showAppBar) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          centerTitle: true,
          title: const Text('프리셋'),
        ),
        body: content,
        floatingActionButton: _buildFloatingActionButton(),
      );
    } else {
      return content;
    }
  }

  Widget _buildFloatingActionButton() {
    return FloatingActionButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const PresetEditorScreen(),
            fullscreenDialog: true,
          ),
        );
      },
      child: const Icon(Icons.add),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome_mosaic_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
          ),
          const SizedBox(height: 16),
          Text(
            '생성된 프리셋이 없습니다.',
            style: TextStyle(fontSize: 18, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            '갤러리에서 이미지를 길게 눌러\n첫 프리셋을 만들어보세요!',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetGridView(List<PromptPreset> presets) {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12.0,
        mainAxisSpacing: 12.0,
        childAspectRatio: 0.8,
      ),
      itemCount: presets.length,
      itemBuilder: (context, index) {
        final preset = presets[index];
        return _buildPresetCard(preset);
      },
    );
  }

  Widget _buildPresetCard(PromptPreset preset) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => PresetDetailScreen(presetId: preset.id)),
        );
      },
      borderRadius: BorderRadius.circular(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 1.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: Image.file(
                  File(preset.thumbnailPath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(
                        Icons.broken_image,
                        color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
                        size: 48,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            preset.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}