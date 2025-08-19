// lib/services/database_service.dart

import 'dart:convert';
import 'package:path/path.dart';
import 'package:prompt_viewer/models/image_metadata.dart';
import 'package:prompt_viewer/models/prompt_preset.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static const _databaseName = "gallery.db";
  // *** 데이터베이스 버전을 6으로 올립니다. ***
  static const _databaseVersion = 6;

  static const imagesTable = 'images';
  static const presetsTable = 'prompt_presets';

  // 싱글톤 패턴을 사용하여 앱 전체에서 단 하나의 DB 서비스 인스턴스만 사용하도록 합니다.
  DatabaseService._privateConstructor();
  static final DatabaseService instance = DatabaseService._privateConstructor();

  // 데이터베이스 연결을 한 번만 생성하고 재사용하기 위한 변수입니다.
  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // 데이터베이스 파일을 열거나 생성합니다.
  _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // 앱이 처음 설치되어 DB가 없을 때 테이블을 생성합니다.
  Future _onCreate(Database db, int version) async {
    await _createImagesTable(db);
    await _createPresetsTable(db);
  }

  // 앱 업데이트 등으로 DB 버전이 올라갔을 때 기존 구조를 변경(마이그레이션)합니다.
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
    // *** 버전 6으로 업그레이드될 때 실행될 마이그레이션 코드 ***
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE $imagesTable ADD COLUMN is_nsfw INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE $presetsTable ADD COLUMN is_nsfw INTEGER NOT NULL DEFAULT 0');
    }
  }

  // 'images' 테이블 생성 SQL (새로운 컬럼 포함)
  Future<void> _createImagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE $imagesTable (
        path TEXT PRIMARY KEY,
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

  // 'prompt_presets' 테이블 생성 SQL (새로운 컬럼 포함)
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

  Future<void> insertOrUpdateImage(ImageMetadata metadata) async {
    final db = await database;
    await db.insert(
      imagesTable,
      metadata.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ImageMetadata>> getAllImages() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(imagesTable, orderBy: 'timestamp DESC');
    return List.generate(maps.length, (i) => ImageMetadata.fromMap(maps[i]));
  }

  Future<List<ImageMetadata>> getImagesByPath(String folderPath) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
        imagesTable,
        where: 'path LIKE ?',
        whereArgs: ['$folderPath%']
    );
    return List.generate(maps.length, (i) => ImageMetadata.fromMap(maps[i]));
  }

  Future<void> deleteImage(String path) async {
    final db = await database;
    await db.delete(imagesTable, where: 'path = ?', whereArgs: [path]);
  }

  Future<void> updateFavoriteStatus(String path, bool isFavorite) async {
    final db = await database;
    await db.update(
      imagesTable,
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  /// *** 새로 추가된 NSFW 상태 업데이트 메서드 ***
  Future<void> updateImageNsfwStatus(String path, bool isNsfw) async {
    final db = await database;
    await db.update(
      imagesTable,
      {'is_nsfw': isNsfw ? 1 : 0},
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  /// *** 새로 추가된 별점 업데이트 메서드 ***
  Future<void> updateImageRating(String path, double rating) async {
    final db = await database;
    await db.update(
      imagesTable,
      {'rating': rating},
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  /// *** 새로 추가된 조회수 증가 메서드 ***
  Future<void> incrementImageViewCount(String path) async {
    final db = await database;
    // 기존 값에 1을 더하는 SQL 쿼리를 직접 실행하여 효율성을 높입니다.
    await db.rawUpdate('UPDATE $imagesTable SET view_count = view_count + 1 WHERE path = ?', [path]);
  }

  Future<void> updateImagePath(String oldPath, String newPath) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(imagesTable, where: 'path = ?', whereArgs: [oldPath]);
    if (maps.isNotEmpty) {
      final oldData = Map<String, dynamic>.from(maps.first);
      oldData['path'] = newPath;
      await db.transaction((txn) async {
        await txn.delete(imagesTable, where: 'path = ?', whereArgs: [oldPath]);
        await txn.insert(imagesTable, oldData);
      });
    }
  }

  // --- 프리셋 관련 CRUD 함수들 ---

  Future<void> insertOrUpdatePreset(PromptPreset preset) async {
    final db = await database;
    await db.insert(
      presetsTable,
      preset.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PromptPreset>> getAllPresets() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(presetsTable, orderBy: 'title ASC');
    return List.generate(maps.length, (i) => PromptPreset.fromMap(maps[i]));
  }

  Future<void> deletePreset(String id) async {
    final db = await database;
    await db.delete(presetsTable, where: 'id = ?', whereArgs: [id]);
  }
}