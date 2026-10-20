import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/attendance_record.dart';
import '../../models/attendance_session.dart';
import '../../models/course.dart';
import '../../models/english_class.dart';
import '../../models/enrollment.dart';
import '../../models/learning_result.dart';
import '../../models/student.dart';
import '../../services/attendance_service.dart';
import '../../services/enrollment_service.dart';
import '../../services/learning_result_service.dart';
import '../../services/student_service.dart';

class LearningResultScreen extends StatefulWidget {
  const LearningResultScreen({super.key});

  @override
  State<LearningResultScreen> createState() => _LearningResultScreenState();
}

class _LearningResultScreenState extends State<LearningResultScreen> {
  late final String? _userUid;
  Stream<List<Student>>? _profile;
  String? _loadedStudentId;
  Stream<List<Enrollment>>? _enrollments;
  Stream<List<LearningResult>>? _results;
  Stream<List<AttendanceRecord>>? _records;

  @override
  void initState() {
    super.initState();
    _userUid = FirebaseAuth.instance.currentUser?.uid;
    final userUid = _userUid;
    if (userUid != null) {
      _profile = StudentService.instance.watchOwnProfile(userUid);
    }
  }

  void _loadStudent(String studentId) {
    if (_loadedStudentId == studentId) return;
    _loadedStudentId = studentId;
    _enrollments = EnrollmentService.instance.watchEnrollmentsForStudent(
      studentId,
    );
    _results = LearningResultService.instance.watchResultsForStudent(studentId);
    _records = AttendanceService.instance.watchRecordsForStudent(studentId);
  }

