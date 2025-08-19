// lib/screens/explore_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/gallery_provider.dart';
import 'package:prompt_viewer/providers/preset_provider.dart';
import 'package:prompt_viewer/providers/settings_provider.dart';
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/models/prompt_preset.dart';
import 'package:prompt_viewer/screens/detail_screen.dart';
import 'package:prompt_viewer/screens/preset_detail_screen.dart';

enum ExploreFilter { none, latest, popular, recommended }

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  ExploreFilter _selectedFilter = ExploreFilter.latest;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text;
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
    // --- START: 수정된 부분 ---
    final galleryState = ref.watch(galleryProvider);
    // galleryState.items 리스트에서 FullImageItem 타입만 골라내고, 그 안의 metadata를 추출하여 List<ImageMetadata>를 만듭니다.
    final allImages = galleryState.items.whereType<FullImageItem>().map((item) => item.metadata).toList();
    // --- END: 수정된 부분 ---

    final allPresets = ref.watch(presetProvider);
    final showNsfw = ref.watch(configProvider).showNsfw;

    final imagesToDisplay = showNsfw ? allImages : allImages.where((img) => !img.isNsfw).toList();
    final presetsToDisplay = showNsfw ? allPresets : allPresets.where((p) => !p.isNsfw).toList();
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

  List<dynamic> _getResults(List<ImageMetadata> images, List<PromptPreset> presets) {
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      final imageResults = images.where((img) =>
      (img.a1111Parameters?.toLowerCase() ?? '').contains(query) ||
          (img.comfyUIWorkflow?.toLowerCase() ?? '').contains(query) ||
          (img.naiComment?.toLowerCase() ?? '').contains(query)).toList();
      final presetResults = presets.where((p) =>
      p.title.toLowerCase().contains(query) || p.prompt.toLowerCase().contains(query)).toList();
      return [...imageResults, ...presetResults];
    }

    List<ImageMetadata> sortedImages = List.from(images);
    switch (_selectedFilter) {
      case ExploreFilter.latest:
        sortedImages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        break;
      case ExploreFilter.popular:
        sortedImages.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case ExploreFilter.recommended:
        sortedImages.sort((a, b) => b.viewCount.compareTo(a.viewCount));
        break;
      case ExploreFilter.none:
      // default clause is not needed because all cases are covered.
    }
    return sortedImages;
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '프롬프트 내용으로 검색...',
          filled: true,
          // [경고 수정] surfaceVariant -> surfaceContainerHighest, withOpacity -> withAlpha
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(128),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24.0), borderSide: BorderSide.none),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => _searchController.clear()) : null,
        ),
      ),
    );
  }

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

  Widget _buildFilterChip(String label, ExploreFilter filter) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: _selectedFilter == filter,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = selected ? filter : ExploreFilter.none;
            _searchController.clear();
          });
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0), side: BorderSide(color: Colors.grey.shade300)),
      ),
    );
  }

  Widget _buildResultsGrid(List<dynamic> results) {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12.0, mainAxisSpacing: 12.0),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        if (item is ImageMetadata) {
          return _buildImageResultCard(item);
        } else if (item is PromptPreset) {
          return _buildPresetResultCard(item);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildImageResultCard(ImageMetadata image) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => DetailScreen(metadata: image))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: Image.file(File(image.thumbnailPath), fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_outlined, color: Colors.grey)),
      ),
    );
  }

  Widget _buildPresetResultCard(PromptPreset preset) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => PresetDetailScreen(presetId: preset.id))),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: GridTile(
          footer: GridTileBar(backgroundColor: Colors.black45, title: Text(preset.title, style: const TextStyle(fontSize: 12)), leading: const Icon(Icons.star, color: Colors.amber, size: 16)),
          child: Image.file(File(preset.thumbnailPath), fit: BoxFit.cover),
        ),
      ),
    );
  }
}