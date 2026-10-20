import 'package:cloud_firestore/cloud_firestore.dart';

class Student {
  const Student({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.dateOfBirth,
    required this.gender,
    required this.consultationNote,
    required this.status,
    required this.userUid,
  });

  static const validStatuses = {'active', 'inactive'};
  static const validGenders = {'male', 'female', 'other'};

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final DateTime? dateOfBirth;
  final String? gender;
  final String consultationNote;
  final String status;
  final String? userUid;

  bool get isActive => status == 'active';
  String get statusLabel => isActive ? 'Đang hoạt động' : 'Ngừng hoạt động';
  String get genderLabel => switch (gender) {
    'male' => 'Nam',
    'female' => 'Nữ',
    'other' => 'Khác',
    _ => 'Chưa cung cấp',
  };

  factory Student.fromMap(String id, Map<String, dynamic> data) {
    final fullName = data['fullName'];
    final email = data['email'];
    final phone = data['phone'];
    final dateOfBirth = data['dateOfBirth'];
    final gender = data['gender'];
    final consultationNote = data['consultationNote'];
    final status = data['status'];
    final userUid = data['userUid'];
    if (fullName is! String ||
        fullName.trim().isEmpty ||
        email is! String ||
        phone is! String ||
        !StudentInput.isValidEmail(email) ||
        !StudentInput.isValidPhone(phone) ||
        (dateOfBirth != null && dateOfBirth is! Timestamp) ||
        (gender != null &&
            (gender is! String || !validGenders.contains(gender))) ||
        consultationNote is! String ||
        status is! String ||
        !validStatuses.contains(status) ||
        (userUid != null && (userUid is! String || userUid.trim().isEmpty))) {
      throw const FormatException('Dữ liệu học viên không hợp lệ.');
    }

    return Student(
      id: id,
      fullName: fullName.trim(),
      email: email.trim(),
      phone: phone,
      dateOfBirth: dateOfBirth is Timestamp ? dateOfBirth.toDate() : null,
      gender: gender as String?,
      consultationNote: consultationNote.trim(),
      status: status,
      userUid: userUid is String ? userUid.trim() : null,
    );
  }
}

class StudentInput {
  const StudentInput({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.dateOfBirth,
    required this.gender,
    required this.consultationNote,
    required this.status,
    required this.userUid,
  });

  final String fullName;
  final String email;
  final String phone;
  final DateTime? dateOfBirth;
  final String? gender;
  final String consultationNote;
  final String status;
  final String? userUid;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phonePattern = RegExp(r'^\+?[0-9]{8,15}$');

  static bool isValidEmail(String value) =>
      value.trim().isEmpty || _emailPattern.hasMatch(value.trim());

  static String normalizePhone(String value) =>
      value.trim().replaceAll(RegExp(r'[\s.-]'), '');

  static bool isValidPhone(String value) {
    final normalized = normalizePhone(value);
    return normalized.isEmpty || _phonePattern.hasMatch(normalized);
  }

  static String? validateFullName(String? value) =>
      (value?.trim().isEmpty ?? true) ? 'Vui lòng nhập họ tên.' : null;

  static String? validateEmail(String? value) =>
      isValidEmail(value ?? '') ? null : 'Email không đúng định dạng.';

  static String? validatePhone(String? value) => isValidPhone(value ?? '')
      ? null
      : 'Số điện thoại phải để trống hoặc có từ 8 đến 15 chữ số.';

  static StudentInput? tryCreate({
    required String fullName,
    required String email,
    required String phone,
    required DateTime? dateOfBirth,
    required String? gender,
    required String consultationNote,
    required String status,
    required String userUid,
  }) {
    final normalizedPhone = normalizePhone(phone);
    final normalizedUid = userUid.trim();
    if (fullName.trim().isEmpty ||
        !isValidEmail(email) ||
        !isValidPhone(normalizedPhone) ||
        !Student.validStatuses.contains(status) ||
        (gender != null && !Student.validGenders.contains(gender))) {
      return null;
    }
    return StudentInput(
      fullName: fullName.trim(),
      email: email.trim(),
      phone: normalizedPhone,
      dateOfBirth: dateOfBirth,
      gender: gender,
      consultationNote: consultationNote.trim(),
      status: status,
      userUid: normalizedUid.isEmpty ? null : normalizedUid,
    );
  }
}

class StudentRegistrationProfile {
  static String documentId(String uid) => uid;

  static Map<String, dynamic>? build({
    required String role,
    required String uid,
    required String fullName,
    required String email,
    required Object timestamp,
  }) {
    if (role != 'student') return null;
    return {
      'fullName': fullName.trim(),
      'email': email.trim(),
      'phone': '',
      'dateOfBirth': null,
      'gender': null,
      'consultationNote': '',
      'status': 'active',
      'userUid': uid,
      'createdAt': timestamp,
      'updatedAt': timestamp,
    };
  }
}

class StudentLinkPolicy {
  static bool hasDuplicate(
    Iterable<String> linkedStudentIds, {
    String? excludedStudentId,
  }) => linkedStudentIds.any((id) => id != excludedStudentId);
}
