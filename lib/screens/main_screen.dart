// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/screens/app_drawer.dart';
import 'package:prompt_viewer/screens/gallery_screen.dart';
import 'package:prompt_viewer/screens/explore_screen.dart';
import 'package:prompt_viewer/screens/generate_screen.dart';
import 'package:prompt_viewer/screens/save_screen.dart';
import 'package:prompt_viewer/screens/my_page_screen.dart';
import 'package:prompt_viewer/screens/settings_screen.dart';

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
    // [핵심 수정] AsyncNotifierProvider는 스스로 초기화를 관리하므로
    // initState에서 수동으로 로드하는 로직은 이제 필요 없습니다. 모두 제거합니다.
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
    // [핵심 수정] galleryProvider는 이제 AsyncValue를 반환합니다.
    final galleryAsyncValue = ref.watch(galleryProvider);

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
          if (_selectedIndex == 0) ...[
            // [핵심 수정] AsyncValue에서 isSyncing 상태를 안전하게 가져와 로딩 아이콘을 표시합니다.
            // valueOrNull은 데이터가 있을 때만 GalleryState를 반환하고, 아니면 null을 반환합니다.
            if (galleryAsyncValue.valueOrNull?.isSyncing == true)
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