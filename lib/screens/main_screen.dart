// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:prompt_viewer/screens/app_drawer.dart';
import 'package:prompt_viewer/screens/gallery_screen.dart';
import 'package:prompt_viewer/screens/explore_screen.dart';
import 'package:prompt_viewer/screens/generate_screen.dart';
import 'package:prompt_viewer/screens/save_screen.dart';
import 'package:prompt_viewer/screens/my_page_screen.dart';
import 'package:prompt_viewer/screens/settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
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

  @override
  Widget build(BuildContext context) {
    // [수정] 테마에서 색상을 가져오기 위해 변수 선언
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;

    return Scaffold(
      // [수정] 하드코딩된 배경색 제거 (테마에서 자동 적용)
      // backgroundColor: Colors.white,
      appBar: AppBar(
        // [수정] 하드코딩된 배경색, 아이콘색, 글자색 모두 제거 (테마에서 자동 적용)
        // backgroundColor: Colors.white,
        // elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu), // 색상 지정 제거
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        centerTitle: true,
        title: Text(
          _titleOptions[_selectedIndex],
          // [수정] appBarTheme에 정의된 스타일을 사용하도록 변경
          style: appBarTheme.titleTextStyle,
        ),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              icon: const Icon(Icons.search), // 색상 지정 제거
              onPressed: () => _onItemTapped(1),
            ),
          if (_selectedIndex == 4)
            IconButton(
              icon: const Icon(Icons.settings_outlined), // 색상 지정 제거
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
        // [수정] 모든 색상 관련 속성을 제거 (테마에서 자동 적용)
        // selectedItemColor: Theme.of(context).colorScheme.primary,
        // unselectedItemColor: Colors.grey,
        // showUnselectedLabels: true,
        // type: BottomNavigationBarType.fixed,
        // backgroundColor: Colors.white,
        // elevation: 5,
      ),
    );
  }
}