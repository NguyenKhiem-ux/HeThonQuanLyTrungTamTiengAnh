import 'package:cloud_firestore/cloud_firestore.dart';

class ClassRegistrationRequest {
  const ClassRegistrationRequest({
    required this.id,
    required this.studentId,
    required this.studentUid,
    required this.requestedClassId,
    required this.assignedClassId,
    required this.status,
    required this.createdAt,
  });

  static const validStatuses = {
    'pending',
    'awaiting_student_confirmation',
    'student_confirmed',
    'approved',
    'rejected',
  };

  final String id;
  final String studentId;
  final String studentUid;
  final String requestedClassId;
  final String? assignedClassId;
  final String status;
  final DateTime? createdAt;

  bool get isOpen => const {
    'pending',
    'awaiting_student_confirmation',
    'student_confirmed',
  }.contains(status);
  bool get needsStudentConfirmation =>
      status == 'awaiting_student_confirmation';
  String get targetClassId => assignedClassId ?? requestedClassId;
  String get statusLabel => switch (status) {
    'pending' => 'Chờ tư vấn viên xác nhận',
    'awaiting_student_confirmation' => 'Chờ bạn xác nhận lớp thay thế',
    'student_confirmed' => 'Đã xác nhận, chờ tư vấn viên xếp lớp',
    'approved' => 'Đã xếp lớp',
    'rejected' => 'Đã từ chối',
    _ => status,
  };

  factory ClassRegistrationRequest.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    final studentId = data['studentId'];
    final studentUid = data['studentUid'];
    final requestedClassId = data['requestedClassId'];
    final assignedClassId = data['assignedClassId'];
    final status = data['status'];
    final createdAt = data['createdAt'];
    if (studentId is! String ||
        studentId.isEmpty ||
        studentUid is! String ||
        studentUid.isEmpty ||
        requestedClassId is! String ||
        requestedClassId.isEmpty ||
        (assignedClassId != null &&
            (assignedClassId is! String || assignedClassId.isEmpty)) ||
        status is! String ||
        !validStatuses.contains(status) ||
        (createdAt != null && createdAt is! Timestamp)) {
      throw const FormatException('Dữ liệu yêu cầu đăng ký không hợp lệ.');
    }
    return ClassRegistrationRequest(
      id: id,
      studentId: studentId,
      studentUid: studentUid,
      requestedClassId: requestedClassId,
      assignedClassId: assignedClassId as String?,
      status: status,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
    );
  }
}

class ClassRegistrationPolicy {
  const ClassRegistrationPolicy._();

  static int remainingSlots({
    required int maxStudents,
    required int activeEnrollments,
  }) => (maxStudents - activeEnrollments).clamp(0, maxStudents);

  static String? requestError({
    required bool studentActive,
    required String classStatus,
    required bool hasSchedule,
    required int? remainingSlots,
    required bool hasOpenRequest,
  }) {
    if (!studentActive) return 'Hồ sơ học viên không hoạt động.';
    if (classStatus != 'pending') return 'Lớp không còn nhận đăng ký.';
    if (!hasSchedule) return 'Lớp chưa thiết lập lịch học và ca học.';
    if (remainingSlots != null && remainingSlots <= 0) {
      return 'Lớp đã đủ sĩ số.';
    }
    if (hasOpenRequest) return 'Bạn đang có một yêu cầu chờ xử lý.';
    return null;
  }
}
