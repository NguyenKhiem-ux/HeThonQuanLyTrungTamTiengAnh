class Enrollment {
  const Enrollment({
    required this.id,
    required this.studentId,
    required this.classId,
    required this.status,
  });

  static const validStatuses = {'active', 'cancelled'};

  final String id;
  final String studentId;
  final String classId;
  final String status;

  bool get isActive => status == 'active';
  bool get canCancel => isActive;
  String get statusLabel => isActive ? 'Đang đăng ký' : 'Đã hủy';

  static String documentId(String classId, String studentId) =>
      '${classId}_$studentId';

  factory Enrollment.fromMap(String id, Map<String, dynamic> data) {
    final studentId = data['studentId'];
    final classId = data['classId'];
    final status = data['status'];
    if (studentId is! String ||
        studentId.trim().isEmpty ||
        classId is! String ||
        classId.trim().isEmpty ||
        status is! String ||
        !validStatuses.contains(status)) {
      throw const FormatException('Dữ liệu đăng ký học không hợp lệ.');
    }
    return Enrollment(
      id: id,
      studentId: studentId.trim(),
      classId: classId.trim(),
      status: status,
    );
  }
}

class EnrollmentPolicy {
  const EnrollmentPolicy._();

  static String? registrationError({
    required bool studentActive,
    required String classStatus,
    required int activeCount,
    required int maxStudents,
    required bool alreadyActive,
  }) {
    if (!studentActive) return 'Học viên không hoạt động.';
    if (classStatus != 'pending') return 'Chỉ đăng ký vào lớp chờ mở.';
    if (alreadyActive) return 'Học viên đã đăng ký lớp này.';
    if (activeCount >= maxStudents) return 'Lớp đã đủ sĩ số.';
    return null;
  }

  static bool canReduceCapacity({
    required int newMaxStudents,
    required int activeCount,
  }) => newMaxStudents >= activeCount;

  static bool canDeleteClass({
    required bool classPending,
    required bool hasRoomAllocations,
    required bool hasActiveEnrollments,
  }) => classPending && !hasRoomAllocations && !hasActiveEnrollments;
}
