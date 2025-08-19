// lib/screens/full_screen_viewer.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

class FullScreenViewer extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;
  // --- START: 수정된 부분 ---
  // [추가] 페이지가 변경될 때마다 호출될 콜백 함수를 받습니다.
  final ValueChanged<int>? onPageChanged;
  // --- END: 수정된 부분 ---

  const FullScreenViewer({
    super.key,
    required this.imagePaths,
    this.initialIndex = 0,
    // --- START: 수정된 부분 ---
    this.onPageChanged, // [추가] 생성자에 콜백 함수 추가
    // --- END: 수정된 부분 ---
  });

  @override
  State<FullScreenViewer> createState() => _FullScreenViewerState();
}

class _FullScreenViewerState extends State<FullScreenViewer> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imagePaths.length,
            // --- START: 수정된 부분 ---
            // [추가] PageView의 페이지가 바뀔 때마다 우리가 전달받은 onPageChanged 함수를 호출합니다.
            onPageChanged: widget.onPageChanged,
            // --- END: 수정된 부분 ---
            itemBuilder: (context, index) {
              final imagePath = widget.imagePaths[index];
              return PhotoView(
                imageProvider: FileImage(File(imagePath)),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4.0,
                heroAttributes: PhotoViewHeroAttributes(tag: imagePath),
              );
            },
          ),
          // 뒤로가기 버튼 추가 (화면 아무데나 누르는 것보다 명시적)
          Positioned(
            top: 40,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}