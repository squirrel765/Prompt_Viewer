// lib/services/database_service.dart

import 'package:path/path.dart';
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/models/prompt_preset.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static const _databaseName = "gallery.db";
  static const _databaseVersion = 7; // 썸네일 경로 추가로 버전 7

  static const imagesTable = 'images';
  static const presetsTable = 'prompt_presets';

  DatabaseService._privateConstructor();
  static final DatabaseService instance = DatabaseService._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onCreate(Database db, int version) async {
    await _createImagesTable(db);
    await _createPresetsTable(db);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await _createPresetsTable(db);
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE $imagesTable ADD COLUMN nai_comment TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE $imagesTable ADD COLUMN rating REAL NOT NULL DEFAULT 0.0');
      await db.execute('ALTER TABLE $imagesTable ADD COLUMN view_count INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE $imagesTable ADD COLUMN is_nsfw INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE $presetsTable ADD COLUMN is_nsfw INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE $imagesTable ADD COLUMN thumbnailPath TEXT NOT NULL DEFAULT ""');
    }
  }

  Future<void> _createImagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE $imagesTable (
        path TEXT PRIMARY KEY,
        thumbnailPath TEXT NOT NULL,
        a1111_parameters TEXT,
        comfyui_workflow TEXT,
        nai_comment TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        timestamp INTEGER NOT NULL,
        rating REAL NOT NULL DEFAULT 0.0,
        view_count INTEGER NOT NULL DEFAULT 0,
        is_nsfw INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createPresetsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $presetsTable (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        prompt TEXT NOT NULL,
        thumbnail_path TEXT NOT NULL,
        image_paths TEXT NOT NULL,
        rating REAL NOT NULL,
        is_nsfw INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // --- 이미지 관련 CRUD 함수들 ---

  /// 증분 동기화를 위해 DB에 저장된 모든 이미지의 경로와 타임스탬프를 가져옵니다.
  Future<Map<String, int>> getAllImagePathsAndTimestamps() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      imagesTable,
      columns: ['path', 'timestamp'], // path와 timestamp 컬럼만 선택하여 효율성 증대
    );

    return { for (var map in maps) map['path'] as String: map['timestamp'] as int };
  }

  /// 점진적 로딩(페이지네이션)을 위한 이미지 조회 메서드 (초기 로딩용)
  Future<List<ImageMetadata>> getImagesPaginated(int limit, int offset) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      imagesTable,
      orderBy: 'timestamp DESC', // 최신순으로 정렬
      limit: limit,
      offset: offset,
    );
    return List.generate(maps.length, (i) => ImageMetadata.fromMap(maps[i]));
  }

  /// [필수] 모든 이미지 정보를 가져옵니다 (백그라운드 전체 로드 및 전체 검색용).
  Future<List<ImageMetadata>> getAllImages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(imagesTable, orderBy: 'timestamp DESC');
    return List.generate(maps.length, (i) => ImageMetadata.fromMap(maps[i]));
  }

  /// 성능 개선을 위한 배치(Batch) 삽입/업데이트 메서드
  Future<void> insertOrUpdateImagesBatch(List<ImageMetadata> metadatas) async {
    if (metadatas.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final metadata in metadatas) {
      batch.insert(
        imagesTable,
        metadata.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 특정 경로의 이미지 정보를 DB에서 삭제합니다.
  Future<void> deleteImage(String path) async {
    final db = await database;
    await db.delete(imagesTable, where: 'path = ?', whereArgs: [path]);
  }

  /// 즐겨찾기 상태를 업데이트합니다.
  Future<void> updateFavoriteStatus(String path, bool isFavorite) async {
    final db = await database;
    await db.update(
      imagesTable,
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  /// NSFW 상태를 업데이트합니다.
  Future<void> updateImageNsfwStatus(String path, bool isNsfw) async {
    final db = await database;
    await db.update(
      imagesTable,
      {'is_nsfw': isNsfw ? 1 : 0},
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  /// 별점을 업데이트합니다.
  Future<void> updateImageRating(String path, double rating) async {
    final db = await database;
    await db.update(
      imagesTable,
      {'rating': rating},
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  /// 조회수를 1 증가시킵니다.
  Future<void> incrementImageViewCount(String path) async {
    final db = await database;
    await db.rawUpdate('UPDATE $imagesTable SET view_count = view_count + 1 WHERE path = ?', [path]);
  }


  // --- 프리셋 관련 CRUD 함수들 ---

  /// 프리셋을 삽입하거나 업데이트합니다.
  Future<void> insertOrUpdatePreset(PromptPreset preset) async {
    final db = await database;
    await db.insert(
      presetsTable,
      preset.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 모든 프리셋을 가져옵니다.
  Future<List<PromptPreset>> getAllPresets() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(presetsTable, orderBy: 'title ASC');
    return List.generate(maps.length, (i) => PromptPreset.fromMap(maps[i]));
  }

  /// 특정 ID의 프리셋을 삭제합니다.
  Future<void> deletePreset(String id) async {
    final db = await database;
    await db.delete(presetsTable, where: 'id = ?', whereArgs: [id]);
  }
}