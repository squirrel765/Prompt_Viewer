// lib/models/image_metadata.dart

class ImageMetadata {
  final String path;
  final int timestamp;
  String? a1111Parameters;
  String? comfyUIWorkflow;
  String? naiComment;
  bool isFavorite;
  // *** 새로 추가된 필드 ***
  double rating; // 0.0 ~ 5.0
  int viewCount;
  bool isNsfw; // NSFW 여부

  ImageMetadata({
    required this.path,
    required this.timestamp,
    this.a1111Parameters,
    this.comfyUIWorkflow,
    this.naiComment,
    this.isFavorite = false,
    // *** 기본값 설정 ***
    this.rating = 0.0,
    this.viewCount = 0,
    this.isNsfw = false, // 기본값은 false
  });

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'a1111_parameters': a1111Parameters,
      'comfyui_workflow': comfyUIWorkflow,
      'nai_comment': naiComment,
      'is_favorite': isFavorite ? 1 : 0,
      'timestamp': timestamp,
      // *** toMap에 추가 ***
      'rating': rating,
      'view_count': viewCount,
      'is_nsfw': isNsfw ? 1 : 0, // toMap에 추가
    };
  }

  factory ImageMetadata.fromMap(Map<String, dynamic> map) {
    return ImageMetadata(
      path: map['path'],
      a1111Parameters: map['a1111_parameters'],
      comfyUIWorkflow: map['comfyui_workflow'],
      naiComment: map['nai_comment'],
      isFavorite: map['is_favorite'] == 1,
      timestamp: map['timestamp'],
      // *** fromMap에 추가 (DB에 값이 없을 경우를 대비해 기본값 제공) ***
      rating: map['rating'] ?? 0.0,
      viewCount: map['view_count'] ?? 0,
      isNsfw: map['is_nsfw'] == 1, // fromMap에 추가
    );
  }
}