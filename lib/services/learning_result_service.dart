import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/course.dart';
import '../models/english_class.dart';
import '../models/enrollment.dart';
import '../models/learning_result.dart';
import '../models/teacher_assignment.dart';

class LearningResultService {
  LearningResultService._();

  static final instance = LearningResultService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<LearningResult>> watchResultsForClass(String classId) =>
      _firestore
          .collection('learning_results')
          .where('classId', isEqualTo: classId)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (document) =>
                      LearningResult.fromMap(document.id, document.data()),
                )
                .toList(),
          );

  Stream<List<LearningResult>> watchResultsForStudent(String studentId) =>
      _firestore
          .collection('learning_results')
          .where('studentId', isEqualTo: studentId)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (document) =>
                      LearningResult.fromMap(document.id, document.data()),
                )
                .toList(),
          );

  Future<void> saveResults({
    required String classId,
    required List<LearningResultInput> inputs,
  }) async {
    final userUid = FirebaseAuth.instance.currentUser?.uid;
    if (userUid == null) throw StateError('Phiên đăng nhập không còn hợp lệ.');
    if (inputs.isEmpty) throw StateError('Lớp chưa có học viên để lưu.');
    if (inputs.map((input) => input.studentId).toSet().length !=
            inputs.length ||
        inputs.any(
          (input) =>
              input.studentId.isEmpty ||
              !LearningResult.isValidScore(input.midtermScore) ||
              !LearningResult.isValidScore(input.finalScore) ||
              input.comment.length > 1000,
        )) {
      throw StateError('Dữ liệu điểm hoặc nhận xét không hợp lệ.');
    }

    final assignmentDocument = await _firestore
        .collection('teacher_assignments')
        .doc(classId)
        .get();
    if (!assignmentDocument.exists) {
      throw StateError('Lớp chưa được phân công giáo viên.');
    }
    final assignment = TeacherAssignment.fromMap(
      assignmentDocument.id,
      assignmentDocument.data()!,
    );
    if (assignment.teacherUid != userUid) {
      throw StateError('Bạn không phải giáo viên phụ trách lớp này.');
    }
    final enrollmentSnapshot = await _firestore
        .collection('enrollments')
        .where('classId', isEqualTo: classId)
        .get();
    final activeStudentIds = enrollmentSnapshot.docs
        .map((document) => Enrollment.fromMap(document.id, document.data()))
        .where((enrollment) => enrollment.isActive)
        .map((enrollment) => enrollment.studentId)
        .toSet();
    if (inputs.any(
      (input) => !LearningResultPolicy.canTeacherManage(
        isAssignedTeacher: true,
        hasActiveEnrollment: activeStudentIds.contains(input.studentId),
      ),
    )) {
      throw StateError('Chỉ được lưu kết quả của học viên đang đăng ký lớp.');
    }

    // shortcut: batch lớn có thể chạm giới hạn 20 document-access calls của Rules; chuyển sang backend khi lớp thường xuyên lưu nhiều học viên cùng lúc.
    final batch = _firestore.batch();
    final timestamp = FieldValue.serverTimestamp();
    for (final input in inputs) {
      final resultId = LearningResult.documentId(classId, input.studentId);
      batch.set(_firestore.collection('learning_results').doc(resultId), {
        'classId': classId,
        'studentId': input.studentId,
        'midtermScore': input.midtermScore,
        'finalScore': input.finalScore,
        'comment': input.comment,
        'updatedAt': timestamp,
      });
    }
    await batch.commit();
  }

  Future<EnglishClass> getClass(String classId) async {
    final document = await _firestore.collection('classes').doc(classId).get();
    if (!document.exists) throw StateError('Lớp học không còn tồn tại.');
    return EnglishClass.fromMap(document.id, document.data()!);
  }

  Future<Course> getCourse(String courseId) async {
    final document = await _firestore.collection('courses').doc(courseId).get();
    if (!document.exists) throw StateError('Khóa học không còn tồn tại.');
    return Course.fromMap(document.id, document.data()!);
  }
}
