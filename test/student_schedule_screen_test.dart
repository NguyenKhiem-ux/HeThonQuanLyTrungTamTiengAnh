import 'package:english_center_management/models/course.dart';
import 'package:english_center_management/models/english_class.dart';
import 'package:english_center_management/models/enrollment.dart';
import 'package:english_center_management/models/room.dart';
import 'package:english_center_management/models/room_allocation.dart';
import 'package:english_center_management/screens/student/student_schedule_screen.dart';
import 'package:english_center_management/screens/student/class_registration_screen.dart';
import 'package:english_center_management/services/student_schedule_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const course = Course(
    id: 'course-1',
    name: 'IELTS Foundation',
    program: 'IELTS',
    durationMonths: 3,
    standardTuition: 3000000,
  );

  EnglishClass englishClass({
    required String id,
    required String name,
    String status = 'ongoing',
    String? studyPattern = '246',
    String? shiftCode = 'evening_1',
  }) => EnglishClass(
    id: id,
    name: name,
    courseId: course.id,
    minStudents: 5,
    maxStudents: 20,
    status: status,
    studyPattern: studyPattern,
    shiftCode: shiftCode,
  );

  StudentScheduleClass scheduleClass({
    required EnglishClass value,
    List<RoomAllocation> allocations = const [],
    Map<String, Room> rooms = const {},
    String? teacherName,
  }) => StudentScheduleClass(
    englishClass: value,
    course: course,
    allocations: allocations,
    rooms: rooms,
    teacherName: teacherName,
  );

  Widget screen(Future<StudentScheduleData> Function(String userUid) loader) =>
      MaterialApp(
        home: Scaffold(
          body: StudentScheduleScreen(
            userUid: 'student-uid',
            loadSchedule: loader,
          ),
        ),
      );

  group('Student schedule selection', () {
    const active = Enrollment(
      id: 'class-1_student-1',
      studentId: 'student-1',
      classId: 'class-1',
      status: 'active',
    );
    const cancelled = Enrollment(
      id: 'class-2_student-1',
      studentId: 'student-1',
      classId: 'class-2',
      status: 'cancelled',
    );
    const anotherStudent = Enrollment(
      id: 'class-3_student-2',
      studentId: 'student-2',
      classId: 'class-3',
      status: 'active',
    );

    test('keeps only active enrollments belonging to the linked student', () {
      final result = filterActiveEnrollments([
        active,
        cancelled,
        anotherStudent,
      ], 'student-1');

      expect(result, [active]);
    });

    test('completed classes are excluded from the current schedule', () {
      expect(
        isCurrentStudentClass(
          englishClass(
            id: 'completed',
            name: 'Lớp đã xong',
            status: 'completed',
          ),
        ),
        isFalse,
      );
    });

    test('246 shift 1 creates Monday, Wednesday and Friday at 18:00', () {
      final item = scheduleClass(
        value: englishClass(id: 'class-246', name: 'IELTS 246'),
      );

      expect(item.entries.map((entry) => entry.weekday), [1, 3, 5]);
      expect(
        item.entries.map((entry) => entry.timeLabel),
        everyElement('18:00–19:45'),
      );
    });

    test('357 shift 2 creates Tuesday, Thursday and Saturday at 20:00', () {
      final item = scheduleClass(
        value: englishClass(
          id: 'class-357',
          name: 'IELTS 357',
          studyPattern: '357',
          shiftCode: 'evening_2',
        ),
      );

      expect(item.entries.map((entry) => entry.weekday), [2, 4, 6]);
      expect(
        item.entries.map((entry) => entry.timeLabel),
        everyElement('20:00–21:45'),
      );
    });

    test('room allocation is applied only to its matching weekday', () {
      final item = scheduleClass(
        value: englishClass(id: 'class-1', name: 'IELTS A1'),
        allocations: const [
          RoomAllocation(
            id: 'allocation-1',
            roomId: 'room-1',
            classId: 'class-1',
            weekday: 1,
            startMinute: 1080,
            endMinute: 1185,
          ),
        ],
        rooms: const {
          'room-1': Room(
            id: 'room-1',
            name: 'P101',
            capacity: 20,
            status: 'active',
          ),
        },
      );

      expect(item.entries[0].roomLabel, 'P101');
      expect(item.entries[1].roomLabel, 'Chưa phân phòng');
      expect(item.entries[2].roomLabel, 'Chưa phân phòng');
    });

    test('classes without schedule fields produce no fake sessions', () {
      final item = scheduleClass(
        value: englishClass(
          id: 'legacy',
          name: 'Lớp cũ',
          studyPattern: null,
          shiftCode: null,
        ),
      );

      expect(item.entries, isEmpty);
    });
  });

  group('Student schedule screen', () {
    testWidgets('shows empty state when there is no active enrollment', (
      tester,
    ) async {
      await tester.pumpWidget(
        screen((_) async => const StudentScheduleData(classes: [])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bạn chưa được xếp vào lớp học nào.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a pending registration request is not treated as a class', (
      tester,
    ) async {
      await tester.pumpWidget(
        screen((_) async => const StudentScheduleData(classes: [])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lớp đang tham gia'), findsNothing);
      expect(find.text('Bạn chưa được xếp vào lớp học nào.'), findsOneWidget);
    });

    testWidgets('shows an active class, course, status and teacher', (
      tester,
    ) async {
      final item = scheduleClass(
        value: englishClass(id: 'class-1', name: 'IELTS A1'),
        teacherName: 'Nguyễn Minh Anh',
      );
      await tester.pumpWidget(
        screen((_) async => StudentScheduleData(classes: [item])),
      );
      await tester.pumpAndSettle();

      expect(find.text('IELTS A1'), findsWidgets);
      expect(find.text('Khóa học: IELTS Foundation'), findsOneWidget);
      expect(find.text('Đang học'), findsOneWidget);
      expect(find.text('Giáo viên: Nguyễn Minh Anh'), findsOneWidget);
    });

    testWidgets('still shows schedule without room or teacher', (tester) async {
      final item = scheduleClass(
        value: englishClass(id: 'class-1', name: 'IELTS A1'),
      );
      await tester.pumpWidget(
        screen((_) async => StudentScheduleData(classes: [item])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Phòng: Chưa phân phòng'), findsNWidgets(3));
      expect(find.text('Giáo viên: Chưa phân công giáo viên'), findsOneWidget);
    });

    testWidgets('shows every class when a student attends multiple classes', (
      tester,
    ) async {
      final first = scheduleClass(
        value: englishClass(id: 'class-1', name: 'IELTS A1'),
      );
      final second = scheduleClass(
        value: englishClass(
          id: 'class-2',
          name: 'TOEIC B1',
          studyPattern: '357',
          shiftCode: 'evening_2',
        ),
      );
      await tester.pumpWidget(
        screen((_) async => StudentScheduleData(classes: [first, second])),
      );
      await tester.pumpAndSettle();

      expect(find.text('IELTS A1'), findsWidgets);
      expect(find.text('TOEIC B1'), findsWidgets);
    });

    testWidgets('shows legacy class without crashing or inventing sessions', (
      tester,
    ) async {
      final item = scheduleClass(
        value: englishClass(
          id: 'legacy',
          name: 'Lớp cũ',
          studyPattern: null,
          shiftCode: null,
        ),
      );
      await tester.pumpWidget(
        screen((_) async => StudentScheduleData(classes: [item])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chưa thiết lập lịch học'), findsOneWidget);
      expect(find.text('Chưa thiết lập ca học'), findsOneWidget);
    });

    testWidgets('Firestore failure ends loading and retry can recover', (
      tester,
    ) async {
      var attempts = 0;
      Future<StudentScheduleData> loader(String _) async {
        attempts++;
        if (attempts == 1) throw StateError('Không thể tải dữ liệu.');
        return const StudentScheduleData(classes: []);
      }

      await tester.pumpWidget(screen(loader));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Thử lại'), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('Bạn chưa được xếp vào lớp học nào.'), findsOneWidget);
    });
  });

  testWidgets('registration does not show a guessed remaining capacity', (
    tester,
  ) async {
    final value = englishClass(id: 'class-1', name: 'IELTS A1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RegistrationClassDetails(
            course: course,
            englishClass: value,
            remainingSlots: null,
            roomLabel: 'Chưa phân phòng',
          ),
        ),
      ),
    );

    expect(find.text('Sĩ số tối đa: 20'), findsOneWidget);
    expect(find.textContaining('Sĩ số còn lại'), findsNothing);
  });
}
