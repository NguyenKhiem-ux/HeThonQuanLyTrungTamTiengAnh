class Teacher {
  const Teacher({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.specialty,
    required this.status,
    required this.userUid,
  });

  static const validStatuses = {'active', 'inactive'};

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String specialty;
  final String status;
  final String? userUid;

  bool get isActive => status == 'active';
  bool get isLinked => userUid != null;
  bool get isAssignable => isActive && isLinked;
  String get statusLabel => isActive ? 'Đang hoạt động' : 'Ngừng hoạt động';
  String get specialtyLabel =>
      specialty.isEmpty ? 'Chưa cập nhật chuyên môn' : specialty;

  factory Teacher.fromMap(String id, Map<String, dynamic> data) {
    final fullName = data['fullName'];
    final email = data['email'];
    final phone = data['phone'];
    final specialty = data['specialty'];
    final status = data['status'];
    final userUid = data['userUid'];
    if (fullName is! String ||
        fullName.trim().isEmpty ||
        email is! String ||
        !TeacherInput.isValidEmail(email) ||
        phone is! String ||
        (phone.trim().isNotEmpty && !TeacherInput.isValidPhone(phone)) ||
        specialty is! String ||
        status is! String ||
        !validStatuses.contains(status) ||
        (userUid != null && (userUid is! String || userUid.trim().isEmpty))) {
      throw const FormatException('Dữ liệu giáo viên không hợp lệ.');
    }

    return Teacher(
      id: id,
      fullName: fullName.trim(),
      email: email.trim(),
      phone: phone,
      specialty: specialty.trim(),
      status: status,
      userUid: userUid is String ? userUid.trim() : null,
    );
  }
}

class TeacherProfileSyncPolicy {
  const TeacherProfileSyncPolicy._();

  static bool isActiveTeacherAccount({
    required String role,
    required String status,
  }) => role == 'teacher' && status == 'active';

  static bool needsSync({
    required String role,
    required String status,
    required Teacher? profile,
  }) =>
      isActiveTeacherAccount(role: role, status: status) &&
      (profile == null || !profile.isAssignable);

  static bool hasDuplicateLink(Iterable<Teacher> teachers, String userUid) =>
      teachers.where((teacher) => teacher.userUid == userUid).length > 1;
}

class TeacherInput {
  const TeacherInput({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.specialty,
    required this.status,
    required this.userUid,
  });

  final String fullName;
  final String email;
  final String phone;
  final String specialty;
  final String status;
  final String? userUid;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phonePattern = RegExp(r'^\+?[0-9]{8,15}$');

  static bool isValidEmail(String value) =>
      _emailPattern.hasMatch(value.trim());

  static String normalizePhone(String value) =>
      value.trim().replaceAll(RegExp(r'[\s.-]'), '');

  static bool isValidPhone(String value) =>
      _phonePattern.hasMatch(normalizePhone(value));

  static String? validateRequired(String? value, String fieldName) =>
      (value?.trim().isEmpty ?? true) ? 'Vui lòng nhập $fieldName.' : null;

  static String? validateEmail(String? value) =>
      isValidEmail(value ?? '') ? null : 'Email không đúng định dạng.';

  static String? validatePhone(String? value) => isValidPhone(value ?? '')
      ? null
      : 'Số điện thoại phải có từ 8 đến 15 chữ số.';

  static TeacherInput? tryCreate({
    required String fullName,
    required String email,
    required String phone,
    required String specialty,
    required String status,
    required String userUid,
  }) {
    final normalizedPhone = normalizePhone(phone);
    final normalizedUid = userUid.trim();
    if (fullName.trim().isEmpty ||
        !isValidEmail(email) ||
        !isValidPhone(normalizedPhone) ||
        specialty.trim().isEmpty ||
        !Teacher.validStatuses.contains(status)) {
      return null;
    }
    return TeacherInput(
      fullName: fullName.trim(),
      email: email.trim(),
      phone: normalizedPhone,
      specialty: specialty.trim(),
      status: status,
      userUid: normalizedUid.isEmpty ? null : normalizedUid,
    );
  }
}
