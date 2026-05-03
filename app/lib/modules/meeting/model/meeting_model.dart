class MeetingModel {
  MeetingModel();

  int id = 0;
  String title = '';
  String type = '';
  int seconds = 0;
  String filepath = '';
  String audiourl = '';
  int tasktype = 0;
  int creationtime = 0;

  factory MeetingModel.fromJson(Map<String, dynamic> map) {
    int asInt(dynamic v) =>
        v is int ? v : (v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0));
    String asStr(dynamic v) => v?.toString() ?? '';
    return MeetingModel()
      ..id = asInt(map["id"])
      ..title = asStr(map["title"])
      ..type = asStr(map["type"])
      ..seconds = asInt(map["seconds"])
      ..filepath = asStr(map["filepath"])
      ..audiourl = asStr(map["audiourl"])
      ..tasktype = asInt(map["tasktype"])
      ..creationtime = asInt(map["creationtime"]);
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['title'] = title;
    data['type'] = type;
    data['seconds'] = seconds;
    data['filepath'] = filepath;
    data['audiourl'] = audiourl;
    data['tasktype'] = tasktype;
    data['creationtime'] = creationtime;
    return data;
  }
}
