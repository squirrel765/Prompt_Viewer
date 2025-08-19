// lib/screens/generate_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/providers/preset_provider.dart';
import 'package:prompt_viewer/providers/saved_prompts_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart';
import 'package:prompt_viewer/services/civitai_service.dart';
import 'package:path/path.dart' as p;

// 생성 화면의 두 가지 모드를 정의합니다.
enum GenerateMode { civitai, fromPrompt }

class GenerateScreen extends ConsumerStatefulWidget {
  const GenerateScreen({super.key});

  @override
  ConsumerState<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends ConsumerState<GenerateScreen> {
  // --- 상태 변수들 ---
  GenerateMode _selectedMode = GenerateMode.civitai;
  final _civitaiUrlController = TextEditingController();
  bool _isLoading = false;
  bool _isSaving = false;
  CivitaiInfo? _importedData; // 최종적으로 선택된 이미지의 정보

  // 'Generate Prompt' 탭을 위한 상태 변수
  String? _selectedMainCategory;
  final List<String> _selectedTags = [];

  @override
  void dispose() {
    _civitaiUrlController.dispose();
    super.dispose();
  }

  /// 'Import' 버튼을 눌렀을 때 실제 Civitai API를 호출하는 함수
  Future<void> _fetchCivitaiData() async {
    if (_civitaiUrlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Civitai 링크를 입력해주세요.')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) { setState(() { _isLoading = false; }); }
    }
  }

  /// 가져온 이미지 목록에서 하나를 선택하게 하는 다이얼로그
  Future<CivitaiInfo?> _showImageSelectionDialog(List<CivitaiInfo> images) {
    return showDialog<CivitaiInfo>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('이미지 선택'),
          contentPadding: const EdgeInsets.all(16),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              itemCount: images.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
              ),
              itemBuilder: (context, index) {
                final imageInfo = images[index];
                return InkWell(
                  onTap: () => Navigator.of(context).pop(imageInfo),
                  borderRadius: BorderRadius.circular(8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.network(
                      '${imageInfo.imageUrl}/width=300',
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (context, error, stack) =>
                      const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
  }

  /// '갤러리에 저장' 버튼을 눌렀을 때 실행되는 함수
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

      // 저장이 완료되면 갤러리를 새로고침하여 앱에 즉시 반영
      await ref.read(galleryProvider.notifier).syncFolder(rootFolder);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('성공적으로 저장되었습니다!\n경로: $destPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isSaving = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTabs(),
        Expanded(
          child: _selectedMode == GenerateMode.civitai
              ? SingleChildScrollView(child: _buildCivitaiImportView())
              : _buildGeneratePromptView(),
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
          _buildTabItem('Import from Civitai', GenerateMode.civitai),
          _buildTabItem('Generate Prompt', GenerateMode.fromPrompt),
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
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCivitaiImportView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _civitaiUrlController,
            decoration: InputDecoration(
              labelText: 'Civitai Model URL',
              hintText: 'https://civitai.com/models/...',
              helperText: '예: civitai.com/models/9409',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _fetchCivitaiData,
              child: const Text('가져오기'),
            ),
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ))
          else if (_importedData != null)
            _buildImportedInfo(),
        ],
      ),
    );
  }

