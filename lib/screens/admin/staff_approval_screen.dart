import 'package:flutter/material.dart';

import '../../services/staff_account_service.dart';
import '../../services/teacher_service.dart';

typedef StaffStatusChanger =
    Future<bool> Function(StaffAccount account, String nextStatus);
typedef StaffAccountAction = Future<void> Function(StaffAccount account);

class StaffApprovalScreen extends StatefulWidget {
  const StaffApprovalScreen({
    super.key,
    this.title = 'Phê duyệt tài khoản nhân sự',
    this.description =
        'Phê duyệt, khóa hoặc kích hoạt lại tài khoản giáo viên và nhân viên tư vấn.',
    this.fixedRole,
    this.onChangeStatus,
    this.onManageTeacherProfile,
  }) : assert(
         fixedRole == null ||
             fixedRole == 'teacher' ||
             fixedRole == 'consultant',
       );

  final String title;
  final String description;
  final String? fixedRole;
  final StaffStatusChanger? onChangeStatus;
  final StaffAccountAction? onManageTeacherProfile;

  @override
  State<StaffApprovalScreen> createState() => _StaffApprovalScreenState();
}

class _StaffApprovalScreenState extends State<StaffApprovalScreen> {
  final _searchController = TextEditingController();
  late Stream<List<StaffAccount>> _accounts;
  var _roleFilter = 'all';
  var _statusFilter = 'all';
  var _isWorking = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _accounts = StaffAccountService.instance.watchStaffAccounts();
  }

  Future<void> _requestStatusChange(
    StaffAccount account,
    String nextStatus,
  ) async {
    final action = _actionLabel(account.status, nextStatus).toLowerCase();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${_actionLabel(account.status, nextStatus)} tài khoản?'),
        content: Text(
          'Bạn có chắc muốn $action tài khoản ${account.fullName} '
          '(${account.email})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Không'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Có'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isWorking = true);
    try {
      final bool changed;
      if (widget.onChangeStatus == null) {
        if (account.role == 'teacher') {
          await TeacherService.instance.changeTeacherAccountStatus(
            account,
            nextStatus,
          );
        } else {
          await StaffAccountService.instance.changeStatus(account, nextStatus);
        }
        changed = true;
      } else {
        changed = await widget.onChangeStatus!(account, nextStatus);
      }
      if (!changed) return;
      if (mounted) {
        _showMessage(
          'Đã ${_actionLabel(account.status, nextStatus).toLowerCase()} '
          'tài khoản ${account.fullName}.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is StateError
              ? error.message.toString()
              : 'Không thể cập nhật trạng thái. Hãy kiểm tra quyền truy cập.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _manageTeacherProfile(StaffAccount account) async {
    final action = widget.onManageTeacherProfile;
    if (action == null) return;
    setState(() => _isWorking = true);
    try {
      await action(account);
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  void _showDetails(StaffAccount account) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(account.fullName),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Email', value: account.email),
              _DetailRow(label: 'Vai trò', value: account.roleLabel),
              _DetailRow(label: 'Trạng thái', value: account.statusLabel),
              _DetailRow(
                label: 'Ngày đăng ký',
                value: _formatDate(account.createdAt),
              ),
              _DetailRow(label: 'UID', value: account.uid),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            widget.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _buildFilters(),
          if (_isWorking) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 20),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => StreamBuilder<List<StaffAccount>>(
                stream: _accounts,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    debugLogFirestoreError(
                      'StaffAccountService.watchStaffAccounts',
                      snapshot.error!,
                    );
                    return _MessageState(
                      icon: Icons.cloud_off_outlined,
                      message: firestoreLoadErrorMessage(
                        snapshot.error,
                        'danh sách tài khoản nhân sự',
                      ),
                      onRetry: () => setState(_reload),
                    );
                  }

                  final allAccounts = snapshot.data ?? const <StaffAccount>[];
                  final accounts = filterStaffAccounts(
                    allAccounts,
                    fixedRole: widget.fixedRole,
                    roleFilter: _roleFilter,
                    statusFilter: _statusFilter,
                    query: _searchController.text,
                  );
                  if (accounts.isEmpty) {
                    return const _MessageState(
                      icon: Icons.manage_accounts_outlined,
                      message: 'Không có tài khoản phù hợp.',
                    );
                  }
                  return constraints.maxWidth >= 900
                      ? _AccountTable(
                          accounts: accounts,
                          isWorking: _isWorking,
                          onView: _showDetails,
                          onChangeStatus: _requestStatusChange,
                          onManageTeacherProfile:
                              widget.onManageTeacherProfile == null
                              ? null
                              : _manageTeacherProfile,
                        )
                      : ListView.separated(
                          itemCount: accounts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final account = accounts[index];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          child: Text(
                                            account.fullName.characters.first
                                                .toUpperCase(),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                account.fullName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(account.email),
                                            ],
                                          ),
                                        ),
                                        _StatusChip(account: account),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '${account.roleLabel} · Đăng ký ${_formatDate(account.createdAt)}',
                                    ),
                                    const SizedBox(height: 8),
                                    _AccountActions(
                                      account: account,
                                      isWorking: _isWorking,
                                      onView: _showDetails,
                                      onChangeStatus: _requestStatusChange,
                                      onManageTeacherProfile:
                                          widget.onManageTeacherProfile == null
                                          ? null
                                          : _manageTeacherProfile,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final search = TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'Tìm theo họ tên hoặc email',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Xóa tìm kiếm',
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.clear),
              ),
      ),
    );
    final role = DropdownButtonFormField<String>(
      initialValue: _roleFilter,
      decoration: const InputDecoration(labelText: 'Vai trò'),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Tất cả vai trò')),
        DropdownMenuItem(value: 'teacher', child: Text('Giáo viên')),
        DropdownMenuItem(value: 'consultant', child: Text('Nhân viên tư vấn')),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _roleFilter = value);
      },
    );
    final status = DropdownButtonFormField<String>(
      initialValue: _statusFilter,
      decoration: const InputDecoration(labelText: 'Trạng thái'),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Tất cả trạng thái')),
        DropdownMenuItem(value: 'pending', child: Text('Chờ duyệt')),
        DropdownMenuItem(value: 'active', child: Text('Đang hoạt động')),
        DropdownMenuItem(value: 'inactive', child: Text('Đã khóa')),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _statusFilter = value);
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final filters = [
          if (widget.fixedRole == null) SizedBox(width: 210, child: role),
          SizedBox(width: 210, child: status),
        ];
        return constraints.maxWidth >= 760
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 12),
                  ...filters.expand(
                    (filter) => [filter, const SizedBox(width: 12)],
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: 12),
                  if (widget.fixedRole == null) ...[
                    role,
                    const SizedBox(height: 12),
                  ],
                  status,
                ],
              );
      },
    );
  }
}

