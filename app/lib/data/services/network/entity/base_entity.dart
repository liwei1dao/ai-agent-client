import 'entity_factory.dart';

class BaseEntity<T> {
  int? code;
  String? message;
  T? data;

  BaseEntity({this.code, this.message, this.data});

  factory BaseEntity.fromJson(json) {
    return BaseEntity(
      code: json["code"],
      message: json["msg"],
      data: EntityFactory.generateOBJ<T>(json["data"]),
    );
  }
}
