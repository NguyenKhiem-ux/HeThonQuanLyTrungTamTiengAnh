import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/attendance_record.dart';
import '../models/attendance_session.dart';
import '../models/english_class.dart';
import '../models/enrollment.dart';
import '../models/student.dart';
import '../models/teacher_assignment.dart';
import 'enrollment_service.dart';

class AttendanceService {
  AttendanceService._();

  static final instance = AttendanceService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<Student>> watchActiveStudents(String classId) =>
      EnrollmentService.instance.watchActiveStudentsForClass(classId);

  Stream<List<AttendanceSession>> watchSessions(String classId) => _firestore
      .collection('attendance_sessions')
      .where('classId', isEqualTo: classId)
      .snapshots()
      .map((snapshot) {
        final sessions = snapshot.docs
            .map(
              (document) =>
                  AttendanceSession.fromMap(document.id, document.data()),
            )
            .toList();
        sessions.sort((a, b) => b.dateKey.compareTo(a.dateKey));
        return sessions;
      });

  Stream<List<AttendanceRecord>> watchRecordsForSession({
    required String classId,
    required String sessionId,
  }) => _firestore
      .collection('attendance_records')
      .where('classId', isEqualTo: classId)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (document) =>
                  AttendanceRecord.fromMap(document.id, document.data()),
            )
            .where((record) => record.sessionId == sessionId)
            .toList(),
      );

  Stream<List<AttendanceRecord>> watchRecordsForStudent(String studentId) =>
      _firestore
          .collection('attendance_records')
          .where('studentId', isEqualTo: studentId)
          .snapshots()
          .map((snapshot) {
            final records = snapshot.docs
                .map(
                  (document) =>
                      AttendanceRecord.fromMap(document.id, document.data()),
                )
                .toList();
            records.sort(
              (a, b) => (b.dateKey ?? '').compareTo(a.dateKey ?? ''),
            );
            return records;
          });

  Future<void> saveAttendance({
    required String classId,
    required DateTime date,
    required Map<String, String> statusesByStudent,
  }) async {
    final userUid = FirebaseAuth.instance.currentUser?.uid;
    if (userUid == null) throw StateError('Phiên đăng nhập không còn hợp lệ.');
    if (statusesByStudent.isEmpty) {
      throw StateError('Hãy đánh dấu ít nhất một học viên trước khi lưu.');
    }
    if (statusesByStudent.values.any(
      (status) => !AttendanceRecord.validStatuses.contains(status),
    )) {
      throw StateError('Trạng thái điểm danh không hợp lệ.');
    }

    final assignmentFuture = _firestore
        .collection('teacher_assignments')
        .doc(classId)
        .get();
    final classFuture = _firestore.collection('classes').doc(classId).get();
    final enrollmentFuture = _firestore
        .collection('enrollments')
        .where('classId', isEqualTo: classId)
        .get();
    final assignmentDocument = await assignmentFuture;
    final classDocument = await classFuture;
    final enrollmentSnapshot = await enrollmentFuture;
    if (!assignmentDocument.exists || !classDocument.exists) {
      throw StateError('Phân công hoặc lớp học không còn tồn tại.');
    }
    final assignment = TeacherAssignment.fromMap(
      assignmentDocument.id,
      assignmentDocument.data()!,
    );
    final englishClass = EnglishClass.fromMap(
      classDocument.id,
      classDocument.data()!,
    );
    if (!AttendancePolicy.canManageClass(
      isAssignedTeacher: assignment.teacherUid == userUid,
      classStatus: englishClass.status,
    )) {
      throw StateError('Chỉ giáo viên phụ trách được điểm danh lớp đang học.');
    }

    final activeStudentIds = enrollmentSnapshot.docs
        .map((document) => Enrollment.fromMap(document.id, document.data()))
        .where((enrollment) => enrollment.isActive)
        .map((enrollment) => enrollment.studentId)
        .toSet();
    if (statusesByStudent.keys.any(
      (studentId) => !AttendancePolicy.canRecordStudent(
        hasActiveEnrollment: activeStudentIds.contains(studentId),
      ),
    )) {
      throw StateError('Chỉ được điểm danh học viên đang đăng ký lớp.');
    }

    final dateKey = AttendanceSession.dateKeyFromDate(date);
    final sessionId = AttendanceSession.documentId(classId, dateKey);
    final sessionReference = _firestore
        .collection('attendance_sessions')
        .doc(sessionId);
    // A missing document has no resource.classId for Rules to authorize.
    final sessionSnapshot = await _firestore
        .collection('attendance_sessions')
        .where('classId', isEqualTo: classId)
        .get();
    final sessionExists = sessionSnapshot.docs.any(
      (document) => document.id == sessionId,
    );
    final timestamp = FieldValue.serverTimestamp();
    // shortcut: batch lớn có thể chạm giới hạn 20 document-access calls của Rules; chuyển sang backend khi lớp thường xuyên lưu nhiều học viên cùng lúc.
    final batch = _firestore.batch();
    if (sessionExists) {
      batch.update(sessionReference, {'updatedAt': timestamp});
    } else {
      batch.set(sessionReference, {
        'classId': classId,
        'dateKey': dateKey,
        'createdByUid': userUid,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      });
    }
    for (final entry in statusesByStudent.entries) {
      final recordId = AttendanceRecord.documentId(sessionId, entry.key);
      batch.set(_firestore.collection('attendance_records').doc(recordId), {
        'sessionId': sessionId,
        'classId': classId,
        'studentId': entry.key,
        'status': entry.value,
        'updatedAt': timestamp,
      });
    }
    await batch.commit();
  }
}
