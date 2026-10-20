import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/course.dart';
import '../models/english_class.dart';
import '../models/enrollment.dart';
import '../models/room.dart';
import '../models/room_allocation.dart';
import '../models/student.dart';
import '../models/teacher.dart';
import '../models/teacher_assignment.dart';

class StudentScheduleService {
  StudentScheduleService._();

  static final instance = StudentScheduleService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<StudentScheduleData> loadForUser(String userUid) =>
      _loadForUser(userUid).timeout(const Duration(seconds: 15));

  Future<StudentScheduleData> _loadForUser(String userUid) async {
    final profileSnapshot = await _firestore
        .collection('students')
        .where('userUid', isEqualTo: userUid)
        .limit(1)
        .get();
    if (profileSnapshot.docs.isEmpty) {
      throw StateError('Tài khoản chưa được liên kết với hồ sơ học viên.');
    }

    final profileDocument = profileSnapshot.docs.first;
    final student = Student.fromMap(profileDocument.id, profileDocument.data());
    if (!student.isActive) {
      throw StateError('Hồ sơ học viên đã ngừng hoạt động.');
    }

    final enrollmentSnapshot = await _firestore
        .collection('enrollments')
        .where('studentId', isEqualTo: student.id)
        .get();
    final enrollments = filterActiveEnrollments(
      enrollmentSnapshot.docs.map(
        (document) => Enrollment.fromMap(document.id, document.data()),
      ),
      student.id,
    );

    final classes = await Future.wait(
      enrollments.map((enrollment) => _loadClass(enrollment.classId)),
    );
    final currentClasses = classes.whereType<StudentScheduleClass>().toList()
      ..sort((a, b) => a.englishClass.name.compareTo(b.englishClass.name));
    return StudentScheduleData(classes: currentClasses);
  }

  Future<StudentScheduleClass?> _loadClass(String classId) async {
    final classDocument = await _firestore
        .collection('classes')
        .doc(classId)
        .get();
    if (!classDocument.exists) {
      throw StateError('Lớp học đã đăng ký không còn tồn tại.');
    }
    final englishClass = EnglishClass.fromMap(
      classDocument.id,
      classDocument.data()!,
    );
    if (!isCurrentStudentClass(englishClass)) return null;

    final details = await Future.wait([
      _firestore.collection('courses').doc(englishClass.courseId).get(),
      _firestore
          .collection('room_allocations')
          .where('classId', isEqualTo: englishClass.id)
          .get(),
      _firestore.collection('teacher_assignments').doc(englishClass.id).get(),
    ]);
    final courseDocument = details[0] as DocumentSnapshot<Map<String, dynamic>>;
    final allocationSnapshot =
        details[1] as QuerySnapshot<Map<String, dynamic>>;
    final assignmentDocument =
        details[2] as DocumentSnapshot<Map<String, dynamic>>;
    if (!courseDocument.exists) {
      throw StateError('Khóa học của lớp không còn tồn tại.');
    }

    final course = Course.fromMap(courseDocument.id, courseDocument.data()!);
    final allocations = allocationSnapshot.docs
        .map((document) => RoomAllocation.fromMap(document.id, document.data()))
        .where(
          (allocation) => englishClass.allocationMatches(
            weekday: allocation.weekday,
            startMinute: allocation.startMinute,
            endMinute: allocation.endMinute,
          ),
        )
        .toList();

    final rooms = <String, Room>{};
    for (final roomId in allocations.map((item) => item.roomId).toSet()) {
      final document = await _firestore.collection('rooms').doc(roomId).get();
      if (document.exists) {
        rooms[roomId] = Room.fromMap(document.id, document.data()!);
      }
    }

    String? teacherName;
    if (assignmentDocument.exists) {
      final assignment = TeacherAssignment.fromMap(
        assignmentDocument.id,
        assignmentDocument.data()!,
      );
      final teacherDocument = await _firestore
          .collection('teachers')
          .doc(assignment.teacherId)
          .get();
      if (teacherDocument.exists) {
        teacherName = Teacher.fromMap(
          teacherDocument.id,
          teacherDocument.data()!,
        ).fullName;
      }
    }

    return StudentScheduleClass(
      englishClass: englishClass,
      course: course,
      allocations: allocations,
      rooms: rooms,
      teacherName: teacherName,
    );
  }
}

List<Enrollment> filterActiveEnrollments(
  Iterable<Enrollment> enrollments,
  String studentId,
) => enrollments
    .where(
      (enrollment) => enrollment.studentId == studentId && enrollment.isActive,
    )
    .toList();

bool isCurrentStudentClass(EnglishClass englishClass) =>
    englishClass.status != 'completed';

class StudentScheduleData {
  const StudentScheduleData({required this.classes});

  final List<StudentScheduleClass> classes;

  List<StudentScheduleEntry> get entries {
    final result = classes.expand((item) => item.entries).toList()
      ..sort((a, b) {
        final weekday = a.weekday.compareTo(b.weekday);
        return weekday != 0 ? weekday : a.startMinute.compareTo(b.startMinute);
      });
    return result;
  }
}

class StudentScheduleClass {
  const StudentScheduleClass({
    required this.englishClass,
    required this.course,
    this.allocations = const [],
    this.rooms = const {},
    this.teacherName,
  });

  final EnglishClass englishClass;
  final Course course;
  final List<RoomAllocation> allocations;
  final Map<String, Room> rooms;
  final String? teacherName;

  String get statusLabel => switch (englishClass.status) {
    'pending' => 'Chờ khai giảng',
    'ongoing' => 'Đang học',
    _ => englishClass.statusLabel,
  };

  List<StudentScheduleEntry> get entries {
    final shift = ClassShift.fromCode(englishClass.shiftCode);
    if (shift == null) return const [];
    return ClassSchedule.weekdaysFor(englishClass.studyPattern).map((weekday) {
      RoomAllocation? matchingAllocation;
      for (final allocation in allocations) {
        if (allocation.weekday == weekday &&
            englishClass.allocationMatches(
              weekday: allocation.weekday,
              startMinute: allocation.startMinute,
              endMinute: allocation.endMinute,
            )) {
          matchingAllocation = allocation;
          break;
        }
      }
      return StudentScheduleEntry(
        className: englishClass.name,
        weekday: weekday,
        startMinute: shift.startMinute,
        endMinute: shift.endMinute,
        roomName: matchingAllocation == null
            ? null
            : rooms[matchingAllocation.roomId]?.name,
      );
    }).toList();
  }
}

class StudentScheduleEntry {
  const StudentScheduleEntry({
    required this.className,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.roomName,
  });

  final String className;
  final int weekday;
  final int startMinute;
  final int endMinute;
  final String? roomName;

  String get timeLabel =>
      '${formatMinute(startMinute)}–${formatMinute(endMinute)}';
  String get roomLabel => roomName ?? 'Chưa phân phòng';
}
