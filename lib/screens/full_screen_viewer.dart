// lib/screens/full_screen_viewer.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart'; // [수정] PhotoViewGallery import

class FullScreenViewer extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;
  final ValueChanged<int>? onPageChanged;

  const FullScreenViewer({
    super.key,
    required this.imagePaths,
    this.initialIndex = 0,
    this.onPageChanged,
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
          // [핵심 수정] PageView.builder를 PhotoViewGallery.builder로 교체
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            builder: (BuildContext context, int index) {
              final imagePath = widget.imagePaths[index];
              return PhotoViewGalleryPageOptions(
                imageProvider: FileImage(File(imagePath)),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4.0,
                heroAttributes: PhotoViewHeroAttributes(tag: imagePath),
              );
            },
            itemCount: widget.imagePaths.length,
            loadingBuilder: (context, event) => const Center(
              child: SizedBox(
                width: 20.0,
                height: 20.0,
                child: CircularProgressIndicator(),
              ),
            ),
            pageController: _pageController,
            onPageChanged: widget.onPageChanged,
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