class _AccountTable extends StatelessWidget {
  const _AccountTable({
    required this.accounts,
    required this.isWorking,
    required this.onView,
    required this.onChangeStatus,
    required this.onManageTeacherProfile,
  });

  final List<StaffAccount> accounts;
  final bool isWorking;
  final ValueChanged<StaffAccount> onView;
  final Future<void> Function(StaffAccount, String) onChangeStatus;
  final StaffAccountAction? onManageTeacherProfile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Họ tên')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('Vai trò')),
              DataColumn(label: Text('Trạng thái')),
              DataColumn(label: Text('Ngày đăng ký')),
              DataColumn(label: Text('Thao tác')),
            ],
            rows: accounts
                .map(
                  (account) => DataRow(
                    cells: [
                      DataCell(
                        Text(account.fullName),
                        onTap: () => onView(account),
                      ),
                      DataCell(Text(account.email)),
                      DataCell(Text(account.roleLabel)),
                      DataCell(_StatusChip(account: account)),
                      DataCell(Text(_formatDate(account.createdAt))),
                      DataCell(
                        _AccountActions(
                          account: account,
                          isWorking: isWorking,
                          onView: onView,
                          onChangeStatus: onChangeStatus,
                          onManageTeacherProfile: onManageTeacherProfile,
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _AccountActions extends StatelessWidget {
  const _AccountActions({
    required this.account,
    required this.isWorking,
    required this.onView,
    required this.onChangeStatus,
    required this.onManageTeacherProfile,
  });

  final StaffAccount account;
  final bool isWorking;
  final ValueChanged<StaffAccount> onView;
  final Future<void> Function(StaffAccount, String) onChangeStatus;
  final StaffAccountAction? onManageTeacherProfile;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      IconButton(
        tooltip: 'Xem chi tiết',
        onPressed: () => onView(account),
        icon: const Icon(Icons.visibility_outlined),
      ),
    ];
    if (onManageTeacherProfile != null &&
        account.role == 'teacher' &&
        account.status == 'active') {
      buttons.add(
        IconButton(
          tooltip: 'Kiểm tra hồ sơ phân công',
          onPressed: isWorking ? null : () => onManageTeacherProfile!(account),
          icon: const Icon(Icons.school_outlined),
        ),
      );
    }
    if (account.status == 'pending') {
      buttons.addAll([
        IconButton(
          tooltip: 'Phê duyệt',
          onPressed: isWorking ? null : () => onChangeStatus(account, 'active'),
          icon: const Icon(Icons.check_circle_outline),
        ),
        IconButton(
          tooltip: 'Từ chối',
          onPressed: isWorking
              ? null
              : () => onChangeStatus(account, 'inactive'),
          icon: const Icon(Icons.cancel_outlined),
        ),
      ]);
    } else if (account.status == 'active') {
      buttons.add(
        IconButton(
          tooltip: 'Khóa tài khoản',
          onPressed: isWorking
              ? null
              : () => onChangeStatus(account, 'inactive'),
          icon: const Icon(Icons.lock_outline),
        ),
      );
    } else {
      buttons.add(
        IconButton(
          tooltip: 'Kích hoạt lại',
          onPressed: isWorking ? null : () => onChangeStatus(account, 'active'),
          icon: const Icon(Icons.lock_open_outlined),
        ),
      );
    }
    return Wrap(spacing: 4, children: buttons);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.account});

  final StaffAccount account;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (account.status) {
      'pending' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      'active' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _ => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Chip(
      label: Text(account.statusLabel),
      backgroundColor: background,
      labelStyle: TextStyle(color: foreground),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ],
      ),
    );
  }
}

String _actionLabel(String currentStatus, String nextStatus) {
  if (currentStatus == 'pending' && nextStatus == 'active') return 'Phê duyệt';
  if (currentStatus == 'pending' && nextStatus == 'inactive') return 'Từ chối';
  if (nextStatus == 'inactive') return 'Khóa';
  return 'Kích hoạt lại';
}

String _formatDate(DateTime? value) {
  if (value == null) return 'Đang cập nhật';
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(value.day)}/${twoDigits(value.month)}/${value.year} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}
