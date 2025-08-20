// lib/models/image_metadata.dart

class ImageMetadata {
  final String path;
  final String thumbnailPath; // 썸네일 이미지 파일의 경로
  final int timestamp;
  String? a1111Parameters;
  String? comfyUIWorkflow;
  String? naiComment;
  bool isFavorite;
  double rating; // 0.0 ~ 5.0
  int viewCount;
  bool isNsfw; // NSFW 여부

  ImageMetadata({
    required this.path,
    required this.thumbnailPath, // 생성자에 추가
    required this.timestamp,
    this.a1111Parameters,
    this.comfyUIWorkflow,
    this.naiComment,
    this.isFavorite = false,
    this.rating = 0.0,
    this.viewCount = 0,
    this.isNsfw = false,
  });

  /// 객체를 데이터베이스에 저장하기 위해 Map 형태로 변환합니다.
  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'thumbnailPath': thumbnailPath, // toMap에 추가
      'timestamp': timestamp,
      'a1111_parameters': a1111Parameters,
      'comfyui_workflow': comfyUIWorkflow,
      'nai_comment': naiComment,
      'is_favorite': isFavorite ? 1 : 0,
      'rating': rating,
      'view_count': viewCount,
      'is_nsfw': isNsfw ? 1 : 0,
    };
  }

  /// 데이터베이스에서 읽어온 Map을 객체로 변환합니다.
  factory ImageMetadata.fromMap(Map<String, dynamic> map) {
    return ImageMetadata(
      path: map['path'],
      // fromMap에 추가: DB에 아직 thumbnailPath가 없는 기존 데이터를 위해 기본값('') 제공
      thumbnailPath: map['thumbnailPath'] ?? '',
      timestamp: map['timestamp'],
      a1111Parameters: map['a1111_parameters'],
      comfyUIWorkflow: map['comfyui_workflow'],
      naiComment: map['nai_comment'],
      isFavorite: map['is_favorite'] == 1,
      rating: map['rating'] ?? 0.0,
      viewCount: map['view_count'] ?? 0,
      isNsfw: map['is_nsfw'] == 1,
    );
  }

  // [추가] 데이터 병합을 위한 copyWith 메서드
  ImageMetadata copyWith({
    String? path,
    String? thumbnailPath,
    int? timestamp,
    String? a1111Parameters,
    String? comfyUIWorkflow,
    String? naiComment,
    bool? isFavorite,
    double? rating,
    int? viewCount,
    bool? isNsfw,
  }) {
    return ImageMetadata(
      path: path ?? this.path,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      timestamp: timestamp ?? this.timestamp,
      a1111Parameters: a1111Parameters ?? this.a1111Parameters,
      comfyUIWorkflow: comfyUIWorkflow ?? this.comfyUIWorkflow,
      naiComment: naiComment ?? this.naiComment,
      isFavorite: isFavorite ?? this.isFavorite,
      rating: rating ?? this.rating,
      viewCount: viewCount ?? this.viewCount,
      isNsfw: isNsfw ?? this.isNsfw,
    );
  }
}