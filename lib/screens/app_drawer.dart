// lib/screens/app_drawer.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/screens/help_screen.dart';
import 'package:prompt_viewer/screens/metadata_embedding_screen.dart';
import 'package:prompt_viewer/screens/preset_list_screen.dart';
import 'package:prompt_viewer/screens/settings_screen.dart';
import 'package:prompt_viewer/screens/tag_library_screen.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final drawerWidth = MediaQuery.of(context).size.width * 0.83;

    return Drawer(
      width: drawerWidth,
      backgroundColor: theme.scaffoldBackgroundColor,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 120,
            child: DrawerHeader(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Prompt Viewer',
                  style: TextStyle(
                    color: theme.textTheme.titleLarge?.color,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          _buildDrawerItem(
            context,
            icon: Icons.auto_awesome_outlined,
            title: 'Presets',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PresetListScreen()),
              );
            },
          ),
          _buildDrawerItem(
            context,
            icon: Icons.tag,
            title: 'Tag Library',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TagLibraryScreen()),
              );
            },
          ),
          _buildDrawerItem(
            context,
            icon: Icons.bookmark_border,
            title: 'Saved Prompts',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('\'저장\' 탭에서 확인하실 수 있습니다.')),
              );
              Navigator.pop(context);
            },
          ),
          const Divider(),
          _buildDrawerItem(
            context,
            icon: Icons.input,
            title: '외부에서 가져오기 (Import)',
            onTap: () async {
              Navigator.pop(context);
              try {
                final pathsToEdit = await ref.read(galleryProvider.notifier).importAndProcessImages();

                if (pathsToEdit.isNotEmpty && context.mounted) {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('${pathsToEdit.length}개의 이미지에 프롬프트 정보가 없습니다.'),
                      content: const Text("지금 추가하시겠습니까?"),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("나중에 하기")),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("추가하기")),
                      ],
                    ),
                  ) ?? false;

                  if (confirm && context.mounted) {
                    for (final path in pathsToEdit) {
                      if (!context.mounted) break;
                      await Navigator.push(context, MaterialPageRoute(builder: (context) => MetadataEmbeddingScreen(imagePath: path)));
                    }
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll("Exception: ", ""))));
                }
              }
            },
          ),
          // [수정] 이미지 내보내기 메뉴 삭제
          const Divider(),
          _buildDrawerItem(
            context,
            icon: Icons.help_outline,
            title: 'Help',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HelpScreen()),
              );
            },
          ),
          _buildDrawerItem(
            context,
            icon: Icons.settings_outlined,
            title: 'Settings',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, {required IconData icon, required String title, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    const bool isSelected = false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        tileColor: isSelected ? theme.colorScheme.primaryContainer : Colors.transparent,
      ),
    );
  }
}