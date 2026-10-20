class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.sessionId,
    required this.classId,
    required this.studentId,
    required this.status,
  });

  static const validStatuses = {'present', 'absent', 'excused'};

  final String id;
  final String sessionId;
  final String classId;
  final String studentId;
  final String status;

  String get statusLabel => switch (status) {
    'present' => 'Có mặt',
    'absent' => 'Vắng mặt',
    'excused' => 'Vắng có phép',
    _ => status,
  };

  static String documentId(String sessionId, String studentId) =>
      '${sessionId}_$studentId';

  String? get dateKey {
    final match = RegExp(
      r'([0-9]{4})([0-9]{2})([0-9]{2})$',
    ).firstMatch(sessionId);
    if (match == null) return null;
    return '${match.group(1)}-${match.group(2)}-${match.group(3)}';
  }

  factory AttendanceRecord.fromMap(String id, Map<String, dynamic> data) {
    final sessionId = data['sessionId'];
    final classId = data['classId'];
    final studentId = data['studentId'];
    final status = data['status'];
    if (sessionId is! String ||
        sessionId.trim().isEmpty ||
        classId is! String ||
        classId.trim().isEmpty ||
        studentId is! String ||
        studentId.trim().isEmpty ||
        id != documentId(sessionId, studentId) ||
        status is! String ||
        !validStatuses.contains(status)) {
      throw const FormatException('Dữ liệu điểm danh không hợp lệ.');
    }
    return AttendanceRecord(
      id: id,
      sessionId: sessionId.trim(),
      classId: classId.trim(),
      studentId: studentId.trim(),
      status: status,
    );
  }
}

class AttendanceStats {
  const AttendanceStats({
    required this.present,
    required this.absent,
    required this.excused,
  });

  final int present;
  final int absent;
  final int excused;

  int get total => present + absent + excused;

  factory AttendanceStats.fromRecords(Iterable<AttendanceRecord> records) {
    var present = 0;
    var absent = 0;
    var excused = 0;
    for (final record in records) {
      if (record.status == 'present') present++;
      if (record.status == 'absent') absent++;
      if (record.status == 'excused') excused++;
    }
    return AttendanceStats(present: present, absent: absent, excused: excused);
  }
}
