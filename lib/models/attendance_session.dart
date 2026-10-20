class AttendanceSession {
  const AttendanceSession({
    required this.id,
    required this.classId,
    required this.dateKey,
    required this.createdByUid,
  });

  final String id;
  final String classId;
  final String dateKey;
  final String createdByUid;

  static String dateKeyFromDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String documentId(String classId, String dateKey) =>
      '${classId}_${dateKey.replaceAll('-', '')}';

  static DateTime? dateFromKey(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    final date = DateTime(year, month, day);
    return dateKeyFromDate(date) == dateKey ? date : null;
  }

  factory AttendanceSession.fromMap(String id, Map<String, dynamic> data) {
    final classId = data['classId'];
    final dateKey = data['dateKey'];
    final createdByUid = data['createdByUid'];
    if (classId is! String ||
        classId.trim().isEmpty ||
        dateKey is! String ||
        dateFromKey(dateKey) == null ||
        id != documentId(classId, dateKey) ||
        createdByUid is! String ||
        createdByUid.trim().isEmpty) {
      throw const FormatException('Dữ liệu phiên điểm danh không hợp lệ.');
    }
    return AttendanceSession(
      id: id,
      classId: classId.trim(),
      dateKey: dateKey,
      createdByUid: createdByUid.trim(),
    );
  }
}

class AttendancePolicy {
  const AttendancePolicy._();

  static bool canManageClass({
    required bool isAssignedTeacher,
    required String classStatus,
  }) => isAssignedTeacher && classStatus == 'ongoing';

  static bool canRecordStudent({required bool hasActiveEnrollment}) =>
      hasActiveEnrollment;
}
