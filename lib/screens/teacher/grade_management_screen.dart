import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/english_class.dart';
import '../../models/learning_result.dart';
import '../../models/student.dart';
import '../../services/enrollment_service.dart';
import '../../services/learning_result_service.dart';
import '../../services/teacher_assignment_service.dart';

class GradeManagementScreen extends StatefulWidget {
  const GradeManagementScreen({super.key});

  @override
  State<GradeManagementScreen> createState() => _GradeManagementScreenState();
}

class _GradeManagementScreenState extends State<GradeManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  late final String? _userUid;
  Stream<List<EnglishClass>>? _classes;
  String? _selectedClassId;
  Stream<List<Student>>? _students;
  Stream<List<LearningResult>>? _results;
  final Map<String, _ResultDraft> _drafts = {};
  String? _draftClassId;
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

  @override
  void dispose() {
    _disposeDrafts();
    super.dispose();
  }

  void _disposeDrafts() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    _drafts.clear();
  }

  void _selectClass(String classId) {
    _disposeDrafts();
    setState(() {
      _selectedClassId = classId;
      _draftClassId = null;
      _students = EnrollmentService.instance.watchActiveStudentsForClass(
        classId,
      );
      _results = LearningResultService.instance.watchResultsForClass(classId);
    });
  }

  void _initializeDrafts(
    String classId,
    List<Student> students,
    List<LearningResult> results,
  ) {
    final sameStudents =
        _drafts.length == students.length &&
        students.every((student) => _drafts.containsKey(student.id));
    if (_draftClassId == classId && sameStudents) {
      for (final result in results) {
        _drafts[result.studentId]?.updatedAt = result.updatedAt;
      }
      return;
    }
    _disposeDrafts();
    final resultByStudent = {
      for (final result in results) result.studentId: result,
    };
    for (final student in students) {
      _drafts[student.id] = _ResultDraft(resultByStudent[student.id]);
    }
    _draftClassId = classId;
  }

  Future<void> _save() async {
    final classId = _selectedClassId;
    if (classId == null || !_formKey.currentState!.validate()) return;
    final inputs = _drafts.entries
        .where((entry) => entry.value.dirty)
        .map(
          (entry) => LearningResultInput.tryCreate(
            studentId: entry.key,
            midtermScore: entry.value.midterm.text,
            finalScore: entry.value.finalScore.text,
            comment: entry.value.comment.text,
          ),
        )
        .whereType<LearningResultInput>()
        .toList();
    if (inputs.isEmpty) {
      _showMessage('Không có thay đổi cần lưu.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await LearningResultService.instance.saveResults(
        classId: classId,
        inputs: inputs,
      );
      if (mounted) {
        for (final draft in _drafts.values) {
          draft.dirty = false;
        }
        _showMessage('Đã lưu điểm và nhận xét học viên.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is StateError
              ? error.message.toString()
              : 'Không thể lưu kết quả. Hãy kiểm tra quyền truy cập.',
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
      return const _GradeMessage(
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
          return const _GradeMessage(
            icon: Icons.cloud_off_outlined,
            message: 'Không thể tải danh sách lớp được phân công.',
          );
        }
        final classes = classSnapshot.data ?? const <EnglishClass>[];
        if (classes.isEmpty) {
          return const _GradeMessage(
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
            if (mounted && _selectedClassId == null) {
              _selectClass(classes.first.id);
            }
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
            'Điểm và nhận xét học viên',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text('Điểm giữa kỳ và cuối kỳ sử dụng thang điểm 0–10.'),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
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
          ),
          if (_isSaving) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 20),
          Expanded(
            child: selectedClass == null
                ? const Center(child: CircularProgressIndicator())
                : _buildResultList(selectedClass.id),
          ),
        ],
      ),
    );
  }

  Widget _buildResultList(String classId) {
    if (_students == null || _results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<List<Student>>(
      stream: _students,
      builder: (context, studentSnapshot) {
        if (studentSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (studentSnapshot.hasError) {
          return const _GradeMessage(
            icon: Icons.cloud_off_outlined,
            message: 'Không thể tải học viên của lớp.',
          );
        }
        final students = studentSnapshot.data ?? const <Student>[];
        if (students.isEmpty) {
          return const _GradeMessage(
            icon: Icons.groups_outlined,
            message: 'Lớp chưa có học viên đang đăng ký.',
          );
        }
        return StreamBuilder<List<LearningResult>>(
          stream: _results,
          builder: (context, resultSnapshot) {
            if (resultSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (resultSnapshot.hasError) {
              return const _GradeMessage(
                icon: Icons.cloud_off_outlined,
                message: 'Không thể tải điểm và nhận xét đã lưu.',
              );
            }
            _initializeDrafts(
              classId,
              students,
              resultSnapshot.data ?? const <LearningResult>[],
            );
            return Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView.separated(
                      itemCount: students.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final student = students[index];
                        return _ResultEditor(
                          student: student,
                          draft: _drafts[student.id]!,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Lưu kết quả'),
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
}

class _ResultDraft {
  _ResultDraft(LearningResult? result)
    : midterm = TextEditingController(text: _scoreText(result?.midtermScore)),
      finalScore = TextEditingController(text: _scoreText(result?.finalScore)),
      comment = TextEditingController(text: result?.comment),
      updatedAt = result?.updatedAt;

  final TextEditingController midterm;
  final TextEditingController finalScore;
  final TextEditingController comment;
  DateTime? updatedAt;
  var dirty = false;

  static String _scoreText(double? score) =>
      score == null ? '' : LearningResult.scoreLabel(score);

  void dispose() {
    midterm.dispose();
    finalScore.dispose();
    comment.dispose();
  }
}

class _ResultEditor extends StatelessWidget {
  const _ResultEditor({required this.student, required this.draft});

  final Student student;
  final _ResultDraft draft;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final name = Text(
              student.fullName,
              style: Theme.of(context).textTheme.titleMedium,
            );
            final updated = Text(
              draft.updatedAt == null
                  ? 'Chưa cập nhật'
                  : 'Cập nhật: ${_formatDateTime(draft.updatedAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            );
            final midterm = TextFormField(
              controller: draft.midterm,
              decoration: const InputDecoration(labelText: 'Giữa kỳ'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: LearningResultInput.validateScore,
              onChanged: (_) => draft.dirty = true,
            );
            final finalScore = TextFormField(
              controller: draft.finalScore,
              decoration: const InputDecoration(labelText: 'Cuối kỳ'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: LearningResultInput.validateScore,
              onChanged: (_) => draft.dirty = true,
            );
            final comment = TextFormField(
              controller: draft.comment,
              decoration: const InputDecoration(labelText: 'Nhận xét'),
              maxLines: 2,
              maxLength: 1000,
              validator: LearningResultInput.validateComment,
              onChanged: (_) => draft.dirty = true,
            );
            if (constraints.maxWidth >= 760) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 200,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [name, const SizedBox(height: 4), updated],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(width: 120, child: midterm),
                  const SizedBox(width: 12),
                  SizedBox(width: 120, child: finalScore),
                  const SizedBox(width: 12),
                  Expanded(child: comment),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                name,
                const SizedBox(height: 4),
                updated,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: midterm),
                    const SizedBox(width: 12),
                    Expanded(child: finalScore),
                  ],
                ),
                const SizedBox(height: 12),
                comment,
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatDateTime(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

class _GradeMessage extends StatelessWidget {
  const _GradeMessage({required this.icon, required this.message});

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
