// lib/screens/help_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/help_provider.dart';

class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // [핵심] 현재 테마 정보를 가져옵니다.
    final theme = Theme.of(context);
    final helpTermsAsync = ref.watch(helpTermsProvider);

    return Scaffold(
      // [수정] backgroundColor를 제거하여 main.dart의 테마를 따릅니다.
      appBar: AppBar(
        // [수정] 모든 스타일 관련 속성을 제거하여 main.dart의 AppBarTheme을 따릅니다.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text('도움말'),
      ),
      body: Column(
        children: [
          // --- 상단 검색창 ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              // [수정] decoration을 간소화하여 main.dart의 inputDecorationTheme을 따릅니다.
              decoration: InputDecoration(
                hintText: '용어 검색...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                )
                    : null,
              ),
            ),
          ),
          // --- 도움말 목록 ---
          Expanded(
            child: helpTermsAsync.when(
              data: (terms) {
                // 검색 쿼리로 목록 필터링
                final filteredTerms = _searchQuery.isEmpty
                    ? terms
                    : terms.where((term) {
                  return term.name.toLowerCase().contains(_searchQuery) ||
                      term.description.toLowerCase().contains(_searchQuery);
                }).toList();

                if (filteredTerms.isEmpty) {
                  return const Center(child: Text('검색 결과가 없습니다.'));
                }

                // ExpansionTile을 사용하여 각 항목을 접고 펼 수 있게 만듦
                return ListView.builder(
                  itemCount: filteredTerms.length,
                  itemBuilder: (context, index) {
                    final term = filteredTerms[index];
                    return ExpansionTile(
                      title: Text(term.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                          child: Text(
                            term.description,
                            // [수정] 글자색을 테마에 맞게 변경합니다. (onSurfaceVariant는 보통 회색 계열)
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('도움말을 불러올 수 없습니다: $err')),
            ),
          ),
        ],
      ),
    );
  }
}