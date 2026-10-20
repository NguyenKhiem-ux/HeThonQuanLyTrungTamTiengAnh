import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../models/english_class.dart';
import '../../models/enrollment.dart';
import '../../models/student.dart';
import '../../services/class_service.dart';
import '../../services/course_service.dart';
import '../../services/enrollment_service.dart';
import '../../services/student_service.dart';

class EnrollmentManagementScreen extends StatefulWidget {
  const EnrollmentManagementScreen({super.key});

  @override
  State<EnrollmentManagementScreen> createState() =>
      _EnrollmentManagementScreenState();
}

class _EnrollmentManagementScreenState
    extends State<EnrollmentManagementScreen> {
  late Stream<List<Student>> _students;
  late Stream<List<Course>> _courses;
  late Stream<List<EnglishClass>> _classes;
  late Stream<List<Enrollment>> _enrollments;
  String? _studentFilter;
  String? _classFilter;
  var _isWorking = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _students = StudentService.instance.watchStudents();
    _courses = CourseService.instance.watchCourses();
    _classes = ClassService.instance.watchClasses();
    _enrollments = EnrollmentService.instance.watchEnrollments();
  }

  Future<void> _openRegistration(
    List<Student> students,
    List<Course> courses,
    List<EnglishClass> classes,
    List<Enrollment> enrollments,
  ) async {
    final activeStudents = students
        .where((student) => student.isActive)
        .toList();
    if (activeStudents.isEmpty) {
      _showMessage(
        'Không có học viên đang hoạt động để đăng ký.',
        isError: true,
      );
      return;
    }
    if (courses.isEmpty) {
      _showMessage('Không có khóa học để đăng ký.', isError: true);
      return;
    }
    if (!classes.any((item) => item.status == 'pending')) {
      _showMessage('Không có lớp chờ mở để đăng ký.', isError: true);
      return;
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RegistrationDialog(
        students: activeStudents,
        courses: courses,
        classes: classes,
        enrollments: enrollments,
      ),
    );
    if (saved == true && mounted) _showMessage('Đăng ký học thành công.');
  }

  Future<void> _cancelEnrollment(Enrollment enrollment) async {
    if (_isWorking || !enrollment.canCancel) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hủy đăng ký học?'),
        content: const Text(
          'Đăng ký sẽ chuyển sang trạng thái Đã hủy và vẫn được giữ lại trong lịch sử.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Không'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hủy đăng ký'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWorking = true);
    try {
      await EnrollmentService.instance.cancel(enrollment);
      if (mounted) _showMessage('Đã hủy đăng ký học.');
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is StateError
              ? error.message.toString()
              : 'Không thể hủy đăng ký học.',
          isError: true,
        );
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
    return StreamBuilder<List<Student>>(
      stream: _students,
      builder: (context, studentSnapshot) {
        if (_isWaiting(studentSnapshot)) return _loading();
        if (studentSnapshot.hasError) {
          return _errorState('Không thể tải học viên.');
        }
        return StreamBuilder<List<Course>>(
          stream: _courses,
          builder: (context, courseSnapshot) {
            if (_isWaiting(courseSnapshot)) return _loading();
            if (courseSnapshot.hasError) {
              return _errorState('Không thể tải khóa học.');
            }
            return StreamBuilder<List<EnglishClass>>(
              stream: _classes,
              builder: (context, classSnapshot) {
                if (_isWaiting(classSnapshot)) return _loading();
                if (classSnapshot.hasError) {
                  return _errorState('Không thể tải lớp học.');
                }
                return StreamBuilder<List<Enrollment>>(
                  stream: _enrollments,
                  builder: (context, enrollmentSnapshot) {
                    if (_isWaiting(enrollmentSnapshot)) return _loading();
                    if (enrollmentSnapshot.hasError) {
                      return _errorState('Không thể tải danh sách đăng ký.');
                    }
                    return _buildContent(
                      studentSnapshot.data ?? const <Student>[],
                      courseSnapshot.data ?? const <Course>[],
                      classSnapshot.data ?? const <EnglishClass>[],
                      enrollmentSnapshot.data ?? const <Enrollment>[],
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
      snapshot.connectionState == ConnectionState.waiting;

  Widget _loading() => const Center(child: CircularProgressIndicator());

  Widget _errorState(String message) => _MessageState(
    icon: Icons.cloud_off_outlined,
    message: message,
    onRetry: () => setState(_reload),
  );

  Widget _buildContent(
    List<Student> students,
    List<Course> courses,
    List<EnglishClass> classes,
    List<Enrollment> enrollments,
  ) {
    final studentIds = students.map((student) => student.id).toSet();
    final classIds = classes.map((item) => item.id).toSet();
    final effectiveStudentFilter = studentIds.contains(_studentFilter)
        ? _studentFilter
        : null;
    final effectiveClassFilter = classIds.contains(_classFilter)
        ? _classFilter
        : null;
    final filtered = enrollments.where((enrollment) {
      return (effectiveStudentFilter == null ||
              enrollment.studentId == effectiveStudentFilter) &&
          (effectiveClassFilter == null ||
              enrollment.classId == effectiveClassFilter);
    }).toList();
    final studentNames = {
      for (final student in students) student.id: student.fullName,
    };
    final classNames = {for (final item in classes) item.id: item.name};
    final activeCounts = <String, int>{};
    for (final enrollment in enrollments.where((item) => item.isActive)) {
      activeCounts.update(
        enrollment.classId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                'Đăng ký học',
                style: Theme.of(context).textTheme.headlineMedium,
              );
              final button = FilledButton.icon(
                onPressed: _isWorking
                    ? null
                    : () => _openRegistration(
                        students,
                        courses,
                        classes,
                        enrollments,
                      ),
                icon: const Icon(Icons.app_registration_outlined),
                label: const Text('Đăng ký học viên'),
              );
              return constraints.maxWidth >= 520
                  ? Row(
                      children: [
                        Expanded(child: title),
                        button,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [title, const SizedBox(height: 16), button],
                    );
            },
          ),
          const SizedBox(height: 16),
          _buildFilters(
            students,
            classes,
            effectiveStudentFilter,
            effectiveClassFilter,
          ),
          const SizedBox(height: 12),
          _buildRaceNotice(),
          if (_isWorking) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (enrollments.isEmpty) {
                  return const _MessageState(
                    icon: Icons.how_to_reg_outlined,
                    message: 'Chưa có đăng ký học nào.',
                  );
                }
                if (filtered.isEmpty) {
                  return const _MessageState(
                    icon: Icons.filter_alt_off_outlined,
                    message: 'Không có đăng ký phù hợp bộ lọc.',
                  );
                }
                return constraints.maxWidth >= 820
                    ? _buildTable(
                        filtered,
                        studentNames,
                        classNames,
                        activeCounts,
                        classes,
                        constraints.maxWidth,
                      )
                    : _buildCards(
                        filtered,
                        studentNames,
                        classNames,
                        activeCounts,
                        classes,
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(
    List<Student> students,
    List<EnglishClass> classes,
    String? studentFilter,
    String? classFilter,
  ) {
    final studentDropdown = _FilterDropdown(
      label: 'Học viên',
      value: studentFilter,
      allLabel: 'Tất cả học viên',
      items: students
          .map((student) => _FilterItem(student.id, student.fullName))
          .toList(),
      onChanged: (value) => setState(() => _studentFilter = value),
    );
    final classDropdown = _FilterDropdown(
      label: 'Lớp học',
      value: classFilter,
      allLabel: 'Tất cả lớp học',
      items: classes.map((item) => _FilterItem(item.id, item.name)).toList(),
      onChanged: (value) => setState(() => _classFilter = value),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 680
          ? Row(
              children: [
                Expanded(child: studentDropdown),
                const SizedBox(width: 16),
                Expanded(child: classDropdown),
              ],
            )
          : Column(
              children: [
                studentDropdown,
                const SizedBox(height: 12),
                classDropdown,
              ],
            ),
    );
  }

  Widget _buildRaceNotice() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sĩ số hiện tại chỉ tính đăng ký đang hoạt động. Giới hạn sĩ số '
              'được kiểm tra lại trước khi ghi.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(
    List<Enrollment> enrollments,
    Map<String, String> studentNames,
    Map<String, String> classNames,
    Map<String, int> activeCounts,
    List<EnglishClass> classes,
    double minWidth,
  ) {
    final classById = {for (final item in classes) item.id: item};
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Học viên')),
                  DataColumn(label: Text('Lớp học')),
                  DataColumn(label: Text('Sĩ số')),
                  DataColumn(label: Text('Trạng thái')),
                  DataColumn(label: Text('Thao tác')),
                ],
                rows: enrollments.map((enrollment) {
                  final englishClass = classById[enrollment.classId];
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          studentNames[enrollment.studentId] ??
                              'Học viên không tồn tại',
                        ),
                      ),
                      DataCell(
                        Text(
                          classNames[enrollment.classId] ?? 'Lớp không tồn tại',
                        ),
                      ),
                      DataCell(
                        Text(
                          englishClass == null
                              ? 'Không xác định'
                              : '${activeCounts[englishClass.id] ?? 0}/${englishClass.maxStudents}',
                        ),
                      ),
                      DataCell(_EnrollmentStatus(enrollment: enrollment)),
                      DataCell(_actions(enrollment)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCards(
    List<Enrollment> enrollments,
    Map<String, String> studentNames,
    Map<String, String> classNames,
    Map<String, int> activeCounts,
    List<EnglishClass> classes,
  ) {
    final classById = {for (final item in classes) item.id: item};
    return ListView.separated(
      itemCount: enrollments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final enrollment = enrollments[index];
        final englishClass = classById[enrollment.classId];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        studentNames[enrollment.studentId] ??
                            'Học viên không tồn tại',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _EnrollmentStatus(enrollment: enrollment),
                  ],
                ),
                const SizedBox(height: 8),
                Text(classNames[enrollment.classId] ?? 'Lớp không tồn tại'),
                const SizedBox(height: 4),
                Text(
                  englishClass == null
                      ? 'Sĩ số: không xác định'
                      : 'Đang đăng ký: ${activeCounts[englishClass.id] ?? 0}/${englishClass.maxStudents}',
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _actions(enrollment),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _actions(Enrollment enrollment) {
    return IconButton(
      tooltip: enrollment.canCancel ? 'Hủy đăng ký' : 'Đăng ký đã hủy',
      onPressed: _isWorking || !enrollment.canCancel
          ? null
          : () => _cancelEnrollment(enrollment),
      icon: const Icon(Icons.person_remove_outlined),
    );
  }
}

class _RegistrationDialog extends StatefulWidget {
  const _RegistrationDialog({
    required this.students,
    required this.courses,
    required this.classes,
    required this.enrollments,
  });

  final List<Student> students;
  final List<Course> courses;
  final List<EnglishClass> classes;
  final List<Enrollment> enrollments;

  @override
  State<_RegistrationDialog> createState() => _RegistrationDialogState();
}

class _RegistrationDialogState extends State<_RegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _studentId;
  late String _courseId;
  String? _classId;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _studentId = widget.students.first.id;
    final firstCourse = widget.courses.firstWhere(
      (course) => widget.classes.any(
        (item) => item.courseId == course.id && item.status == 'pending',
      ),
      orElse: () => widget.courses.first,
    );
    _courseId = firstCourse.id;
    _classId = _classesForCourse.firstOrNull?.id;
  }

  List<EnglishClass> get _classesForCourse => widget.classes
      .where((item) => item.courseId == _courseId && item.status == 'pending')
      .toList();

  int _activeCount(String classId) => widget.enrollments
      .where((item) => item.classId == classId && item.isActive)
      .length;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _classId == null) return;
    final englishClass = widget.classes.firstWhere(
      (item) => item.id == _classId,
    );
    if (_activeCount(englishClass.id) >= englishClass.maxStudents) {
      setState(() => _error = 'Lớp đã đủ sĩ số.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await EnrollmentService.instance.register(
        studentId: _studentId,
        courseId: _courseId,
        classId: _classId!,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StateError
              ? error.message.toString()
              : 'Không thể kiểm tra dữ liệu đăng ký. Chưa có dữ liệu nào được ghi.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableClasses = _classesForCourse;
    final selectedClass = _classId == null
        ? null
        : widget.classes.where((item) => item.id == _classId).firstOrNull;
    final activeCount = selectedClass == null
        ? 0
        : _activeCount(selectedClass.id);
    final isFull =
        selectedClass != null && activeCount >= selectedClass.maxStudents;

    return AlertDialog(
      title: const Text('Đăng ký học viên vào lớp'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _studentId,
                  decoration: const InputDecoration(labelText: 'Học viên'),
                  items: widget.students
                      .map(
                        (student) => DropdownMenuItem(
                          value: student.id,
                          child: Text(student.fullName),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _studentId = value;
                              _error = null;
                            });
                          }
                        },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _courseId,
                  decoration: const InputDecoration(labelText: 'Khóa học'),
                  items: widget.courses
                      .map(
                        (course) => DropdownMenuItem(
                          value: course.id,
                          child: Text(course.name),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _courseId = value;
                              _classId = _classesForCourse.firstOrNull?.id;
                              _error = null;
                            });
                          }
                        },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(_courseId),
                  initialValue: _classId,
                  decoration: const InputDecoration(labelText: 'Lớp học'),
                  items: availableClasses
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Khóa học chưa có lớp chờ mở.' : null,
                  onChanged: _saving
                      ? null
                      : (value) {
                          setState(() {
                            _classId = value;
                            _error = null;
                          });
                        },
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    selectedClass == null
                        ? 'Hãy chọn lớp học.'
                        : isFull
                        ? 'Lớp đã đủ sĩ số ($activeCount/${selectedClass.maxStudents}).'
                        : 'Đang đăng ký: $activeCount/${selectedClass.maxStudents} · '
                              'Còn ${selectedClass.maxStudents - activeCount} chỗ.',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                if (_saving) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _saving || selectedClass == null || isFull
              ? null
              : _submit,
          child: const Text('Xác nhận đăng ký'),
        ),
      ],
    );
  }
}

class _EnrollmentStatus extends StatelessWidget {
  const _EnrollmentStatus({required this.enrollment});

  final Enrollment enrollment;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(enrollment.statusLabel),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.allLabel,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final String allLabel;
  final List<_FilterItem> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isDense: true,
          isExpanded: true,
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(allLabel)),
            ...items.map(
              (item) => DropdownMenuItem<String?>(
                value: item.value,
                child: Text(item.label),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _FilterItem {
  const _FilterItem(this.value, this.label);

  final String value;
  final String label;
}

class _MessageState extends StatelessWidget {
  const _MessageState({
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
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ],
      ),
    );
  }
}
