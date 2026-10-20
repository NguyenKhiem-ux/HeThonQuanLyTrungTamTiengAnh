import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/class_registration_request.dart';
import '../../models/course.dart';
import '../../models/english_class.dart';
import '../../models/enrollment.dart';
import '../../models/room.dart';
import '../../models/room_allocation.dart';
import '../../models/student.dart';
import '../../services/class_registration_service.dart';
import '../../services/class_service.dart';
import '../../services/course_service.dart';
import '../../services/enrollment_service.dart';
import '../../services/room_allocation_service.dart';
import '../../services/room_service.dart';
import '../../services/student_service.dart';

class ClassRegistrationScreen extends StatefulWidget {
  const ClassRegistrationScreen({super.key});

  @override
  State<ClassRegistrationScreen> createState() =>
      _ClassRegistrationScreenState();
}

class _ClassRegistrationScreenState extends State<ClassRegistrationScreen> {
  var _patternFilter = 'all';
  var _shiftFilter = 'all';
  var _working = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _message(String value, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _submit(Student student, EnglishClass englishClass) async {
    setState(() => _working = true);
    try {
      await ClassRegistrationService.instance.submit(
        student: student,
        studentUid: _uid,
        englishClass: englishClass,
      );
      if (mounted) _message('Đã gửi yêu cầu đăng ký.');
    } catch (error) {
      if (mounted) {
        _message(
          error is StateError
              ? error.message.toString()
              : 'Không thể gửi yêu cầu đăng ký.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _respondToAlternative(
    ClassRegistrationRequest request, {
    required bool accept,
  }) async {
    setState(() => _working = true);
    try {
      if (accept) {
        await ClassRegistrationService.instance.confirmAlternative(request);
      } else {
        await ClassRegistrationService.instance.reject(
          request,
          byStudent: true,
        );
      }
      if (mounted) {
        _message(accept ? 'Đã xác nhận lớp thay thế.' : 'Đã từ chối đề xuất.');
      }
    } catch (error) {
      if (mounted) {
        _message(
          error is StateError
              ? error.message.toString()
              : 'Không thể cập nhật yêu cầu.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      return const Center(child: Text('Vui lòng đăng nhập lại.'));
    }
    return StreamBuilder<List<Student>>(
      stream: StudentService.instance.watchOwnProfile(_uid),
      builder: (context, studentSnapshot) {
        if (!studentSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final profiles = studentSnapshot.data!;
        if (profiles.isEmpty) {
          return const Center(child: Text('Không tìm thấy hồ sơ học viên.'));
        }
        return _buildCourseData(profiles.first);
      },
    );
  }

  Widget _buildCourseData(Student student) {
    return StreamBuilder<List<Course>>(
      stream: CourseService.instance.watchCourses(),
      builder: (context, courseSnapshot) => StreamBuilder<List<EnglishClass>>(
        stream: ClassService.instance.watchClasses(),
        builder: (context, classSnapshot) => StreamBuilder<List<Enrollment>>(
          stream: EnrollmentService.instance.watchEnrollments(),
          builder: (context, enrollmentSnapshot) =>
              StreamBuilder<List<ClassRegistrationRequest>>(
                stream: ClassRegistrationService.instance
                    .watchRequestsForStudent(_uid),
                builder: (context, requestSnapshot) =>
                    StreamBuilder<List<RoomAllocation>>(
                      stream: RoomAllocationService.instance.watchAllocations(),
                      builder: (context, allocationSnapshot) =>
                          StreamBuilder<List<Room>>(
                            stream: RoomService.instance.watchRooms(),
                            builder: (context, roomSnapshot) {
                              final snapshots = [
                                courseSnapshot,
                                classSnapshot,
                                enrollmentSnapshot,
                                requestSnapshot,
                                allocationSnapshot,
                                roomSnapshot,
                              ];
                              if (snapshots.any((item) => item.hasError)) {
                                return const Center(
                                  child: Text(
                                    'Không thể tải danh sách lớp học.',
                                  ),
                                );
                              }
                              if (snapshots.any((item) => !item.hasData)) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              return _buildContent(
                                student,
                                courseSnapshot.data!,
                                classSnapshot.data!,
                                enrollmentSnapshot.data!,
                                requestSnapshot.data!,
                                allocationSnapshot.data!,
                                roomSnapshot.data!,
                              );
                            },
                          ),
                    ),
              ),
        ),
      ),
    );
  }

  Widget _buildContent(
    Student student,
    List<Course> courses,
    List<EnglishClass> classes,
    List<Enrollment> enrollments,
    List<ClassRegistrationRequest> requests,
    List<RoomAllocation> allocations,
    List<Room> rooms,
  ) {
    final courseById = {for (final item in courses) item.id: item};
    final classById = {for (final item in classes) item.id: item};
    final roomById = {for (final item in rooms) item.id: item.name};
    final activeCounts = <String, int>{};
    for (final enrollment in enrollments.where((item) => item.isActive)) {
      activeCounts.update(
        enrollment.classId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final openRequest = requests.where((item) => item.isOpen).firstOrNull;
    final availableClasses = classes.where((item) {
      if (item.status != 'pending') return false;
      if (_patternFilter != 'all' && item.studyPattern != _patternFilter) {
        return false;
      }
      return _shiftFilter == 'all' || item.shiftCode == _shiftFilter;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Đăng ký lớp học',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  initialValue: _patternFilter,
                  decoration: const InputDecoration(labelText: 'Lịch học'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                    DropdownMenuItem(value: '246', child: Text('Lịch 246')),
                    DropdownMenuItem(value: '357', child: Text('Lịch 357')),
                  ],
                  onChanged: (value) =>
                      setState(() => _patternFilter = value ?? 'all'),
                ),
              ),
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  initialValue: _shiftFilter,
                  decoration: const InputDecoration(labelText: 'Ca học'),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                    ...ClassShift.values.map(
                      (shift) => DropdownMenuItem(
                        value: shift.code,
                        child: Text(shift.label),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _shiftFilter = value ?? 'all'),
                ),
              ),
            ],
          ),
          if (openRequest != null) ...[
            const SizedBox(height: 16),
            _buildOpenRequest(
              openRequest,
              classById,
              courseById,
              activeCounts,
              allocations,
              roomById,
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: availableClasses.isEmpty
                ? const Center(child: Text('Không có lớp phù hợp.'))
                : ListView.separated(
                    itemCount: availableClasses.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final englishClass = availableClasses[index];
                      final course = courseById[englishClass.courseId];
                      if (course == null) return const SizedBox.shrink();
                      final activeCount = activeCounts[englishClass.id] ?? 0;
                      final remaining = ClassRegistrationPolicy.remainingSlots(
                        maxStudents: englishClass.maxStudents,
                        activeEnrollments: activeCount,
                      );
                      final isEnrolled = enrollments.any(
                        (item) =>
                            item.isActive &&
                            item.studentId == student.id &&
                            item.classId == englishClass.id,
                      );
                      final classRequest = _latestRequestForClass(
                        requests,
                        englishClass.id,
                      );
                      final error = ClassRegistrationPolicy.requestError(
                        studentActive: student.isActive,
                        classStatus: englishClass.status,
                        hasSchedule: englishClass.hasConfiguredSchedule,
                        remainingSlots: remaining,
                        hasOpenRequest: openRequest != null,
                      );
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              RegistrationClassDetails(
                                course: course,
                                englishClass: englishClass,
                                remainingSlots: remaining,
                                roomLabel: _roomLabel(
                                  englishClass.id,
                                  allocations,
                                  roomById,
                                ),
                              ),
                              if (classRequest != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Trạng thái đăng ký: ${classRequest.statusLabel}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.icon(
                                  onPressed:
                                      _working || error != null || isEnrolled
                                      ? null
                                      : () => _submit(student, englishClass),
                                  icon: const Icon(Icons.send_outlined),
                                  label: Text(
                                    isEnrolled
                                        ? 'Đã xếp lớp'
                                        : error ?? 'Gửi yêu cầu',
                                  ),
                                ),
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

  Widget _buildOpenRequest(
    ClassRegistrationRequest request,
    Map<String, EnglishClass> classById,
    Map<String, Course> courseById,
    Map<String, int> activeCounts,
    List<RoomAllocation> allocations,
    Map<String, String> roomById,
  ) {
    final englishClass = classById[request.targetClassId];
    final course = englishClass == null
        ? null
        : courseById[englishClass.courseId];
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              request.statusLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (englishClass != null && course != null) ...[
              const SizedBox(height: 10),
              RegistrationClassDetails(
                course: course,
                englishClass: englishClass,
                remainingSlots: ClassRegistrationPolicy.remainingSlots(
                  maxStudents: englishClass.maxStudents,
                  activeEnrollments: activeCounts[englishClass.id] ?? 0,
                ),
                roomLabel: _roomLabel(englishClass.id, allocations, roomById),
              ),
            ],
            if (request.needsStudentConfirmation) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => _respondToAlternative(request, accept: false),
                    child: const Text('Từ chối'),
                  ),
                  FilledButton(
                    onPressed: _working
                        ? null
                        : () => _respondToAlternative(request, accept: true),
                    child: const Text('Xác nhận lớp này'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

ClassRegistrationRequest? _latestRequestForClass(
  List<ClassRegistrationRequest> requests,
  String classId,
) {
  for (final request in requests) {
    if (request.requestedClassId == classId ||
        request.assignedClassId == classId) {
      return request;
    }
  }
  return null;
}

class RegistrationClassDetails extends StatelessWidget {
  const RegistrationClassDetails({
    super.key,
    required this.course,
    required this.englishClass,
    required this.remainingSlots,
    required this.roomLabel,
  });

  final Course course;
  final EnglishClass englishClass;
  final int remainingSlots;
  final String roomLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(course.name, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Lớp: ${englishClass.name}'),
        Text('Học phí: ${_formatMoney(course.standardTuition)} VNĐ'),
        Text('Thời lượng: ${course.durationLabel}'),
        Text(englishClass.studyPatternLabel),
        Text(englishClass.shiftLabel),
        Text('Sĩ số còn lại: $remainingSlots'),
        Text('Phòng: $roomLabel'),
      ],
    );
  }
}

String _roomLabel(
  String classId,
  List<RoomAllocation> allocations,
  Map<String, String> roomById,
) {
  final roomNames = allocations
      .where((item) => item.classId == classId)
      .map((item) => roomById[item.roomId] ?? 'Phòng không tồn tại')
      .toSet();
  return roomNames.isEmpty ? 'Chưa phân phòng' : roomNames.join(', ');
}

String _formatMoney(num value) {
  final digits = value.toStringAsFixed(0);
  return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
}
