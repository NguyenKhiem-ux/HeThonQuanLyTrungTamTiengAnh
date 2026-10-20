import 'room_allocation.dart';

class TeacherAssignment {
  const TeacherAssignment({
    required this.classId,
    required this.teacherId,
    required this.teacherUid,
  });

  final String classId;
  final String teacherId;
  final String teacherUid;

  static String documentId(String classId) => classId;

  factory TeacherAssignment.fromMap(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final classId = data['classId'];
    final teacherId = data['teacherId'];
    final teacherUid = data['teacherUid'];
    if (classId is! String ||
        classId.trim().isEmpty ||
        classId != documentId ||
        teacherId is! String ||
        teacherId.trim().isEmpty ||
        teacherUid is! String ||
        teacherUid.trim().isEmpty) {
      throw const FormatException('Dữ liệu phân công giảng dạy không hợp lệ.');
    }
    return TeacherAssignment(
      classId: classId,
      teacherId: teacherId.trim(),
      teacherUid: teacherUid.trim(),
    );
  }
}

class TeacherAssignmentPolicy {
  const TeacherAssignmentPolicy._();

  static String? assignmentError({
    required bool teacherActive,
    required bool teacherLinked,
    required bool linkedUserActive,
    required String classStatus,
  }) {
    if (!teacherActive) return 'Giáo viên đã ngừng hoạt động.';
    if (!teacherLinked) return 'Giáo viên chưa liên kết tài khoản.';
    if (!linkedUserActive) {
      return 'Tài khoản giáo viên không tồn tại hoặc chưa hoạt động.';
    }
    if (classStatus == 'completed') {
      return 'Không thể phân công cho lớp đã kết thúc.';
    }
    return null;
  }

  static bool canManage({required bool isAdmin}) => isAdmin;

  static bool schedulesOverlap(
    Iterable<RoomAllocation> first,
    Iterable<RoomAllocation> second,
  ) {
    for (final left in first) {
      for (final right in second) {
        if (left.weekday == right.weekday &&
            timeRangesOverlap(
              left.startMinute,
              left.endMinute,
              right.startMinute,
              right.endMinute,
            )) {
          return true;
        }
      }
    }
    return false;
  }
}
