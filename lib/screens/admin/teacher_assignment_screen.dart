import 'package:flutter/material.dart';

import '../../models/english_class.dart';
import '../../models/room_allocation.dart';
import '../../models/teacher.dart';
import '../../models/teacher_assignment.dart';
import '../../services/class_service.dart';
import '../../services/room_allocation_service.dart';
import '../../services/staff_account_service.dart';
import '../../services/teacher_assignment_service.dart';
import '../../services/teacher_service.dart';

class TeacherAssignmentScreen extends StatefulWidget {
  const TeacherAssignmentScreen({super.key});

  @override
  State<TeacherAssignmentScreen> createState() =>
      _TeacherAssignmentScreenState();
}

class _TeacherAssignmentScreenState extends State<TeacherAssignmentScreen> {
  late Stream<List<EnglishClass>> _classes;
  late Stream<List<Teacher>> _teachers;
  late Stream<List<TeacherAssignment>> _assignments;
  late Stream<List<RoomAllocation>> _allocations;
  var _isWorking = false;
  var _isSyncingTeachers = true;
  Object? _teacherSyncError;

  @override
  void initState() {
    super.initState();
    _reload();
    _syncActiveTeachers();
  }

  void _reload() {
    _classes = ClassService.instance.watchClasses();
    _teachers = TeacherService.instance.watchTeachers();
    _assignments = TeacherAssignmentService.instance.watchAssignments();
    _allocations = RoomAllocationService.instance.watchAllocations();
  }

  Future<void> _syncActiveTeachers() async {
    if (mounted) {
      setState(() {
        _isSyncingTeachers = true;
        _teacherSyncError = null;
      });
    }
    try {
      await TeacherService.instance.syncActiveTeacherProfiles();
    } catch (error) {
      debugLogFirestoreError('TeacherAssignmentScreen.sync', error);
      _teacherSyncError = error;
    } finally {
      if (mounted) setState(() => _isSyncingTeachers = false);
    }
  }

