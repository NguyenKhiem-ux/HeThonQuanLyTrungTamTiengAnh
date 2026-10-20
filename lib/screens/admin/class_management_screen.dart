import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../models/english_class.dart';
import '../../services/class_service.dart';
import '../../services/course_service.dart';

class ClassManagementScreen extends StatefulWidget {
  const ClassManagementScreen({super.key});

  @override
  State<ClassManagementScreen> createState() => _ClassManagementScreenState();
}

class _ClassManagementScreenState extends State<ClassManagementScreen> {
  final _searchController = TextEditingController();
  late Stream<List<Course>> _courses;
  late Stream<List<EnglishClass>> _classes;
  var _statusFilter = 'all';
  var _isWorking = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _courses = CourseService.instance.watchCourses();
    _classes = ClassService.instance.watchClasses();
  }

  Future<void> _openForm(
    List<Course> courses, [
    EnglishClass? englishClass,
  ]) async {
    if (englishClass?.canEdit == false) {
      _showMessage('Lớp đã kết thúc không thể chỉnh sửa.', isError: true);
      return;
    }
    if (courses.isEmpty) {
      _showMessage(
        'Cần tạo ít nhất một khóa học trước khi mở lớp.',
        isError: true,
      );
      return;
    }
    if (englishClass != null &&
        !courses.any((course) => course.id == englishClass.courseId)) {
      _showMessage(
        'Không thể sửa vì khóa học liên kết không còn tồn tại.',
        isError: true,
      );
      return;
    }

    final input = await showDialog<EnglishClassInput>(
      context: context,
      builder: (_) =>
          _ClassFormDialog(courses: courses, englishClass: englishClass),
    );
    if (input == null || !mounted) return;

    setState(() => _isWorking = true);
    try {
      if (englishClass == null) {
        await ClassService.instance.addClass(input);
      } else {
        await ClassService.instance.updateClass(englishClass, input);
      }
      if (mounted) {
        _showMessage(
          englishClass == null ? 'Đã thêm lớp học.' : 'Đã cập nhật lớp học.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is StateError
              ? error.message.toString()
              : 'Không thể lưu lớp học. Hãy kiểm tra dữ liệu và quyền truy cập.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _deleteClass(EnglishClass englishClass) async {
    if (_isWorking) return;
    if (!englishClass.canDelete) {
      _showMessage('Chỉ lớp ở trạng thái Chờ mở mới được xóa.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa lớp học?'),
        content: Text(
          'Bạn có chắc muốn xóa lớp “${englishClass.name}”? '
          'Thao tác này không thể hoàn tác và không xóa dữ liệu liên quan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Không'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Có, xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWorking = true);
    try {
      await ClassService.instance.deleteClass(englishClass);
      if (mounted) _showMessage('Đã xóa lớp học.');
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is StateError
              ? error.message.toString()
              : 'Không thể kiểm tra lịch phân bổ hoặc xóa lớp học.',
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
    return StreamBuilder<List<Course>>(
      stream: _courses,
      builder: (context, courseSnapshot) {
        final courses = courseSnapshot.data ?? const <Course>[];
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(courses, courseSnapshot.hasData),
              const SizedBox(height: 20),
              _buildFilters(),
              if (_isWorking) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 12),
              _buildEnrollmentNotice(),
              const SizedBox(height: 20),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildContent(courseSnapshot, constraints.maxWidth),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(List<Course> courses, bool coursesLoaded) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final title = Text(
          'Quản lý lớp học',
          style: Theme.of(context).textTheme.headlineMedium,
        );
        final addButton = FilledButton.icon(
          onPressed: _isWorking || !coursesLoaded
              ? null
              : () => _openForm(courses),
          icon: const Icon(Icons.add),
          label: const Text('Mở lớp học'),
        );
        if (constraints.maxWidth >= 520) {
          return Row(
            children: [
              Expanded(child: title),
              addButton,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [title, const SizedBox(height: 16), addButton],
        );
      },
    );
  }

  Widget _buildFilters() {
    final search = TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'Tìm theo tên lớp học',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Xóa tìm kiếm',
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.clear),
              ),
      ),
    );
    final status = InputDecorator(
      decoration: const InputDecoration(labelText: 'Trạng thái'),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _statusFilter,
          isExpanded: true,
          isDense: true,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Tất cả')),
            DropdownMenuItem(value: 'pending', child: Text('Chờ mở')),
            DropdownMenuItem(value: 'ongoing', child: Text('Đang học')),
            DropdownMenuItem(value: 'completed', child: Text('Đã kết thúc')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _statusFilter = value);
          },
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 680) {
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 16),
              SizedBox(width: 220, child: status),
            ],
          );
        }
        return Column(children: [search, const SizedBox(height: 12), status]);
      },
    );
  }

  Widget _buildEnrollmentNotice() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: colors.onSecondaryContainer),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Khi xóa lớp chờ mở, hệ thống sẽ từ chối nếu lớp còn lịch phân bổ. '
              'Lớp còn học viên đang đăng ký cũng phải được xử lý trước khi xóa.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    AsyncSnapshot<List<Course>> courseSnapshot,
    double width,
  ) {
    if (courseSnapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (courseSnapshot.hasError) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        message:
            'Không thể tải khóa học liên kết. Hãy kiểm tra kết nối và quyền truy cập.',
        actionLabel: 'Thử lại',
        onAction: () => setState(_reload),
      );
    }

    final courses = courseSnapshot.data ?? const <Course>[];
    final courseNames = {for (final course in courses) course.id: course.name};
    return StreamBuilder<List<EnglishClass>>(
      stream: _classes,
      builder: (context, classSnapshot) {
        if (classSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (classSnapshot.hasError) {
          return _MessageState(
            icon: Icons.cloud_off_outlined,
            message:
                'Không thể tải danh sách lớp học. Hãy kiểm tra kết nối và quyền truy cập.',
            actionLabel: 'Thử lại',
            onAction: () => setState(_reload),
          );
        }

        final allClasses = classSnapshot.data ?? const <EnglishClass>[];
        if (allClasses.isEmpty) {
          return const _MessageState(
            icon: Icons.class_outlined,
            message: 'Chưa có lớp học nào.',
          );
        }

        final query = _searchController.text.trim().toLowerCase();
        final classes = allClasses.where((englishClass) {
          final matchesName =
              query.isEmpty || englishClass.name.toLowerCase().contains(query);
          final matchesStatus =
              _statusFilter == 'all' || englishClass.status == _statusFilter;
          return matchesName && matchesStatus;
        }).toList();
        if (classes.isEmpty) {
          return const _MessageState(
            icon: Icons.search_off_outlined,
            message: 'Không tìm thấy lớp học phù hợp.',
          );
        }

        return width >= 880
            ? _buildTable(classes, courseNames, courses, width)
            : _buildCards(classes, courseNames, courses);
      },
    );
  }

  Widget _buildTable(
    List<EnglishClass> classes,
    Map<String, String> courseNames,
    List<Course> courses,
    double minWidth,
  ) {
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
                  DataColumn(label: Text('Tên lớp')),
                  DataColumn(label: Text('Khóa học')),
                  DataColumn(label: Text('Lịch học')),
                  DataColumn(label: Text('Ca học')),
                  DataColumn(label: Text('Sĩ số tối thiểu')),
                  DataColumn(label: Text('Sĩ số tối đa')),
                  DataColumn(label: Text('Trạng thái')),
                  DataColumn(label: Text('Thao tác')),
                ],
                rows: classes
                    .map(
                      (englishClass) => DataRow(
                        cells: [
                          DataCell(Text(englishClass.name)),
                          DataCell(
                            Text(
                              courseNames[englishClass.courseId] ??
                                  'Khóa học không tồn tại',
                            ),
                          ),
                          DataCell(Text(englishClass.studyPatternLabel)),
                          DataCell(Text(englishClass.shiftLabel)),
                          DataCell(Text('${englishClass.minStudents}')),
                          DataCell(Text('${englishClass.maxStudents}')),
                          DataCell(_buildStatus(englishClass)),
                          DataCell(_buildActions(englishClass, courses)),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCards(
    List<EnglishClass> classes,
    Map<String, String> courseNames,
    List<Course> courses,
  ) {
    return ListView.separated(
      itemCount: classes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final englishClass = classes[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        englishClass.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _buildStatus(englishClass),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  courseNames[englishClass.courseId] ??
                      'Khóa học không tồn tại',
                ),
                const SizedBox(height: 8),
                Text(englishClass.studyPatternLabel),
                const SizedBox(height: 4),
                Text(englishClass.shiftLabel),
                const SizedBox(height: 12),
                Text(
                  'Sĩ số: ${englishClass.minStudents}–${englishClass.maxStudents} học viên',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildActions(englishClass, courses),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatus(EnglishClass englishClass) {
    return Chip(
      label: Text(englishClass.statusLabel),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildActions(EnglishClass englishClass, List<Course> courses) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: englishClass.canEdit ? 'Sửa' : 'Lớp đã kết thúc',
          onPressed: _isWorking || !englishClass.canEdit
              ? null
              : () => _openForm(courses, englishClass),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: englishClass.canDelete ? 'Xóa' : 'Chỉ xóa lớp chờ mở',
          onPressed: _isWorking || !englishClass.canDelete
              ? null
              : () => _deleteClass(englishClass),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}

class _ClassFormDialog extends StatefulWidget {
  const _ClassFormDialog({required this.courses, this.englishClass});

  final List<Course> courses;
  final EnglishClass? englishClass;

  @override
  State<_ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends State<_ClassFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  late String _courseId;
  late String _status;
  String? _studyPattern;
  String? _shiftCode;

  @override
  void initState() {
    super.initState();
    final englishClass = widget.englishClass;
    _nameController = TextEditingController(text: englishClass?.name);
    _minController = TextEditingController(
      text: englishClass?.minStudents.toString(),
    );
    _maxController = TextEditingController(
      text: englishClass?.maxStudents.toString(),
    );
    _courseId = englishClass?.courseId ?? widget.courses.first.id;
    _status = englishClass?.status ?? 'pending';
    _studyPattern = englishClass?.studyPattern;
    _shiftCode = englishClass?.shiftCode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  List<String> get _availableStatuses {
    return switch (widget.englishClass?.status) {
      'pending' => const ['pending', 'ongoing'],
      'ongoing' => const ['ongoing', 'completed'],
      'completed' => const ['completed'],
      _ => const ['pending'],
    };
  }

  String _statusLabel(String status) => switch (status) {
    'pending' => 'Chờ mở',
    'ongoing' => 'Đang học',
    'completed' => 'Đã kết thúc',
    _ => status,
  };

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final input = EnglishClassInput.tryParse(
      name: _nameController.text,
      courseId: _courseId,
      minStudents: _minController.text,
      maxStudents: _maxController.text,
      status: _status,
      studyPattern: _studyPattern,
      shiftCode: _shiftCode,
    );
    if (input != null) Navigator.pop(context, input);
  }

  @override
  Widget build(BuildContext context) {
    final canChangeCourse =
        widget.englishClass == null || widget.englishClass!.status == 'pending';
    final canChangeSchedule =
        widget.englishClass == null || widget.englishClass!.canChangeSchedule;
    return AlertDialog(
      title: Text(widget.englishClass == null ? 'Mở lớp học' : 'Sửa lớp học'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Tên lớp học'),
                  validator: (value) =>
                      EnglishClassInput.validateRequired(value, 'tên lớp học'),
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
                  onChanged: canChangeCourse
                      ? (value) {
                          if (value != null) _courseId = value;
                        }
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _studyPattern,
                  decoration: const InputDecoration(labelText: 'Lịch học'),
                  items: ClassSchedule.studyPatterns
                      .map(
                        (pattern) => DropdownMenuItem(
                          value: pattern,
                          child: Text('Lịch $pattern'),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      EnglishClassInput.validateSelection(value, 'lịch học'),
                  onChanged: canChangeSchedule
                      ? (value) => setState(() => _studyPattern = value)
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _shiftCode,
                  decoration: const InputDecoration(labelText: 'Ca học'),
                  items: ClassShift.values
                      .map(
                        (shift) => DropdownMenuItem(
                          value: shift.code,
                          child: Text(shift.label),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      EnglishClassInput.validateSelection(value, 'ca học'),
                  onChanged: canChangeSchedule
                      ? (value) => setState(() => _shiftCode = value)
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _minController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sĩ số tối thiểu',
                  ),
                  validator: EnglishClassInput.validateMinStudents,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _maxController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sĩ số tối đa'),
                  validator: (value) => EnglishClassInput.validateMaxStudents(
                    value,
                    _minController.text,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Trạng thái'),
                  items: _availableStatuses
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(_statusLabel(status)),
                        ),
                      )
                      .toList(),
                  onChanged: widget.englishClass == null
                      ? null
                      : (value) {
                          if (value != null) _status = value;
                        },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
