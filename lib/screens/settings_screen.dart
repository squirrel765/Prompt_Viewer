// lib/screens/settings_screen.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/providers/preset_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart';
import 'package:prompt_viewer/providers/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: ref.read(configProvider).civitaiApiKey ?? '');
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _pickNewFolder() async {
    final folderPath = await FilePicker.platform.getDirectoryPath();
    if (folderPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('새 폴더를 동기화합니다...'), duration: Duration(days: 1)),
      );
      await ref.read(galleryProvider.notifier).syncFolder(folderPath);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('동기화 완료!'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _refreshCurrentFolder() async {
    final currentFolder = ref.read(folderPathProvider);
    if (currentFolder != null && currentFolder.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 폴더를 새로고침합니다...')),
      );
      await ref.read(galleryProvider.notifier).syncFolder(currentFolder);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('새로고침 완료!'), duration: Duration(seconds: 2)),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 폴더를 선택해주세요.')),
      );
    }
  }

  /// [수정] 커스텀 태그 JSON 파일을 가져와서 "파일명"과 함께 저장합니다.
  Future<void> _importCustomTags() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null && result.files.single.path != null) {
      try {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name; // 파일명 가져오기
        final jsonString = await file.readAsString();

        // Notifier에 파일명과 JSON 내용을 함께 전달
        await ref.read(customTagsProvider.notifier).importFromJson(jsonString, fileName);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('\'$fileName\' 태그를 성공적으로 가져왔습니다!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('오류: ${e.toString().replaceAll("Exception: ", "")}')),
          );
        }
      }
    }
  }

  Future<void> _clearCustomTags() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('태그 초기화'),
        content: const Text('사용자가 직접 추가한 모든 태그를 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('삭제', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(customTagsProvider.notifier).clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('가져온 태그를 모두 삭제했습니다.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTheme = ref.watch(themeProvider);
    final currentFolderPath = ref.watch(folderPathProvider);
    final appConfig = ref.watch(configProvider);
    final configNotifier = ref.read(configProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text('설정'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('테마'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  _buildThemeChip('라이트', ThemeMode.light, currentTheme),
                  const SizedBox(width: 8),
                  _buildThemeChip('다크', ThemeMode.dark, currentTheme),
                ],
              ),
            ),

            _buildSectionHeader('NSFW 설정'),
            SwitchListTile(
              title: const Text('NSFW 이미지 표시'),
              subtitle: const Text('앱 전체에서 NSFW로 지정된 콘텐츠를 보여줍니다.'),
              value: appConfig.showNsfw,
              onChanged: (value) => configNotifier.setShowNsfw(value),
            ),

            _buildSectionHeader('공유 설정'),
            SwitchListTile(
              title: const Text('메타데이터 포함하여 공유'),
              subtitle: const Text('꺼진 경우, 프롬프트 정보가 제거된 이미지만 공유됩니다.'),
              value: appConfig.shareWithMetadata,
              onChanged: (value) => configNotifier.setShareWithMetadata(value),
            ),

            _buildSectionHeader('폴더 선택'),
            _buildSettingItem(
              title: '현재 선택된 폴더',
              subtitle: currentFolderPath ?? '선택된 폴더 없음',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(child: _buildActionButton('새로운 폴더 선택', _pickNewFolder)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildActionButton('현재 폴더 새로고침', _refreshCurrentFolder)),
                ],
              ),
            ),

            // --- 태그 라이브러리 섹션 (신규) ---
            _buildSectionHeader('태그 라이브러리'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  _buildActionButton('커스텀 태그 JSON 가져오기', _importCustomTags, isFullWidth: true),
                  const SizedBox(height: 16),
                  // [신규] 불러온 태그 목록 관리 UI
                  _buildCustomTagsManagement(),
                  const SizedBox(height: 8),
                  _buildActionButton('가져온 태그 모두 초기화', _clearCustomTags, isDestructive: true, isFullWidth: true),
                ],
              ),
            ),

            _buildSectionHeader('Civitai API 설정'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                controller: _apiKeyController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'API 키 입력 (선택 사항)',
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(128),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.0),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  configNotifier.setCivitaiApiKey(value.isNotEmpty ? value : null);
                },
              ),
            ),
            _buildSettingItem(
              title: 'API 키는 Civitai 계정 설정에서 발급받을 수 있습니다.',
              subtitle: 'API 키를 입력하면 더 많은 정보를 안정적으로 가져올 수 있습니다.',
            ),

            _buildSectionHeader('기타 설정'),
            _buildSettingItem(
              title: '개발자 GitHub',
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final url = Uri.parse('https://github.com'); // TODO: 실제 GitHub 주소로 변경
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- [신규] 커스텀 태그 관리 UI를 생성하는 위젯 ---
  Widget _buildCustomTagsManagement() {
    final customTagSources = ref.watch(customTagsProvider);
    final sourceKeys = customTagSources.keys.toList();

    if (sourceKeys.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          '불러온 커스텀 태그 파일이 없습니다.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text("불러온 파일 목록", style: Theme.of(context).textTheme.titleMedium),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sourceKeys.length,
          itemBuilder: (context, index) {
            final sourceName = sourceKeys[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(sourceName),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  onPressed: () {
                    ref.read(customTagsProvider.notifier).removeSource(sourceName);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('\'$sourceName\' 태그를 삭제했습니다.')),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // --- UI 구성을 위한 헬퍼 메서드들 ---

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 8.0),
      child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSettingItem({required String title, String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: Colors.grey)) : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildThemeChip(String label, ThemeMode theme, ThemeMode currentTheme) {
    final isSelected = theme == currentTheme;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          ref.read(themeProvider.notifier).setTheme(theme);
        }
      },
      selectedColor: Theme.of(context).colorScheme.primary,
      labelStyle: TextStyle(
        color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.0),
        side: BorderSide(
          color: isSelected ? Colors.transparent : Theme.of(context).dividerColor,
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, VoidCallback onPressed, {bool isDestructive = false, bool isFullWidth = false}) {
    final theme = Theme.of(context);
    final backgroundColor = isDestructive ? theme.colorScheme.errorContainer : theme.colorScheme.surfaceContainerHighest;
    final foregroundColor = isDestructive ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSurfaceVariant;

    final button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label),
    );

    return isFullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}