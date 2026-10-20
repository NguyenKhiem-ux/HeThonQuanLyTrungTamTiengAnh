import 'package:flutter/material.dart';

import '../../models/student.dart';
import '../../services/student_service.dart';

class StudentManagementScreen extends StatefulWidget {
  const StudentManagementScreen({super.key});

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen> {
  final _searchController = TextEditingController();
  late Stream<List<Student>> _students;
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
    _students = StudentService.instance.watchStudents();
  }

  Future<void> _openForm([Student? student]) async {
    final input = await showDialog<StudentInput>(
      context: context,
      builder: (_) => _StudentFormDialog(student: student),
    );
    if (input == null || !mounted) return;

    setState(() => _isWorking = true);
    try {
      if (student == null) {
        await StudentService.instance.addStudent(input);
      } else {
        await StudentService.instance.updateStudent(student.id, input);
      }
      if (mounted) {
        _showMessage(
          student == null
              ? 'Đã thêm hồ sơ học viên.'
              : 'Đã cập nhật hồ sơ học viên.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is StateError
              ? error.message.toString()
              : 'Không thể lưu hồ sơ học viên. Hãy kiểm tra quyền truy cập.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  void _showDetails(Student student) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(student.fullName),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow(label: 'Email', value: _valueOrEmpty(student.email)),
                _DetailRow(
                  label: 'Điện thoại',
                  value: _valueOrEmpty(student.phone),
                ),
                _DetailRow(
                  label: 'Ngày sinh',
                  value: student.dateOfBirth == null
                      ? 'Chưa cung cấp'
                      : _formatDate(student.dateOfBirth!),
                ),
                _DetailRow(label: 'Giới tính', value: student.genderLabel),
                _DetailRow(label: 'Trạng thái', value: student.statusLabel),
                _DetailRow(
                  label: 'UID tài khoản',
                  value: student.userUid ?? 'Chưa liên kết',
                ),
                _DetailRow(
                  label: 'Ghi chú tư vấn',
                  value: _valueOrEmpty(student.consultationNote),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openForm(student);
            },
            child: const Text('Sửa'),
          ),
        ],
      ),
    );
  }

  String _valueOrEmpty(String value) => value.isEmpty ? 'Chưa cung cấp' : value;

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
                'Quản lý học viên',
                style: Theme.of(context).textTheme.headlineMedium,
              );
              final button = FilledButton.icon(
                onPressed: _isWorking ? null : () => _openForm(),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Thêm học viên'),
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
          const SizedBox(height: 20),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Tìm theo họ tên, email hoặc số điện thoại',
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
              builder: (context, constraints) => StreamBuilder<List<Student>>(
                stream: _students,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _MessageState(
                      icon: Icons.cloud_off_outlined,
                      message: 'Không thể tải danh sách học viên.',
                      onRetry: () => setState(_reload),
                    );
                  }
                  final allStudents = snapshot.data ?? const <Student>[];
                  if (allStudents.isEmpty) {
                    return const _MessageState(
                      icon: Icons.groups_outlined,
                      message: 'Chưa có hồ sơ học viên nào.',
                    );
                  }
                  final query = _searchController.text.trim().toLowerCase();
                  final students = allStudents.where((student) {
                    return query.isEmpty ||
                        student.fullName.toLowerCase().contains(query) ||
                        student.email.toLowerCase().contains(query) ||
                        student.phone.toLowerCase().contains(query);
                  }).toList();
                  if (students.isEmpty) {
                    return const _MessageState(
                      icon: Icons.search_off_outlined,
                      message: 'Không tìm thấy học viên phù hợp.',
                    );
                  }
                  return constraints.maxWidth >= 800
                      ? _buildTable(students, constraints.maxWidth)
                      : _buildCards(students);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<Student> students, double minWidth) {
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
                  DataColumn(label: Text('Họ tên')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Điện thoại')),
                  DataColumn(label: Text('Trạng thái')),
                  DataColumn(label: Text('Thao tác')),
                ],
                rows: students
                    .map(
                      (student) => DataRow(
                        cells: [
                          DataCell(Text(student.fullName)),
                          DataCell(Text(_valueOrEmpty(student.email))),
                          DataCell(Text(_valueOrEmpty(student.phone))),
                          DataCell(_StudentStatus(student: student)),
                          DataCell(_actions(student)),
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

  Widget _buildCards(List<Student> students) {
    return ListView.separated(
      itemCount: students.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final student = students[index];
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
                        student.fullName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _StudentStatus(student: student),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_valueOrEmpty(student.email)),
                const SizedBox(height: 4),
                Text(_valueOrEmpty(student.phone)),
                Align(
                  alignment: Alignment.centerRight,
                  child: _actions(student),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _actions(Student student) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Xem chi tiết',
          onPressed: () => _showDetails(student),
          icon: const Icon(Icons.visibility_outlined),
        ),
        IconButton(
          tooltip: 'Sửa',
          onPressed: _isWorking ? null : () => _openForm(student),
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    );
  }
}

class _StudentFormDialog extends StatefulWidget {
  const _StudentFormDialog({this.student});

  final Student? student;

  @override
  State<_StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<_StudentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _noteController;
  late final TextEditingController _uidController;
  DateTime? _dateOfBirth;
  late String _gender;
  late String _status;

  @override
  void initState() {
    super.initState();
    final student = widget.student;
    _fullNameController = TextEditingController(text: student?.fullName);
    _emailController = TextEditingController(text: student?.email);
    _phoneController = TextEditingController(text: student?.phone);
    _noteController = TextEditingController(text: student?.consultationNote);
    _uidController = TextEditingController(text: student?.userUid);
    _dateOfBirth = student?.dateOfBirth;
    _gender = student?.gender ?? '';
    _status = student?.status ?? 'active';
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    _uidController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 18),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (date != null && mounted) setState(() => _dateOfBirth = date);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final input = StudentInput.tryCreate(
      fullName: _fullNameController.text,
      email: _emailController.text,
      phone: _phoneController.text,
      dateOfBirth: _dateOfBirth,
      gender: _gender.isEmpty ? null : _gender,
      consultationNote: _noteController.text,
      status: _status,
      userUid: _uidController.text,
    );
    if (input != null) Navigator.pop(context, input);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.student == null ? 'Thêm học viên' : 'Sửa hồ sơ học viên',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _fullNameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Họ tên'),
                  validator: StudentInput.validateFullName,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email (không bắt buộc)',
                  ),
                  validator: StudentInput.validateEmail,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Số điện thoại'),
                  validator: StudentInput.validatePhone,
                ),
                const SizedBox(height: 16),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Ngày sinh (không bắt buộc)',
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dateOfBirth == null
                              ? 'Chưa chọn'
                              : _formatDate(_dateOfBirth!),
                        ),
                      ),
                      if (_dateOfBirth != null)
                        IconButton(
                          tooltip: 'Xóa ngày sinh',
                          onPressed: () => setState(() => _dateOfBirth = null),
                          icon: const Icon(Icons.clear),
                        ),
                      IconButton(
                        tooltip: 'Chọn ngày sinh',
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Giới tính'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Chưa cung cấp')),
                    DropdownMenuItem(value: 'male', child: Text('Nam')),
                    DropdownMenuItem(value: 'female', child: Text('Nữ')),
                    DropdownMenuItem(value: 'other', child: Text('Khác')),
                  ],
                  onChanged: (value) => _gender = value ?? '',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú tư vấn (không bắt buộc)',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _uidController,
                  decoration: const InputDecoration(
                    labelText: 'UID tài khoản Student (không bắt buộc)',
                    helperText: 'Chỉ liên kết khi đã biết chính xác UID.',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Trạng thái'),
                  items: const [
                    DropdownMenuItem(
                      value: 'active',
                      child: Text('Đang hoạt động'),
                    ),
                    DropdownMenuItem(
                      value: 'inactive',
                      child: Text('Ngừng hoạt động'),
                    ),
                  ],
                  onChanged: (value) {
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

class _StudentStatus extends StatelessWidget {
  const _StudentStatus({required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(student.statusLabel),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 3),
          Text(value),
        ],
      ),
    );
  }
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

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';
