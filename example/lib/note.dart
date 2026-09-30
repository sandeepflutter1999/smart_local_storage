/// Plain model class — no annotations, no codegen, no base class to extend.
/// You just write toMap()/fromMap() yourself.
class Note {
  Note({this.id, required this.title, required this.detail});

  final String? id;
  final String title;
  final String detail;

  Map<String, dynamic> toMap() => {'title': title, 'detail': detail};

  static Note fromMap(Map<String, dynamic> map) => Note(
        id: map['id'] as String?,
        title: map['title'] as String,
        detail: map['detail'] as String,
      );

  Note copyWith({String? title, String? detail}) => Note(
        id: id,
        title: title ?? this.title,
        detail: detail ?? this.detail,
      );
}
