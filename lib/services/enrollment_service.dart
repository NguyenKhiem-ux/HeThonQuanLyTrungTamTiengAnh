import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/english_class.dart';
import '../models/enrollment.dart';
import '../models/student.dart';

class EnrollmentService {
  EnrollmentService._();

  static final instance = EnrollmentService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<Enrollment>> watchEnrollments() =>
      _firestore.collection('enrollments').snapshots().map((snapshot) {
        final enrollments = snapshot.docs
            .map((document) => Enrollment.fromMap(document.id, document.data()))
            .toList();
        enrollments.sort((a, b) {
          final classComparison = a.classId.compareTo(b.classId);
          return classComparison != 0
              ? classComparison
              : a.studentId.compareTo(b.studentId);
        });
        return enrollments;
      });

  Stream<List<Enrollment>> watchEnrollmentsForStudent(String studentId) =>
      _firestore
          .collection('enrollments')
          .where('studentId', isEqualTo: studentId)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (document) =>
                      Enrollment.fromMap(document.id, document.data()),
                )
                .toList(),
          );

  Stream<List<Student>> watchActiveStudentsForClass(String classId) =>
      _firestore
          .collection('enrollments')
          .where('classId', isEqualTo: classId)
          .snapshots()
          .asyncMap((snapshot) async {
            final activeEnrollments = snapshot.docs
                .map(
                  (document) =>
                      Enrollment.fromMap(document.id, document.data()),
                )
                .where((enrollment) => enrollment.isActive)
                .toList();
            final students = await Future.wait(
              activeEnrollments.map((enrollment) async {
                final document = await _firestore
                    .collection('students')
                    .doc(enrollment.studentId)
                    .get();
                if (!document.exists) {
                  throw StateError('Học viên đăng ký không còn tồn tại.');
                }
                return Student.fromMap(document.id, document.data()!);
              }),
            );
            students.sort((a, b) => a.fullName.compareTo(b.fullName));
            return students;
          });

  Future<void> register({
    required String studentId,
    required String courseId,
    required String classId,
  }) async {
    final studentDocument = await _firestore
        .collection('students')
        .doc(studentId)
        .get();
    final courseDocument = await _firestore
        .collection('courses')
        .doc(courseId)
        .get();
    final classDocument = await _firestore
        .collection('classes')
        .doc(classId)
        .get();
    if (!studentDocument.exists ||
        !courseDocument.exists ||
        !classDocument.exists) {
      throw StateError('Học viên, khóa học hoặc lớp học không còn tồn tại.');
    }

    final student = Student.fromMap(studentId, studentDocument.data()!);
    final englishClass = EnglishClass.fromMap(classId, classDocument.data()!);
    if (englishClass.courseId != courseId) {
      throw StateError('Lớp học không thuộc khóa học đã chọn.');
    }

    final enrollmentId = Enrollment.documentId(classId, studentId);
    final enrollmentReference = _firestore
        .collection('enrollments')
        .doc(enrollmentId);
    final currentEnrollment = await enrollmentReference.get();
    final activeEnrollments = await _firestore
        .collection('enrollments')
        .where('classId', isEqualTo: classId)
        .where('status', isEqualTo: 'active')
        .get();
    final error = EnrollmentPolicy.registrationError(
      studentActive: student.isActive,
      classStatus: englishClass.status,
      activeCount: activeEnrollments.docs.length,
      maxStudents: englishClass.maxStudents,
      alreadyActive: currentEnrollment.data()?['status'] == 'active',
    );
    if (error != null) throw StateError(error);

    // shortcut: đếm sĩ số phía client có thể race, chuyển sang backend nguyên tử khi có nhiều tiến trình ghi.
    final timestamp = FieldValue.serverTimestamp();
    if (currentEnrollment.exists) {
      await enrollmentReference.update({
        'status': 'active',
        'enrolledAt': timestamp,
        'updatedAt': timestamp,
      });
    } else {
      await enrollmentReference.set({
        'studentId': studentId,
        'classId': classId,
        'status': 'active',
        'enrolledAt': timestamp,
        'updatedAt': timestamp,
      });
    }
  }

  Future<void> cancel(Enrollment enrollment) async {
    if (!enrollment.canCancel) {
      throw StateError('Đăng ký này đã được hủy.');
    }
    await _firestore.collection('enrollments').doc(enrollment.id).update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