  @override
  Widget build(BuildContext context) {
    if (_userUid == null) {
      return const _StudentResultMessage(
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
            'Kết quả học tập',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text('Điểm, nhận xét và lịch sử chuyên cần của bạn.'),
          const SizedBox(height: 20),
          Expanded(
            child: StreamBuilder<List<Student>>(
              stream: _profile,
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (profileSnapshot.hasError) {
                  return const _StudentResultMessage(
                    icon: Icons.cloud_off_outlined,
                    message: 'Không thể tải hồ sơ học viên.',
                  );
                }
                final profiles = profileSnapshot.data ?? const <Student>[];
                if (profiles.isEmpty) {
                  return const _StudentResultMessage(
                    icon: Icons.link_off_outlined,
                    message: 'Tài khoản chưa được liên kết với hồ sơ học viên.',
                  );
                }
                _loadStudent(profiles.first.id);
                return _buildStudentData();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentData() {
    return StreamBuilder<List<Enrollment>>(
      stream: _enrollments,
      builder: (context, enrollmentSnapshot) {
        if (enrollmentSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (enrollmentSnapshot.hasError) {
          return const _StudentResultMessage(
            icon: Icons.cloud_off_outlined,
            message: 'Không thể tải danh sách lớp đã đăng ký.',
          );
        }
        final enrollments = enrollmentSnapshot.data ?? const <Enrollment>[];
        if (enrollments.isEmpty) {
          return const _StudentResultMessage(
            icon: Icons.class_outlined,
            message: 'Bạn chưa đăng ký lớp học nào.',
          );
        }
        return StreamBuilder<List<LearningResult>>(
          stream: _results,
          builder: (context, resultSnapshot) {
            if (resultSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (resultSnapshot.hasError) {
              return const _StudentResultMessage(
                icon: Icons.cloud_off_outlined,
                message: 'Không thể tải điểm và nhận xét.',
              );
            }
            return StreamBuilder<List<AttendanceRecord>>(
              stream: _records,
              builder: (context, recordSnapshot) {
                if (recordSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (recordSnapshot.hasError) {
                  return const _StudentResultMessage(
                    icon: Icons.cloud_off_outlined,
                    message: 'Không thể tải lịch sử điểm danh.',
                  );
                }
                final resultByClass = {
                  for (final result
                      in resultSnapshot.data ?? const <LearningResult>[])
                    result.classId: result,
                };
                final recordsByClass = <String, List<AttendanceRecord>>{};
                for (final record
                    in recordSnapshot.data ?? const <AttendanceRecord>[]) {
                  recordsByClass
                      .putIfAbsent(record.classId, () => [])
                      .add(record);
                }
                return ListView.separated(
                  itemCount: enrollments.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final enrollment = enrollments[index];
                    return _StudentClassResultCard(
                      key: ValueKey(enrollment.id),
                      enrollment: enrollment,
                      result: resultByClass[enrollment.classId],
                      records:
                          recordsByClass[enrollment.classId] ??
                          const <AttendanceRecord>[],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _StudentClassResultCard extends StatefulWidget {
  const _StudentClassResultCard({
    super.key,
    required this.enrollment,
    required this.result,
    required this.records,
  });

  final Enrollment enrollment;
  final LearningResult? result;
  final List<AttendanceRecord> records;

  @override
  State<_StudentClassResultCard> createState() =>
      _StudentClassResultCardState();
}

class _StudentClassResultCardState extends State<_StudentClassResultCard> {
  late final Future<_StudentClassDetails> _details;

  @override
  void initState() {
    super.initState();
    _details = _loadDetails();
  }

  Future<_StudentClassDetails> _loadDetails() async {
    final englishClass = await LearningResultService.instance.getClass(
      widget.enrollment.classId,
    );
    final course = await LearningResultService.instance.getCourse(
      englishClass.courseId,
    );
    return _StudentClassDetails(englishClass: englishClass, course: course);
  }

  @override
  Widget build(BuildContext context) {
    final records = [...widget.records]
      ..sort((a, b) => (b.dateKey ?? '').compareTo(a.dateKey ?? ''));
    final stats = AttendanceStats.fromRecords(records);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<_StudentClassDetails>(
          future: _details,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError || snapshot.data == null) {
              return const Text('Không thể tải thông tin lớp và khóa học.');
            }
            final details = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      details.englishClass.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Chip(label: Text(widget.enrollment.statusLabel)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Khóa học: ${details.course.name}'),
                const Divider(height: 28),
                if (widget.result == null)
                  const Text('Điểm và nhận xét: Chưa có dữ liệu')
                else ...[
                  Wrap(
                    spacing: 24,
                    runSpacing: 10,
                    children: [
                      _ResultValue(
                        label: 'Điểm giữa kỳ',
                        value: LearningResult.scoreLabel(
                          widget.result!.midtermScore,
                        ),
                      ),
                      _ResultValue(
                        label: 'Điểm cuối kỳ',
                        value: LearningResult.scoreLabel(
                          widget.result!.finalScore,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nhận xét: ${widget.result!.comment.isEmpty ? 'Chưa có dữ liệu' : widget.result!.comment}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.result!.updatedAt == null
                        ? 'Thời gian cập nhật: Chưa có dữ liệu'
                        : 'Cập nhật: ${_formatDateTime(widget.result!.updatedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const Divider(height: 28),
                Text(
                  'Chuyên cần',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('Có mặt: ${stats.present}')),
                    Chip(label: Text('Vắng: ${stats.absent}')),
                    Chip(label: Text('Có phép: ${stats.excused}')),
                  ],
                ),
                const SizedBox(height: 12),
                if (records.isEmpty)
                  const Text('Lịch sử điểm danh: Chưa có dữ liệu')
                else
                  Column(
                    children: records
                        .map(
                          (record) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.event_outlined),
                            title: Text(_formatDateKey(record.dateKey)),
                            trailing: Text(record.statusLabel),
                          ),
                        )
                        .toList(),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatDateKey(String? dateKey) {
    if (dateKey == null) return 'Ngày không hợp lệ';
    final date = AttendanceSession.dateFromKey(dateKey);
    if (date == null) return dateKey;
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDateTime(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

class _StudentClassDetails {
  const _StudentClassDetails({
    required this.englishClass,
    required this.course,
  });

  final EnglishClass englishClass;
  final Course course;
}

class _ResultValue extends StatelessWidget {
  const _ResultValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _StudentResultMessage extends StatelessWidget {
  const _StudentResultMessage({required this.icon, required this.message});

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
