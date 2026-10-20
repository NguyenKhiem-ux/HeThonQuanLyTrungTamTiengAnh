import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../admin/class_management_screen.dart';
import '../admin/consultant_management_screen.dart';
import '../admin/course_management_screen.dart';
import '../admin/enrollment_management_screen.dart';
import '../admin/room_allocation_screen.dart';
import '../admin/staff_approval_screen.dart';
import '../admin/student_management_screen.dart';
import '../admin/teacher_assignment_screen.dart';
import '../admin/teacher_management_screen.dart';
import '../consultant/registration_approval_screen.dart';
import '../student/class_registration_screen.dart';
import '../student/learning_result_screen.dart';
import '../student/student_schedule_screen.dart';
import '../teacher/attendance_screen.dart';
import '../teacher/grade_management_screen.dart';
import '../teacher/teaching_schedule_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  var _selectedIndex = 0;

  List<_MenuItem> get _items {
    if (widget.profile.status != 'active') {
      return const [_MenuItem('Tổng quan', Icons.dashboard_outlined)];
    }
    return switch (widget.profile.role) {
      'admin' => const [
        _MenuItem('Tổng quan', Icons.dashboard_outlined),
        _MenuItem('Quản lý khóa học', Icons.menu_book_outlined),
        _MenuItem('Quản lý lớp học', Icons.class_outlined),
        _MenuItem('Phân bổ phòng học', Icons.meeting_room_outlined),
        _MenuItem('Quản lý giáo viên', Icons.co_present_outlined),
        _MenuItem('Phân công giảng dạy', Icons.assignment_ind_outlined),
        _MenuItem('Quản lý học viên', Icons.groups_outlined),
        _MenuItem('Đăng ký học', Icons.app_registration_outlined),
        _MenuItem('Phê duyệt tài khoản', Icons.how_to_reg_outlined),
        _MenuItem('Quản lý tư vấn viên', Icons.support_agent_outlined),
      ],
      'consultant' => const [
        _MenuItem('Tổng quan', Icons.dashboard_outlined),
        _MenuItem('Quản lý học viên', Icons.groups_outlined),
        _MenuItem('Xét duyệt đăng ký', Icons.fact_check_outlined),
        _MenuItem('Danh sách lớp học', Icons.class_outlined),
      ],
      'teacher' => const [
        _MenuItem('Tổng quan', Icons.dashboard_outlined),
        _MenuItem('Lịch dạy', Icons.calendar_month_outlined),
        _MenuItem('Điểm danh', Icons.fact_check_outlined),
        _MenuItem('Nhập điểm', Icons.edit_note_outlined),
        _MenuItem('Nhận xét học viên', Icons.rate_review_outlined),
      ],
      'student' => const [
        _MenuItem('Tổng quan', Icons.dashboard_outlined),
        _MenuItem('Đăng ký lớp học', Icons.app_registration_outlined),
        _MenuItem('Lịch học', Icons.calendar_month_outlined),
        _MenuItem('Kết quả học tập', Icons.assessment_outlined),
      ],
      _ => const [],
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Hệ thống quản lý trung tâm tiếng Anh'),
            actions: [
              if (wide)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: Text(
                      '${widget.profile.fullName} · ${widget.profile.roleLabel}',
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Đăng xuất',
                onPressed: AuthService.instance.signOut,
                icon: const Icon(Icons.logout),
              ),
              const SizedBox(width: 8),
            ],
          ),
          drawer: wide ? null : Drawer(child: _buildSidebar(closeDrawer: true)),
          body: Row(
            children: [
              if (wide)
                SizedBox(width: 280, child: _buildSidebar(closeDrawer: false)),
              Expanded(child: _buildContent()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar({required bool closeDrawer}) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    child: Text(
                      widget.profile.fullName.characters.first.toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.profile.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.profile.roleLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      selected: index == _selectedIndex,
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(item.icon),
                      title: Text(item.label),
                      onTap: () {
                        setState(() => _selectedIndex = index);
                        if (closeDrawer) Navigator.of(context).pop();
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final item = _items[_selectedIndex];
    if (widget.profile.role == 'admin' && _selectedIndex == 1) {
      return const CourseManagementScreen();
    }
    if (widget.profile.role == 'admin' && _selectedIndex == 2) {
      return const ClassManagementScreen();
    }
    if (widget.profile.role == 'admin' && _selectedIndex == 3) {
      return const RoomAllocationScreen();
    }
    if (widget.profile.role == 'admin' && _selectedIndex == 4) {
      return const TeacherManagementScreen();
    }
    if (widget.profile.role == 'admin' && _selectedIndex == 5) {
      return const TeacherAssignmentScreen();
    }
    if (widget.profile.role == 'admin' && _selectedIndex == 6) {
      return const StudentManagementScreen();
    }
    if (widget.profile.role == 'admin' && _selectedIndex == 7) {
      return const EnrollmentManagementScreen();
    }
    if (widget.profile.role == 'admin' && _selectedIndex == 8) {
      return const StaffApprovalScreen();
    }
    if (widget.profile.role == 'admin' && _selectedIndex == 9) {
      return const ConsultantManagementScreen();
    }
    if (widget.profile.role == 'consultant' && _selectedIndex == 1) {
      return const StudentManagementScreen();
    }
    if (widget.profile.role == 'consultant' && _selectedIndex == 2) {
      return const RegistrationApprovalScreen();
    }
    if (widget.profile.role == 'consultant' && _selectedIndex == 3) {
      return const EnrollmentManagementScreen();
    }
    if (widget.profile.role == 'teacher' && _selectedIndex == 1) {
      return const TeachingScheduleScreen();
    }
    if (widget.profile.role == 'teacher' && _selectedIndex == 2) {
      return const AttendanceScreen();
    }
    if (widget.profile.role == 'teacher' &&
        (_selectedIndex == 3 || _selectedIndex == 4)) {
      return const GradeManagementScreen();
    }
    if (widget.profile.role == 'student' && _selectedIndex == 1) {
      return const ClassRegistrationScreen();
    }
    if (widget.profile.role == 'student' && _selectedIndex == 2) {
      return const StudentScheduleScreen();
    }
    if (widget.profile.role == 'student' && _selectedIndex == 3) {
      return const LearningResultScreen();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.label, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          if (_selectedIndex == 0) _buildOverview() else _buildPlaceholder(),
        ],
      ),
    );
  }

  Widget _buildOverview() {
    final description = switch (widget.profile.role) {
      'admin' => 'Theo dõi và quản lý hoạt động chung của trung tâm.',
      'consultant' => 'Quản lý thông tin học viên và hoạt động đăng ký học.',
      'teacher' => 'Theo dõi lịch dạy và công việc giảng dạy của bạn.',
      'student' => 'Theo dõi lịch học và kết quả học tập của bạn.',
      _ => '',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Icon(
                  Icons.waving_hand_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Xin chào, ${widget.profile.fullName}!',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(description),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _InfoCard(
              icon: Icons.badge_outlined,
              label: 'Vai trò',
              value: widget.profile.roleLabel,
            ),
            const _InfoCard(
              icon: Icons.verified_user_outlined,
              label: 'Trạng thái',
              value: 'Đang hoạt động',
            ),
            _InfoCard(
              icon: Icons.apps_outlined,
              label: 'Chức năng',
              value: '${_items.length - 1} mục',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Card(
      child: SizedBox(
        width: double.infinity,
        height: 300,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Chức năng đang phát triển',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.label, this.icon);

  final String label;
  final IconData icon;
}
