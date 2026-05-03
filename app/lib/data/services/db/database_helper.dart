import 'dart:async';
import 'package:get_storage/get_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static Database? _database;
  static String _userId = '';

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final GetStorage storage = GetStorage();
    Map? userInfo = storage.read("user_info");
    if (userInfo != null) {
      _userId = userInfo['user']['uid'];
    } else {
      _userId = '';
    }
    String path = join(
      await getDatabasesPath(),
      _userId.isNotEmpty ? '${_userId}database1.db' : 'database1.db',
    );
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    final batch = db.batch();
    // 用户信息
    batch.execute('''
      CREATE TABLE IF NOT EXISTS user (
        id TEXT PRIMARY KEY,
        synctime INTEGER,
        privatecloud INTEGER
      )
    ''');
    // 商务会议助手列表
    batch.execute('''
      CREATE TABLE IF NOT EXISTS meeting (
        id INTEGER PRIMARY KEY,
        title TEXT,
        type TEXT,
        seconds INTEGER,
        filepath TEXT,
        audiourl TEXT,
        tasktype INTEGER,
        creationtime INTEGER
      )
    ''');
    // 商务会议助手详情内容
    batch.execute('''
      CREATE TABLE IF NOT EXISTS meetingdetails (
        id INTEGER PRIMARY KEY,
        meetingid INTEGER,
        address TEXT,
        personnel TEXT,
        taskid TEXT,
        tasktype INTEGER,
        overview TEXT,
        summary TEXT,
        mindmap TEXT
      )
    ''');
    // 商务会议助手转写内容
    batch.execute('''
      CREATE TABLE IF NOT EXISTS meetingspeaker (
        id INTEGER PRIMARY KEY,
        meetingid INTEGER,
        content TEXT,
        starttime INTEGER,
        endtime INTEGER,
        speaker TEXT
      )
    ''');
    // 商务会议助手Ask AI
    batch.execute('''
      CREATE TABLE IF NOT EXISTS meetingai (
        id INTEGER PRIMARY KEY,
        meetingid INTEGER,
        user TEXT,
        assistant TEXT,
        cruxtext TEXT
      )
    ''');
    // 商务会议助手模版分类
    batch.execute('''
      CREATE TABLE IF NOT EXISTS meetingcategorytemplate (
        id INTEGER PRIMARY KEY,
        name TEXT,
        language TEXT
      )
    ''');
    // 商务会议助手模版
    batch.execute('''
      CREATE TABLE IF NOT EXISTS meetingtemplate (
        id INTEGER PRIMARY KEY,
        tid TEXT,
        categoryid INTEGER,
        name TEXT,
        icon TEXT,
        tag TEXT,
        desc TEXT,
        outline TEXT,
        prompt TEXT,
        language TEXT
      )
    ''');
    batch.insert('user', {
      'id': _userId,
      'synctime': 0,
      'privatecloud': 0,
    });
    await batch.commit();
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