  Future<void> _openAssignment(
    EnglishClass englishClass,
    TeacherAssignment? current,
    List<Teacher> teachers,
  ) async {
    final eligible = teachers.where((teacher) => teacher.isAssignable).toList();
    if (eligible.isEmpty) {
      _showMessage(
        'Chưa có giáo viên hoạt động đã liên kết tài khoản.',
        isError: true,
      );
      return;
    }
    final teacherId = await showDialog<String>(
      context: context,
      builder: (_) => _AssignmentDialog(
        englishClass: englishClass,
        teachers: eligible,
        currentTeacherId: current?.teacherId,
      ),
    );
    if (teacherId == null || !mounted) return;

    setState(() => _isWorking = true);
    try {
      await TeacherAssignmentService.instance.assign(
        classId: englishClass.id,
        teacherId: teacherId,
      );
      if (mounted) {
        _showMessage(
          current == null
              ? 'Đã phân công giáo viên cho lớp.'
              : 'Đã thay đổi giáo viên phụ trách.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is StateError
              ? error.message.toString()
              : 'Không thể lưu phân công. Hãy kiểm tra quyền truy cập.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _cancelAssignment(
    EnglishClass englishClass,
    Teacher teacher,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hủy phân công giảng dạy?'),
        content: Text(
          'Hủy phân công ${teacher.fullName} khỏi lớp ${englishClass.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Không'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Có, hủy phân công'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWorking = true);
    try {
      await TeacherAssignmentService.instance.cancel(englishClass.id);
      if (mounted) _showMessage('Đã hủy phân công giảng dạy.');
    } catch (_) {
      if (mounted) {
        _showMessage('Không thể hủy phân công giảng dạy.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_isSyncingTeachers) return _loading();
    if (_teacherSyncError case final error?) {
      return _error(
        firestoreLoadErrorMessage(error, 'tài khoản giáo viên để đồng bộ'),
        onRetry: _syncActiveTeachers,
      );
    }
    return StreamBuilder<List<EnglishClass>>(
      stream: _classes,
      builder: (context, classSnapshot) {
        if (classSnapshot.hasError) {
          return _streamError(classSnapshot.error!, 'lớp học');
        }
        if (_isWaiting(classSnapshot)) return _loading();
        return StreamBuilder<List<Teacher>>(
          stream: _teachers,
          builder: (context, teacherSnapshot) {
            if (teacherSnapshot.hasError) {
              return _streamError(teacherSnapshot.error!, 'giáo viên');
            }
            if (_isWaiting(teacherSnapshot)) return _loading();
            return StreamBuilder<List<TeacherAssignment>>(
              stream: _assignments,
              builder: (context, assignmentSnapshot) {
                if (assignmentSnapshot.hasError) {
                  return _streamError(
                    assignmentSnapshot.error!,
                    'phân công giảng dạy',
                  );
                }
                if (_isWaiting(assignmentSnapshot)) return _loading();
                return StreamBuilder<List<RoomAllocation>>(
                  stream: _allocations,
                  builder: (context, allocationSnapshot) {
                    if (allocationSnapshot.hasError) {
                      return _streamError(
                        allocationSnapshot.error!,
                        'lịch học để kiểm tra',
                      );
                    }
                    if (_isWaiting(allocationSnapshot)) return _loading();
                    return _buildContent(
                      classSnapshot.data ?? const <EnglishClass>[],
                      teacherSnapshot.data ?? const <Teacher>[],
                      assignmentSnapshot.data ?? const <TeacherAssignment>[],
                      allocationSnapshot.data ?? const <RoomAllocation>[],
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

  bool _isWaiting(AsyncSnapshot<Object?> snapshot) =>
      snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;

  Widget _loading() => const Center(child: CircularProgressIndicator());

  Widget _error(String message, {VoidCallback? onRetry}) => _AssignmentMessage(
    icon: Icons.cloud_off_outlined,
    message: message,
    onRetry: onRetry ?? () => setState(_reload),
  );

  Widget _streamError(Object error, String subject) {
    debugLogFirestoreError('TeacherAssignmentScreen.$subject', error);
    return _error(firestoreLoadErrorMessage(error, subject));
  }

  Widget _buildContent(
    List<EnglishClass> classes,
    List<Teacher> teachers,
    List<TeacherAssignment> assignments,
    List<RoomAllocation> allocations,
  ) {
    final teacherById = {for (final teacher in teachers) teacher.id: teacher};
    final assignmentByClass = {
      for (final assignment in assignments) assignment.classId: assignment,
    };
    final schedulesByClass = <String, List<RoomAllocation>>{};
    for (final allocation in allocations) {
      schedulesByClass
          .putIfAbsent(allocation.classId, () => [])
          .add(allocation);
    }

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Phân công giảng dạy',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Mỗi lớp có tối đa một giáo viên phụ trách. Hệ thống kiểm tra trùng lịch trước khi lưu.',
          ),
          if (_isWorking) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 20),
          Expanded(
            child: classes.isEmpty
                ? const _AssignmentMessage(
                    icon: Icons.class_outlined,
                    message: 'Chưa có lớp học để phân công.',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 920) {
                        return SingleChildScrollView(
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Lớp học')),
                                  DataColumn(label: Text('Trạng thái')),
                                  DataColumn(label: Text('Giáo viên')),
                                  DataColumn(label: Text('Lịch học')),
                                  DataColumn(label: Text('Thao tác')),
                                ],
                                rows: classes.map((englishClass) {
                                  final assignment =
                                      assignmentByClass[englishClass.id];
                                  final teacher = assignment == null
                                      ? null
                                      : teacherById[assignment.teacherId];
                                  final schedules =
                                      schedulesByClass[englishClass.id] ??
                                      const <RoomAllocation>[];
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(englishClass.name)),
                                      DataCell(Text(englishClass.statusLabel)),
                                      DataCell(
                                        Text(
                                          teacher?.fullName ?? 'Chưa phân công',
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 250,
                                          child: Text(_scheduleText(schedules)),
                                        ),
                                      ),
                                      DataCell(
                                        _AssignmentActions(
                                          canAssign:
                                              !_isWorking &&
                                              englishClass.status !=
                                                  'completed',
                                          hasAssignment: assignment != null,
                                          onAssign: () => _openAssignment(
                                            englishClass,
                                            assignment,
                                            teachers,
                                          ),
                                          onCancel: teacher == null
                                              ? null
                                              : () => _cancelAssignment(
                                                  englishClass,
                                                  teacher,
                                                ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: classes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final englishClass = classes[index];
                          final assignment = assignmentByClass[englishClass.id];
                          final teacher = assignment == null
                              ? null
                              : teacherById[assignment.teacherId];
                          final schedules =
                              schedulesByClass[englishClass.id] ??
                              const <RoomAllocation>[];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    englishClass.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Trạng thái: ${englishClass.statusLabel}',
                                  ),
                                  Text(
                                    'Giáo viên: ${teacher?.fullName ?? 'Chưa phân công'}',
                                  ),
                                  const SizedBox(height: 6),
                                  Text(_scheduleText(schedules)),
                                  const SizedBox(height: 12),
                                  _AssignmentActions(
                                    canAssign:
                                        !_isWorking &&
                                        englishClass.status != 'completed',
                                    hasAssignment: assignment != null,
                                    onAssign: () => _openAssignment(
                                      englishClass,
                                      assignment,
                                      teachers,
                                    ),
                                    onCancel: teacher == null
                                        ? null
                                        : () => _cancelAssignment(
                                            englishClass,
                                            teacher,
                                          ),
                                  ),
                                ],
                              ),
                            ),
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

  String _scheduleText(List<RoomAllocation> schedules) {
    if (schedules.isEmpty) return 'Chưa có lịch học để kiểm tra xung đột';
    return schedules
        .map((schedule) => '${schedule.weekdayLabel} ${schedule.timeLabel}')
        .join('\n');
  }
}

class _AssignmentActions extends StatelessWidget {
  const _AssignmentActions({
    required this.canAssign,
    required this.hasAssignment,
    required this.onAssign,
    required this.onCancel,
  });

  final bool canAssign;
  final bool hasAssignment;
  final VoidCallback onAssign;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: canAssign ? onAssign : null,
          icon: const Icon(Icons.assignment_ind_outlined),
          label: Text(hasAssignment ? 'Thay đổi' : 'Phân công'),
        ),
        if (hasAssignment)
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Hủy'),
          ),
      ],
    );
  }
}

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog({
    required this.englishClass,
    required this.teachers,
    required this.currentTeacherId,
  });

  final EnglishClass englishClass;
  final List<Teacher> teachers;
  final String? currentTeacherId;

  @override
  State<_AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<_AssignmentDialog> {
  String? _teacherId;

  @override
  void initState() {
    super.initState();
    _teacherId =
        widget.teachers.any((teacher) => teacher.id == widget.currentTeacherId)
        ? widget.currentTeacherId
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Phân công giáo viên'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lớp: ${widget.englishClass.name}'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _teacherId,
              decoration: const InputDecoration(labelText: 'Giáo viên *'),
              items: widget.teachers
                  .map(
                    (teacher) => DropdownMenuItem(
                      value: teacher.id,
                      child: Text(
                        '${teacher.fullName} · ${teacher.specialtyLabel}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _teacherId = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _teacherId == null
              ? null
              : () => Navigator.pop(context, _teacherId),
          child: const Text('Lưu phân công'),
        ),
      ],
    );
  }
}

class _AssignmentMessage extends StatelessWidget {
  const _AssignmentMessage({
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
            OutlinedButton.icon(
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
