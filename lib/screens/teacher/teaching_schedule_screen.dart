import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../models/english_class.dart';
import '../../models/room.dart';
import '../../models/room_allocation.dart';
import '../../models/teacher.dart';
import '../../models/teacher_assignment.dart';
import '../../services/teacher_assignment_service.dart';
import '../../services/teacher_service.dart';

class TeachingScheduleScreen extends StatefulWidget {
  const TeachingScheduleScreen({super.key});

  @override
  State<TeachingScheduleScreen> createState() => _TeachingScheduleScreenState();
}

class _TeachingScheduleScreenState extends State<TeachingScheduleScreen> {
  late final String? _userUid;
  Stream<List<Teacher>>? _profileStream;
  Stream<List<TeacherAssignment>>? _assignmentStream;

  @override
  void initState() {
    super.initState();
    _userUid = FirebaseAuth.instance.currentUser?.uid;
    final userUid = _userUid;
    if (userUid != null) {
      _profileStream = TeacherService.instance.watchOwnProfile(userUid);
      _assignmentStream = TeacherAssignmentService.instance
          .watchAssignmentsForTeacher(userUid);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userUid == null) {
      return const _TeacherMessage(
        icon: Icons.lock_outline,
        message: 'Phiên đăng nhập không còn hợp lệ.',
      );
    }
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Lịch dạy của tôi',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text('Danh sách lớp và lịch học đã được Admin phân công.'),
          const SizedBox(height: 20),
          Expanded(
            child: StreamBuilder<List<Teacher>>(
              stream: _profileStream,
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (profileSnapshot.hasError) {
                  return const _TeacherMessage(
                    icon: Icons.cloud_off_outlined,
                    message: 'Không thể tải hồ sơ giáo viên.',
                  );
                }
                final profiles = profileSnapshot.data ?? const <Teacher>[];
                if (profiles.isEmpty) {
                  return const _TeacherMessage(
                    icon: Icons.link_off_outlined,
                    message:
                        'Tài khoản chưa được liên kết với hồ sơ giáo viên.',
                  );
                }
                if (!profiles.first.isActive) {
                  return const _TeacherMessage(
                    icon: Icons.person_off_outlined,
                    message: 'Hồ sơ giáo viên đã ngừng hoạt động.',
                  );
                }
                return StreamBuilder<List<TeacherAssignment>>(
                  stream: _assignmentStream,
                  builder: (context, assignmentSnapshot) {
                    if (assignmentSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (assignmentSnapshot.hasError) {
                      return const _TeacherMessage(
                        icon: Icons.cloud_off_outlined,
                        message: 'Không thể tải phân công giảng dạy.',
                      );
                    }
                    final assignments =
                        assignmentSnapshot.data ?? const <TeacherAssignment>[];
                    if (assignments.isEmpty) {
                      return const _TeacherMessage(
                        icon: Icons.event_available_outlined,
                        message: 'Bạn chưa được phân công lớp học nào.',
                      );
                    }
                    return ListView.separated(
                      itemCount: assignments.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _TeachingClassCard(assignment: assignments[index]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TeachingClassCard extends StatefulWidget {
  const _TeachingClassCard({required this.assignment});

  final TeacherAssignment assignment;

  @override
  State<_TeachingClassCard> createState() => _TeachingClassCardState();
}

class _TeachingClassCardState extends State<_TeachingClassCard> {
  late final Future<_TeachingClassData> _details;
  late final Stream<List<RoomAllocation>> _schedule;

  @override
  void initState() {
    super.initState();
    _details = _loadDetails();
    _schedule = TeacherAssignmentService.instance.watchClassSchedule(
      widget.assignment.classId,
    );
  }

  Future<_TeachingClassData> _loadDetails() async {
    final englishClass = await TeacherAssignmentService.instance
        .getAssignedClass(widget.assignment.classId);
    final course = await TeacherAssignmentService.instance.getCourse(
      englishClass.courseId,
    );
    return _TeachingClassData(englishClass: englishClass, course: course);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<_TeachingClassData>(
          future: _details,
          builder: (context, detailSnapshot) {
            if (detailSnapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            if (detailSnapshot.hasError || detailSnapshot.data == null) {
              return const Text('Không thể tải thông tin lớp học.');
            }
            final details = detailSnapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      details.englishClass.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Chip(label: Text(details.englishClass.statusLabel)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Khóa học: ${details.course.name}'),
                const Divider(height: 28),
                Text(
                  'Lịch học hằng tuần',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<RoomAllocation>>(
                  stream: _schedule,
                  builder: (context, scheduleSnapshot) {
                    if (scheduleSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (scheduleSnapshot.hasError) {
                      return const Text('Không thể tải lịch học và phòng học.');
                    }
                    final schedules =
                        scheduleSnapshot.data ?? const <RoomAllocation>[];
                    if (schedules.isEmpty) {
                      return const Text('Lớp chưa có lịch học.');
                    }
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: schedules
                          .map(
                            (allocation) =>
                                _ScheduleTile(allocation: allocation),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ScheduleTile extends StatefulWidget {
  const _ScheduleTile({required this.allocation});

  final RoomAllocation allocation;

  @override
  State<_ScheduleTile> createState() => _ScheduleTileState();
}

class _ScheduleTileState extends State<_ScheduleTile> {
  late final Future<Room> _room;

  @override
  void initState() {
    super.initState();
    _room = TeacherAssignmentService.instance.getRoom(widget.allocation.roomId);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.allocation.weekdayLabel} · ${widget.allocation.timeLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                FutureBuilder<Room>(
                  future: _room,
                  builder: (context, snapshot) => Text(
                    snapshot.hasData
                        ? 'Phòng: ${snapshot.data!.name}'
                        : snapshot.hasError
                        ? 'Không tải được phòng'
                        : 'Đang tải phòng…',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeachingClassData {
  const _TeachingClassData({required this.englishClass, required this.course});

  final EnglishClass englishClass;
  final Course course;
}

class _TeacherMessage extends StatelessWidget {
  const _TeacherMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
