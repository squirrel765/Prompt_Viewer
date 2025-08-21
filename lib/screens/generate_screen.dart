// lib/screens/generate_screen.dart

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/providers/memos_provider.dart';
import 'package:prompt_viewer/providers/preset_provider.dart';
import 'package:prompt_viewer/providers/saved_prompts_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart';
import 'package:prompt_viewer/screens/image_selection_screen.dart';
import 'package:prompt_viewer/services/civitai_service.dart';
import 'package:path/path.dart' as p;
import 'package:prompt_viewer/services/gemini_api_service.dart';

// 생성 화면의 세 가지 모드를 정의합니다.
enum GenerateMode { import, studio, gemini }

class GenerateScreen extends ConsumerStatefulWidget {
  const GenerateScreen({super.key});

  @override
  ConsumerState<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends ConsumerState<GenerateScreen> {
  // --- 상태 변수들 ---
  GenerateMode _selectedMode = GenerateMode.import;

  // 'Import' 탭 상태 변수
  final _civitaiUrlController = TextEditingController();
  bool _isLoading = false;
  bool _isSaving = false;
  CivitaiInfo? _importedData;

  // 'Studio' 탭 상태 변수
  String? _selectedMainCategory;
  final List<String> _selectedTags = [];

  // 'Gemini' 탭 상태 변수
  final _geminiInputController = TextEditingController();
  final List<ChatMessage> _geminiConversation = [];
  bool _isGeminiLoading = false;
  bool _useTagLibrary = false;
  String? _attachedImagePath;

  @override
  void dispose() {
    _civitaiUrlController.dispose();
    _geminiInputController.dispose();
    super.dispose();
  }

  // --- 'Import' 탭 메서드들 ---
  Future<void> _fetchCivitaiData() async {
    if (_civitaiUrlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Civitai 링크를 입력해주세요.')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _isLoading = true; _importedData = null; });
    try {
      final apiKey = ref.read(configProvider).civitaiApiKey;
      final service = CivitaiService(apiKey: apiKey);
      final List<CivitaiInfo> imageList = await service.fetchImagesFromModelUrl(_civitaiUrlController.text);
      if (mounted) {
        if (imageList.isEmpty) {
          throw Exception('모델에서 이미지를 찾을 수 없습니다.');
        } else if (imageList.length == 1) {
          setState(() { _importedData = imageList.first; });
        } else {
          final selectedImage = await _showImageSelectionDialog(imageList);
          if (selectedImage != null) {
            setState(() { _importedData = selectedImage; });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: ${e.toString().replaceAll('Exception: ', '')}')));
      }
    } finally {
      if (mounted) { setState(() { _isLoading = false; }); }
    }
  }

  Future<CivitaiInfo?> _showImageSelectionDialog(List<CivitaiInfo> images) {
    return showDialog<CivitaiInfo>(context: context, builder: (context) => AlertDialog(title: const Text('이미지 선택'), contentPadding: const EdgeInsets.all(16), content: SizedBox(width: double.maxFinite, child: GridView.builder(itemCount: images.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,), itemBuilder: (context, index) { final imageInfo = images[index]; return InkWell(onTap: () => Navigator.of(context).pop(imageInfo), borderRadius: BorderRadius.circular(8.0), child: ClipRRect(borderRadius: BorderRadius.circular(8.0), child: Image.network('${imageInfo.imageUrl}/width=300', fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stack) => const Icon(Icons.broken_image, color: Colors.grey),),),); },),), actions: [TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('취소'),),],),);
  }

  Future<void> _saveToGallery() async {
    if (_importedData == null) return;
    setState(() { _isSaving = true; });
    try {
      final rootFolder = ref.read(folderPathProvider);
      if (rootFolder == null || rootFolder.isEmpty) {
        throw Exception("먼저 홈 화면에서 갤러리 폴더를 선택해주세요.");
      }
      final fileName = '${_importedData!.id}.png';
      final destPath = p.join(rootFolder, 'civitai', fileName);
      final service = CivitaiService();
      await service.downloadImageWithMetadata(_importedData!, destPath);
      await ref.read(galleryProvider.notifier).syncFolder(rootFolder);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('성공적으로 저장되었습니다!\n경로: $destPath')),);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: ${e.toString().replaceAll('Exception: ', '')}')),);
      }
    } finally {
      if (mounted) { setState(() { _isSaving = false; }); }
    }
  }

  // --- 'Gemini' 탭 메서드들 ---
  Future<void> _handleGeminiSubmit() async {
    final prompt = _geminiInputController.text;
    if (prompt.isEmpty) return;
    FocusScope.of(context).unfocus();
    _geminiInputController.clear();

    setState(() {
      _geminiConversation.add(ChatMessage(text: prompt, isFromUser: true, attachedImagePath: _attachedImagePath));
      _isGeminiLoading = true;
    });

    try {
      final geminiService = ref.read(geminiApiServiceProvider);
      final response = await geminiService.getResponse(
        prompt,
        useTags: _useTagLibrary,
        imagePath: _attachedImagePath,
      );
      setState(() {
        _geminiConversation.add(ChatMessage(text: response, isFromUser: false, attachedImagePath: null));
        _attachedImagePath = null; // 질문 후 이미지 첨부 상태 초기화
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gemini 요청 실패: ${e.toString().replaceAll("Exception: ", "")}')));
      }
    } finally {
      if (mounted) {
        setState(() { _isGeminiLoading = false; });
      }
    }
  }

  Future<void> _pickImageForGemini() async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Wrap(children: [
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('갤러리에서 선택'),
          onTap: () async {
            Navigator.pop(ctx);
            final List<String>? result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const ImageSelectionScreen(initialSelection: {})));
            if (result != null && result.isNotEmpty) {
              setState(() { _attachedImagePath = result.first; });
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('외부 파일 가져오기'),
          onTap: () async {
            Navigator.pop(ctx);
            final result = await FilePicker.platform.pickFiles(type: FileType.image);
            if (result != null && result.files.single.path != null) {
              setState(() {
                _attachedImagePath = result.files.single.path!;
              });
            }
          },
        ),
      ]),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTabs(),
        Expanded(
          child: switch (_selectedMode) {
            GenerateMode.import => SingleChildScrollView(child: _buildImportView()),
            GenerateMode.studio => _buildStudioView(),
            GenerateMode.gemini => _buildGeminiView(),
          },
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          _buildTabItem('Import', GenerateMode.import),
          _buildTabItem('Studio', GenerateMode.studio),
          _buildTabItem('Gemini', GenerateMode.gemini),
        ],
      ),
    );
  }

  Widget _buildTabItem(String title, GenerateMode mode) {
    final isSelected = _selectedMode == mode;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => setState(() => _selectedMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isSelected ? theme.colorScheme.primary : Colors.transparent,
              width: 3.0,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withAlpha(179),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildImportView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Civitai 모델 페이지 URL을 입력하여 이미지와 프롬프트를 가져올 수 있습니다.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(
            controller: _civitaiUrlController,
            decoration: InputDecoration(
              labelText: 'Civitai Model URL',
              hintText: 'https://civitai.com/models/...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text('가져오기'),
            onPressed: _isLoading ? null : _fetchCivitaiData,
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(),))
          else if (_importedData != null)
            _buildImportedInfo(),
        ],
      ),
    );
  }

  Widget _buildImportedInfo() {
    final detailsString = _importedData!.otherDetails.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('가져온 정보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ClipRRect(borderRadius: BorderRadius.circular(12.0), child: Image.network(_importedData!.imageUrl, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stack) => const Icon(Icons.broken_image, size: 48, color: Colors.grey),),),
        const SizedBox(height: 16),
        if (_importedData!.prompt != null && _importedData!.prompt!.isNotEmpty) _buildDetailRow('Prompt', _importedData!.prompt!),
        if (_importedData!.negativePrompt != null && _importedData!.negativePrompt!.isNotEmpty) _buildDetailRow('Negative Prompt', _importedData!.negativePrompt!),
        if (detailsString.isNotEmpty) _buildDetailRow('Other Details', detailsString),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_alt), label: Text(_isSaving ? '저장하는 중...' : '갤러리에 저장'), onPressed: _isSaving ? null : _saveToGallery,),),
      ],
    );
  }

  Widget _buildDetailRow(String title, String value) {
    return Container(padding: const EdgeInsets.symmetric(vertical: 12.0), decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.copy_all_outlined, size: 18), tooltip: '복사', onPressed: () { Clipboard.setData(ClipboardData(text: value)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title 복사 완료!'), duration: const Duration(seconds: 1)),); },),],), const SizedBox(height: 4), SelectableText(value, style: const TextStyle(fontSize: 14)),],),);
  }

  Widget _buildStudioView() {
    final tagsAsyncValue = ref.watch(tagsProvider);
    return tagsAsyncValue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('태그를 불러올 수 없습니다: $err')),
      data: (allTags) {
        final mainCategories = allTags.keys.toList();
        final subCategoryData = _selectedMainCategory != null ? allTags[_selectedMainCategory!] : null;
        return Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildPromptDisplayArea(),
          const SizedBox(height: 16),
          _buildMainCategoryChips(mainCategories),
          const Divider(height: 24),
          Expanded(child: _buildSubTagSelectionArea(subCategoryData),),
          ElevatedButton(onPressed: () { if (_selectedTags.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장할 태그를 먼저 선택해주세요.')),); return; } final promptToSave = _selectedTags.join(', '); ref.read(savedPromptsProvider.notifier).addPrompt(promptToSave); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('프롬프트가 저장되었습니다! \'저장\' 탭에서 확인하세요.')),); setState(() { _selectedTags.clear(); }); }, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16.0)), child: const Text('프롬프트 저장'),),
        ],),);
      },
    );
  }

  Widget _buildPromptDisplayArea() {
    return Container(
      height: 150,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: _selectedTags.isEmpty
          ? Center(child: Text('아래에서 태그를 선택하여 프롬프트를 조합하세요.', style: TextStyle(color: Colors.grey)))
          : SingleChildScrollView(child: Wrap(spacing: 8.0, runSpacing: 4.0, children: _selectedTags.map((tag) => Chip(label: Text(tag), onDeleted: () { setState(() { _selectedTags.remove(tag); }); },)).toList(),),),
    );
  }

  Widget _buildMainCategoryChips(List<String> categories) {
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: categories.map((category) => Padding(padding: const EdgeInsets.only(right: 8.0), child: ChoiceChip(label: Text(category), selected: _selectedMainCategory == category, onSelected: (isSelected) { setState(() { _selectedMainCategory = isSelected ? category : null; }); },),)).toList(),),);
  }

  Widget _buildSubTagSelectionArea(Map<String, dynamic>? data) {
    if (_selectedMainCategory == null || data == null) { return Center(child: Text('상단에서 태그 대분류를 선택하세요.', style: TextStyle(color: Colors.grey))); }
    final List<Widget> tagWidgets = [];
    data.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        final String subCategory = key;
        final Map<String, dynamic> tags = value;
        tagWidgets.add(Padding(padding: const EdgeInsets.only(top: 16.0, bottom: 8.0), child: Text(subCategory, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),));
        tagWidgets.add(Wrap(spacing: 8.0, runSpacing: 8.0, children: tags.entries.map((entry) { return _buildTagChip(entry.key, entry.value.toString()); }).toList(),));
      } else {
        tagWidgets.add(_buildTagChip(key, value.toString()));
      }
    });
    return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Wrap(spacing: 8.0, runSpacing: 8.0, children: tagWidgets,)],),);
  }

  Widget _buildTagChip(String englishTag, String koreanMeaning) {
    final bool isTagSelected = _selectedTags.contains(englishTag);
    return FilterChip(
      label: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(koreanMeaning, style: const TextStyle(fontWeight: FontWeight.w500)), Text(englishTag, style: TextStyle(fontSize: 12, color: Colors.grey)),],),
      selected: isTagSelected,
      onSelected: (selected) { setState(() { if (selected) { _selectedTags.add(englishTag); } else { _selectedTags.remove(englishTag); } }); },
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(
          color: isTagSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
          width: 1.0,
        ),
      ),
    );
  }

  Widget _buildGeminiView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: _geminiConversation.isEmpty
                ? Center(child: Text("Gemini에게 무엇이든 물어보세요!", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                : ListView.builder(
              reverse: true,
              itemCount: _geminiConversation.length,
              itemBuilder: (context, index) {
                final message = _geminiConversation.reversed.toList()[index];
                return _buildChatBubble(message);
              },
            ),
          ),
          if (_isGeminiLoading) const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: CircularProgressIndicator()),

          _buildGeminiControls(),

          _buildGeminiInputArea(),
        ],
      ),
    );
  }

  Widget _buildGeminiControls() {
    final lastResponse = _geminiConversation.lastWhere((m) => !m.isFromUser, orElse: () => ChatMessage(text: '', isFromUser: false)).text;
    return Column(
      children: [
        if (_attachedImagePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Chip(
              label: Text(p.basename(_attachedImagePath!)),
              avatar: const Icon(Icons.image_outlined),
              onDeleted: () => setState(() => _attachedImagePath = null),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Checkbox(value: _useTagLibrary, onChanged: (val) => setState(() => _useTagLibrary = val!)),
                const Text('태그 사용'),
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  tooltip: '이미지 첨부',
                  onPressed: _pickImageForGemini,
                ),
              ],
            ),
            Row(
              children: [
                TextButton(
                  onPressed: lastResponse.isEmpty ? null : () {
                    ref.read(memosProvider.notifier).addMemo(lastResponse);
                    // [수정] 안내 메시지를 더 명확하게 변경
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('답변이 \'메모\' 탭에 저장되었습니다!')));
                  },
                  child: const Text('답변 저장'),
                ),
                TextButton(
                  onPressed: () => setState(() => _geminiConversation.clear()),
                  child: const Text('새 채팅'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGeminiInputArea() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _geminiInputController,
              decoration: InputDecoration(
                hintText: 'Gemini에게 메시지 보내기...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24.0)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              ),
              onSubmitted: (_) => _handleGeminiSubmit(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            icon: const Icon(Icons.send),
            onPressed: _isGeminiLoading ? null : _handleGeminiSubmit,
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    final bubbleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.attachedImagePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.file(
                File(message.attachedImagePath!),
                height: 150,
                width: 150,
                fit: BoxFit.cover,
              ),
            ),
          ),
        SelectableText(message.text),
      ],
    );

    return Align(
      alignment: message.isFromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        decoration: BoxDecoration(
          color: message.isFromUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: bubbleContent,
      ),
    );
  }
}