import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../services/course_service.dart';

class CourseManagementScreen extends StatefulWidget {
  const CourseManagementScreen({super.key});

  @override
  State<CourseManagementScreen> createState() => _CourseManagementScreenState();
}

class _CourseManagementScreenState extends State<CourseManagementScreen> {
  final _searchController = TextEditingController();
  late Stream<List<Course>> _courses;
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
  }

  Future<void> _openForm([Course? course]) async {
    final input = await showDialog<CourseInput>(
      context: context,
      builder: (_) => _CourseFormDialog(course: course),
    );
    if (input == null || !mounted) return;

    setState(() => _isWorking = true);
    try {
      if (course == null) {
        await CourseService.instance.addCourse(input);
      } else {
        await CourseService.instance.updateCourse(course.id, input);
      }
      if (mounted) {
        _showMessage(
          course == null
              ? 'Đã thêm khóa học thành công.'
              : 'Đã cập nhật khóa học thành công.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Không thể lưu khóa học. Hãy kiểm tra kết nối và quyền truy cập.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _deleteCourse(Course course) async {
    if (_isWorking) return;

    setState(() => _isWorking = true);
    late bool hasClasses;
    try {
      hasClasses = await CourseService.instance.hasClasses(course.id);
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Không thể kiểm tra lớp học liên quan. Khóa học chưa bị xóa.',
          isError: true,
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }

    if (!mounted) return;
    if (hasClasses) {
      _showMessage('Không thể xóa khóa học đang có lớp mở', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa khóa học?'),
        content: Text(
          'Bạn có chắc muốn xóa khóa học “${course.name}”? '
          'Thao tác này không thể hoàn tác.',
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
      // shortcut: kiểm tra tham chiếu ở client có thể race; chuyển sang backend khi có ghi đồng thời.
      await CourseService.instance.deleteCourse(course.id);
      if (mounted) _showMessage('Đã xóa khóa học.');
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Không thể xóa khóa học. Hãy kiểm tra kết nối và quyền truy cập.',
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
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                'Quản lý khóa học',
                style: Theme.of(context).textTheme.headlineMedium,
              );
              final addButton = FilledButton.icon(
                onPressed: _isWorking ? null : _openForm,
                icon: const Icon(Icons.add),
                label: const Text('Thêm khóa học'),
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
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Tìm theo tên khóa học',
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
          ),
          if (_isWorking) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 20),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => StreamBuilder<List<Course>>(
                stream: _courses,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _MessageState(
                      icon: Icons.cloud_off_outlined,
                      message:
                          'Không thể tải danh sách khóa học. Hãy kiểm tra kết nối và quyền truy cập.',
                      actionLabel: 'Thử lại',
                      onAction: () => setState(_reload),
                    );
                  }

                  final allCourses = snapshot.data ?? const <Course>[];
                  if (allCourses.isEmpty) {
                    return const _MessageState(
                      icon: Icons.menu_book_outlined,
                      message: 'Chưa có khóa học nào.',
                    );
                  }

                  final query = _searchController.text.trim().toLowerCase();
                  final courses = query.isEmpty
                      ? allCourses
                      : allCourses
                            .where(
                              (course) =>
                                  course.name.toLowerCase().contains(query),
                            )
                            .toList();
                  if (courses.isEmpty) {
                    return const _MessageState(
                      icon: Icons.search_off_outlined,
                      message: 'Không tìm thấy khóa học phù hợp.',
                    );
                  }

                  return constraints.maxWidth >= 760
                      ? _buildTable(courses, constraints.maxWidth)
                      : _buildCards(courses);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<Course> courses, double minWidth) {
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
                  DataColumn(label: Text('Tên khóa học')),
                  DataColumn(label: Text('Chương trình')),
                  DataColumn(label: Text('Thời lượng')),
                  DataColumn(label: Text('Học phí')),
                  DataColumn(label: Text('Thao tác')),
                ],
                rows: courses
                    .map(
                      (course) => DataRow(
                        cells: [
                          DataCell(Text(course.name)),
                          DataCell(Text(course.program)),
                          DataCell(Text(course.durationLabel)),
                          DataCell(
                            Text(_formatTuition(course.standardTuition)),
                          ),
                          DataCell(_buildActions(course)),
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

  Widget _buildCards(List<Course> courses) {
    return ListView.separated(
      itemCount: courses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final course = courses[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(course.program),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text(course.durationLabel),
                    Text(_formatTuition(course.standardTuition)),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildActions(course),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions(Course course) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Sửa',
          onPressed: _isWorking ? null : () => _openForm(course),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Xóa',
          onPressed: _isWorking ? null : () => _deleteCourse(course),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  String _formatTuition(num value) {
    final text = value % 1 == 0 ? value.toInt().toString() : value.toString();
    final parts = text.split('.');
    final integer = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}.',
    );
    return '${parts.length == 1 ? integer : '$integer,${parts[1]}'} VNĐ';
  }
}

class _CourseFormDialog extends StatefulWidget {
  const _CourseFormDialog({this.course});

  final Course? course;

  @override
  State<_CourseFormDialog> createState() => _CourseFormDialogState();
}

class _CourseFormDialogState extends State<_CourseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _programController;
  late final TextEditingController _durationController;
  late final TextEditingController _tuitionController;

  @override
  void initState() {
    super.initState();
    final course = widget.course;
    _nameController = TextEditingController(text: course?.name);
    _programController = TextEditingController(text: course?.program);
    _durationController = TextEditingController(
      text: course?.durationMonths?.toString() ?? '',
    );
    _tuitionController = TextEditingController(
      text: course?.standardTuition.toString(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _programController.dispose();
    _durationController.dispose();
    _tuitionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final input = CourseInput.tryParse(
      name: _nameController.text,
      program: _programController.text,
      durationMonths: _durationController.text,
      standardTuition: _tuitionController.text,
    );
    if (input != null) Navigator.pop(context, input);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.course == null ? 'Thêm khóa học' : 'Sửa khóa học'),
      content: SizedBox(
        width: 480,
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
                  decoration: const InputDecoration(labelText: 'Tên khóa học'),
                  validator: (value) =>
                      CourseInput.validateRequired(value, 'tên khóa học'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _programController,
                  decoration: const InputDecoration(
                    labelText: 'Chương trình học',
                  ),
                  maxLines: 2,
                  validator: (value) =>
                      CourseInput.validateRequired(value, 'chương trình học'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Thời lượng (tháng)',
                  ),
                  validator: CourseInput.validateDuration,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _tuitionController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Học phí tiêu chuẩn (VNĐ)',
                  ),
                  validator: CourseInput.validateTuition,
                  onFieldSubmitted: (_) => _submit(),
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
