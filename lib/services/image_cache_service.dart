// lib/services/image_cache_service.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'dart:collection';

// [수정] ChangeNotifier를 상속받아 상태 변경 알림 기능을 추가
class ImageCacheService extends ChangeNotifier {
  final int maxSize;
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();

  ImageCacheService({this.maxSize = 100});

  // 캐시된 데이터를 직접 접근할 수 있도록 getter 추가
  UnmodifiableMapView<String, Uint8List> get entries => UnmodifiableMapView(_cache);

  Future<void> loadImage(String path) async {
    if (_cache.containsKey(path)) {
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        _cache[path] = bytes;

        if (_cache.length > maxSize) {
          _cache.remove(_cache.keys.first);
        }
        // 캐시에 이미지가 추가되었음을 알림
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Failed to load image for cache: $e");
    }
  }

  Uint8List? getImage(String path) {
    if (_cache.containsKey(path)) {
      final bytes = _cache.remove(path)!;
      _cache[path] = bytes;
      return bytes;
    }
    return null;
  }

  void clear() {
    _cache.clear();
    notifyListeners();
  }
}