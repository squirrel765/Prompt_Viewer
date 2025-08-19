// lib/screens/explore_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/providers/preset_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart'; // 설정 provider 임포트
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/models/prompt_preset.dart';
import 'package:prompt_viewer/screens/detail_screen.dart';
import 'package:prompt_viewer/screens/preset_detail_screen.dart';

// 필터 종류를 명확하게 정의하기 위한 enum
enum ExploreFilter { none, latest, popular, recommended }

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  // 기본 필터를 '최신이미지'로 설정
  ExploreFilter _selectedFilter = ExploreFilter.latest;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
          // 검색어가 입력되면, 필터 선택 상태를 해제
          if (_searchQuery.isNotEmpty) {
            _selectedFilter = ExploreFilter.none;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // galleryProvider와 presetProvider를 모두 watch하여 데이터 변경을 감지
    final allImages = ref.watch(galleryProvider);
    final allPresets = ref.watch(presetProvider);

    // NSFW 설정에 따라 필터링
    final showNsfw = ref.watch(configProvider).showNsfw;
    final imagesToDisplay = showNsfw ? allImages : allImages.where((img) => !img.isNsfw).toList();
    final presetsToDisplay = showNsfw ? allPresets : allPresets.where((p) => !p.isNsfw).toList();

    // 필터링 및 검색 로직을 통해 최종 결과 목록을 가져옴
    final List<dynamic> results = _getResults(imagesToDisplay, presetsToDisplay);

    return Column(
      children: [
        _buildSearchBar(),
        _buildFilterChips(),
        Expanded(
          child: results.isEmpty
              ? const Center(child: Text('결과가 없습니다.'))
              : _buildResultsGrid(results),
        ),
      ],
    );
  }

  /// 필터링 및 검색 결과를 반환하는 핵심 로직
  List<dynamic> _getResults(List<ImageMetadata> images, List<PromptPreset> presets) {
    // 1. 검색어가 있는 경우 (검색 우선)
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();

      // 이미지에서 프롬프트 내용 검색
      final imageResults = images.where((img) {
        return (img.a1111Parameters?.toLowerCase() ?? '').contains(query) ||
            (img.comfyUIWorkflow?.toLowerCase() ?? '').contains(query) ||
            (img.naiComment?.toLowerCase() ?? '').contains(query);
      }).toList();

      // 프리셋에서 제목 또는 프롬프트 내용 검색
      final presetResults = presets.where((p) {
        return p.title.toLowerCase().contains(query) || p.prompt.toLowerCase().contains(query);
      }).toList();

      // 두 검색 결과를 합쳐서 반환
      return [...imageResults, ...presetResults];
    }

    // 2. 검색어가 없는 경우 (필터 적용)
    // 필터는 이미지에만 적용됩니다.
    List<ImageMetadata> sortedImages = List.from(images);
    switch (_selectedFilter) {
      case ExploreFilter.latest: // 최신순 (수정 날짜 기준)
        sortedImages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        break;
      case ExploreFilter.popular: // 인기순 (별점 기준)
        sortedImages.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case ExploreFilter.recommended: // 추천순 (조회수 기준)
        sortedImages.sort((a, b) => b.viewCount.compareTo(a.viewCount));
        break;
      case ExploreFilter.none:
      default:
      // 필터가 선택되지 않았으면 기본 정렬(최신순) 유지
        break;
    }
    return sortedImages;
  }

  /// 상단 검색창 UI
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '프롬프트 내용으로 검색...',
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24.0),
            borderSide: BorderSide.none,
          ),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => _searchController.clear(),
          )
              : null,
        ),
      ),
    );
  }

  /// 필터 칩 UI
  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          _buildFilterChip('최신이미지', ExploreFilter.latest),
          _buildFilterChip('인기 이미지', ExploreFilter.popular),
          _buildFilterChip('추천 이미지', ExploreFilter.recommended),
        ],
      ),
    );
  }

  /// 개별 필터 칩 위젯
  Widget _buildFilterChip(String label, ExploreFilter filter) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: _selectedFilter == filter,
        onSelected: (selected) {
          setState(() {
            // 칩을 선택하면 해당 필터를 활성화하고, 다시 누르면 필터 해제
            _selectedFilter = selected ? filter : ExploreFilter.none;
            // 필터를 선택하면 검색어는 초기화
            _searchController.clear();
          });
        },
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
            side: BorderSide(color: Colors.grey.shade300)
        ),
      ),
    );
  }

  /// 검색/필터 결과 그리드 뷰 UI
  Widget _buildResultsGrid(List<dynamic> results) {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12.0,
        mainAxisSpacing: 12.0,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        // 아이템의 타입에 따라 다른 카드 위젯을 반환
        if (item is ImageMetadata) {
          return _buildImageResultCard(item);
        } else if (item is PromptPreset) {
          return _buildPresetResultCard(item);
        }
        return const SizedBox.shrink();
      },
    );
  }

  /// 이미지 검색 결과 카드
  Widget _buildImageResultCard(ImageMetadata image) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => DetailScreen(metadata: image)),
      ),
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
  }

  /// 프리셋 검색 결과 카드
  Widget _buildPresetResultCard(PromptPreset preset) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => PresetDetailScreen(presetId: preset.id)),
      ),
      // 프리셋임을 시각적으로 구분해주기 위해 Card로 감싸고 아이콘 추가
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: GridTile(
          footer: GridTileBar(
            backgroundColor: Colors.black45,
            title: Text(preset.title, style: const TextStyle(fontSize: 12)),
            leading: const Icon(Icons.star, color: Colors.amber, size: 16),
          ),
          child: Image.file(
            File(preset.thumbnailPath),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}