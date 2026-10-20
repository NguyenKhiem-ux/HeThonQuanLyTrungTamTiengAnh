import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/student.dart';
import '../models/user_profile.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static final instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User> _authenticate({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthFailure('Không thể xác thực. Vui lòng thử lại.');
      }
      return user;
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_authMessage(error));
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    await _authenticate(email: email, password: password);
  }

  Future<void> signInAdmin({
    required String email,
    required String password,
  }) async {
    final user = await _authenticate(email: email, password: password);
    try {
      final profile = await _getProfile(user.uid);
      await verifyDesignatedAdmin(profile);
    } on FormatException catch (error) {
      await _auth.signOut();
      throw AuthFailure(error.message);
    } on AuthFailure {
      await _auth.signOut();
      rethrow;
    }
  }

  Future<void> registerUser({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    const statuses = {
      'student': 'active',
      'teacher': 'pending',
      'consultant': 'pending',
    };
    final status = statuses[role];
    if (status == null) {
      throw const AuthFailure('Vai trò đăng ký không hợp lệ.');
    }

    UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_authMessage(error));
    }

    final user = credential.user;
    if (user == null) {
      throw const AuthFailure('Không thể tạo tài khoản. Vui lòng thử lại.');
    }

    try {
      final timestamp = FieldValue.serverTimestamp();
      final normalizedName = fullName.trim();
      final normalizedEmail = user.email ?? email.trim();
      final batch = _firestore.batch();
      batch.set(_firestore.collection('users').doc(user.uid), {
        'uid': user.uid,
        'fullName': normalizedName,
        'email': normalizedEmail,
        'role': role,
        'status': status,
        'createdAt': timestamp,
      });
      final studentProfile = StudentRegistrationProfile.build(
        role: role,
        uid: user.uid,
        fullName: normalizedName,
        email: normalizedEmail,
        timestamp: timestamp,
      );
      if (studentProfile != null) {
        batch.set(
          _firestore
              .collection('students')
              .doc(StudentRegistrationProfile.documentId(user.uid)),
          studentProfile,
        );
      }
      await batch.commit();
    } catch (_) {
      var accountRemoved = false;
      try {
        await user.delete();
        accountRemoved = true;
      } catch (_) {
        await _auth.signOut();
      }

      if (accountRemoved) {
        throw const AuthFailure(
          'Không thể lưu hồ sơ. Tài khoản vừa tạo đã được hoàn tác; '
          'hãy kiểm tra Firestore Rules rồi đăng ký lại.',
        );
      }
      throw const AuthFailure(
        'Đã tạo tài khoản xác thực nhưng chưa lưu được hồ sơ. '
        'Tài khoản đã được đăng xuất; hãy liên hệ quản trị viên để xử lý.',
      );
    }
  }

  Stream<UserProfile> profileChanges(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((document) => UserProfile.fromMap(document.id, document.data()));

  Future<UserProfile> _getProfile(String uid) async {
    try {
      final document = await _firestore.collection('users').doc(uid).get();
      return UserProfile.fromMap(document.id, document.data());
    } on FirebaseException {
      throw const AuthFailure(
        'Không thể tải hồ sơ người dùng. Hãy kiểm tra kết nối và quyền truy cập.',
      );
    }
  }

  Future<void> verifyDesignatedAdmin(UserProfile profile) async {
    if (profile.role != 'admin' || profile.status != 'active') {
      throw const AuthFailure('Tài khoản này không có quyền Admin.');
    }

    try {
      final adminDocument = await _firestore
          .collection('system')
          .doc('admin')
          .get();
      if (!adminDocument.exists ||
          adminDocument.data()?['uid'] != profile.uid) {
        throw const AuthFailure(
          'Tài khoản không khớp với Admin duy nhất của hệ thống.',
        );
      }
    } on FirebaseException {
      throw const AuthFailure(
        'Không thể xác minh quyền Admin. Hãy kiểm tra Firestore Rules.',
      );
    }
  }

  Future<void> signOut() async => _auth.signOut();

  String _authMessage(FirebaseAuthException error) => switch (error.code) {
    'invalid-email' => 'Email không đúng định dạng.',
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'Email hoặc mật khẩu không chính xác.',
    'user-disabled' => 'Tài khoản này đã bị vô hiệu hóa.',
    'email-already-in-use' => 'Email này đã được sử dụng.',
    'weak-password' => 'Mật khẩu chưa đủ mạnh (tối thiểu 6 ký tự).',
    'too-many-requests' => 'Bạn thao tác quá nhiều lần. Vui lòng thử lại sau.',
    'network-request-failed' => 'Không thể kết nối mạng. Vui lòng thử lại.',
    _ => 'Không thể xác thực. Vui lòng thử lại.',
  };
}
