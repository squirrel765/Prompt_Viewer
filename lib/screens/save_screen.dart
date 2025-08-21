// lib/screens/save_screen.dart

import 'package:flutter/material.dart';
import 'package:prompt_viewer/screens/memos_screen.dart';
import 'package:prompt_viewer/screens/preset_list_screen.dart';
import 'package:prompt_viewer/screens/tag_library_screen.dart';
import 'package:prompt_viewer/screens/saved_prompts_screen.dart';

// [수정] '메모' 탭을 추가
enum SaveTab { presets, tags, prompts, memos }

class SaveScreen extends StatefulWidget {
  const SaveScreen({super.key});

  @override
  State<SaveScreen> createState() => _SaveScreenState();
}

class _SaveScreenState extends State<SaveScreen> {
  // 현재 선택된 탭을 관리하는 상태 변수, 기본값은 '프리셋'
  SaveTab _selectedTab = SaveTab.presets;

  @override
  Widget build(BuildContext context) {
    // 화면의 전체 구조는 세로로 배치된 Column
    return Column(
      children: [
        // 상단 탭 UI
        _buildTabs(),
        // 선택된 탭에 따라 다른 화면의 '내용'만 보여주는 영역
        Expanded(
          child: switch (_selectedTab) {
          // '프리셋' 탭이 선택된 경우
            SaveTab.presets => const PresetListScreen(showAppBar: false),
          // '태그 라이브러리' 탭이 선택된 경우
            SaveTab.tags => const TagLibraryScreen(showAppBar: false),
          // '저장된 프롬프트' 탭이 선택된 경우
            SaveTab.prompts => const SavedPromptsScreen(),
          // [추가] '메모' 탭 선택 시 MemosScreen 표시
            SaveTab.memos => const MemosScreen(),
          },
        ),
      ],
    );
  }

  /// 상단 탭 UI를 생성하는 위젯
  Widget _buildTabs() {
    // [핵심] 현재 테마 정보를 가져옵니다.
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          // [수정] 하단 구분선 색상을 테마의 dividerColor로 변경합니다.
          bottom: BorderSide(color: theme.dividerColor, width: 1.0),
        ),
      ),
      child: Row(
        // 탭들을 가로로 배치
        children: [
          _buildTabItem('프리셋', SaveTab.presets),
          _buildTabItem('태그 라이브러리', SaveTab.tags),
          _buildTabItem('저장된 프롬프트', SaveTab.prompts),
          // [추가] '메모' 탭 아이템
          _buildTabItem('메모', SaveTab.memos),
        ],
      ),
    );
  }

  /// 개별 탭 아이템 위젯
  Widget _buildTabItem(String title, SaveTab tab) {
    // [핵심] 현재 테마 정보를 가져옵니다.
    final theme = Theme.of(context);
    final isSelected = _selectedTab == tab;

    return GestureDetector(
      // 탭을 누르면 _selectedTab 상태를 변경하여 화면을 다시 그림
      onTap: () => setState(() => _selectedTab = tab),
      child: Container(
        decoration: BoxDecoration(
          // 탭 효과를 위해 배경색은 투명하게 설정
          color: Colors.transparent,
          border: Border(
            // [수정] 선택된 탭의 밑줄 색상을 테마의 primary 색상으로 변경합니다.
            bottom: BorderSide(
              color: isSelected ? theme.colorScheme.primary : Colors.transparent,
              width: 3.0,
            ),
          ),
        ),
        // 탭의 패딩을 조절하여 터치 영역 확보 및 디자인 개선
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
        child: Text(
          title,
          style: TextStyle(
            // [수정] 선택/비선택 상태에 따라 테마에 맞는 글자색으로 변경합니다.
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}