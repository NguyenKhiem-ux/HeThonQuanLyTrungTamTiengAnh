class Course {
  const Course({
    required this.id,
    required this.name,
    required this.program,
    required this.durationMonths,
    required this.standardTuition,
  });

  final String id;
  final String name;
  final String program;
  final int? durationMonths;
  final num standardTuition;

  String get durationLabel => durationMonths == null
      ? 'Chưa cập nhật thời lượng theo tháng'
      : '$durationMonths tháng';

  factory Course.fromMap(String id, Map<String, dynamic> data) {
    final name = data['name'];
    final program = data['program'];
    final durationMonths = data['durationMonths'];
    final standardTuition = data['standardTuition'];

    if (name is! String ||
        name.trim().isEmpty ||
        program is! String ||
        program.trim().isEmpty ||
        (durationMonths != null &&
            (durationMonths is! int || durationMonths <= 0)) ||
        standardTuition is! num ||
        !standardTuition.isFinite ||
        standardTuition < 0) {
      throw const FormatException('Dữ liệu khóa học không hợp lệ.');
    }

    return Course(
      id: id,
      name: name.trim(),
      program: program.trim(),
      durationMonths: durationMonths as int?,
      standardTuition: standardTuition,
    );
  }
}

class CourseInput {
  const CourseInput({
    required this.name,
    required this.program,
    required this.durationMonths,
    required this.standardTuition,
  });

  final String name;
  final String program;
  final int durationMonths;
  final num standardTuition;

  static String? validateRequired(String? value, String fieldName) =>
      (value?.trim().isEmpty ?? true) ? 'Vui lòng nhập $fieldName.' : null;

  static String? validateDuration(String? value) {
    final duration = int.tryParse(value?.trim() ?? '');
    return duration == null || duration <= 0
        ? 'Thời lượng phải là số nguyên lớn hơn 0.'
        : null;
  }

  static String? validateTuition(String? value) {
    final tuition = num.tryParse(value?.trim() ?? '');
    return tuition == null || !tuition.isFinite || tuition < 0
        ? 'Học phí phải là số lớn hơn hoặc bằng 0.'
        : null;
  }

  static CourseInput? tryParse({
    required String name,
    required String program,
    required String durationMonths,
    required String standardTuition,
  }) {
    final duration = int.tryParse(durationMonths.trim());
    final tuition = num.tryParse(standardTuition.trim());
    if (name.trim().isEmpty ||
        program.trim().isEmpty ||
        duration == null ||
        duration <= 0 ||
        tuition == null ||
        !tuition.isFinite ||
        tuition < 0) {
      return null;
    }

    return CourseInput(
      name: name.trim(),
      program: program.trim(),
      durationMonths: duration,
      standardTuition: tuition,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'program': program,
    'durationMonths': durationMonths,
    'standardTuition': standardTuition,
  };
}
