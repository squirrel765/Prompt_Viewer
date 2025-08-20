// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart'; // [추가]
import 'package:prompt_viewer/screens/app_drawer.dart';
import 'package:prompt_viewer/screens/gallery_screen.dart';
import 'package:prompt_viewer/screens/explore_screen.dart';
import 'package:prompt_viewer/screens/generate_screen.dart';
import 'package:prompt_viewer/screens/save_screen.dart';
import 'package:prompt_viewer/screens/my_page_screen.dart';
import 'package:prompt_viewer/screens/settings_screen.dart';

// [수정] ConsumerStatefulWidget으로 변경하여 ref를 사용할 수 있게 합니다.
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  late final PageController _pageController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  static const List<Widget> _widgetOptions = <Widget>[
    GalleryScreen(),
    ExploreScreen(),
    GenerateScreen(),
    SaveScreen(),
    MyPageScreen(),
  ];

  static const List<String> _titleOptions = ['AI Image Viewer', '탐색', 'Generate', '저장', '마이페이지'];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // [추가] 새로고침 로직
  Future<void> _refreshCurrentFolder() async {
    final currentFolder = ref.read(folderPathProvider);
    if (currentFolder != null && currentFolder.isNotEmpty) {
      await ref.read(galleryProvider.notifier).syncFolder(currentFolder);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 폴더를 선택해주세요.')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;
    // [추가] galleryProvider의 상태를 감시합니다.
    final galleryState = ref.watch(galleryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        centerTitle: true,
        title: Text(
          _titleOptions[_selectedIndex],
          style: appBarTheme.titleTextStyle,
        ),
        actions: [
          // [핵심 수정] 홈 화면일 때 로딩 상태에 따라 다른 아이콘을 표시합니다.
          if (_selectedIndex == 0) ...[
            if (galleryState.isLoading)
              const Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3.0),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '새로고침',
                onPressed: _refreshCurrentFolder,
              ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _onItemTapped(1),
            ),
          ],
          if (_selectedIndex == 4)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
            ),
        ],
      ),
      drawer: const AppDrawer(),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: _widgetOptions,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.search_outlined), activeIcon: Icon(Icons.search), label: '탐색'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box_outlined), activeIcon: Icon(Icons.add_box), label: '생성'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark_border), activeIcon: Icon(Icons.bookmark), label: '저장'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: '마이페이지'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}