import 'package:flutter/material.dart';

import '../../models/class_registration_request.dart';
import '../../models/course.dart';
import '../../models/english_class.dart';
import '../../models/enrollment.dart';
import '../../models/student.dart';
import '../../services/class_registration_service.dart';
import '../../services/class_service.dart';
import '../../services/course_service.dart';
import '../../services/enrollment_service.dart';
import '../../services/student_service.dart';
import '../student/class_registration_screen.dart';

class RegistrationApprovalScreen extends StatefulWidget {
  const RegistrationApprovalScreen({super.key});

  @override
  State<RegistrationApprovalScreen> createState() =>
      _RegistrationApprovalScreenState();
}

class _RegistrationApprovalScreenState
    extends State<RegistrationApprovalScreen> {
  final _selectedClassIds = <String, String>{};
  var _working = false;

  void _message(String value, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _process(
    ClassRegistrationRequest request,
    EnglishClass englishClass,
  ) async {
    setState(() => _working = true);
    try {
      if (request.status == 'pending' &&
          englishClass.id != request.requestedClassId) {
        await ClassRegistrationService.instance.proposeAlternative(
          request,
          englishClass,
        );
        if (mounted) {
          _message('Đã gửi lớp thay thế để học viên xác nhận.');
        }
      } else {
        await ClassRegistrationService.instance.approve(request, englishClass);
        if (mounted) _message('Đã xác nhận và xếp lớp cho học viên.');
      }
    } catch (error) {
      if (mounted) {
        _message(
          error is StateError
              ? error.message.toString()
              : 'Không thể xử lý yêu cầu đăng ký.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _reject(ClassRegistrationRequest request) async {
    setState(() => _working = true);
    try {
      await ClassRegistrationService.instance.reject(request, byStudent: false);
      if (mounted) _message('Đã từ chối yêu cầu đăng ký.');
    } catch (_) {
      if (mounted) _message('Không thể từ chối yêu cầu.', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClassRegistrationRequest>>(
      stream: ClassRegistrationService.instance.watchRequests(),
      builder: (context, requestSnapshot) => StreamBuilder<List<EnglishClass>>(
        stream: ClassService.instance.watchClasses(),
        builder: (context, classSnapshot) => StreamBuilder<List<Course>>(
          stream: CourseService.instance.watchCourses(),
          builder: (context, courseSnapshot) => StreamBuilder<List<Student>>(
            stream: StudentService.instance.watchStudents(),
            builder: (context, studentSnapshot) =>
                StreamBuilder<List<Enrollment>>(
                  stream: EnrollmentService.instance.watchEnrollments(),
                  builder: (context, enrollmentSnapshot) {
                    final snapshots = [
                      requestSnapshot,
                      classSnapshot,
                      courseSnapshot,
                      studentSnapshot,
                      enrollmentSnapshot,
                    ];
                    if (snapshots.any((item) => item.hasError)) {
                      return const Center(
                        child: Text('Không thể tải yêu cầu đăng ký.'),
                      );
                    }
                    if (snapshots.any((item) => !item.hasData)) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _buildContent(
                      requestSnapshot.data!,
                      classSnapshot.data!,
                      courseSnapshot.data!,
                      studentSnapshot.data!,
                      enrollmentSnapshot.data!,
                    );
                  },
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    List<ClassRegistrationRequest> requests,
    List<EnglishClass> classes,
    List<Course> courses,
    List<Student> students,
    List<Enrollment> enrollments,
  ) {
    final openRequests = requests.where((item) => item.isOpen).toList();
    final classById = {for (final item in classes) item.id: item};
    final courseById = {for (final item in courses) item.id: item};
    final studentById = {for (final item in students) item.id: item};
    final activeCounts = <String, int>{};
    for (final enrollment in enrollments.where((item) => item.isActive)) {
      activeCounts.update(
        enrollment.classId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Xét duyệt đăng ký lớp học',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: openRequests.isEmpty
                ? const Center(child: Text('Không có yêu cầu chờ xử lý.'))
                : ListView.separated(
                    itemCount: openRequests.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final request = openRequests[index];
                      final requestedClass =
                          classById[request.requestedClassId];
                      if (requestedClass == null) {
                        return const Card(
                          child: ListTile(
                            title: Text('Lớp học đã chọn không còn tồn tại.'),
                          ),
                        );
                      }
                      final sameCourseClasses = classes
                          .where(
                            (item) =>
                                item.courseId == requestedClass.courseId &&
                                item.status == 'pending' &&
                                item.hasConfiguredSchedule,
                          )
                          .toList();
                      final fixedClassId = request.status == 'pending'
                          ? null
                          : request.assignedClassId;
                      final selectedId =
                          fixedClassId ??
                          _selectedClassIds.putIfAbsent(
                            request.id,
                            () => request.requestedClassId,
                          );
                      final selectedClass = classById[selectedId];
                      final course = selectedClass == null
                          ? null
                          : courseById[selectedClass.courseId];
                      final remaining = selectedClass == null
                          ? 0
                          : ClassRegistrationPolicy.remainingSlots(
                              maxStudents: selectedClass.maxStudents,
                              activeEnrollments:
                                  activeCounts[selectedClass.id] ?? 0,
                            );
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                studentById[request.studentId]?.fullName ??
                                    'Học viên không tồn tại',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(request.statusLabel),
                              const SizedBox(height: 12),
                              if (request.status == 'pending')
                                DropdownButtonFormField<String>(
                                  initialValue: selectedId,
                                  decoration: const InputDecoration(
                                    labelText: 'Lớp phân bổ',
                                  ),
                                  items: sameCourseClasses
                                      .map(
                                        (item) => DropdownMenuItem(
                                          value: item.id,
                                          child: Text(
                                            '${item.name} · ${item.studyPatternLabel} · ${item.shiftLabel}',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _working
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            setState(
                                              () =>
                                                  _selectedClassIds[request
                                                          .id] =
                                                      value,
                                            );
                                          }
                                        },
                                ),
                              if (request.status ==
                                  'awaiting_student_confirmation')
                                const Text(
                                  'Đang chờ học viên xác nhận lớp thay thế.',
                                ),
                              if (selectedClass != null && course != null) ...[
                                const SizedBox(height: 12),
                                RegistrationClassDetails(
                                  course: course,
                                  englishClass: selectedClass,
                                  remainingSlots: remaining,
                                  roomLabel: 'Xem tại phân bổ phòng học',
                                ),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: _working
                                        ? null
                                        : () => _reject(request),
                                    child: const Text('Từ chối'),
                                  ),
                                  if (request.status !=
                                          'awaiting_student_confirmation' &&
                                      selectedClass != null)
                                    FilledButton(
                                      onPressed: _working || remaining <= 0
                                          ? null
                                          : () => _process(
                                              request,
                                              selectedClass,
                                            ),
                                      child: Text(
                                        request.status == 'pending' &&
                                                selectedClass.id !=
                                                    request.requestedClassId
                                            ? 'Gửi lớp thay thế'
                                            : 'Xác nhận xếp lớp',
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
