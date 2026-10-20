import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/english_class.dart';
import '../models/room.dart';
import '../models/room_allocation.dart';
import 'firestore_stream.dart';

class RoomAllocationService {
  RoomAllocationService._();

  static final instance = RoomAllocationService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<RoomAllocation>> watchAllocations() => _firestore
      .collection('room_allocations')
      .snapshots()
      .withInitialSnapshotTimeout()
      .map((snapshot) {
        final allocations = snapshot.docs
            .map(
              (document) =>
                  RoomAllocation.fromMap(document.id, document.data()),
            )
            .toList();
        allocations.sort((a, b) {
          final weekdayComparison = a.weekday.compareTo(b.weekday);
          return weekdayComparison != 0
              ? weekdayComparison
              : a.startMinute.compareTo(b.startMinute);
        });
        return allocations;
      });

  Future<void> addAllocation(RoomAllocationInput input) async {
    await _validate(input);
    final timestamp = FieldValue.serverTimestamp();
    await _firestore.collection('room_allocations').add({
      'roomId': input.roomId,
      'classId': input.classId,
      'weekday': input.weekday,
      'startMinute': input.startMinute,
      'endMinute': input.endMinute,
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
  }

  Future<void> updateAllocation(
    RoomAllocation allocation,
    RoomAllocationInput input,
  ) async {
    await _validate(input, excludedId: allocation.id);
    await _firestore.collection('room_allocations').doc(allocation.id).update({
      'roomId': input.roomId,
      'classId': input.classId,
      'weekday': input.weekday,
      'startMinute': input.startMinute,
      'endMinute': input.endMinute,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAllocation(String allocationId) =>
      _firestore.collection('room_allocations').doc(allocationId).delete();

  Future<void> _validate(
    RoomAllocationInput input, {
    String? excludedId,
  }) async {
    if (!input.isValid) {
      throw StateError('Thông tin phân bổ phòng không hợp lệ.');
    }

    final documents = await Future.wait([
      _firestore.collection('rooms').doc(input.roomId).get(),
      _firestore.collection('classes').doc(input.classId).get(),
    ]);
    if (!documents[0].exists || !documents[1].exists) {
      throw StateError('Lớp học hoặc phòng học không còn tồn tại.');
    }
    final room = Room.fromMap(input.roomId, documents[0].data()!);
    final englishClass = EnglishClass.fromMap(
      input.classId,
      documents[1].data()!,
    );
    if (!room.isActive) {
      throw StateError('Phòng đã ngừng hoạt động.');
    }
    if (!englishClass.canEdit) {
      throw StateError('Không thể phân bổ phòng cho lớp đã kết thúc.');
    }
    if (!englishClass.hasConfiguredSchedule) {
      throw StateError('Lớp chưa được thiết lập đầy đủ lịch học và ca học.');
    }
    if (!englishClass.allocationMatches(
      weekday: input.weekday,
      startMinute: input.startMinute,
      endMinute: input.endMinute,
    )) {
      throw StateError(
        'Thứ và thời gian phân phòng phải khớp lịch học, ca học của lớp.',
      );
    }
    if (room.capacity < englishClass.maxStudents) {
      throw StateError(
        'Sức chứa phòng phải từ ${englishClass.maxStudents} học viên.',
      );
    }

    // shortcut: kiểm tra xung đột ở client có thể race, chuyển sang backend nguyên tử khi có nhiều tiến trình ghi.
    final snapshot = await _firestore
        .collection('room_allocations')
        .where('weekday', isEqualTo: input.weekday)
        .get();
    for (final document in snapshot.docs) {
      if (document.id == excludedId) continue;
      final allocation = RoomAllocation.fromMap(document.id, document.data());
      if (input.conflictsWith(allocation)) {
        final target = allocation.roomId == input.roomId ? 'phòng' : 'lớp';
        throw StateError(
          'Lịch bị trùng: $target đã có phân bổ trong khoảng thời gian này.',
        );
      }
    }

    final currentAssignment = await _firestore
        .collection('teacher_assignments')
        .doc(input.classId)
        .get();
    if (!currentAssignment.exists) return;
    final teacherId = currentAssignment.data()?['teacherId'];
    if (teacherId is! String || teacherId.isEmpty) {
      throw StateError('Dữ liệu phân công giáo viên không hợp lệ.');
    }
    final teacherAssignments = await _firestore
        .collection('teacher_assignments')
        .where('teacherId', isEqualTo: teacherId)
        .get();
    final otherClassIds = teacherAssignments.docs
        .map((document) => document.data()['classId'])
        .whereType<String>()
        .where((classId) => classId != input.classId)
        .toSet();
    for (final document in snapshot.docs) {
      if (document.id == excludedId) continue;
      final allocation = RoomAllocation.fromMap(document.id, document.data());
      if (otherClassIds.contains(allocation.classId) &&
          timeRangesOverlap(
            input.startMinute,
            input.endMinute,
            allocation.startMinute,
            allocation.endMinute,
          )) {
        throw StateError(
          'Giáo viên của lớp đã có lịch dạy khác trong khoảng thời gian này.',
        );
      }
    }
  }
}
