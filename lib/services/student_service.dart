import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student.dart';

class StudentService {
  StudentService._();

  static final instance = StudentService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<Student>> watchStudents() => _firestore
      .collection('students')
      .orderBy('fullName')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) => Student.fromMap(document.id, document.data()))
            .toList(),
      );

  Stream<List<Student>> watchOwnProfile(String userUid) => _firestore
      .collection('students')
      .where('userUid', isEqualTo: userUid)
      .limit(1)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) => Student.fromMap(document.id, document.data()))
            .toList(),
      );

  Future<void> addStudent(StudentInput input) async {
    await _validateUserLink(input.userUid);
    final timestamp = FieldValue.serverTimestamp();
    await _firestore.collection('students').add({
      'fullName': input.fullName,
      'email': input.email,
      'phone': input.phone,
      'dateOfBirth': input.dateOfBirth == null
          ? null
          : Timestamp.fromDate(input.dateOfBirth!),
      'gender': input.gender,
      'consultationNote': input.consultationNote,
      'status': input.status,
      'userUid': input.userUid,
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
  }

  Future<void> updateStudent(String studentId, StudentInput input) async {
    await _validateUserLink(input.userUid, excludedStudentId: studentId);
    await _firestore.collection('students').doc(studentId).update({
      'fullName': input.fullName,
      'email': input.email,
      'phone': input.phone,
      'dateOfBirth': input.dateOfBirth == null
          ? null
          : Timestamp.fromDate(input.dateOfBirth!),
      'gender': input.gender,
      'consultationNote': input.consultationNote,
      'status': input.status,
      'userUid': input.userUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _validateUserLink(
    String? userUid, {
    String? excludedStudentId,
  }) async {
    if (userUid == null) return;
    final results = await Future.wait([
      _firestore.collection('users').doc(userUid).get(),
      _firestore
          .collection('students')
          .where('userUid', isEqualTo: userUid)
          .limit(2)
          .get(),
    ]);
    final user = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    if (!user.exists || user.data()?['role'] != 'student') {
      throw StateError(
        'UID liên kết phải thuộc một tài khoản Student đã tồn tại.',
      );
    }
    final linked = results[1] as QuerySnapshot<Map<String, dynamic>>;
    if (StudentLinkPolicy.hasDuplicate(
      linked.docs.map((document) => document.id),
      excludedStudentId: excludedStudentId,
    )) {
      throw StateError('Tài khoản này đã liên kết với hồ sơ học viên khác.');
    }
  }
}
