class MeetingDetailsModel {
  MeetingDetailsModel();

  int id = 0;
  int meetingid = 0;
  String address = '';
  String personnel = '';
  String taskid = '';
  int tasktype = 0;
  String overview = '';
  String summary = '';
  String mindmap = '';

  factory MeetingDetailsModel.fromJson(Map<String, dynamic> map) {
    int asInt(dynamic v) => v is int
        ? v
        : (v is num
            ? v.toInt()
            : (v is String ? int.tryParse(v) ?? 0 : 0));
    String asStr(dynamic v) => v?.toString() ?? '';
    return MeetingDetailsModel()
      ..id = asInt(map["id"])
      ..meetingid = asInt(map["meetingid"])
      ..address = asStr(map["address"])
      ..personnel = asStr(map["personnel"])
      ..taskid = asStr(map["taskid"])
      ..tasktype = asInt(map["tasktype"])
      ..overview = asStr(map["overview"])
      ..summary = asStr(map["summary"])
      ..mindmap = asStr(map["mindmap"]);
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['id'] = id;
    data['meetingid'] = meetingid;
    data['address'] = address;
    data['personnel'] = personnel;
    data['taskid'] = taskid;
    data['tasktype'] = tasktype;
    data['overview'] = overview;
    data['summary'] = summary;
    data['mindmap'] = mindmap;
    return data;
  }
}
