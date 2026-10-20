import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/english_class.dart';
import '../models/enrollment.dart';
import 'firestore_stream.dart';

class ClassService {
  ClassService._();

  static final instance = ClassService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<EnglishClass>> watchClasses() => _firestore
      .collection('classes')
      .orderBy('name')
      .snapshots()
      .withInitialSnapshotTimeout()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (document) => EnglishClass.fromMap(document.id, document.data()),
            )
            .toList(),
      );

  Future<void> addClass(EnglishClassInput input) async {
    final timestamp = FieldValue.serverTimestamp();
    await _firestore.collection('classes').add({
      'name': input.name,
      'courseId': input.courseId,
      'minStudents': input.minStudents,
      'maxStudents': input.maxStudents,
      'studyPattern': input.studyPattern,
      'shiftCode': input.shiftCode,
      'status': 'pending',
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
  }

  Future<void> updateClass(
    EnglishClass englishClass,
    EnglishClassInput input,
  ) async {
    if (!englishClass.canEdit) {
      throw StateError('Lớp đã kết thúc không thể chỉnh sửa.');
    }
    if (!EnglishClass.isValidStatusTransition(
      englishClass.status,
      input.status,
    )) {
      throw StateError('Chuyển trạng thái lớp học không hợp lệ.');
    }
    if (englishClass.status != 'pending' &&
        englishClass.courseId != input.courseId) {
      throw StateError('Chỉ lớp chờ mở mới được đổi khóa học.');
    }
    if (!englishClass.canChangeScheduleTo(
      input.studyPattern,
      input.shiftCode,
    )) {
      throw StateError(
        'Không thể thay đổi lịch học hoặc ca học của lớp đang học.',
      );
    }
    final scheduleChanged =
        englishClass.studyPattern != input.studyPattern ||
        englishClass.shiftCode != input.shiftCode;
    if (scheduleChanged) {
      final allocations = await _firestore
          .collection('room_allocations')
          .where('classId', isEqualTo: englishClass.id)
          .get();
      final hasIncompatibleAllocation = allocations.docs.any((document) {
        final data = document.data();
        return !ClassSchedule.allocationMatches(
          studyPattern: input.studyPattern,
          shiftCode: input.shiftCode,
          weekday: data['weekday'] as int? ?? -1,
          startMinute: data['startMinute'] as int? ?? -1,
          endMinute: data['endMinute'] as int? ?? -1,
        );
      });
      if (hasIncompatibleAllocation) {
        throw StateError(
          'Lịch hoặc ca mới không khớp lịch phân phòng hiện tại. '
          'Hãy điều chỉnh hoặc hủy lịch phân phòng trước.',
        );
      }
    }
    if (input.maxStudents < englishClass.maxStudents) {
      final activeEnrollments = await _firestore
          .collection('enrollments')
          .where('classId', isEqualTo: englishClass.id)
          .where('status', isEqualTo: 'active')
          .get();
      if (!EnrollmentPolicy.canReduceCapacity(
        newMaxStudents: input.maxStudents,
        activeCount: activeEnrollments.docs.length,
      )) {
        throw StateError(
          'Không thể giảm sĩ số tối đa dưới số học viên đang đăng ký.',
        );
      }
    }

    await _firestore.collection('classes').doc(englishClass.id).update({
      'name': input.name,
      'courseId': input.courseId,
      'minStudents': input.minStudents,
      'maxStudents': input.maxStudents,
      'studyPattern': input.studyPattern,
      'shiftCode': input.shiftCode,
      'startMinute': FieldValue.delete(),
      'endMinute': FieldValue.delete(),
      'status': input.status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteClass(EnglishClass englishClass) async {
    if (!englishClass.canDelete) {
      throw StateError('Chỉ lớp chờ mở mới được xóa.');
    }
    final allocations = await _firestore
        .collection('room_allocations')
        .where('classId', isEqualTo: englishClass.id)
        .limit(1)
        .get();
    final activeEnrollments = await _firestore
        .collection('enrollments')
        .where('classId', isEqualTo: englishClass.id)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    final assignment = await _firestore
        .collection('teacher_assignments')
        .doc(englishClass.id)
        .get();
    if (assignment.exists) {
      throw StateError(
        'Không thể xóa lớp đang có giáo viên được phân công. Hãy hủy phân công trước.',
      );
    }
    if (!EnrollmentPolicy.canDeleteClass(
      classPending: englishClass.canDelete,
      hasRoomAllocations: allocations.docs.isNotEmpty,
      hasActiveEnrollments: activeEnrollments.docs.isNotEmpty,
    )) {
      if (allocations.docs.isNotEmpty) {
        throw StateError(
          'Không thể xóa lớp đang có lịch phân bổ. Hãy hủy lịch trước.',
        );
      }
      throw StateError(
        'Không thể xóa lớp còn học viên đang đăng ký. Hãy xử lý đăng ký trước.',
      );
    }
    await _firestore.collection('classes').doc(englishClass.id).delete();
  }
}
