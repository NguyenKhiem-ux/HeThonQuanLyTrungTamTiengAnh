class ClassShift {
  const ClassShift({
    required this.code,
    required this.name,
    required this.startMinute,
    required this.endMinute,
  });

  static const evening1 = ClassShift(
    code: 'evening_1',
    name: 'Ca 1',
    startMinute: 1080,
    endMinute: 1185,
  );
  static const evening2 = ClassShift(
    code: 'evening_2',
    name: 'Ca 2',
    startMinute: 1200,
    endMinute: 1305,
  );
  static const values = [evening1, evening2];

  final String code;
  final String name;
  final int startMinute;
  final int endMinute;

  String get timeLabel =>
      '${_formatMinute(startMinute)}–${_formatMinute(endMinute)}';
  String get label => '$name: $timeLabel';

  static ClassShift? fromCode(String? code) {
    for (final shift in values) {
      if (shift.code == code) return shift;
    }
    return null;
  }
}

class ClassSchedule {
  const ClassSchedule._();

  static const studyPatterns = ['246', '357'];

  static bool isValidPattern(String? value) => studyPatterns.contains(value);

  static List<int> weekdaysFor(String? studyPattern) => switch (studyPattern) {
    '246' => const [1, 3, 5],
    '357' => const [2, 4, 6],
    _ => const [],
  };

  static String patternLabel(String? studyPattern) => switch (studyPattern) {
    '246' => 'Lịch 246',
    '357' => 'Lịch 357',
    _ => 'Chưa thiết lập lịch học',
  };

  static String shiftLabel(String? shiftCode) =>
      ClassShift.fromCode(shiftCode)?.label ?? 'Chưa thiết lập ca học';

  static bool allocationMatches({
    required String? studyPattern,
    required String? shiftCode,
    required int weekday,
    required int startMinute,
    required int endMinute,
  }) {
    final shift = ClassShift.fromCode(shiftCode);
    return shift != null &&
        weekdaysFor(studyPattern).contains(weekday) &&
        startMinute == shift.startMinute &&
        endMinute == shift.endMinute;
  }
}

class EnglishClass {
  const EnglishClass({
    required this.id,
    required this.name,
    required this.courseId,
    required this.minStudents,
    required this.maxStudents,
    required this.status,
    this.studyPattern,
    this.shiftCode,
  });

  static const validStatuses = {'pending', 'ongoing', 'completed'};

  final String id;
  final String name;
  final String courseId;
  final int minStudents;
  final int maxStudents;
  final String status;
  final String? studyPattern;
  final String? shiftCode;

  bool get canEdit => status != 'completed';
  bool get canChangeSchedule => status == 'pending';
  bool get canDelete => status == 'pending';
  bool get hasConfiguredSchedule =>
      ClassSchedule.isValidPattern(studyPattern) &&
      ClassShift.fromCode(shiftCode) != null;
  String get studyPatternLabel => ClassSchedule.patternLabel(studyPattern);
  String get shiftLabel => ClassSchedule.shiftLabel(shiftCode);

  bool canDeleteWithAllocations({required bool hasAllocations}) =>
      canDelete && !hasAllocations;

  bool allocationMatches({
    required int weekday,
    required int startMinute,
    required int endMinute,
  }) => ClassSchedule.allocationMatches(
    studyPattern: studyPattern,
    shiftCode: shiftCode,
    weekday: weekday,
    startMinute: startMinute,
    endMinute: endMinute,
  );

  String get statusLabel => switch (status) {
    'pending' => 'Chờ mở',
    'ongoing' => 'Đang học',
    'completed' => 'Đã kết thúc',
    _ => status,
  };

  static bool isValidStatusTransition(String current, String next) {
    if (!validStatuses.contains(current) || !validStatuses.contains(next)) {
      return false;
    }
    return current == next ||
        (current == 'pending' && next == 'ongoing') ||
        (current == 'ongoing' && next == 'completed');
  }

