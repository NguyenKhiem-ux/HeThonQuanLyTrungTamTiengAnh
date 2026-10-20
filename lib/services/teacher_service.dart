import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/teacher.dart';
import 'staff_account_service.dart';

class TeacherService {
  TeacherService._();

  static final instance = TeacherService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<Teacher>> watchTeachers() =>
      _firestore.collection('teachers').snapshots().map((snapshot) {
        final teachers = snapshot.docs
            .map((document) => Teacher.fromMap(document.id, document.data()))
            .toList();
        teachers.sort(
          (left, right) => left.fullName.toLowerCase().compareTo(
            right.fullName.toLowerCase(),
          ),
        );
        return teachers;
      });

  Stream<List<Teacher>> watchOwnProfile(String userUid) => _firestore
      .collection('teachers')
      .where('userUid', isEqualTo: userUid)
      .limit(1)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) => Teacher.fromMap(document.id, document.data()))
            .toList(),
      );

  Future<Teacher?> findProfileForAccount(
    StaffAccount account, {
    bool includeEmailMatch = true,
  }) async {
    // shortcut: teacher counts are small; add normalized lookup fields before this collection grows large.
    final snapshot = await _firestore.collection('teachers').get();
    final teachers = snapshot.docs
        .map((document) => Teacher.fromMap(document.id, document.data()))
        .toList();
    final linked = teachers
        .where((teacher) => teacher.userUid == account.uid)
        .toList();
    if (linked.length > 1) {
      throw StateError('Tài khoản đang liên kết với nhiều hồ sơ giáo viên.');
    }
    if (linked.isNotEmpty) return linked.single;
    if (!includeEmailMatch) return null;

    final emailMatches = teachers
        .where(
          (teacher) =>
              teacher.email.toLowerCase() == account.email.toLowerCase(),
        )
        .toList();
    if (emailMatches.any(
      (teacher) => teacher.userUid != null && teacher.userUid != account.uid,
    )) {
      throw StateError('Email này đã liên kết với tài khoản giáo viên khác.');
    }
    final available = emailMatches
        .where((teacher) => teacher.userUid == null)
        .toList();
    if (available.length > 1) {
      throw StateError(
        'Có nhiều hồ sơ giáo viên trùng email; cần xử lý dữ liệu trước.',
      );
    }
    return available.firstOrNull;
  }

  Future<void> changeTeacherAccountStatus(
    StaffAccount account,
    String nextStatus,
  ) => _syncTeacherAccount(account, nextStatus: nextStatus);

  Future<void> ensureActiveTeacherProfile(StaffAccount account) =>
      _syncTeacherAccount(account);

  Future<int> syncActiveTeacherProfiles() async {
    final results = await Future.wait([
      _firestore.collection('users').where('role', isEqualTo: 'teacher').get(),
      _firestore.collection('teachers').get(),
    ]);
    final accountDocuments = results[0];
    final teacherDocuments = results[1];
    final accounts = accountDocuments.docs
        .map((document) => StaffAccount.fromMap(document.id, document.data()))
        .where((account) => account.status == 'active')
        .toList();
    final teachers = teacherDocuments.docs
        .map((document) => Teacher.fromMap(document.id, document.data()))
        .toList();
    final teacherById = {for (final teacher in teachers) teacher.id: teacher};
    final batch = _firestore.batch();
    var changes = 0;

    for (final account in accounts) {
      if (TeacherProfileSyncPolicy.hasDuplicateLink(teachers, account.uid)) {
        throw StateError(
          'Tài khoản ${account.email} đang liên kết với nhiều hồ sơ giáo viên.',
        );
      }
      final linked = teachers
          .where((teacher) => teacher.userUid == account.uid)
          .firstOrNull;
      final emailMatches = teachers
          .where(
            (teacher) =>
                teacher.email.toLowerCase() == account.email.toLowerCase(),
          )
          .toList();
      if (emailMatches.any(
        (teacher) => teacher.userUid != null && teacher.userUid != account.uid,
      )) {
        throw StateError(
          'Email ${account.email} đã liên kết với tài khoản giáo viên khác.',
        );
      }
      final availableMatches = emailMatches
          .where((teacher) => teacher.userUid == null)
          .toList();
      if (linked == null && availableMatches.length > 1) {
        throw StateError(
          'Có nhiều hồ sơ giáo viên trùng email ${account.email}.',
        );
      }
      final profile = linked ?? availableMatches.firstOrNull;
      final timestamp = FieldValue.serverTimestamp();
      if (profile != null) {
        if (!profile.isAssignable) {
          batch.update(_firestore.collection('teachers').doc(profile.id), {
            'userUid': account.uid,
            'status': 'active',
            'updatedAt': timestamp,
          });
          changes++;
        }
        continue;
      }
      if (teacherById.containsKey(account.uid)) {
        throw StateError(
          'ID tài khoản ${account.uid} đang trùng một hồ sơ giáo viên khác.',
        );
      }
      batch.set(_firestore.collection('teachers').doc(account.uid), {
        'fullName': account.fullName,
        'email': account.email,
        'phone': '',
        'specialty': '',
        'status': 'active',
        'userUid': account.uid,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      });
      changes++;
    }

    // shortcut: một batch phù hợp quy mô MVP dưới 500 giáo viên; chia batch
    // khi trung tâm vượt giới hạn ghi của Firestore.
    if (changes > 0) await batch.commit();
    return changes;
  }

  Future<void> _syncTeacherAccount(
    StaffAccount account, {
    String? nextStatus,
  }) async {
    final activatesProfile = nextStatus == null || nextStatus == 'active';
    final profile = await findProfileForAccount(
      account,
      includeEmailMatch: activatesProfile,
    );
    final userReference = _firestore.collection('users').doc(account.uid);
    final teacherReference = profile == null
        ? _firestore.collection('teachers').doc(account.uid)
        : _firestore.collection('teachers').doc(profile.id);
    await _firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userReference);
      final userData = userSnapshot.data();
      if (userData == null) throw StateError('Tài khoản không còn tồn tại.');
      final latestAccount = StaffAccount.fromMap(userSnapshot.id, userData);
      if (latestAccount.role != 'teacher') {
        throw StateError('Tài khoản không còn là giáo viên.');
      }
      final teacherSnapshot = await transaction.get(teacherReference);
      if (profile == null && teacherSnapshot.exists) {
        throw StateError(
          'ID tài khoản đang trùng một hồ sơ giáo viên chưa liên kết.',
        );
      }

      if (nextStatus == null) {
        if (latestAccount.status != 'active') {
          throw StateError('Chỉ tài khoản giáo viên active mới được liên kết.');
        }
      } else {
        final error = StaffApprovalPolicy.transitionError(
          isDesignatedAdmin: true,
          targetRole: latestAccount.role,
          currentStatus: latestAccount.status,
          nextStatus: nextStatus,
        );
        if (error != null) throw StateError(error);
        transaction.update(userReference, {'status': nextStatus});
      }

      if (!activatesProfile && !teacherSnapshot.exists) return;
      final timestamp = FieldValue.serverTimestamp();
      if (teacherSnapshot.exists) {
        final current = Teacher.fromMap(
          teacherSnapshot.id,
          teacherSnapshot.data()!,
        );
        if (current.userUid != null && current.userUid != latestAccount.uid) {
          throw StateError('Hồ sơ giáo viên đã liên kết với tài khoản khác.');
        }
        transaction.update(teacherReference, {
          if (activatesProfile) ...{'userUid': latestAccount.uid},
          'status': activatesProfile ? 'active' : 'inactive',
          'updatedAt': timestamp,
        });
        return;
      }

      transaction.set(teacherReference, {
        'fullName': latestAccount.fullName,
        'email': latestAccount.email,
        'phone': '',
        'specialty': '',
        'status': 'active',
        'userUid': latestAccount.uid,
        'createdAt': timestamp,
        'updatedAt': timestamp,
      });
    });
  }

  Future<void> addTeacher(TeacherInput input) async {
    await _validateLink(input.userUid);
    final timestamp = FieldValue.serverTimestamp();
    await _firestore.collection('teachers').add({
      'fullName': input.fullName,
      'email': input.email,
      'phone': input.phone,
      'specialty': input.specialty,
      'status': input.status,
      'userUid': input.userUid,
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
  }

  Future<void> updateTeacher(Teacher teacher, TeacherInput input) async {
    await _validateLink(input.userUid, excludedTeacherId: teacher.id);
    final changesAssignmentIdentity = teacher.userUid != input.userUid;
    final deactivatesTeacher = teacher.isActive && input.status == 'inactive';
    if (changesAssignmentIdentity || deactivatesTeacher) {
      final assignments = await _firestore
          .collection('teacher_assignments')
          .where('teacherId', isEqualTo: teacher.id)
          .limit(1)
          .get();
      if (assignments.docs.isNotEmpty) {
        if (changesAssignmentIdentity) {
          throw StateError(
            'Hãy hủy các phân công giảng dạy trước khi đổi liên kết tài khoản.',
          );
        }
        if (deactivatesTeacher) {
          throw StateError(
            'Hãy hủy các phân công giảng dạy trước khi ngừng hoạt động giáo viên.',
          );
        }
      }
    }
    await _firestore.collection('teachers').doc(teacher.id).update({
      'fullName': input.fullName,
      'email': input.email,
      'phone': input.phone,
      'specialty': input.specialty,
      'status': input.status,
      'userUid': input.userUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _validateLink(
    String? userUid, {
    String? excludedTeacherId,
  }) async {
    if (userUid == null) return;
    final results = await Future.wait([
      _firestore.collection('users').doc(userUid).get(),
      _firestore
          .collection('teachers')
          .where('userUid', isEqualTo: userUid)
          .limit(2)
          .get(),
    ]);
    final user = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    if (!user.exists ||
        user.data()?['role'] != 'teacher' ||
        user.data()?['status'] != 'active') {
      throw StateError('UID phải thuộc tài khoản giáo viên đang hoạt động.');
    }
    final linked = results[1] as QuerySnapshot<Map<String, dynamic>>;
    if (linked.docs.any((document) => document.id != excludedTeacherId)) {
      throw StateError('Tài khoản này đã liên kết với giáo viên khác.');
    }
  }
}
