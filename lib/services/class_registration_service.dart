import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/class_registration_request.dart';
import '../models/english_class.dart';
import '../models/enrollment.dart';
import '../models/student.dart';

class ClassRegistrationService {
  ClassRegistrationService._();

  static final instance = ClassRegistrationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<ClassRegistrationRequest>> watchRequests() => _firestore
      .collection('class_registration_requests')
      .snapshots()
      .map(_mapRequests);

  Stream<List<ClassRegistrationRequest>> watchRequestsForStudent(
    String studentUid,
  ) => _firestore
      .collection('class_registration_requests')
      .where('studentUid', isEqualTo: studentUid)
      .snapshots()
      .map(_mapRequests);

  List<ClassRegistrationRequest> _mapRequests(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final requests = snapshot.docs
        .map(
          (document) =>
              ClassRegistrationRequest.fromMap(document.id, document.data()),
        )
        .toList();
    requests.sort(
      (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
        a.createdAt ?? DateTime(1970),
      ),
    );
    return requests;
  }

  Future<void> submit({
    required Student student,
    required String studentUid,
    required EnglishClass englishClass,
  }) async {
    final results = await Future.wait([
      _firestore
          .collection('class_registration_requests')
          .where('studentUid', isEqualTo: studentUid)
          .get(),
      _firestore
          .collection('enrollments')
          .where('studentId', isEqualTo: student.id)
          .get(),
    ]);
    final currentRequests = results[0];
    final ownEnrollments = results[1];
    final alreadyEnrolled = ownEnrollments.docs.any((document) {
      final data = document.data();
      return data['classId'] == englishClass.id && data['status'] == 'active';
    });
    if (alreadyEnrolled) {
      throw StateError('Bạn đã được xếp vào lớp này.');
    }
    final hasOpenRequest = currentRequests.docs.any((document) {
      final status = document.data()['status'];
      return const {
        'pending',
        'awaiting_student_confirmation',
        'student_confirmed',
      }.contains(status);
    });
    final error = ClassRegistrationPolicy.requestError(
      studentActive: student.isActive,
      classStatus: englishClass.status,
      hasSchedule: englishClass.hasConfiguredSchedule,
      remainingSlots: null,
      hasOpenRequest: hasOpenRequest,
    );
    if (error != null) throw StateError(error);

    // shortcut: kiểm tra sức chứa khi tư vấn viên duyệt để không lộ enrollment của học viên khác.
    final timestamp = FieldValue.serverTimestamp();
    await _firestore.collection('class_registration_requests').add({
      'studentId': student.id,
      'studentUid': studentUid,
      'requestedClassId': englishClass.id,
      'assignedClassId': null,
      'status': 'pending',
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
  }

  Future<void> proposeAlternative(
    ClassRegistrationRequest request,
    EnglishClass alternativeClass,
  ) async {
    if (request.status != 'pending') {
      throw StateError('Yêu cầu không còn ở trạng thái chờ xét duyệt.');
    }
    await _validateAvailableClass(alternativeClass);
    await _firestore
        .collection('class_registration_requests')
        .doc(request.id)
        .update({
          'assignedClassId': alternativeClass.id,
          'status': 'awaiting_student_confirmation',
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> confirmAlternative(ClassRegistrationRequest request) async {
    if (!request.needsStudentConfirmation || request.assignedClassId == null) {
      throw StateError('Yêu cầu này không chờ học viên xác nhận.');
    }
    await _firestore
        .collection('class_registration_requests')
        .doc(request.id)
        .update({
          'status': 'student_confirmed',
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> reject(
    ClassRegistrationRequest request, {
    required bool byStudent,
  }) async {
    if (byStudent && !request.needsStudentConfirmation) {
      throw StateError('Yêu cầu này không chờ học viên phản hồi.');
    }
    await _firestore
        .collection('class_registration_requests')
        .doc(request.id)
        .update({
          'status': 'rejected',
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> approve(
    ClassRegistrationRequest request,
    EnglishClass targetClass,
  ) async {
    final canApproveRequested =
        request.status == 'pending' &&
        targetClass.id == request.requestedClassId &&
        request.assignedClassId == null;
    final canApproveConfirmed =
        request.status == 'student_confirmed' &&
        targetClass.id == request.assignedClassId;
    if (!canApproveRequested && !canApproveConfirmed) {
      throw StateError(
        'Lớp thay thế phải được học viên xác nhận trước khi xếp lớp.',
      );
    }
    await _validateAvailableClass(targetClass);

    final requestReference = _firestore
        .collection('class_registration_requests')
        .doc(request.id);
    final enrollmentReference = _firestore
        .collection('enrollments')
        .doc(Enrollment.documentId(targetClass.id, request.studentId));
    await _firestore.runTransaction((transaction) async {
      final documents = await Future.wait([
        transaction.get(requestReference),
        transaction.get(enrollmentReference),
      ]);
      final currentRequest = ClassRegistrationRequest.fromMap(
        documents[0].id,
        documents[0].data()!,
      );
      final stillApprovable =
          (currentRequest.status == 'pending' &&
              currentRequest.requestedClassId == targetClass.id &&
              currentRequest.assignedClassId == null) ||
          (currentRequest.status == 'student_confirmed' &&
              currentRequest.assignedClassId == targetClass.id);
      if (!stillApprovable) {
        throw StateError('Yêu cầu đã thay đổi, vui lòng tải lại danh sách.');
      }
      if (documents[1].data()?['status'] == 'active') {
        throw StateError('Học viên đã được xếp vào lớp này.');
      }

      final timestamp = FieldValue.serverTimestamp();
      transaction.set(enrollmentReference, {
        'studentId': request.studentId,
        'classId': targetClass.id,
        'status': 'active',
        'enrolledAt': timestamp,
        'updatedAt': timestamp,
      });
      transaction.update(requestReference, {
        'status': 'approved',
        'updatedAt': timestamp,
      });
    });
  }

  Future<void> _validateAvailableClass(EnglishClass englishClass) async {
    final activeEnrollments = await _activeEnrollmentsForClass(englishClass.id);
    final error = ClassRegistrationPolicy.requestError(
      studentActive: true,
      classStatus: englishClass.status,
      hasSchedule: englishClass.hasConfiguredSchedule,
      remainingSlots: ClassRegistrationPolicy.remainingSlots(
        maxStudents: englishClass.maxStudents,
        activeEnrollments: activeEnrollments.docs.length,
      ),
      hasOpenRequest: false,
    );
    if (error != null) throw StateError(error);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _activeEnrollmentsForClass(
    String classId,
  ) => _firestore
      .collection('enrollments')
      .where('classId', isEqualTo: classId)
      .where('status', isEqualTo: 'active')
      .get();
}
