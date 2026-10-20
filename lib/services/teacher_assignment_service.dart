import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/course.dart';
import '../models/english_class.dart';
import '../models/room.dart';
import '../models/room_allocation.dart';
import '../models/teacher.dart';
import '../models/teacher_assignment.dart';

class TeacherAssignmentService {
  TeacherAssignmentService._();

  static final instance = TeacherAssignmentService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<TeacherAssignment>> watchAssignments() => _firestore
      .collection('teacher_assignments')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (document) =>
                  TeacherAssignment.fromMap(document.id, document.data()),
            )
            .toList(),
      );

  Stream<List<TeacherAssignment>> watchAssignmentsForTeacher(String userUid) =>
      _firestore
          .collection('teacher_assignments')
          .where('teacherUid', isEqualTo: userUid)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (document) =>
                      TeacherAssignment.fromMap(document.id, document.data()),
                )
                .toList(),
          );

  Stream<List<EnglishClass>> watchAssignedClassesForTeacher(String userUid) =>
      _firestore
          .collection('teacher_assignments')
          .where('teacherUid', isEqualTo: userUid)
          .snapshots()
          .asyncMap((snapshot) async {
            final classes = await Future.wait(
              snapshot.docs.map((assignmentDocument) async {
                final assignment = TeacherAssignment.fromMap(
                  assignmentDocument.id,
                  assignmentDocument.data(),
                );
                final classDocument = await _firestore
                    .collection('classes')
                    .doc(assignment.classId)
                    .get();
                if (!classDocument.exists) {
                  throw StateError('Lớp được phân công không còn tồn tại.');
                }
                return EnglishClass.fromMap(
                  classDocument.id,
                  classDocument.data()!,
                );
              }),
            );
            classes.sort((a, b) => a.name.compareTo(b.name));
            return classes;
          });

  Future<void> assign({
    required String classId,
    required String teacherId,
  }) async {
    final teacherDocument = await _firestore
        .collection('teachers')
        .doc(teacherId)
        .get();
    final classDocument = await _firestore
        .collection('classes')
        .doc(classId)
        .get();
    if (!teacherDocument.exists || !classDocument.exists) {
      throw StateError('Giáo viên hoặc lớp học không còn tồn tại.');
    }
    final teacher = Teacher.fromMap(teacherId, teacherDocument.data()!);
    final englishClass = EnglishClass.fromMap(classId, classDocument.data()!);
    final teacherUid = teacher.userUid;
    DocumentSnapshot<Map<String, dynamic>>? userDocument;
    if (teacherUid != null) {
      userDocument = await _firestore.collection('users').doc(teacherUid).get();
    }
    final linkedUserActive =
        userDocument?.exists == true &&
        userDocument?.data()?['role'] == 'teacher' &&
        userDocument?.data()?['status'] == 'active';
    final error = TeacherAssignmentPolicy.assignmentError(
      teacherActive: teacher.isActive,
      teacherLinked: teacherUid != null,
      linkedUserActive: linkedUserActive,
      classStatus: englishClass.status,
    );
    if (error != null) throw StateError(error);

    final results = await Future.wait([
      _firestore
          .collection('teacher_assignments')
          .where('teacherId', isEqualTo: teacherId)
          .get(),
      _firestore.collection('room_allocations').get(),
    ]);
    final assignmentSnapshot = results[0];
    final allocationSnapshot = results[1];
    final otherClassIds = assignmentSnapshot.docs
        .map((document) => document.data()['classId'])
        .whereType<String>()
        .where((id) => id != classId)
        .toSet();
    final allocations = allocationSnapshot.docs
        .map((document) => RoomAllocation.fromMap(document.id, document.data()))
        .toList();
    final targetSchedules = allocations.where(
      (allocation) => allocation.classId == classId,
    );
    final otherSchedules = allocations.where(
      (allocation) => otherClassIds.contains(allocation.classId),
    );
    if (TeacherAssignmentPolicy.schedulesOverlap(
      targetSchedules,
      otherSchedules,
    )) {
      throw StateError('Giáo viên đã có lớp khác trùng thời gian với lớp này.');
    }

    final reference = _firestore
        .collection('teacher_assignments')
        .doc(TeacherAssignment.documentId(classId));
    final existing = await reference.get();
    final timestamp = FieldValue.serverTimestamp();
    if (existing.exists) {
      await reference.update({
        'teacherId': teacherId,
        'teacherUid': teacherUid,
        'updatedAt': timestamp,
      });
    } else {
      await reference.set({
        'classId': classId,
        'teacherId': teacherId,
        'teacherUid': teacherUid,
        'assignedAt': timestamp,
        'updatedAt': timestamp,
      });
    }
  }

  Future<void> cancel(String classId) => _firestore
      .collection('teacher_assignments')
      .doc(TeacherAssignment.documentId(classId))
      .delete();

  Future<EnglishClass> getAssignedClass(String classId) async {
    final document = await _firestore.collection('classes').doc(classId).get();
    if (!document.exists) throw StateError('Lớp học không còn tồn tại.');
    return EnglishClass.fromMap(document.id, document.data()!);
  }

  Future<Course> getCourse(String courseId) async {
    final document = await _firestore.collection('courses').doc(courseId).get();
    if (!document.exists) throw StateError('Khóa học không còn tồn tại.');
    return Course.fromMap(document.id, document.data()!);
  }

  Future<Room> getRoom(String roomId) async {
    final document = await _firestore.collection('rooms').doc(roomId).get();
    if (!document.exists) throw StateError('Phòng học không còn tồn tại.');
    return Room.fromMap(document.id, document.data()!);
  }

  Stream<List<RoomAllocation>> watchClassSchedule(String classId) => _firestore
      .collection('room_allocations')
      .where('classId', isEqualTo: classId)
      .snapshots()
      .map((snapshot) {
        final allocations = snapshot.docs
            .map(
              (document) =>
                  RoomAllocation.fromMap(document.id, document.data()),
            )
            .toList();
        allocations.sort((a, b) {
          final day = a.weekday.compareTo(b.weekday);
          return day != 0 ? day : a.startMinute.compareTo(b.startMinute);
        });
        return allocations;
      });
}
