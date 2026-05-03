import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '/core/utils/logger.dart';

import 'database_helper.dart';

class SqfliteApi {
  // 获取个人信息
  static Future getUser() async {
    final db = await DatabaseHelper().database;
    List userList = await db.query('user');
    return userList.first;
  }

  // 修改个人信息
  static Future editUser(id, Map<String, Object?> user) async {
    final db = await DatabaseHelper().database;
    await db.update('user', user, where: 'id = ?', whereArgs: [id]);
  }

  /// 清除当前 sqlite 里所有"会议"相关数据 —— 用户登出 / 切账号时调用，
  /// 避免上一个账号的本地缓存被新账号看到。
  static Future<void> clearAllMeetingData() async {
    final db = await DatabaseHelper().database;
    await db.transaction((txn) async {
      await txn.delete('meeting');
      await txn.delete('meetingdetails');
      await txn.delete('meetingspeaker');
      await txn.delete('meetingai');
      await txn.delete('meetingtemplate');
      await txn.delete('meetingcategorytemplate');
    });
  }

  // 获取商务会议助手列表
  static Future getMeetingList() async {
    final db = await DatabaseHelper().database;
    // 顺手把 id<=0 的脏数据清掉。这种记录是早期 addRecordEchomeet
    // 响应字段缺失时残留下来的，留着会让"开始撰写"反复触发 id=0 的
    // 请求 / 触发"会议 id 无效"提示。
    await db.delete('meeting', where: 'id IS NULL OR id <= 0');
    await db.delete('meetingdetails',
        where: 'meetingid IS NULL OR meetingid <= 0');
    return await db.query(
      'meeting',
      orderBy: 'creationtime DESC',
    );
  }

  // 获取商务会议助手详情
  static Future getMeetingDetails(id) async {
    final db = await DatabaseHelper().database;
    List meetingList =
        await db.query('meeting', where: 'id = ?', whereArgs: [id]);
    List detailsList = await db.query(
      'meetingdetails',
      where: 'meetingid = ?',
      whereArgs: [id],
    );
    final meeting = meetingList.isNotEmpty
        ? Map<String, dynamic>.from(meetingList.first as Map)
        : <String, dynamic>{};
    final details = detailsList.isNotEmpty
        ? Map<String, dynamic>.from(detailsList.first as Map)
        : <String, dynamic>{
            'meetingid': id,
            'address': '',
            'personnel': '',
            'taskid': '',
            'tasktype': 0,
            'overview': '',
            'summary': '',
            'mindmap': '',
          };
    return <String, dynamic>{
      ...meeting,
      'taskid': details['taskid'] ?? '',
      'details': details,
    };
  }

  // 获取商务会议助手转写内容
  static Future getMeetingSpeaker(id) async {
    final db = await DatabaseHelper().database;
    return await db.query(
      'meetingspeaker',
      where: 'meetingid = ?',
      whereArgs: [id],
    );
  }

  // 插入商务会议助手
  static Future insertMeeting(Map<String, Object?> meeting) async {
    final db = await DatabaseHelper().database;
    try {
      await db.transaction((txn) async {
        await txn.insert('meeting', meeting);
        await txn.insert('meetingdetails', {
          'meetingid': meeting['id'],
          'address': '',
          'personnel': '',
          'taskid': '',
          'tasktype': 0,
          'overview': '',
          'summary': '',
          'mindmap': '',
        });
      });
      return true;
    } catch (e) {
      Get.snackbar(
        'error'.tr, // 错误
        'unknownError'.tr,
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.withOpacity(0.1),
        colorText: Colors.red,
      );
      return;
    }
  }

  // 修改商务会议助手详情内容
  static Future editMeeting(id, Map<String, Object?> meeting) async {
    final db = await DatabaseHelper().database;
    try {
      await db.update(
        'meetingdetails',
        meeting,
        where: 'meetingid = ?',
        whereArgs: [id],
      );
      return true;
    } catch (e) {
      Get.snackbar(
        'error'.tr, // 错误
        'unknownError'.tr,
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.withOpacity(0.1),
        colorText: Colors.red,
      );
      return;
    }
  }

