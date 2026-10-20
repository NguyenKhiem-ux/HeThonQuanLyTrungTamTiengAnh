import 'package:flutter/material.dart';

import 'staff_approval_screen.dart';

class ConsultantManagementScreen extends StatelessWidget {
  const ConsultantManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StaffApprovalScreen(
      title: 'Quản lý nhân viên tư vấn',
      fixedRole: 'consultant',
    );
  }
}