  bool canChangeScheduleTo(String nextPattern, String nextShiftCode) =>
      canChangeSchedule ||
      (studyPattern == nextPattern && shiftCode == nextShiftCode);

  factory EnglishClass.fromMap(String id, Map<String, dynamic> data) {
    final name = data['name'];
    final courseId = data['courseId'];
    final minStudents = data['minStudents'];
    final maxStudents = data['maxStudents'];
    final status = data['status'];
    final studyPattern = data['studyPattern'];
    final shiftCode = data['shiftCode'];

    if (name is! String ||
        name.trim().isEmpty ||
        courseId is! String ||
        courseId.trim().isEmpty ||
        minStudents is! int ||
        minStudents <= 0 ||
        maxStudents is! int ||
        maxStudents < minStudents ||
        status is! String ||
        !validStatuses.contains(status) ||
        (studyPattern != null && !ClassSchedule.isValidPattern(studyPattern)) ||
        (shiftCode != null && ClassShift.fromCode(shiftCode) == null)) {
      throw const FormatException('Dữ liệu lớp học không hợp lệ.');
    }

    return EnglishClass(
      id: id,
      name: name.trim(),
      courseId: courseId.trim(),
      minStudents: minStudents,
      maxStudents: maxStudents,
      status: status,
      studyPattern: studyPattern as String?,
      shiftCode: shiftCode as String?,
    );
  }
}

class EnglishClassInput {
  const EnglishClassInput({
    required this.name,
    required this.courseId,
    required this.minStudents,
    required this.maxStudents,
    required this.status,
    required this.studyPattern,
    required this.shiftCode,
  });

  final String name;
  final String courseId;
  final int minStudents;
  final int maxStudents;
  final String status;
  final String studyPattern;
  final String shiftCode;

  static String? validateRequired(String? value, String fieldName) =>
      (value?.trim().isEmpty ?? true) ? 'Vui lòng nhập $fieldName.' : null;

  static String? validateSelection(String? value, String fieldName) =>
      value == null || value.isEmpty ? 'Vui lòng chọn $fieldName.' : null;

  static String? validateMinStudents(String? value) {
    final minStudents = int.tryParse(value?.trim() ?? '');
    return minStudents == null || minStudents <= 0
        ? 'Sĩ số tối thiểu phải là số nguyên lớn hơn 0.'
        : null;
  }

  static String? validateMaxStudents(String? value, String minValue) {
    final minStudents = int.tryParse(minValue.trim());
    final maxStudents = int.tryParse(value?.trim() ?? '');
    if (maxStudents == null) {
      return 'Sĩ số tối đa phải là số nguyên.';
    }
    if (minStudents == null || minStudents <= 0 || maxStudents < minStudents) {
      return 'Sĩ số tối đa phải lớn hơn hoặc bằng sĩ số tối thiểu.';
    }
    return null;
  }

  static EnglishClassInput? tryParse({
    required String name,
    required String courseId,
    required String minStudents,
    required String maxStudents,
    required String status,
    String? studyPattern,
    String? shiftCode,
  }) {
    final min = int.tryParse(minStudents.trim());
    final max = int.tryParse(maxStudents.trim());
    if (name.trim().isEmpty ||
        courseId.trim().isEmpty ||
        min == null ||
        min <= 0 ||
        max == null ||
        max < min ||
        !EnglishClass.validStatuses.contains(status) ||
        !ClassSchedule.isValidPattern(studyPattern) ||
        ClassShift.fromCode(shiftCode) == null) {
      return null;
    }

    return EnglishClassInput(
      name: name.trim(),
      courseId: courseId.trim(),
      minStudents: min,
      maxStudents: max,
      status: status,
      studyPattern: studyPattern!,
      shiftCode: shiftCode!,
    );
  }
}

String _formatMinute(int minute) {
  final hours = minute ~/ 60;
  final minutes = minute % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}
