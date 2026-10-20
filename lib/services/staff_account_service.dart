import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class StaffAccount {
  const StaffAccount({
    required this.id,
    required this.uid,
    required this.fullName,
    required this.email,
    required this.role,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String uid;
  final String fullName;
  final String email;
  final String role;
  final String status;
  final DateTime? createdAt;

  String get roleLabel => role == 'teacher' ? 'Giáo viên' : 'Nhân viên tư vấn';

  String get statusLabel => switch (status) {
    'pending' => 'Chờ duyệt',
    'active' => 'Đang hoạt động',
    'inactive' => 'Ngừng hoạt động',
    _ => status,
  };

  factory StaffAccount.fromMap(String id, Map<String, dynamic> data) {
    final uid = data['uid'];
    final fullName = data['fullName'];
    final email = data['email'];
    final role = data['role'];
    final status = data['status'];
    final createdAt = data['createdAt'];
    if (uid != id ||
        fullName is! String ||
        fullName.trim().isEmpty ||
        email is! String ||
        email.trim().isEmpty ||
        role is! String ||
        !StaffApprovalPolicy.staffRoles.contains(role) ||
        status is! String ||
        !StaffApprovalPolicy.staffStatuses.contains(status) ||
        (createdAt != null &&
            createdAt is! Timestamp &&
            createdAt is! DateTime)) {
      throw const FormatException('Dữ liệu tài khoản nhân sự không hợp lệ.');
    }

    return StaffAccount(
      id: id,
      uid: uid,
      fullName: fullName.trim(),
      email: email.trim(),
      role: role,
      status: status,
      createdAt: createdAt is Timestamp
          ? createdAt.toDate()
          : createdAt as DateTime?,
    );
  }
}

class StaffApprovalPolicy {
  static const staffRoles = {'teacher', 'consultant'};
  static const staffStatuses = {'pending', 'active', 'inactive'};

  static String? transitionError({
    required bool isDesignatedAdmin,
    required String targetRole,
    required String currentStatus,
    required String nextStatus,
    bool changesOnlyStatus = true,
  }) {
    if (!isDesignatedAdmin) {
      return 'Chỉ Admin được chỉ định mới có thể đổi trạng thái tài khoản.';
    }
    if (!staffRoles.contains(targetRole)) {
      return 'Chỉ được quản lý tài khoản giáo viên hoặc nhân viên tư vấn.';
    }
    if (!changesOnlyStatus) {
      return 'Phê duyệt chỉ được thay đổi trạng thái tài khoản.';
    }
    final validTransition =
        (currentStatus == 'pending' &&
            (nextStatus == 'active' || nextStatus == 'inactive')) ||
        (currentStatus == 'active' && nextStatus == 'inactive') ||
        (currentStatus == 'inactive' && nextStatus == 'active');
    if (!validTransition) return 'Chuyển trạng thái tài khoản không hợp lệ.';
    return null;
  }
}

List<StaffAccount> filterStaffAccounts(
  Iterable<StaffAccount> accounts, {
  String? fixedRole,
  String roleFilter = 'all',
  String statusFilter = 'all',
  String query = '',
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final role = fixedRole ?? roleFilter;
  return accounts
      .where(
        (account) =>
            (role == 'all' || account.role == role) &&
            (statusFilter == 'all' || account.status == statusFilter) &&
            (normalizedQuery.isEmpty ||
                account.fullName.toLowerCase().contains(normalizedQuery) ||
                account.email.toLowerCase().contains(normalizedQuery)),
      )
      .toList();
}

String firestoreLoadErrorMessage(Object? error, String subject) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'Không có quyền tải $subject. Hãy kiểm tra tài khoản Admin được chỉ '
        'định và xuất bản Firestore Rules mới nhất.';
  }
  if (error is FirebaseException && error.code == 'failed-precondition') {
    return 'Không thể tải $subject do thiếu chỉ mục Firestore.';
  }
  if (error is FirebaseException && error.code == 'unavailable') {
    return 'Firebase đang tạm thời không khả dụng. Vui lòng thử lại.';
  }
  if (error is FormatException) return error.message;
  return 'Không thể tải $subject. Vui lòng thử lại.';
}

void debugLogFirestoreError(String scope, Object error) {
  if (!kDebugMode) return;
  final code = error is FirebaseException ? error.code : error.runtimeType;
  debugPrint('[$scope] $code: $error');
}

class StaffAccountService {
  StaffAccountService._();

  static final instance = StaffAccountService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<List<StaffAccount>> watchStaffAccounts() => _firestore
      .collection('users')
      .where('role', whereIn: StaffApprovalPolicy.staffRoles.toList())
      .snapshots()
      .map((snapshot) {
        final accounts = snapshot.docs
            .map(
              (document) => StaffAccount.fromMap(document.id, document.data()),
            )
            .toList();
        accounts.sort((left, right) {
          final leftDate = left.createdAt;
          final rightDate = right.createdAt;
          if (leftDate == null && rightDate == null) {
            return left.fullName.compareTo(right.fullName);
          }
          if (leftDate == null) return 1;
          if (rightDate == null) return -1;
          return rightDate.compareTo(leftDate);
        });
        return accounts;
      });

  Future<void> changeStatus(StaffAccount account, String nextStatus) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) {
      throw StateError('Phiên đăng nhập đã hết hạn.');
    }
    if (currentUid == account.uid) {
      throw StateError('Admin không thể tự phê duyệt hoặc tự khóa tài khoản.');
    }

    final reference = _firestore.collection('users').doc(account.id);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final data = snapshot.data();
      if (data == null) throw StateError('Tài khoản không còn tồn tại.');
      final latest = StaffAccount.fromMap(snapshot.id, data);
      final error = StaffApprovalPolicy.transitionError(
        isDesignatedAdmin: true,
        targetRole: latest.role,
        currentStatus: latest.status,
        nextStatus: nextStatus,
      );
      if (error != null) throw StateError(error);
      transaction.update(reference, {'status': nextStatus});
    });
  }
}
