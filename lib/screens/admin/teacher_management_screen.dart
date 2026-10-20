import 'package:flutter/material.dart';

import '../../services/staff_account_service.dart';
import '../../services/teacher_service.dart';
import 'staff_approval_screen.dart';

class TeacherManagementScreen extends StatefulWidget {
  const TeacherManagementScreen({super.key});

  @override
  State<TeacherManagementScreen> createState() =>
      _TeacherManagementScreenState();
}

class _TeacherManagementScreenState extends State<TeacherManagementScreen> {
  Future<bool> _changeStatus(StaffAccount account, String nextStatus) async {
    await TeacherService.instance.changeTeacherAccountStatus(
      account,
      nextStatus,
    );
    return true;
  }

  Future<void> _manageTeacherProfile(StaffAccount account) async {
    try {
      final profile = await TeacherService.instance.findProfileForAccount(
        account,
      );
      if (profile != null && profile.isLinked && profile.isActive) {
        _showMessage('Giáo viên đã sẵn sàng để phân công giảng dạy.');
        return;
      }

      await TeacherService.instance.ensureActiveTeacherProfile(account);
      if (mounted) {
        _showMessage('Đã hoàn thiện liên kết để phân công giảng dạy.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is StateError
              ? error.message.toString()
              : 'Không thể hoàn thiện hồ sơ phân công. Hãy kiểm tra quyền truy cập.',
          isError: true,
        );
      }
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
    return StaffApprovalScreen(
      title: 'Quản lý giáo viên',
      description: 'Phê duyệt, khóa hoặc kích hoạt lại tài khoản giáo viên.',
      fixedRole: 'teacher',
      onChangeStatus: _changeStatus,
      onManageTeacherProfile: _manageTeacherProfile,
    );
  }
}
