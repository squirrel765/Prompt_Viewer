// lib/screens/app_drawer.dart

import 'package:flutter/material.dart';
import 'package:prompt_viewer/screens/help_screen.dart';
import 'package:prompt_viewer/screens/preset_list_screen.dart';
import 'package:prompt_viewer/screens/settings_screen.dart';
import 'package:prompt_viewer/screens/tag_library_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    // [핵심] 현재 테마 정보를 가져옵니다.
    final theme = Theme.of(context);
    final drawerWidth = MediaQuery.of(context).size.width * 0.83;

    return Drawer(
      width: drawerWidth,
      // [수정] Drawer의 배경색을 현재 테마의 Scaffold 배경색과 일치시킵니다.
      backgroundColor: theme.scaffoldBackgroundColor,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 120,
            child: DrawerHeader(
              // [수정] 헤더의 배경색도 테마를 따르도록 명시합니다.
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Prompt Viewer',
                  style: TextStyle(
                    // [수정] 헤더의 글자색이 테마의 기본 글자색을 따르도록 합니다.
                    color: theme.textTheme.titleLarge?.color,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          // --- 각 메뉴 아이템 ---
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

  /// 공통 드로어 아이템 위젯을 생성하는 헬퍼 메서드
  Widget _buildDrawerItem(BuildContext context, {required IconData icon, required String title, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    const bool isSelected = false; // 현재 화면에 따라 선택 상태를 표시하는 로직 추가 가능

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ListTile(
        // [수정] 아이콘 색상을 테마의 onSurfaceVariant 색상으로 지정하여 일관성을 유지합니다.
        leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          // Text의 color를 지정하지 않으면 ListTile이 테마에 맞는 기본 글자색을 자동으로 적용합니다.
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        // [수정] 선택되었을 때의 배경색을 테마의 primaryContainer 색상으로 지정합니다.
        tileColor: isSelected ? theme.colorScheme.primaryContainer : Colors.transparent,
      ),
    );
  }
}