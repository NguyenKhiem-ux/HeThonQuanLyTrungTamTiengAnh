import 'dart:async';

import 'package:english_center_management/models/attendance_record.dart';
import 'package:english_center_management/models/attendance_session.dart';
import 'package:english_center_management/models/class_registration_request.dart';
import 'package:english_center_management/models/course.dart';
import 'package:english_center_management/models/english_class.dart';
import 'package:english_center_management/models/enrollment.dart';
import 'package:english_center_management/models/learning_result.dart';
import 'package:english_center_management/models/room.dart';
import 'package:english_center_management/models/room_allocation.dart';
import 'package:english_center_management/models/student.dart';
import 'package:english_center_management/models/teacher.dart';
import 'package:english_center_management/models/teacher_assignment.dart';
import 'package:english_center_management/models/user_profile.dart';
import 'package:english_center_management/services/staff_account_service.dart';
import 'package:english_center_management/services/firestore_stream.dart';
import 'package:english_center_management/screens/admin/room_allocation_screen.dart';
import 'package:english_center_management/screens/student/class_registration_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserProfile', () {
    test('accepts an active profile with a supported role', () {
      final profile = UserProfile.fromMap('user-1', {
        'uid': 'user-1',
        'fullName': 'Nguyễn Văn An',
        'email': 'an@example.com',
        'role': 'student',
        'status': 'active',
        'createdAt': Object(),
      });

      expect(profile.roleLabel, 'Học viên');
    });

    test('accepts a pending teacher profile for the approval screen', () {
      final profile = UserProfile.fromMap('teacher-1', {
        'uid': 'teacher-1',
        'fullName': 'Giáo viên Demo',
        'email': 'teacher.demo@example.com',
        'role': 'teacher',
        'status': 'pending',
        'createdAt': Object(),
      });

      expect(profile.isPending, isTrue);
    });

    test('rejects pending status for a student', () {
      expect(
        () => UserProfile.fromMap('student-1', {
          'uid': 'student-1',
          'fullName': 'Học viên Demo',
          'email': 'student.demo@example.com',
          'role': 'student',
          'status': 'pending',
          'createdAt': Object(),
        }),
        throwsFormatException,
      );
    });

    test('rejects profiles that could grant an unsupported role', () {
      expect(
        () => UserProfile.fromMap('user-1', {
          'uid': 'user-1',
          'fullName': 'Nguyễn Văn An',
          'email': 'an@example.com',
          'role': 'super-admin',
          'status': 'active',
          'createdAt': Object(),
        }),
        throwsFormatException,
      );
    });

    test('accepts an inactive staff profile for the locked account screen', () {
      final profile = UserProfile.fromMap('consultant-1', {
        'uid': 'consultant-1',
        'fullName': 'Tư vấn viên Demo',
        'email': 'consultant@example.com',
        'role': 'consultant',
        'status': 'inactive',
        'createdAt': Object(),
      });

      expect(profile.isInactive, isTrue);
    });
  });

  group('Staff account approval', () {
    test('admin can approve a pending teacher', () {
      expect(
        StaffApprovalPolicy.transitionError(
          isDesignatedAdmin: true,
          targetRole: 'teacher',
          currentStatus: 'pending',
          nextStatus: 'active',
        ),
        isNull,
      );
    });

    test('admin can approve a pending consultant', () {
      expect(
        StaffApprovalPolicy.transitionError(
          isDesignatedAdmin: true,
          targetRole: 'consultant',
          currentStatus: 'pending',
          nextStatus: 'active',
        ),
        isNull,
      );
    });

    test('admin can reject a pending staff account', () {
      expect(
        StaffApprovalPolicy.transitionError(
          isDesignatedAdmin: true,
          targetRole: 'teacher',
          currentStatus: 'pending',
          nextStatus: 'inactive',
        ),
        isNull,
      );
    });

    test('admin can lock an active staff account', () {
      expect(
        StaffApprovalPolicy.transitionError(
          isDesignatedAdmin: true,
          targetRole: 'consultant',
          currentStatus: 'active',
          nextStatus: 'inactive',
        ),
        isNull,
      );
    });

    test('admin can reactivate an inactive staff account', () {
      expect(
        StaffApprovalPolicy.transitionError(
          isDesignatedAdmin: true,
          targetRole: 'teacher',
          currentStatus: 'inactive',
          nextStatus: 'active',
        ),
        isNull,
      );
    });

    test('pending teacher is not eligible but active teacher can sync', () {
      expect(
        TeacherProfileSyncPolicy.isActiveTeacherAccount(
          role: 'teacher',
          status: 'pending',
        ),
        isFalse,
      );
      expect(
        TeacherProfileSyncPolicy.needsSync(
          role: 'teacher',
          status: 'active',
          profile: null,
        ),
        isTrue,
      );
    });

    test('minimal synced teacher profile is assignable without fake data', () {
      final teacher = Teacher.fromMap('teacher-1', {
        'fullName': 'Giáo viên Demo',
        'email': 'teacher@example.com',
        'phone': '',
        'specialty': '',
        'status': 'active',
        'userUid': 'teacher-1',
      });

      expect(teacher.isAssignable, isTrue);
      expect(teacher.specialtyLabel, 'Chưa cập nhật chuyên môn');
      expect(
        TeacherProfileSyncPolicy.needsSync(
          role: 'teacher',
          status: 'active',
          profile: teacher,
        ),
        isFalse,
      );
    });

    test('detects duplicate teacher profiles for one account', () {
      const teachers = [
        Teacher(
          id: 'profile-1',
          fullName: 'Giáo viên Demo',
          email: 'teacher@example.com',
          phone: '',
          specialty: '',
          status: 'active',
          userUid: 'teacher-uid',
        ),
        Teacher(
          id: 'profile-2',
          fullName: 'Giáo viên Demo',
          email: 'teacher@example.com',
          phone: '',
          specialty: '',
          status: 'active',
          userUid: 'teacher-uid',
        ),
      ];

      expect(
        TeacherProfileSyncPolicy.hasDuplicateLink(teachers, 'teacher-uid'),
        isTrue,
      );
      expect(
        TeacherProfileSyncPolicy.hasDuplicateLink(
          teachers.take(1),
          'teacher-uid',
        ),
        isFalse,
      );
    });

    test('active linked teacher profile remains assignable', () {
      expect(
        TeacherAssignmentPolicy.assignmentError(
          teacherActive: true,
          teacherLinked: true,
          linkedUserActive: true,
          classStatus: 'pending',
        ),
        isNull,
      );
    });

    test('student cannot self-approve', () {
      expect(
        StaffApprovalPolicy.transitionError(
          isDesignatedAdmin: false,
          targetRole: 'student',
          currentStatus: 'pending',
          nextStatus: 'active',
        ),
        isNotNull,
      );
    });

    test('teacher and consultant cannot change their own status', () {
      for (final role in ['teacher', 'consultant']) {
        expect(
          StaffApprovalPolicy.transitionError(
            isDesignatedAdmin: false,
            targetRole: role,
            currentStatus: 'pending',
            nextStatus: 'active',
          ),
          isNotNull,
        );
      }
    });

    test('admin account cannot be edited by the approval flow', () {
      expect(
        StaffApprovalPolicy.transitionError(
          isDesignatedAdmin: true,
          targetRole: 'admin',
          currentStatus: 'active',
          nextStatus: 'inactive',
        ),
        isNotNull,
      );
    });

    test('approval cannot change role or other account fields', () {
      expect(
        StaffApprovalPolicy.transitionError(
          isDesignatedAdmin: true,
          targetRole: 'teacher',
          currentStatus: 'pending',
          nextStatus: 'active',
          changesOnlyStatus: false,
        ),
        isNotNull,
      );
    });

    test('teacher account list excludes consultants', () {
      const accounts = [
        StaffAccount(
          id: 'teacher-1',
          uid: 'teacher-1',
          fullName: 'Giáo viên Demo',
          email: 'teacher@example.com',
          role: 'teacher',
          status: 'active',
          createdAt: null,
        ),
        StaffAccount(
          id: 'consultant-1',
          uid: 'consultant-1',
          fullName: 'Tư vấn viên Demo',
          email: 'consultant@example.com',
          role: 'consultant',
          status: 'active',
          createdAt: null,
        ),
      ];

      final teachers = filterStaffAccounts(accounts, fixedRole: 'teacher');

      expect(teachers.map((account) => account.role), everyElement('teacher'));
      expect(teachers, hasLength(1));
    });

    test('permission denied has a clear user-facing message', () {
      final message = firestoreLoadErrorMessage(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        'danh sách giáo viên',
      );

      expect(message, contains('Không có quyền'));
      expect(message, contains('Firestore Rules'));
    });
  });

  group('CourseInput', () {
    test('parses valid course data', () {
      final input = CourseInput.tryParse(
        name: '  IELTS Foundation ',
        program: ' IELTS ',
        durationMonths: '3',
        standardTuition: '3500000',
      );

      expect(input, isNotNull);
      expect(input!.name, 'IELTS Foundation');
      expect(input.durationMonths, 3);
      expect(input.standardTuition, 3500000);
      expect(input.toFirestore()['durationMonths'], 3);
      expect(input.toFirestore(), isNot(contains('durationHours')));
    });

    test('rejects invalid duration and tuition', () {
      for (final duration in ['', '0', '-1', '1.5']) {
        expect(
          CourseInput.tryParse(
            name: 'IELTS',
            program: 'IELTS',
            durationMonths: duration,
            standardTuition: '1000',
          ),
          isNull,
        );
      }
      expect(
        CourseInput.tryParse(
          name: 'IELTS',
          program: 'IELTS',
          durationMonths: '6',
          standardTuition: '-1',
        ),
        isNull,
      );
    });

    test('reads legacy duration without converting hours to months', () {
      final legacy = Course.fromMap('course-old', {
        'name': 'IELTS cũ',
        'program': 'IELTS',
        'durationHours': 40,
        'standardTuition': 3500000,
      });

      expect(legacy.durationMonths, isNull);
      expect(legacy.durationLabel, 'Chưa cập nhật thời lượng theo tháng');
    });

    test('displays current duration in months', () {
      final course = Course.fromMap('course-new', {
        'name': 'IELTS mới',
        'program': 'IELTS',
        'durationMonths': 6,
        'standardTuition': 3500000,
      });

      expect(course.durationLabel, '6 tháng');
    });
  });

  group('EnglishClass', () {
    test('validates minimum and maximum capacity', () {
      expect(
        EnglishClassInput.tryParse(
          name: 'IELTS A1',
          courseId: 'course-1',
          minStudents: '0',
          maxStudents: '20',
          status: 'pending',
        ),
        isNull,
      );
      expect(
        EnglishClassInput.tryParse(
          name: 'IELTS A1',
          courseId: 'course-1',
          minStudents: '15',
          maxStudents: '14',
          status: 'pending',
        ),
        isNull,
      );
    });

    test('accepts only the three supported status values', () {
      expect(EnglishClass.validStatuses, {'pending', 'ongoing', 'completed'});
      expect(
        EnglishClassInput.tryParse(
          name: 'IELTS A1',
          courseId: 'course-1',
          minStudents: '10',
          maxStudents: '20',
          status: 'cancelled',
        ),
        isNull,
      );
    });

    test('allows only forward status transitions or no status change', () {
      expect(
        EnglishClass.isValidStatusTransition('pending', 'ongoing'),
        isTrue,
      );
      expect(
        EnglishClass.isValidStatusTransition('ongoing', 'completed'),
        isTrue,
      );
      expect(
        EnglishClass.isValidStatusTransition('pending', 'completed'),
        isFalse,
      );
      expect(
        EnglishClass.isValidStatusTransition('completed', 'ongoing'),
        isFalse,
      );
    });

    test('permits deletion only while a class is pending', () {
      const pendingClass = EnglishClass(
        id: 'class-1',
        name: 'IELTS A1',
        courseId: 'course-1',
        minStudents: 10,
        maxStudents: 20,
        status: 'pending',
      );
      const ongoingClass = EnglishClass(
        id: 'class-2',
        name: 'IELTS A2',
        courseId: 'course-1',
        minStudents: 10,
        maxStudents: 20,
        status: 'ongoing',
      );

      expect(pendingClass.canDelete, isTrue);
      expect(ongoingClass.canDelete, isFalse);
    });
  });

  group('Class schedule and shifts', () {
    test('creates a 246 class in evening shift 1', () {
      final input = EnglishClassInput.tryParse(
        name: 'IELTS 246-1',
        courseId: 'course-1',
        minStudents: '10',
        maxStudents: '20',
        status: 'pending',
        studyPattern: '246',
        shiftCode: 'evening_1',
      );

      expect(input, isNotNull);
      expect(input!.studyPattern, '246');
      expect(input.shiftCode, 'evening_1');
    });

    test('creates a 357 class in evening shift 2', () {
      final input = EnglishClassInput.tryParse(
        name: 'IELTS 357-2',
        courseId: 'course-1',
        minStudents: '10',
        maxStudents: '20',
        status: 'pending',
        studyPattern: '357',
        shiftCode: 'evening_2',
      );

      expect(input, isNotNull);
      expect(input!.studyPattern, '357');
      expect(input.shiftCode, 'evening_2');
    });

    test('rejects a new class without a shift', () {
      expect(
        EnglishClassInput.tryParse(
          name: 'IELTS A1',
          courseId: 'course-1',
          minStudents: '10',
          maxStudents: '20',
          status: 'pending',
          studyPattern: '246',
        ),
        isNull,
      );
    });

    test('maps both fixed shifts and study-pattern weekdays exactly', () {
      expect(ClassShift.evening1.startMinute, 1080);
      expect(ClassShift.evening1.endMinute, 1185);
      expect(ClassShift.evening2.startMinute, 1200);
      expect(ClassShift.evening2.endMinute, 1305);
      expect(ClassSchedule.weekdaysFor('246'), [1, 3, 5]);
      expect(ClassSchedule.weekdaysFor('357'), [2, 4, 6]);
    });

    test('rejects room allocation outside the selected shift', () {
      expect(
        ClassSchedule.allocationMatches(
          studyPattern: '246',
          shiftCode: 'evening_1',
          weekday: 1,
          startMinute: 1080,
          endMinute: 1185,
        ),
        isTrue,
      );
      expect(
        ClassSchedule.allocationMatches(
          studyPattern: '246',
          shiftCode: 'evening_1',
          weekday: 1,
          startMinute: 1200,
          endMinute: 1305,
        ),
        isFalse,
      );
      expect(
        ClassSchedule.allocationMatches(
          studyPattern: '246',
          shiftCode: 'evening_1',
          weekday: 2,
          startMinute: 1080,
          endMinute: 1185,
        ),
        isFalse,
      );
    });

    test('does not allow changing the shift of an ongoing class', () {
      const ongoingClass = EnglishClass(
        id: 'class-1',
        name: 'IELTS A1',
        courseId: 'course-1',
        minStudents: 10,
        maxStudents: 20,
        status: 'ongoing',
        studyPattern: '246',
        shiftCode: 'evening_1',
      );

      expect(ongoingClass.canChangeScheduleTo('246', 'evening_2'), isFalse);
      expect(ongoingClass.canChangeScheduleTo('246', 'evening_1'), isTrue);
    });

    test('reads a legacy class without shift without crashing', () {
      final legacy = EnglishClass.fromMap('class-old', {
        'name': 'Lớp cũ',
        'courseId': 'course-1',
        'minStudents': 5,
        'maxStudents': 10,
        'status': 'pending',
      });

      expect(legacy.shiftCode, isNull);
      expect(legacy.shiftLabel, 'Chưa thiết lập ca học');
      expect(legacy.hasConfiguredSchedule, isFalse);
    });

    testWidgets(
      'registration details show schedule and shift before approval',
      (tester) async {
        const course = Course(
          id: 'course-1',
          name: 'IELTS Foundation',
          program: 'IELTS',
          durationMonths: 3,
          standardTuition: 3000000,
        );
        const englishClass = EnglishClass(
          id: 'class-1',
          name: 'IELTS 246-1',
          courseId: 'course-1',
          minStudents: 10,
          maxStudents: 20,
          status: 'pending',
          studyPattern: '246',
          shiftCode: 'evening_1',
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: RegistrationClassDetails(
                course: course,
                englishClass: englishClass,
                remainingSlots: 7,
                roomLabel: 'Chưa phân phòng',
              ),
            ),
          ),
        );

        expect(find.text('Lịch 246'), findsOneWidget);
        expect(find.text('Ca 1: 18:00–19:45'), findsOneWidget);
        expect(find.text('Thời lượng: 3 tháng'), findsOneWidget);
        expect(find.text('Sĩ số còn lại: 7'), findsOneWidget);
        expect(find.text('Phòng: Chưa phân phòng'), findsOneWidget);
      },
    );

    test('student request policy keeps enrollment pending', () {
      expect(
        ClassRegistrationPolicy.requestError(
          studentActive: true,
          classStatus: 'pending',
          hasSchedule: true,
          remainingSlots: 2,
          hasOpenRequest: false,
        ),
        isNull,
      );
      expect(
        ClassRegistrationPolicy.requestError(
          studentActive: true,
          classStatus: 'pending',
          hasSchedule: true,
          remainingSlots: 2,
          hasOpenRequest: true,
        ),
        isNotNull,
      );
    });
  });

  group('Room and room allocation', () {
    const testRooms = <Room>[
      Room(id: 'room-1', name: 'P101', capacity: 20, status: 'active'),
      Room(id: 'room-2', name: 'P202', capacity: 30, status: 'active'),
    ];

    Widget buildRoomAllocationScreen(
      Stream<List<Room>> Function() roomsStreamFactory,
    ) => MaterialApp(
      home: Scaffold(
        body: RoomAllocationScreen(
          roomsStreamFactory: roomsStreamFactory,
          classesStreamFactory: () => Stream<List<EnglishClass>>.multi(
            (controller) => controller.add(const <EnglishClass>[]),
            isBroadcast: true,
          ),
          allocationsStreamFactory: () => Stream<List<RoomAllocation>>.multi(
            (controller) => controller.add(const <RoomAllocation>[]),
            isBroadcast: true,
          ),
        ),
      ),
    );

    test(
      'initial snapshot timeout does not affect a loaded realtime stream',
      () async {
        final source = StreamController<int>();
        final errors = <Object>[];
        final values = <int>[];
        final subscription = source.stream
            .withInitialSnapshotTimeout(const Duration(milliseconds: 20))
            .listen(values.add, onError: errors.add);

        source.add(1);
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(values, [1]);
        expect(errors, isEmpty);
        await subscription.cancel();
        await source.close();
      },
    );

    test(
      'initial snapshot timeout reports a stalled Firestore stream',
      () async {
        final source = StreamController<int>();

        await expectLater(
          source.stream
              .withInitialSnapshotTimeout(const Duration(milliseconds: 10))
              .first,
          throwsA(isA<TimeoutException>()),
        );
        await source.close();
      },
    );

    test(
      'a shared broadcast source does not replay its initial snapshot',
      () async {
        final source = StreamController<List<Room>>.broadcast();
        final stream = source.stream.withInitialSnapshotTimeout(
          const Duration(milliseconds: 20),
        );
        final firstValues = <List<Room>>[];
        final lateValues = <List<Room>>[];
        final lateErrors = <Object>[];
        final firstSubscription = stream.listen(firstValues.add);

        source.add(testRooms);
        await Future<void>.delayed(Duration.zero);
        final lateSubscription = stream.listen(
          lateValues.add,
          onError: lateErrors.add,
        );
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(firstValues, [testRooms]);
        expect(lateValues, isEmpty);
        expect(lateErrors.single, isA<TimeoutException>());
        await firstSubscription.cancel();
        await lateSubscription.cancel();
        await source.close();
      },
    );

    test(
      'independent room streams deliver data to a late second listener',
      () async {
        Stream<List<Room>> createStream() => Stream.value(
          testRooms,
        ).withInitialSnapshotTimeout(const Duration(milliseconds: 20));

        expect(await createStream().first, testRooms);
        await Future<void>.delayed(Duration.zero);
        expect(await createStream().first, testRooms);
      },
    );

    testWidgets(
      'creates one room stream per tab and keeps both after tab changes',
      (tester) async {
        var streamCreations = 0;
        var cancellations = 0;
        final controllers = <StreamController<List<Room>>>[];

        Stream<List<Room>> createStream() {
          streamCreations++;
          late StreamController<List<Room>> controller;
          controller = StreamController<List<Room>>.broadcast(
            onListen: () => scheduleMicrotask(() => controller.add(testRooms)),
            onCancel: () => cancellations++,
          );
          controllers.add(controller);
          return controller.stream;
        }

        await tester.pumpWidget(buildRoomAllocationScreen(createStream));
        await tester.pumpAndSettle();

        expect(streamCreations, 2);
        expect(find.text('P101'), findsOneWidget);
        expect(find.text('P202'), findsOneWidget);

        await tester.tap(find.text('Lịch phân bổ'));
        await tester.pumpAndSettle();
        expect(find.text('Chưa có lịch phân bổ nào.'), findsOneWidget);
        expect(find.textContaining('Chưa có phòng học.'), findsNothing);

        await tester.tap(find.text('Phòng học'));
        await tester.pumpAndSettle();
        expect(find.text('P101'), findsOneWidget);
        await tester.tap(find.text('Lịch phân bổ'));
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(cancellations, greaterThanOrEqualTo(2));
        for (final controller in controllers) {
          await controller.close();
        }
      },
    );

    testWidgets('retry cancels old room streams and loads new streams', (
      tester,
    ) async {
      var streamCreations = 0;
      var cancellations = 0;
      final controllers = <StreamController<List<Room>>>[];

      Stream<List<Room>> createStream() {
        final shouldFail = streamCreations < 2;
        streamCreations++;
        late StreamController<List<Room>> controller;
        controller = StreamController<List<Room>>.broadcast(
          onListen: () => scheduleMicrotask(() {
            if (shouldFail) {
              controller.addError(
                FirebaseException(
                  plugin: 'cloud_firestore',
                  code: 'unavailable',
                ),
              );
            } else {
              controller.add(testRooms);
            }
          }),
          onCancel: () => cancellations++,
        );
        controllers.add(controller);
        return controller.stream;
      }

      await tester.pumpWidget(buildRoomAllocationScreen(createStream));
      await tester.pumpAndSettle();
      expect(find.text('Thử lại'), findsOneWidget);

      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(streamCreations, 4);
      expect(cancellations, greaterThanOrEqualTo(1));
      expect(find.text('P101'), findsOneWidget);

      await tester.tap(find.text('Lịch phân bổ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa có phòng học.'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      for (final controller in controllers) {
        await controller.close();
      }
    });

    testWidgets('empty room streams show empty states in both tabs', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildRoomAllocationScreen(() => Stream.value(const <Room>[])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chưa có phòng học nào.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Lịch phân bổ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa có phòng học.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows an empty allocation state instead of loading forever', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RoomAllocationMessageState(
              icon: Icons.event_available_outlined,
              message: 'Chưa có lịch phân bổ nào.',
            ),
          ),
        ),
      );

      expect(find.text('Chưa có lịch phân bổ nào.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    test('maps Firestore query failures to actionable messages', () {
      expect(
        roomAllocationLoadErrorMessage(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
          'lịch phân bổ phòng',
        ),
        contains('Không có quyền'),
      );
      expect(
        roomAllocationLoadErrorMessage(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'failed-precondition',
          ),
          'lịch phân bổ phòng',
        ),
        contains('chỉ mục Firestore'),
      );
      expect(
        roomAllocationLoadErrorMessage(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          'lịch phân bổ phòng',
        ),
        contains('tạm thời không khả dụng'),
      );
      expect(
        roomAllocationLoadErrorMessage(
          TimeoutException('Firestore timeout'),
          'lịch phân bổ phòng',
        ),
        contains('không phản hồi'),
      );
    });

    testWidgets('retry action is available after an allocation load error', (
      tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomAllocationMessageState(
              icon: Icons.cloud_off_outlined,
              message: 'Không thể tải lịch phân bổ phòng.',
              onRetry: () => retries++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Thử lại'));
      expect(retries, 1);
    });

    test('validates room capacity', () {
      expect(
        RoomInput.tryParse(name: 'P101', capacity: '30', status: 'active'),
        isNotNull,
      );
      expect(
        RoomInput.tryParse(name: 'P101', capacity: '0', status: 'active'),
        isNull,
      );
      expect(
        RoomInput.tryParse(name: 'P101', capacity: '10.5', status: 'active'),
        isNull,
      );
    });

    test('validates allocation time range', () {
      expect(isValidTimeRange(1080, 1200), isTrue);
      expect(isValidTimeRange(1200, 1200), isFalse);
      expect(isValidTimeRange(-1, 1200), isFalse);
      expect(isValidTimeRange(1200, 1441), isFalse);
    });

    test('detects conflicts for the same room or class', () {
      const existing = RoomAllocation(
        id: 'allocation-1',
        roomId: 'room-1',
        classId: 'class-1',
        weekday: 1,
        startMinute: 1080,
        endMinute: 1200,
      );
      const sameRoom = RoomAllocationInput(
        roomId: 'room-1',
        classId: 'class-2',
        weekday: 1,
        startMinute: 1140,
        endMinute: 1260,
      );
      const sameClass = RoomAllocationInput(
        roomId: 'room-2',
        classId: 'class-1',
        weekday: 1,
        startMinute: 1140,
        endMinute: 1260,
      );

      expect(sameRoom.conflictsWith(existing), isTrue);
      expect(sameClass.conflictsWith(existing), isTrue);
    });

    test('allows adjacent schedules', () {
      expect(timeRangesOverlap(1080, 1200, 1200, 1320), isFalse);
    });

    test('refuses room and class deletion when allocations exist', () {
      const room = Room(
        id: 'room-1',
        name: 'P101',
        capacity: 30,
        status: 'active',
      );
      const englishClass = EnglishClass(
        id: 'class-1',
        name: 'IELTS A1',
        courseId: 'course-1',
        minStudents: 10,
        maxStudents: 20,
        status: 'pending',
      );

      expect(room.canDelete(hasAllocations: true), isFalse);
      expect(
        englishClass.canDeleteWithAllocations(hasAllocations: true),
        isFalse,
      );
      expect(room.canDelete(hasAllocations: false), isTrue);
      expect(
        englishClass.canDeleteWithAllocations(hasAllocations: false),
        isTrue,
      );
    });
  });

  group('Student and enrollment', () {
    test('student registration builds one UID-linked profile', () {
      final timestamp = Object();
      final profile = StudentRegistrationProfile.build(
        role: 'student',
        uid: 'student-uid',
        fullName: ' Nguyễn Văn An ',
        email: ' an@example.com ',
        timestamp: timestamp,
      );

      expect(
        StudentRegistrationProfile.documentId('student-uid'),
        'student-uid',
      );
      expect(profile, isNotNull);
      expect(profile!['fullName'], 'Nguyễn Văn An');
      expect(profile['email'], 'an@example.com');
      expect(profile['phone'], '');
      expect(profile['dateOfBirth'], isNull);
      expect(profile['gender'], isNull);
      expect(profile['consultationNote'], '');
      expect(profile['status'], 'active');
      expect(profile['userUid'], 'student-uid');
      expect(profile['createdAt'], same(timestamp));
      expect(profile['updatedAt'], same(timestamp));
    });

    test('staff registration does not build a student profile', () {
      for (final role in ['teacher', 'consultant']) {
        expect(
          StudentRegistrationProfile.build(
            role: role,
            uid: '$role-uid',
            fullName: 'Nhân sự Demo',
            email: '$role@example.com',
            timestamp: Object(),
          ),
          isNull,
        );
      }
    });

    test('student registration allows missing optional phone', () {
      expect(
        StudentInput.tryCreate(
          fullName: 'Nguyễn Văn An',
          email: 'an@example.com',
          phone: '',
          dateOfBirth: null,
          gender: null,
          consultationNote: '',
          status: 'active',
          userUid: 'student-uid',
        ),
        isNotNull,
      );
    });

    test('detects a second profile linked to the same account', () {
      expect(StudentLinkPolicy.hasDuplicate(['student-1']), isTrue);
      expect(
        StudentLinkPolicy.hasDuplicate([
          'student-1',
        ], excludedStudentId: 'student-1'),
        isFalse,
      );
    });

    test('validates required student data, email and phone', () {
      expect(
        StudentInput.tryCreate(
          fullName: 'Nguyễn Văn An',
          email: 'an@example.com',
          phone: '0901 234 567',
          dateOfBirth: null,
          gender: null,
          consultationNote: '',
          status: 'active',
          userUid: '',
        ),
        isNotNull,
      );
      expect(
        StudentInput.tryCreate(
          fullName: '',
          email: 'invalid-email',
          phone: '123',
          dateOfBirth: null,
          gender: null,
          consultationNote: '',
          status: 'active',
          userUid: '',
        ),
        isNull,
      );
    });

    test('rejects an active duplicate enrollment', () {
      expect(
        EnrollmentPolicy.registrationError(
          studentActive: true,
          classStatus: 'pending',
          activeCount: 5,
          maxStudents: 20,
          alreadyActive: true,
        ),
        isNotNull,
      );
    });

    test('new active student can register for a pending class', () {
      expect(
        EnrollmentPolicy.registrationError(
          studentActive: true,
          classStatus: 'pending',
          activeCount: 0,
          maxStudents: 20,
          alreadyActive: false,
        ),
        isNull,
      );
    });

    test('rejects enrollment when class capacity is full', () {
      expect(
        EnrollmentPolicy.registrationError(
          studentActive: true,
          classStatus: 'pending',
          activeCount: 20,
          maxStudents: 20,
          alreadyActive: false,
        ),
        isNotNull,
      );
    });

    test('rejects enrollment into ongoing or completed classes', () {
      for (final status in ['ongoing', 'completed']) {
        expect(
          EnrollmentPolicy.registrationError(
            studentActive: true,
            classStatus: status,
            activeCount: 0,
            maxStudents: 20,
            alreadyActive: false,
          ),
          isNotNull,
        );
      }
    });

    test('keeps cancelled enrollment as history', () {
      const active = Enrollment(
        id: 'class-1_student-1',
        studentId: 'student-1',
        classId: 'class-1',
        status: 'active',
      );
      const cancelled = Enrollment(
        id: 'class-1_student-1',
        studentId: 'student-1',
        classId: 'class-1',
        status: 'cancelled',
      );

      expect(active.canCancel, isTrue);
      expect(cancelled.canCancel, isFalse);
      expect(cancelled.statusLabel, 'Đã hủy');
    });

    test('rejects class deletion with active enrollments', () {
      expect(
        EnrollmentPolicy.canDeleteClass(
          classPending: true,
          hasRoomAllocations: false,
          hasActiveEnrollments: true,
        ),
        isFalse,
      );
    });

    test('rejects reducing max students below active count', () {
      expect(
        EnrollmentPolicy.canReduceCapacity(newMaxStudents: 14, activeCount: 15),
        isFalse,
      );
      expect(
        EnrollmentPolicy.canReduceCapacity(newMaxStudents: 15, activeCount: 15),
        isTrue,
      );
    });
  });

  group('Teacher and teaching assignment', () {
    test('validates required teacher data, email and phone', () {
      expect(
        TeacherInput.tryCreate(
          fullName: 'Nguyễn Minh Anh',
          email: 'minhanh@example.com',
          phone: '0901 234 567',
          specialty: 'IELTS',
          status: 'active',
          userUid: 'teacher-user-1',
        ),
        isNotNull,
      );
      expect(
        TeacherInput.tryCreate(
          fullName: '',
          email: 'invalid-email',
          phone: '123',
          specialty: '',
          status: 'active',
          userUid: '',
        ),
        isNull,
      );
    });

    test('blocks an inactive teacher', () {
      expect(
        TeacherAssignmentPolicy.assignmentError(
          teacherActive: false,
          teacherLinked: true,
          linkedUserActive: true,
          classStatus: 'pending',
        ),
        isNotNull,
      );
    });

    test('blocks assignment to a completed class', () {
      expect(
        TeacherAssignmentPolicy.assignmentError(
          teacherActive: true,
          teacherLinked: true,
          linkedUserActive: true,
          classStatus: 'completed',
        ),
        isNotNull,
      );
    });

    test('uses the class id as the single current assignment document', () {
      expect(TeacherAssignment.documentId('class-1'), 'class-1');
      expect(TeacherAssignment.documentId('class-1'), isNot('teacher-1'));
    });

    test('detects overlapping teaching schedules', () {
      const target = RoomAllocation(
        id: 'allocation-1',
        roomId: 'room-1',
        classId: 'class-1',
        weekday: 2,
        startMinute: 480,
        endMinute: 600,
      );
      const other = RoomAllocation(
        id: 'allocation-2',
        roomId: 'room-2',
        classId: 'class-2',
        weekday: 2,
        startMinute: 540,
        endMinute: 660,
      );

      expect(
        TeacherAssignmentPolicy.schedulesOverlap([target], [other]),
        isTrue,
      );
    });

    test('allows adjacent teaching schedules', () {
      const target = RoomAllocation(
        id: 'allocation-1',
        roomId: 'room-1',
        classId: 'class-1',
        weekday: 2,
        startMinute: 480,
        endMinute: 600,
      );
      const adjacent = RoomAllocation(
        id: 'allocation-2',
        roomId: 'room-2',
        classId: 'class-2',
        weekday: 2,
        startMinute: 600,
        endMinute: 720,
      );

      expect(
        TeacherAssignmentPolicy.schedulesOverlap([target], [adjacent]),
        isFalse,
      );
    });

    test('does not allow a teacher to manage assignments', () {
      expect(TeacherAssignmentPolicy.canManage(isAdmin: false), isFalse);
      expect(TeacherAssignmentPolicy.canManage(isAdmin: true), isTrue);
    });
  });

  group('Attendance and learning results', () {
    test('rejects scores outside the 0 to 10 range', () {
      expect(LearningResultInput.validateScore('-0.1'), isNotNull);
      expect(LearningResultInput.validateScore('10.1'), isNotNull);
      expect(LearningResultInput.validateScore('NaN'), isNotNull);
      expect(LearningResultInput.validateScore('Infinity'), isNotNull);
      expect(LearningResultInput.validateScore('7.5'), isNull);
    });

    test('uses one attendance session id for the same class and date', () {
      final morning = AttendanceSession.dateKeyFromDate(
        DateTime(2026, 10, 15, 8),
      );
      final evening = AttendanceSession.dateKeyFromDate(
        DateTime(2026, 10, 15, 20),
      );

      expect(morning, evening);
      expect(
        AttendanceSession.documentId('class-1', morning),
        AttendanceSession.documentId('class-1', evening),
      );
    });

    test('blocks attendance for a student without active enrollment', () {
      expect(
        AttendancePolicy.canRecordStudent(hasActiveEnrollment: false),
        isFalse,
      );
      expect(
        AttendancePolicy.canRecordStudent(hasActiveEnrollment: true),
        isTrue,
      );
    });

    test('only assigned teacher can manage an ongoing class', () {
      expect(
        AttendancePolicy.canManageClass(
          isAssignedTeacher: false,
          classStatus: 'ongoing',
        ),
        isFalse,
      );
      expect(
        AttendancePolicy.canManageClass(
          isAssignedTeacher: true,
          classStatus: 'pending',
        ),
        isFalse,
      );
      expect(
        AttendancePolicy.canManageClass(
          isAssignedTeacher: true,
          classStatus: 'ongoing',
        ),
        isTrue,
      );
    });

    test('student can only view their own result', () {
      expect(
        LearningResultPolicy.canStudentView(
          profileStudentId: 'student-1',
          resultStudentId: 'student-2',
        ),
        isFalse,
      );
      expect(
        LearningResultPolicy.canStudentView(
          profileStudentId: 'student-1',
          resultStudentId: 'student-1',
        ),
        isTrue,
      );
    });

    test('distinguishes a missing score from score zero', () {
      final input = LearningResultInput.tryCreate(
        studentId: 'student-1',
        midtermScore: '',
        finalScore: '0',
        comment: '',
      );

      expect(input, isNotNull);
      expect(input!.midtermScore, isNull);
      expect(input.finalScore, 0);
      expect(LearningResult.scoreLabel(null), 'Chưa nhập');
      expect(LearningResult.scoreLabel(0), '0');
    });

    test('counts attendance statuses correctly', () {
      const records = [
        AttendanceRecord(
          id: 'session_student-1',
          sessionId: 'session',
          classId: 'class-1',
          studentId: 'student-1',
          status: 'present',
        ),
        AttendanceRecord(
          id: 'session_student-1',
          sessionId: 'session',
          classId: 'class-1',
          studentId: 'student-1',
          status: 'present',
        ),
        AttendanceRecord(
          id: 'session_student-1',
          sessionId: 'session',
          classId: 'class-1',
          studentId: 'student-1',
          status: 'absent',
        ),
        AttendanceRecord(
          id: 'session_student-1',
          sessionId: 'session',
          classId: 'class-1',
          studentId: 'student-1',
          status: 'excused',
        ),
      ];

      final stats = AttendanceStats.fromRecords(records);
      expect(stats.present, 2);
      expect(stats.absent, 1);
      expect(stats.excused, 1);
      expect(stats.total, 4);
    });
  });
}
