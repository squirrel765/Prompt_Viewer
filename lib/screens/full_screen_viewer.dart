// lib/screens/full_screen_viewer.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

class FullScreenViewer extends StatefulWidget {
  // [수정] 단일 경로 대신 이미지 경로 리스트와 시작 인덱스를 받습니다.
  final List<String> imagePaths;
  final int initialIndex;

  const FullScreenViewer({
    super.key,
    required this.imagePaths,
    this.initialIndex = 0,
  });

  @override
  State<FullScreenViewer> createState() => _FullScreenViewerState();
}

class _FullScreenViewerState extends State<FullScreenViewer> {
  // PageView를 제어하기 위한 컨트롤러
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    // 전달받은 initialIndex로 PageController를 초기화합니다.
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
      body: GestureDetector(
        // 화면의 아무 곳이나 탭하면 뒤로 돌아가는 기능은 유지합니다.
        onTap: () {
          Navigator.pop(context);
        },
        // [수정] 단일 PhotoView 대신 PageView.builder를 사용합니다.
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.imagePaths.length,
          itemBuilder: (context, index) {
            final imagePath = widget.imagePaths[index];
            return PhotoView(
              imageProvider: FileImage(File(imagePath)),
              // 화면에 꽉 차게 시작
              initialScale: PhotoViewComputedScale.contained,
              // 최소/최대 배율 설정
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4.0,
              // Hero 애니메이션을 위한 태그 (각 이미지마다 고유한 경로를 태그로 사용)
              heroAttributes: PhotoViewHeroAttributes(tag: imagePath),
            );
          },
        ),
      ),
    );
  }
}