  Widget _buildImportedInfo() {
    final detailsString = _importedData!.otherDetails.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('가져온 정보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(12.0),
          child: Image.network(
            _importedData!.imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
            errorBuilder: (context, error, stack) => const Icon(Icons.broken_image, size: 48, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 16),
        if (_importedData!.prompt != null && _importedData!.prompt!.isNotEmpty)
          _buildDetailRow('Prompt', _importedData!.prompt!),
        if (_importedData!.negativePrompt != null && _importedData!.negativePrompt!.isNotEmpty)
          _buildDetailRow('Negative Prompt', _importedData!.negativePrompt!),
        if (detailsString.isNotEmpty)
          _buildDetailRow('Other Details', detailsString),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_alt),
            label: Text(_isSaving ? '저장하는 중...' : '갤러리에 저장'),
            onPressed: _isSaving ? null : _saveToGallery,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                tooltip: '복사',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$title 복사 완료!'), duration: const Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildGeneratePromptView() {
    final tagsAsyncValue = ref.watch(tagsProvider);

    return tagsAsyncValue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('태그를 불러올 수 없습니다: $err')),
      data: (allTags) {
        final mainCategories = allTags.keys.toList();
        final subCategoryData = _selectedMainCategory != null ? allTags[_selectedMainCategory!] : null;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPromptDisplayArea(),
              const SizedBox(height: 16),
              _buildMainCategoryChips(mainCategories),
              const Divider(height: 24),
              Expanded(
                child: _buildSubTagSelectionArea(subCategoryData),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_selectedTags.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('저장할 태그를 먼저 선택해주세요.')),
                    );
                    return;
                  }
                  final promptToSave = _selectedTags.join(', ');
                  ref.read(savedPromptsProvider.notifier).addPrompt(promptToSave);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('프롬프트가 저장되었습니다! \'저장\' 탭에서 확인하세요.')),
                  );
                  setState(() { _selectedTags.clear(); });
                },
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0)
                ),
                child: const Text('프롬프트 저장'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPromptDisplayArea() {
    return Container(
      height: 150,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: _selectedTags.isEmpty
          ? Center(child: Text('아래에서 태그를 선택하여 프롬프트를 조합하세요.', style: TextStyle(color: Colors.grey[600])))
          : SingleChildScrollView(
        child: Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: _selectedTags.map((tag) => Chip(
            label: Text(tag),
            onDeleted: () {
              setState(() { _selectedTags.remove(tag); });
            },
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildMainCategoryChips(List<String> categories) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((category) => Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: ChoiceChip(
            label: Text(category),
            selected: _selectedMainCategory == category,
            onSelected: (isSelected) {
              setState(() { _selectedMainCategory = isSelected ? category : null; });
            },
          ),
        )).toList(),
      ),
    );
  }

  // --- START: 핵심 수정 부분 ---
  Widget _buildSubTagSelectionArea(Map<String, dynamic>? data) {
    if (_selectedMainCategory == null || data == null) {
      return Center(child: Text('상단에서 태그 대분류를 선택하세요.', style: TextStyle(color: Colors.grey[600])));
    }

    final List<Widget> tagWidgets = [];

    // 주어진 데이터(data)의 각 항목에 대해 반복
    data.forEach((key, value) {
      // 만약 value가 Map 타입이라면, 이는 '소분류'에 해당합니다.
      if (value is Map<String, dynamic>) {
        final String subCategory = key;
        final Map<String, dynamic> tags = value;

        // 소분류 제목을 추가합니다.
        tagWidgets.add(Padding(
          padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
          child: Text(subCategory, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ));

        // 소분류에 속한 모든 태그들을 Wrap 위젯으로 감싸서 추가합니다.
        tagWidgets.add(Wrap(
          spacing: 8.0, runSpacing: 8.0,
          children: tags.entries.map((entry) {
            return _buildTagChip(entry.key, entry.value.toString());
          }).toList(),
        ));
      }
      // value가 Map이 아니라면 (보통 String), 이는 '소분류가 없는 직접적인 태그'입니다.
      else {
        // 이 경우 key가 영어 태그, value가 한글 뜻이 됩니다.
        // 소분류가 없으므로 별도의 제목 없이 바로 태그 칩을 추가합니다.
        // (주의: 이 로직은 현재 파일 구조에서는 잘 사용되지 않지만, 코드의 안정성을 높여줍니다.)
        tagWidgets.add(_buildTagChip(key, value.toString()));
      }
    });

    // 위에서 생성된 모든 위젯들을 스크롤 가능한 Column으로 묶어서 반환합니다.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap( // 소분류 없는 태그들을 한 곳에 모아 표시하기 위한 Wrap
            spacing: 8.0,
            runSpacing: 8.0,
            children: tagWidgets,
          )
        ],
      ),
    );
  }

  /// 태그 칩(FilterChip) 생성을 위한 헬퍼 위젯
  Widget _buildTagChip(String englishTag, String koreanMeaning) {
    final bool isTagSelected = _selectedTags.contains(englishTag);
    return FilterChip(
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(koreanMeaning, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(englishTag, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
      selected: isTagSelected,
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _selectedTags.add(englishTag);
          } else {
            _selectedTags.remove(englishTag);
          }
        });
      },
      selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(
          color: isTagSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
          width: 1.0,
        ),
      ),
    );
  }
// --- END: 핵심 수정 부분 ---
}