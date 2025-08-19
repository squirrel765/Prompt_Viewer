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
  String? _profileImagePath;
  String _userName = 'User';
  String _userHandle = '@user_handle';

  static const String _profileImageKey = 'profile_image_path';
  static const String _userNameKey = 'user_name';
  static const String _userHandleKey = 'user_handle';

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

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

  Future<void> _pickAndSetProfileImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() => _profileImagePath = path);
      await _saveProfileData();
    }
  }

  Future<void> _showEditProfileDialog() async {
    final nameController = TextEditingController(text: _userName);
    final handleController = TextEditingController(text: _userHandle);
    final formKey = GlobalKey<FormState>();

    return showDialog<void>(context: context, builder: (BuildContext context) => AlertDialog(
      title: const Text('프로필 편집'),
      content: Form(key: formKey, child: SingleChildScrollView(child: ListBody(children: <Widget>[
        TextFormField(controller: nameController, decoration: const InputDecoration(labelText: '이름'), validator: (value) => (value == null || value.isEmpty) ? '이름을 입력해주세요.' : null),
        const SizedBox(height: 12),
        TextFormField(controller: handleController, decoration: const InputDecoration(labelText: '핸들 (@)'), validator: (value) => (value == null || value.isEmpty) ? '핸들을 입력해주세요.' : null),
      ],
      ),
      ),),
      actions: <Widget>[
        TextButton(child: const Text('취소'), onPressed: () => Navigator.of(context).pop()),
        TextButton(child: const Text('저장'), onPressed: () {
          if (formKey.currentState!.validate()) {
            setState(() { _userName = nameController.text; _userHandle = handleController.text; });
            _saveProfileData();
            Navigator.of(context).pop();
          }
        },
        ),
      ],
    ));
  }

  void _showContextMenu(BuildContext context, ImageMetadata image) {
    showModalBottomSheet(context: context, builder: (context) => Wrap(children: <Widget>[
      ListTile(leading: Icon(image.isFavorite ? Icons.star : Icons.star_border), title: Text(image.isFavorite ? '즐겨찾기에서 제거' : '즐겨찾기에 추가'), onTap: () { ref.read(galleryProvider.notifier).toggleFavorite(image); Navigator.pop(context); }),
      ListTile(leading: const Icon(Icons.star_half_outlined), title: const Text('별점 매기기'), onTap: () { Navigator.pop(context); _showRatingDialog(context, image); }),
      ListTile(leading: const Icon(Icons.add_photo_alternate_outlined), title: const Text('프리셋 만들기'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => PresetEditorScreen(initialImagePath: image.path), fullscreenDialog: true)); }),
      ListTile(leading: Icon(image.isNsfw ? Icons.visibility_off_outlined : Icons.visibility_outlined), title: Text(image.isNsfw ? 'NSFW 해제' : 'NSFW로 표시'), onTap: () { ref.read(galleryProvider.notifier).toggleNsfw(image); Navigator.pop(context); }),
      const Divider(),
      ListTile(leading: Icon(Icons.delete_outline, color: Colors.red.shade400), title: Text('삭제', style: TextStyle(color: Colors.red.shade400)), onTap: () { Navigator.pop(context); ref.read(galleryProvider.notifier).deleteImage(image); }),
    ],
    ));
  }

  Future<void> _showRatingDialog(BuildContext context, ImageMetadata image) async {
    double currentRating = image.rating;
    return showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('별점 매기기'),
      content: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (index) => IconButton(
        icon: Icon(index < currentRating ? Icons.star : Icons.star_border, color: Colors.amber),
        onPressed: () => setDialogState(() => currentRating = index + 1.0),
      ))),
      actions: [
        TextButton(child: const Text('취소'), onPressed: () => Navigator.pop(context)),
        TextButton(child: const Text('저장'), onPressed: () { ref.read(galleryProvider.notifier).rateImage(image.path, currentRating); Navigator.pop(context); }),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    // --- START: 수정된 부분 ---
    final galleryState = ref.watch(galleryProvider);
    final allImages = galleryState.items.whereType<FullImageItem>().map((item) => item.metadata).toList();
    // --- END: 수정된 부분 ---
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

  Widget _buildProfileSection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickAndSetProfileImage,
              child: CircleAvatar(
                radius: 60,
                // [경고 수정] surfaceVariant -> surfaceContainerHighest
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                backgroundImage: _profileImagePath != null ? FileImage(File(_profileImagePath!)) : null,
                child: _profileImagePath == null ? Icon(Icons.person, size: 60, color: Theme.of(context).colorScheme.onSurfaceVariant) : null,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _showEditProfileDialog,
              borderRadius: BorderRadius.circular(12.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  children: [
                    Text(_userName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_userHandle, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesSection(List<ImageMetadata> favoriteImages) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('좋아하는 이미지', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (favoriteImages.isEmpty)
            Container(
              height: 200,
              alignment: Alignment.center,
              child: const Text('즐겨찾기한 이미지가 없습니다.\n(NSFW 이미지는 여기에 표시되지 않습니다)', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: favoriteImages.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12.0, mainAxisSpacing: 12.0),
              itemBuilder: (context, index) {
                final image = favoriteImages[index];
                return InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => DetailScreen(metadata: image))),
                  onLongPress: () => _showContextMenu(context, image),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Image.file(File(image.thumbnailPath), fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_outlined, color: Colors.grey)),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}