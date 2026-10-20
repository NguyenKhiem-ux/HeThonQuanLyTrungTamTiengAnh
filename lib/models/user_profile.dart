class UserProfile {
  const UserProfile({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.role,
    required this.status,
  });

  static const validRoles = {'admin', 'consultant', 'teacher', 'student'};

  final String uid;
  final String fullName;
  final String email;
  final String role;
  final String status;

  bool get isPending => status == 'pending';
  bool get isInactive => status == 'inactive';

  String get roleLabel => switch (role) {
    'admin' => 'Admin',
    'consultant' => 'Nhân viên tư vấn',
    'teacher' => 'Giáo viên',
    'student' => 'Học viên',
    _ => 'Không xác định',
  };

  factory UserProfile.fromMap(String documentId, Map<String, dynamic>? data) {
    if (data == null) {
      throw const FormatException('Không tìm thấy hồ sơ người dùng.');
    }

    final uid = data['uid'];
    final fullName = data['fullName'];
    final email = data['email'];
    final role = data['role'];
    final status = data['status'];

    final isStaff = role == 'teacher' || role == 'consultant';
    final validStatus =
        status == 'active' ||
        (isStaff && (status == 'pending' || status == 'inactive'));

    if (uid != documentId ||
        fullName is! String ||
        fullName.trim().isEmpty ||
        email is! String ||
        email.trim().isEmpty ||
        role is! String ||
        !validRoles.contains(role) ||
        status is! String ||
        !validStatus ||
        data['createdAt'] == null) {
      throw const FormatException(
        'Hồ sơ người dùng có vai trò hoặc trạng thái không hợp lệ.',
      );
    }

    return UserProfile(
      uid: uid,
      fullName: fullName.trim(),
      email: email.trim(),
      role: role,
      status: status,
    );
  }
}