  // 插入商务会议助手转写内容
  static Future insertMeetingSpeaker(List<Map<String, Object?>> data) async {
    final db = await DatabaseHelper().database;
    try {
      final batch = db.batch();
      for (var item in data) {
        batch.insert('meetingspeaker', item);
      }
      await batch.commit();
      return true;
    } catch (e) {
      Get.snackbar(
        'error'.tr, // 错误
        'unknownError'.tr,
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.withOpacity(0.1),
        colorText: Colors.red,
      );
      return;
    }
  }

  // 修改商务会议助手转写内容
  static Future editMeetingSpeaker(List data) async {
    final db = await DatabaseHelper().database;
    try {
      final batch = db.batch();
      for (var item in data) {
        Map<String, Object?> values = item['content'] != null
            ? {'content': item['content']}
            : {'speaker': item['speaker']};
        batch.update(
          'meetingspeaker',
          values,
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      }
      await batch.commit();
      return true;
    } catch (e) {
      Get.snackbar(
        'error'.tr, // 错误
        'unknownError'.tr,
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.withOpacity(0.1),
        colorText: Colors.red,
      );
      return;
    }
  }

  // 删除商务会议助手转写内容
  static Future deleteMeetingSpeaker(id) async {
    final db = await DatabaseHelper().database;
    await db.delete('meetingspeaker', where: 'meetingid = ?', whereArgs: [id]);
  }

  // 修改商务会议助手标题
  static Future editMeetingTitle(id, Map<String, Object?> meeting) async {
    final db = await DatabaseHelper().database;
    await db.update('meeting', meeting, where: 'id = ?', whereArgs: [id]);
  }

  // 删除商务会议助手
  static Future deleteMeeting(id) async {
    final db = await DatabaseHelper().database;
    await db.transaction((txn) async {
      await txn.delete('meeting', where: 'id = ?', whereArgs: [id]);
      await txn
          .delete('meetingdetails', where: 'meetingid = ?', whereArgs: [id]);
      await txn
          .delete('meetingspeaker', where: 'meetingid = ?', whereArgs: [id]);
    });
  }

  static String _getMeetingTemplateLanguageCode() {
    final locale = Get.locale ?? Get.deviceLocale;
    if (locale == null) {
      return 'en-US';
    }
    final code = locale.languageCode.toLowerCase();
    switch (code) {
      case 'zh':
        return 'zh-CN';
      case 'en':
        return 'en-US';
      case 'ja':
        return 'ja-JP';
      case 'ko':
        return 'ko-KR';
      case 'fr':
        return 'fr-FR';
      case 'de':
        return 'de-DE';
      case 'es':
        return 'es-ES';
      case 'it':
        return 'it-IT';
      case 'pt':
        return 'pt-BR';
      case 'ru':
        return 'ru-RU';
      case 'ar':
        return 'ar-SA';
      case 'hi':
        return 'hi-IN';
      default:
        return 'en-US';
    }
  }

  // 获取商务会议助手Ask AI列表
  static Future getMeetingAiList(int id) async {
    final db = await DatabaseHelper().database;
    return await db.query(
      'meetingai',
      where: 'meetingid = ?',
      whereArgs: [id],
      orderBy: 'id DESC',
    );
  }

  // 插入商务会议助手Ask AI
  static Future insertMeetingAi(Map<String, Object?> meeting) async {
    final db = await DatabaseHelper().database;
    await db.insert('meetingai', meeting);
  }

  // 初始化模版
  static Future initMeetingTemplate(List data) async {
    final db = await DatabaseHelper().database;
    await db.transaction((txn) async {
      // 清空旧数据
      await txn.delete('meetingtemplate');
      await txn.delete('meetingcategorytemplate');

      List categoryList = [];

      for (var i = 0; i < data.length; i++) {
        Map item = data[i];
        Map? result = categoryList.firstWhere(
          (category) => category['name'] == item['ttype'],
          orElse: () => null,
        );
        Map template = {
          "id": item['id'],
          'tid': item['tid'],
          'name': item['title'],
          'icon': item['icon'],
          'tag': item['tags'] ?? '',
          'desc': item['description'],
          'outline': item['outline'],
          'prompt': item['template'],
          'language': item['language'],
        };
        if (result != null) {
          result['templates'].add(template);
        } else {
          categoryList.add({
            'name': item['ttype'],
            'templates': [template],
            'language': item['language'],
          });
        }
      }

      final int customIndex =
          categoryList.indexWhere((e) => e['name'] == '自定义');
      if (customIndex != -1) {
        final customCategory = categoryList.removeAt(customIndex);
        categoryList.add(customCategory);
      } else {
        categoryList.add({
          'name': 'custom'.tr,
          'templates': [],
        });
      }

      for (var i = 0; i < categoryList.length; i++) {
        Map item = categoryList[i];
        int categoryId = i + 1;
        await txn.insert('meetingcategorytemplate', {
          'id': categoryId,
          'name': item['name'],
          'language': item['language'],
        });
        for (var j = 0; j < item['templates'].length; j++) {
          Map template = item['templates'][j];
          await txn.insert('meetingtemplate', {
            "id": template['id'],
            'tid': template['tid'],
            'categoryid': categoryId,
            'name': template['name'],
            'icon': template['icon'],
            'tag': template['tag'],
            'desc': template['desc'],
            'outline': template['outline'],
            'prompt': template['prompt'],
            'language': template['language'],
          });
        }
      }
    });
  }

  // 获取商务会议助手所有分类模版列表
  static Future getMeetingCategoryTemplateList() async {
    final language = _getMeetingTemplateLanguageCode();
    Logger.info('language: $language');
    final db = await DatabaseHelper().database;
    List categorytemplateList = await db.query(
      'meetingcategorytemplate',
      where: '(language = ? OR language IS NULL OR language = "")',
      whereArgs: [language],
    );
    Logger.info('categorytemplateList: $categorytemplateList');
    final dataList =
        categorytemplateList.map((item) => Map.from(item)).toList();
    for (var element in dataList) {
      final List templateList = await db.query(
        'meetingtemplate',
        limit: 4,
        where: 'categoryid = ? ',
        whereArgs: [element['id']],
        orderBy: 'id ${element['name'] == '自定义' ? 'DESC' : 'ASC'}',
      );
      element['template'] = templateList
          .map((item) => {
                ...Map.from(item),
                'tag': item['tag'].isNotEmpty ? item['tag'].split(',') : [],
              })
          .toList();
    }
    return dataList;
  }

  // 获取商务会议助手模版列表
  static Future getMeetingTemplateList(int id, {bool isCustom = false}) async {
    final language = _getMeetingTemplateLanguageCode();
    Logger.info('language: $language');
    final db = await DatabaseHelper().database;
    return await db.query(
      'meetingtemplate',
      where: 'categoryid = ? AND language = ?',
      whereArgs: [id, language],
      orderBy: 'id ${isCustom ? 'DESC' : 'ASC'}',
    );
  }

  // 插入商务会议助手模版
  static Future insertMeetingTemplate(Map<String, Object?> meeting) async {
    final db = await DatabaseHelper().database;
    await db.insert('meetingtemplate', meeting);
  }

  // 修改商务会议助手模版
  static Future editMeetingTemplate(id, Map<String, Object?> meeting) async {
    final db = await DatabaseHelper().database;
    await db
        .update('meetingtemplate', meeting, where: 'id = ?', whereArgs: [id]);
  }

  // 删除商务会议助手模版
  static Future deleteMeetingTemplate(id) async {
    final db = await DatabaseHelper().database;
    await db.delete('meetingtemplate', where: 'id = ?', whereArgs: [id]);
  }
}
