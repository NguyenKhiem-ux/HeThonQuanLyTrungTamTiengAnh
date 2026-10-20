import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/room_allocation.dart';
import '../../services/student_schedule_service.dart';

typedef StudentScheduleLoader =
    Future<StudentScheduleData> Function(String userUid);

class StudentScheduleScreen extends StatefulWidget {
  const StudentScheduleScreen({super.key, this.userUid, this.loadSchedule});

  final String? userUid;
  final StudentScheduleLoader? loadSchedule;

  @override
  State<StudentScheduleScreen> createState() => _StudentScheduleScreenState();
}

class _StudentScheduleScreenState extends State<StudentScheduleScreen> {
  late final String? _userUid;
  late Future<StudentScheduleData>? _schedule;

  @override
  void initState() {
    super.initState();
    _userUid = widget.userUid ?? FirebaseAuth.instance.currentUser?.uid;
    _load();
  }

  void _load() {
    final userUid = _userUid;
    _schedule = userUid == null
        ? null
        : (widget.loadSchedule ?? StudentScheduleService.instance.loadForUser)(
            userUid,
          );
  }

  void _retry() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 28.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            24,
            horizontalPadding,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Lịch học của tôi',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('Lịch chính thức của các lớp bạn đang tham gia.'),
              const SizedBox(height: 20),
              Expanded(child: _buildBody()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    final schedule = _schedule;
    if (schedule == null) {
      return const StudentScheduleMessage(
        icon: Icons.lock_outline,
        message: 'Phiên đăng nhập không còn hợp lệ.',
      );
    }
    return FutureBuilder<StudentScheduleData>(
      future: schedule,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return StudentScheduleMessage(
            icon: Icons.cloud_off_outlined,
            message: studentScheduleErrorMessage(snapshot.error!),
            onRetry: _retry,
          );
        }
        final data = snapshot.data ?? const StudentScheduleData(classes: []);
        if (data.classes.isEmpty) {
          return const StudentScheduleMessage(
            icon: Icons.event_available_outlined,
            message: 'Bạn chưa được xếp vào lớp học nào.',
          );
        }
        return _StudentScheduleContent(data: data);
      },
    );
  }
}

class _StudentScheduleContent extends StatelessWidget {
  const _StudentScheduleContent({required this.data});

  final StudentScheduleData data;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Lịch học trong tuần',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1050
                  ? 3
                  : constraints.maxWidth >= 650
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - ((columns - 1) * 12)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var weekday = 1; weekday <= 7; weekday++)
                    SizedBox(
                      width: width,
                      child: _WeekdayCard(
                        weekday: weekday,
                        entries: data.entries
                            .where((entry) => entry.weekday == weekday)
                            .toList(),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          Text(
            'Lớp đang tham gia',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final item in data.classes) ...[
            _ParticipatingClassCard(item: item),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _WeekdayCard extends StatelessWidget {
  const _WeekdayCard({required this.weekday, required this.entries});

  final int weekday;
  final List<StudentScheduleEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              weekdayName(weekday),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              Text(
                'Không có lịch học',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              for (var index = 0; index < entries.length; index++) ...[
                if (index > 0) const Divider(height: 20),
                Text(
                  entries[index].className,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(entries[index].timeLabel),
                Text('Phòng: ${entries[index].roomLabel}'),
              ],
          ],
        ),
      ),
    );
  }
}

class _ParticipatingClassCard extends StatelessWidget {
  const _ParticipatingClassCard({required this.item});

  final StudentScheduleClass item;

  @override
  Widget build(BuildContext context) {
    final englishClass = item.englishClass;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  englishClass.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Chip(label: Text(item.statusLabel)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Khóa học: ${item.course.name}'),
            const SizedBox(height: 4),
            Text(englishClass.studyPatternLabel),
            Text(englishClass.shiftLabel),
            const SizedBox(height: 4),
            Text(
              'Giáo viên: '
              '${item.teacherName ?? 'Chưa phân công giáo viên'}',
            ),
          ],
        ),
      ),
    );
  }
}

class StudentScheduleMessage extends StatelessWidget {
  const StudentScheduleMessage({
    super.key,
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ],
      ),
    );
  }
}

String studentScheduleErrorMessage(Object error) {
  if (error is TimeoutException) {
    return 'Firestore không phản hồi. Vui lòng thử lại.';
  }
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'Không có quyền tải lịch học. Hãy kiểm tra Firestore Rules.';
  }
  if (error is StateError) return error.message;
  return 'Không thể tải lịch học. Vui lòng thử lại.';
}
