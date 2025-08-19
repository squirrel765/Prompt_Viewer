// lib/screens/my_page_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/screens/detail_screen.dart';
import 'package:prompt_viewer/screens/preset_editor_screen.dart';

class MyPageScreen extends ConsumerStatefulWidget {
  const MyPageScreen({super.key});

  @override
  ConsumerState<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends ConsumerState<MyPageScreen> {
  // --- 상태 변수 및 SharedPreferences 키 정의 ---
  String? _profileImagePath;
  String _userName = 'User';
  String _userHandle = '@user_handle';

  static const String _profileImageKey = 'profile_image_path';
  static const String _userNameKey = 'user_name';
  static const String _userHandleKey = 'user_handle';

  @override
  void initState() {
    super.initState();
    // 위젯 생성 시 저장된 모든 프로필 데이터를 불러옵니다.
    _loadProfileData();
  }

  /// SharedPreferences에서 모든 프로필 데이터를 불러오는 함수
  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _profileImagePath = prefs.getString(_profileImageKey);
        _userName = prefs.getString(_userNameKey) ?? 'User';
        _userHandle = prefs.getString(_userHandleKey) ?? '@user_handle';
      });
    }
  }

  /// 모든 프로필 데이터를 SharedPreferences에 저장하는 함수
  Future<void> _saveProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    if (_profileImagePath != null) {
      await prefs.setString(_profileImageKey, _profileImagePath!);
    } else {
      await prefs.remove(_profileImageKey);
    }
    await prefs.setString(_userNameKey, _userName);
    await prefs.setString(_userHandleKey, _userHandle);
  }

  /// 갤러리에서 이미지를 선택하고 프로필 사진으로 설정하는 함수
  Future<void> _pickAndSetProfileImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _profileImagePath = path;
      });
      await _saveProfileData();
    }
  }

  /// 프로필 편집 팝업(Dialog)을 보여주는 함수
  Future<void> _showEditProfileDialog() async {
    final nameController = TextEditingController(text: _userName);
    final handleController = TextEditingController(text: _userHandle);
    final formKey = GlobalKey<FormState>();

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('프로필 편집'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '이름'),
                    validator: (value) => (value == null || value.isEmpty) ? '이름을 입력해주세요.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: handleController,
                    decoration: const InputDecoration(labelText: '핸들 (@)'),
                    validator: (value) => (value == null || value.isEmpty) ? '핸들을 입력해주세요.' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('취소'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('저장'),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  setState(() {
                    _userName = nameController.text;
                    _userHandle = handleController.text;
                  });
                  _saveProfileData();
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  // --- 컨텍스트 메뉴 및 별점 다이얼로그 로직 ---

  /// 이미지를 길게 눌렀을 때 표시될 컨텍스트 메뉴
  void _showContextMenu(BuildContext context, ImageMetadata image) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: Icon(image.isFavorite ? Icons.star : Icons.star_border),
              title: Text(image.isFavorite ? '즐겨찾기에서 제거' : '즐겨찾기에 추가'),
              onTap: () {
                ref.read(galleryProvider.notifier).toggleFavorite(image);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_half_outlined),
              title: const Text('별점 매기기'),
              onTap: () {
                Navigator.pop(context);
                _showRatingDialog(context, image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text('프리셋 만들기'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PresetEditorScreen(initialImagePath: image.path),
                    fullscreenDialog: true,
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(image.isNsfw ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              title: Text(image.isNsfw ? 'NSFW 해제' : 'NSFW로 표시'),
              onTap: () {
                ref.read(galleryProvider.notifier).toggleNsfw(image);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
              title: Text('삭제', style: TextStyle(color: Colors.red.shade400)),
              onTap: () {
                Navigator.pop(context);
                ref.read(galleryProvider.notifier).deleteImage(image);
              },
            ),
          ],
        );
      },
    );
  }

  /// 별점 선택 팝업(Dialog)을 띄우는 함수
  Future<void> _showRatingDialog(BuildContext context, ImageMetadata image) async {
    double currentRating = image.rating;
    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('별점 매기기'),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < currentRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        if (currentRating == index + 0.5) {
                          currentRating = index + 1.0;
                        } else if(currentRating == index + 1.0){
                          currentRating = index + 0.5;
                        } else {
                          currentRating = index + 1.0;
                        }
                      });
                    },
                  );
                }),
              ),
              actions: [
                TextButton(child: const Text('취소'), onPressed: () => Navigator.pop(context)),
                TextButton(
                  child: const Text('저장'),
                  onPressed: () {
                    ref.read(galleryProvider.notifier).rateImage(image.path, currentRating);
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allImages = ref.watch(galleryProvider);
    final favoriteImages = allImages.where((img) => img.isFavorite && !img.isNsfw).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileSection(),
          _buildFavoritesSection(favoriteImages),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  /// 프로필 정보 UI 위젯
  Widget _buildProfileSection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Column(
          children: [
            // 프로필 이미지
            GestureDetector(
              onTap: _pickAndSetProfileImage,
              child: CircleAvatar(
                radius: 60,
                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                backgroundImage: _profileImagePath != null ? FileImage(File(_profileImagePath!)) : null,
                child: _profileImagePath == null ? Icon(Icons.person, size: 60, color: Theme.of(context).colorScheme.onSurfaceVariant) : null,
              ),
            ),
            const SizedBox(height: 16),
            // 이름과 핸들 영역
            InkWell(
              onTap: _showEditProfileDialog,
              borderRadius: BorderRadius.circular(12.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  children: [
                    Text(
                      _userName,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _userHandle,
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 즐겨찾기 섹션 UI 위젯
  Widget _buildFavoritesSection(List<ImageMetadata> favoriteImages) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '좋아하는 이미지',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (favoriteImages.isEmpty)
            Container(
              height: 200,
              alignment: Alignment.center,
              child: const Text(
                '즐겨찾기한 이미지가 없습니다.\n(NSFW 이미지는 여기에 표시되지 않습니다)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: favoriteImages.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12.0,
                mainAxisSpacing: 12.0,
              ),
              itemBuilder: (context, index) {
                final image = favoriteImages[index];
                return InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => DetailScreen(metadata: image)),
                  ),
                  onLongPress: () => _showContextMenu(context, image),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Image.file(
                      File(image.path),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.broken_image_outlined, color: Colors.grey);
                      },
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}