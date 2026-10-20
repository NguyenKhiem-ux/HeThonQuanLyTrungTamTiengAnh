import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/attendance_record.dart';
import '../../models/attendance_session.dart';
import '../../models/english_class.dart';
import '../../models/student.dart';
import '../../services/attendance_service.dart';
import '../../services/teacher_assignment_service.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late final String? _userUid;
  Stream<List<EnglishClass>>? _classes;
  String? _selectedClassId;
  var _selectedDate = DateTime.now();
  Stream<List<Student>>? _students;
  Stream<List<AttendanceRecord>>? _records;
  Stream<List<AttendanceSession>>? _sessions;
  Map<String, String> _draftStatuses = {};
  final Set<String> _dirtyStudentIds = {};
  var _recordsApplied = false;
  var _isSaving = false;

  @override
  void initState() {
    super.initState();
    _userUid = FirebaseAuth.instance.currentUser?.uid;
    final userUid = _userUid;
    if (userUid != null) {
      _classes = TeacherAssignmentService.instance
          .watchAssignedClassesForTeacher(userUid);
    }
  }

  void _selectClass(String classId) {
    setState(() {
      _selectedClassId = classId;
      _students = AttendanceService.instance.watchActiveStudents(classId);
      _sessions = AttendanceService.instance.watchSessions(classId);
      _setRecordStream();
    });
  }

  void _setRecordStream() {
    final classId = _selectedClassId;
    if (classId == null) return;
    final dateKey = AttendanceSession.dateKeyFromDate(_selectedDate);
    _records = AttendanceService.instance.watchRecordsForSession(
      classId: classId,
      sessionId: AttendanceSession.documentId(classId, dateKey),
    );
    _draftStatuses = {};
    _dirtyStudentIds.clear();
    _recordsApplied = false;
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    setState(() {
      _selectedDate = date;
      _setRecordStream();
    });
  }

  void _openSession(AttendanceSession session) {
    final date = AttendanceSession.dateFromKey(session.dateKey);
    if (date == null) return;
    setState(() {
      _selectedDate = date;
      _setRecordStream();
    });
  }

  Future<void> _save(List<Student> students) async {
    final classId = _selectedClassId;
    if (classId == null) return;
    final visibleStudentIds = students.map((student) => student.id).toSet();
    final statuses = Map<String, String>.fromEntries(
      _draftStatuses.entries.where(
        (entry) =>
            visibleStudentIds.contains(entry.key) &&
            _dirtyStudentIds.contains(entry.key),
      ),
    );
    setState(() => _isSaving = true);
    try {
      await AttendanceService.instance.saveAttendance(
        classId: classId,
        date: _selectedDate,
        statusesByStudent: statuses,
      );
      if (mounted) {
        _dirtyStudentIds.clear();
        _showMessage('Đã lưu điểm danh.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is StateError
              ? error.message.toString()
              : 'Không thể lưu điểm danh. Hãy kiểm tra quyền truy cập.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
    if (_userUid == null) {
      return const _AttendanceMessage(
        icon: Icons.lock_outline,
        message: 'Phiên đăng nhập không còn hợp lệ.',
      );
    }
    return StreamBuilder<List<EnglishClass>>(
      stream: _classes,
      builder: (context, classSnapshot) {
        if (classSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (classSnapshot.hasError) {
          return const _AttendanceMessage(
            icon: Icons.cloud_off_outlined,
            message: 'Không thể tải danh sách lớp được phân công.',
          );
        }
        final classes = classSnapshot.data ?? const <EnglishClass>[];
        if (classes.isEmpty) {
          return const _AttendanceMessage(
            icon: Icons.class_outlined,
            message: 'Bạn chưa được phân công lớp học nào.',
          );
        }
        EnglishClass? selectedClass;
        for (final item in classes) {
          if (item.id == _selectedClassId) selectedClass = item;
        }
        if (selectedClass == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _selectClass(classes.first.id);
          });
        }
        return _buildContent(classes, selectedClass);
      },
    );
  }

  Widget _buildContent(
    List<EnglishClass> classes,
    EnglishClass? selectedClass,
  ) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Điểm danh học viên',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final classPicker = DropdownButtonFormField<String>(
                initialValue: selectedClass?.id,
                decoration: const InputDecoration(labelText: 'Lớp phụ trách'),
                items: classes
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text('${item.name} · ${item.statusLabel}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) _selectClass(value);
                },
              );
              final datePicker = OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(_formatDate(_selectedDate)),
              );
              return constraints.maxWidth >= 720
                  ? Row(
                      children: [
                        Expanded(child: classPicker),
                        const SizedBox(width: 16),
                        SizedBox(height: 56, child: datePicker),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        classPicker,
                        const SizedBox(height: 12),
                        SizedBox(height: 48, child: datePicker),
                      ],
                    );
            },
          ),
          if (_isSaving) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          _buildHistory(),
          const SizedBox(height: 16),
          if (selectedClass == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            if (selectedClass.status != 'ongoing') ...[
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Chỉ lớp đang học mới được sửa điểm danh. Bạn vẫn có thể xem dữ liệu đã lưu.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: _buildStudentList(
                canEdit: selectedClass.status == 'ongoing',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistory() {
    if (_sessions == null) return const SizedBox.shrink();
    return StreamBuilder<List<AttendanceSession>>(
      stream: _sessions,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Không thể tải lịch sử điểm danh.');
        }
        final sessions = snapshot.data ?? const <AttendanceSession>[];
        if (sessions.isEmpty) {
          return const Text('Lịch sử điểm danh: Chưa có dữ liệu');
        }
        return SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final session = sessions[index];
              final selected =
                  session.dateKey ==
                  AttendanceSession.dateKeyFromDate(_selectedDate);
              return ChoiceChip(
                selected: selected,
                label: Text(_formatDateKey(session.dateKey)),
                onSelected: (_) => _openSession(session),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStudentList({required bool canEdit}) {
    if (_students == null || _records == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<List<Student>>(
      stream: _students,
      builder: (context, studentSnapshot) {
        if (studentSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (studentSnapshot.hasError) {
          return const _AttendanceMessage(
            icon: Icons.cloud_off_outlined,
            message: 'Không thể tải học viên của lớp.',
          );
        }
        final students = studentSnapshot.data ?? const <Student>[];
        if (students.isEmpty) {
          return const _AttendanceMessage(
            icon: Icons.groups_outlined,
            message: 'Lớp chưa có học viên đang đăng ký.',
          );
        }
        return StreamBuilder<List<AttendanceRecord>>(
          stream: _records,
          builder: (context, recordSnapshot) {
            if (recordSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (recordSnapshot.hasError) {
              return const _AttendanceMessage(
                icon: Icons.cloud_off_outlined,
                message: 'Không thể tải dữ liệu điểm danh đã lưu.',
              );
            }
            if (!_recordsApplied) {
              _draftStatuses = {
                for (final record
                    in recordSnapshot.data ?? const <AttendanceRecord>[])
                  record.studentId: record.status,
              };
              _dirtyStudentIds.clear();
              _recordsApplied = true;
            }
            return LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: constraints.maxWidth >= 760
                        ? _AttendanceTable(
                            students: students,
                            statuses: _draftStatuses,
                            enabled: canEdit,
                            onChanged: _changeStatus,
                          )
                        : ListView.separated(
                            itemCount: students.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final student = students[index];
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        student.fullName,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 10),
                                      _StatusPicker(
                                        value: _draftStatuses[student.id],
                                        enabled: canEdit,
                                        onChanged: (value) =>
                                            _changeStatus(student.id, value),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isSaving || !canEdit
                          ? null
                          : () => _save(students),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Lưu điểm danh'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _changeStatus(String studentId, String? status) {
    if (status == null) return;
    setState(() {
      _draftStatuses[studentId] = status;
      _dirtyStudentIds.add(studentId);
    });
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _formatDateKey(String dateKey) {
    final date = AttendanceSession.dateFromKey(dateKey);
    return date == null ? dateKey : _formatDate(date);
  }
}

class _AttendanceTable extends StatelessWidget {
  const _AttendanceTable({
    required this.students,
    required this.statuses,
    required this.enabled,
    required this.onChanged,
  });

  final List<Student> students;
  final Map<String, String> statuses;
  final bool enabled;
  final void Function(String studentId, String? status) onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Học viên')),
              DataColumn(label: Text('Trạng thái điểm danh')),
            ],
            rows: students
                .map(
                  (student) => DataRow(
                    cells: [
                      DataCell(Text(student.fullName)),
                      DataCell(
                        SizedBox(
                          width: 210,
                          child: _StatusPicker(
                            value: statuses[student.id],
                            enabled: enabled,
                            onChanged: (value) => onChanged(student.id, value),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _StatusPicker extends StatelessWidget {
  const _StatusPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      isExpanded: true,
      hint: const Text('Chưa đánh dấu'),
      items: const [
        DropdownMenuItem(value: 'present', child: Text('Có mặt')),
        DropdownMenuItem(value: 'absent', child: Text('Vắng mặt')),
        DropdownMenuItem(value: 'excused', child: Text('Vắng có phép')),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _AttendanceMessage extends StatelessWidget {
  const _AttendanceMessage({required this.icon, required this.message});

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
