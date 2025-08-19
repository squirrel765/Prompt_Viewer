// lib/screens/tag_library_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/preset_provider.dart';

class TagLibraryScreen extends ConsumerStatefulWidget {
  /// AppBar 표시 여부를 제어하는 파라미터.
  /// true이면 독립된 화면으로, false이면 다른 화면의 탭 내용으로 사용됩니다.
  final bool showAppBar;

  const TagLibraryScreen({super.key, this.showAppBar = true});

  @override
  ConsumerState<TagLibraryScreen> createState() => _TagLibraryScreenState();
}

class _TagLibraryScreenState extends ConsumerState<TagLibraryScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.toLowerCase();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 검색 쿼리를 기반으로 태그 맵을 필터링하는 함수
  Map<String, dynamic> _filterTags(Map<String, dynamic> allTags) {
    if (_searchQuery.isEmpty) {
      return allTags;
    }

    final filteredCategories = <String, dynamic>{};
    allTags.forEach((categoryKey, categoryValue) {
      // 타입 체크 추가: categoryValue가 Map이 아니면 필터링 로직을 건너뜁니다.
      if (categoryValue is! Map<String, dynamic>) return;

      final filteredSubCategories = <String, dynamic>{};
      categoryValue.forEach((subCategoryKey, subCategoryValue) {
        // 타입 체크 추가: subCategoryValue가 Map이면 태그 목록으로 간주하고 필터링합니다.
        if (subCategoryValue is Map<String, dynamic>) {
          final filteredTags = <String, dynamic>{};
          subCategoryValue.forEach((tagKey, tagValue) {
            if (tagKey.toLowerCase().contains(_searchQuery) ||
                (tagValue as String).toLowerCase().contains(_searchQuery)) {
              filteredTags[tagKey] = tagValue;
            }
          });
          if (filteredTags.isNotEmpty) {
            filteredSubCategories[subCategoryKey] = filteredTags;
          }
        }
        // subCategoryValue가 Map이 아니면(String이면) 직접 태그로 간주하고 필터링합니다.
        else if (subCategoryValue is String) {
          if (subCategoryKey.toLowerCase().contains(_searchQuery) ||
              subCategoryValue.toLowerCase().contains(_searchQuery)) {
            filteredSubCategories[subCategoryKey] = subCategoryValue;
          }
        }
      });
      if (filteredSubCategories.isNotEmpty) {
        filteredCategories[categoryKey] = filteredSubCategories;
      }
    });

    return filteredCategories;
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsyncValue = ref.watch(tagsProvider);

    // 화면의 핵심 콘텐츠 UI
    final content = tagsAsyncValue.when(
      data: (allTags) {
        final filteredTags = _filterTags(allTags);
        if (filteredTags.isEmpty && _searchQuery.isNotEmpty) {
          return const Center(child: Text('검색 결과가 없습니다.'));
        }
        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: filteredTags.entries.map((category) {
            // [수정] Card 위젯은 main.dart의 cardTheme을 자동으로 따릅니다.
            return Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                title: Text(category.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                initiallyExpanded: _searchQuery.isNotEmpty,
                children: (category.value as Map<String, dynamic>).entries.map((subCategory) {
                  // --- START: 핵심 수정 부분 ---
                  // subCategory의 값이 Map인지 확인합니다.
                  if (subCategory.value is Map<String, dynamic>) {
                    // 값이 Map이면, 하위 태그를 가진 SubCategory로 간주하고 ExpansionTile을 만듭니다.
                    return ExpansionTile(
                      title: Padding(
                        padding: const EdgeInsets.only(left: 16.0),
                        child: Text(subCategory.key, style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      initiallyExpanded: _searchQuery.isNotEmpty,
                      children: (subCategory.value as Map<String, dynamic>).entries.map((tag) {
                        return ListTile(
                          contentPadding: const EdgeInsets.only(left: 48, right: 16),
                          title: Text(tag.value.toString()), // 한글 뜻
                          subtitle: Text(tag.key), // 영어 태그
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: tag.key));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("'${tag.key}' 복사 완료!"),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    );
                  } else {
                    // 값이 Map이 아니면(String이면), 직접적인 Tag로 간주하고 ListTile을 만듭니다.
                    return ListTile(
                      contentPadding: const EdgeInsets.only(left: 32, right: 16),
                      title: Text(subCategory.value.toString()), // 한글 뜻
                      subtitle: Text(subCategory.key), // 영어 태그
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: subCategory.key));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("'${subCategory.key}' 복사 완료!"),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                    );
                  }
                  // --- END: 핵심 수정 부분 ---
                }).toList(),
              ),
            );
          }).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('태그를 불러올 수 없습니다: $err')),
    );

    // showAppBar 값에 따라 Scaffold를 포함하거나 내용만 반환
    if (widget.showAppBar) {
      // 독립 페이지로 사용될 때
      return Scaffold(
        // [수정] backgroundColor 제거 (테마 자동 적용)
        appBar: AppBar(
          // [수정] backgroundColor, elevation, icon color 등 모두 제거 (테마 자동 적용)
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: _buildSearchField(),
        ),
        body: content,
      );
    } else {
      // 다른 화면의 탭 안에 포함될 때
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: _buildSearchField(isContained: true),
          ),
          Expanded(child: content),
        ],
      );
    }
  }

  /// 검색창 UI를 별도 메서드로 분리
  Widget _buildSearchField({bool isContained = false}) {
    // [핵심 수정] InputDecoration을 대폭 간소화하여 main.dart의 inputDecorationTheme을 따르도록 함
    final inputDecoration = InputDecoration(
      hintText: '태그 검색 (한글/영문)',
      prefixIcon: const Icon(Icons.search), // Icon 색상은 테마에 의해 자동 결정됨
      suffixIcon: _searchQuery.isNotEmpty
          ? IconButton(
        icon: const Icon(Icons.clear), // Icon 색상은 테마에 의해 자동 결정됨
        onPressed: () {
          _searchController.clear();
        },
      )
          : null,
      // fillColor, border, contentPadding 등은 모두 중앙 테마에서 가져옴
    );

    if (isContained) {
      return TextField(
        controller: _searchController,
        decoration: inputDecoration,
      );
    } else {
      // AppBar의 title로 사용될 때
      return SizedBox(
        height: 40,
        child: TextField(
          controller: _searchController,
          autofocus: true,
          // [수정] style 제거 (AppBar의 foregroundColor가 적용됨)
          decoration: inputDecoration,
        ),
      );
    }
  }
}