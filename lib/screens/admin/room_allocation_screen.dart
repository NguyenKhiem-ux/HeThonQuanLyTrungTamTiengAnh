import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/english_class.dart';
import '../../models/room.dart';
import '../../models/room_allocation.dart';
import '../../services/class_service.dart';
import '../../services/room_allocation_service.dart';
import '../../services/room_service.dart';

String roomAllocationLoadErrorMessage(Object? error, String subject) {
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'Không có quyền tải $subject. Hãy kiểm tra tài khoản Admin và '
            'Firestore Rules.',
      'failed-precondition' =>
        'Không thể tải $subject do thiếu chỉ mục Firestore.',
      'unavailable' =>
        'Firebase đang tạm thời không khả dụng. Vui lòng thử lại.',
      _ => 'Không thể tải $subject. Vui lòng thử lại.',
    };
  }
  if (error is TimeoutException) {
    return 'Firebase không phản hồi khi tải $subject. Vui lòng thử lại.';
  }
  if (error is FormatException) return error.message;
  return 'Không thể tải $subject. Vui lòng thử lại.';
}

void _debugLogLoadError(String source, Object error) {
  if (!kDebugMode) return;
  final code = error is FirebaseException ? error.code : error.runtimeType;
  debugPrint('[RoomAllocationScreen:$source] $code: $error');
}

class RoomAllocationScreen extends StatefulWidget {
  const RoomAllocationScreen({
    super.key,
    this.roomsStreamFactory,
    this.classesStreamFactory,
    this.allocationsStreamFactory,
  });

  @visibleForTesting
  final Stream<List<Room>> Function()? roomsStreamFactory;

  @visibleForTesting
  final Stream<List<EnglishClass>> Function()? classesStreamFactory;

  @visibleForTesting
  final Stream<List<RoomAllocation>> Function()? allocationsStreamFactory;

  @override
  State<RoomAllocationScreen> createState() => _RoomAllocationScreenState();
}

class _RoomAllocationScreenState extends State<RoomAllocationScreen> {
  late Stream<List<Room>> _roomsForRoomTab;
  late Stream<List<Room>> _roomsForAllocationTab;
  late Stream<List<EnglishClass>> _classes;
  late Stream<List<RoomAllocation>> _allocations;
  var _isWorking = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final roomsStreamFactory =
        widget.roomsStreamFactory ?? RoomService.instance.watchRooms;
    _roomsForRoomTab = roomsStreamFactory();
    _roomsForAllocationTab = roomsStreamFactory();
    _classes =
        (widget.classesStreamFactory ?? ClassService.instance.watchClasses)();
    _allocations =
        (widget.allocationsStreamFactory ??
        RoomAllocationService.instance.watchAllocations)();
    if (kDebugMode && widget.roomsStreamFactory == null) {
      unawaited(RoomService.instance.debugRoomsServerRead());
    }
  }

  Future<void> _openRoomForm([Room? room]) async {
    final input = await showDialog<RoomInput>(
      context: context,
      builder: (_) => _RoomFormDialog(room: room),
    );
    if (input == null || !mounted) return;

    setState(() => _isWorking = true);
    try {
      if (room == null) {
        await RoomService.instance.addRoom(input);
      } else {
        await RoomService.instance.updateRoom(room, input);
      }
      if (mounted) {
        _showMessage(
          room == null ? 'Đã thêm phòng học.' : 'Đã cập nhật phòng.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          _errorMessage(error, 'Không thể lưu phòng học.'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _deleteRoom(Room room) async {
    if (_isWorking) return;
    final confirmed = await _confirm(
      title: 'Xóa phòng học?',
      message:
          'Bạn có chắc muốn xóa phòng “${room.name}”? Phòng đang có lịch phân bổ sẽ không thể xóa.',
      confirmLabel: 'Có, xóa',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isWorking = true);
    try {
      await RoomService.instance.deleteRoom(room);
      if (mounted) _showMessage('Đã xóa phòng học.');
    } catch (error) {
      if (mounted) {
        _showMessage(
          _errorMessage(
            error,
            'Không thể kiểm tra lịch phân bổ hoặc xóa phòng.',
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _openAllocationForm(
    List<Room> rooms,
    List<EnglishClass> classes, [
    RoomAllocation? allocation,
  ]) async {
    final activeRooms = rooms.where((room) => room.isActive).toList();
    final openClasses = classes
        .where((item) => item.canEdit && item.hasConfiguredSchedule)
        .toList();
    if (activeRooms.isEmpty) {
      _showMessage('Cần có ít nhất một phòng đang hoạt động.', isError: true);
      return;
    }
    if (openClasses.isEmpty) {
      _showMessage(
        'Không có lớp chưa kết thúc đã thiết lập lịch học và ca học.',
        isError: true,
      );
      return;
    }
    if (allocation != null &&
        !openClasses.any((item) => item.id == allocation.classId)) {
      _showMessage(
        'Hãy thiết lập lịch học và ca học cho lớp trước khi sửa phân bổ.',
        isError: true,
      );
      return;
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AllocationFormDialog(
        rooms: activeRooms,
        classes: openClasses,
        allocation: allocation,
        onSave: (input) => allocation == null
            ? RoomAllocationService.instance.addAllocation(input)
            : RoomAllocationService.instance.updateAllocation(
                allocation,
                input,
              ),
      ),
    );
    if (saved == true && mounted) {
      _showMessage(
        allocation == null
            ? 'Đã lưu lịch phân bổ.'
            : 'Đã cập nhật lịch phân bổ.',
      );
    }
  }

  Future<void> _deleteAllocation(RoomAllocation allocation) async {
    if (_isWorking) return;
    final confirmed = await _confirm(
      title: 'Hủy lịch phân bổ?',
      message:
          'Lịch ${allocation.weekdayLabel}, ${allocation.timeLabel} sẽ bị xóa.',
      confirmLabel: 'Hủy lịch',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isWorking = true);
    try {
      await RoomAllocationService.instance.deleteAllocation(allocation.id);
      if (mounted) _showMessage('Đã hủy lịch phân bổ.');
    } catch (_) {
      if (mounted) {
        _showMessage('Không thể hủy lịch phân bổ.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Không'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  String _errorMessage(Object error, String fallback) =>
      error is StateError ? error.message.toString() : fallback;

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
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Phân bổ phòng học',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.meeting_room_outlined), text: 'Phòng học'),
                Tab(
                  icon: Icon(Icons.event_note_outlined),
                  text: 'Lịch phân bổ',
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isWorking) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: TabBarView(
                children: [_buildRoomsTab(), _buildAllocationsTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Danh sách phòng học',
          buttonLabel: 'Thêm phòng',
          onPressed: _isWorking ? null : () => _openRoomForm(),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => StreamBuilder<List<Room>>(
              stream: _roomsForRoomTab,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _loadError(
                    snapshot.error!,
                    source: 'rooms',
                    subject: 'danh sách phòng học',
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rooms = snapshot.data ?? const <Room>[];
                if (rooms.isEmpty) {
                  return const RoomAllocationMessageState(
                    icon: Icons.meeting_room_outlined,
                    message: 'Chưa có phòng học nào.',
                  );
                }
                return constraints.maxWidth >= 720
                    ? _buildRoomTable(rooms, constraints.maxWidth)
                    : _buildRoomCards(rooms);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoomTable(List<Room> rooms, double minWidth) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Tên/mã phòng')),
                  DataColumn(label: Text('Sức chứa')),
                  DataColumn(label: Text('Trạng thái')),
                  DataColumn(label: Text('Thao tác')),
                ],
                rows: rooms
                    .map(
                      (room) => DataRow(
                        cells: [
                          DataCell(Text(room.name)),
                          DataCell(Text('${room.capacity} học viên')),
                          DataCell(_RoomStatus(room: room)),
                          DataCell(_roomActions(room)),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCards(List<Room> rooms) {
    return ListView.separated(
      itemCount: rooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final room = rooms[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        room.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _RoomStatus(room: room),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Sức chứa: ${room.capacity} học viên'),
                Align(
                  alignment: Alignment.centerRight,
                  child: _roomActions(room),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _roomActions(Room room) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Sửa',
          onPressed: _isWorking ? null : () => _openRoomForm(room),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Xóa',
          onPressed: _isWorking ? null : () => _deleteRoom(room),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  Widget _buildAllocationsTab() {
    return StreamBuilder<List<Room>>(
      stream: _roomsForAllocationTab,
      builder: (context, roomSnapshot) {
        if (roomSnapshot.hasError) {
          return _loadError(
            roomSnapshot.error!,
            source: 'allocation-rooms',
            subject: 'phòng học để phân bổ',
          );
        }
        if (roomSnapshot.connectionState == ConnectionState.waiting &&
            !roomSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return StreamBuilder<List<EnglishClass>>(
          stream: _classes,
          builder: (context, classSnapshot) {
            if (classSnapshot.hasError) {
              return _loadError(
                classSnapshot.error!,
                source: 'allocation-classes',
                subject: 'lớp học để phân bổ',
              );
            }
            if (classSnapshot.connectionState == ConnectionState.waiting &&
                !classSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final rooms = roomSnapshot.data ?? const <Room>[];
            final classes = classSnapshot.data ?? const <EnglishClass>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  title: 'Lịch phân bổ hàng tuần',
                  buttonLabel: 'Phân bổ phòng học',
                  onPressed: _isWorking
                      ? null
                      : () => _openAllocationForm(rooms, classes),
                ),
                if (rooms.isEmpty) ...[
                  const SizedBox(height: 12),
                  const _MissingRoomNotice(),
                ],
                const SizedBox(height: 12),
                _buildConflictNotice(),
                const SizedBox(height: 16),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        StreamBuilder<List<RoomAllocation>>(
                          stream: _allocations,
                          builder: (context, allocationSnapshot) {
                            if (allocationSnapshot.hasError) {
                              return _loadError(
                                allocationSnapshot.error!,
                                source: 'room-allocations',
                                subject: 'lịch phân bổ phòng',
                              );
                            }
                            if (allocationSnapshot.connectionState ==
                                    ConnectionState.waiting &&
                                !allocationSnapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final allocations =
                                allocationSnapshot.data ??
                                const <RoomAllocation>[];
                            if (allocations.isEmpty) {
                              return const RoomAllocationMessageState(
                                icon: Icons.event_available_outlined,
                                message: 'Chưa có lịch phân bổ nào.',
                              );
                            }
                            final roomNames = {
                              for (final room in rooms) room.id: room.name,
                            };
                            final classNames = {
                              for (final item in classes) item.id: item.name,
                            };
                            return constraints.maxWidth >= 800
                                ? _buildAllocationTable(
                                    allocations,
                                    roomNames,
                                    classNames,
                                    rooms,
                                    classes,
                                    constraints.maxWidth,
                                  )
                                : _buildAllocationCards(
                                    allocations,
                                    roomNames,
                                    classNames,
                                    rooms,
                                    classes,
                                  );
                          },
                        ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildConflictNotice() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Lịch lặp hàng tuần. Xung đột phòng và lớp được kiểm tra trước khi lưu; '
              'hai lịch liền kề được phép.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllocationTable(
    List<RoomAllocation> allocations,
    Map<String, String> roomNames,
    Map<String, String> classNames,
    List<Room> rooms,
    List<EnglishClass> classes,
    double minWidth,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Lớp học')),
                  DataColumn(label: Text('Phòng')),
                  DataColumn(label: Text('Thứ')),
                  DataColumn(label: Text('Thời gian')),
                  DataColumn(label: Text('Thao tác')),
                ],
                rows: allocations
                    .map(
                      (allocation) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              classNames[allocation.classId] ??
                                  'Lớp không tồn tại',
                            ),
                          ),
                          DataCell(
                            Text(
                              roomNames[allocation.roomId] ??
                                  'Phòng không tồn tại',
                            ),
                          ),
                          DataCell(Text(allocation.weekdayLabel)),
                          DataCell(Text(allocation.timeLabel)),
                          DataCell(
                            _allocationActions(allocation, rooms, classes),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllocationCards(
    List<RoomAllocation> allocations,
    Map<String, String> roomNames,
    Map<String, String> classNames,
    List<Room> rooms,
    List<EnglishClass> classes,
  ) {
    return ListView.separated(
      itemCount: allocations.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final allocation = allocations[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classNames[allocation.classId] ?? 'Lớp không tồn tại',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(roomNames[allocation.roomId] ?? 'Phòng không tồn tại'),
                const SizedBox(height: 8),
                Text('${allocation.weekdayLabel} · ${allocation.timeLabel}'),
                Align(
                  alignment: Alignment.centerRight,
                  child: _allocationActions(allocation, rooms, classes),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _allocationActions(
    RoomAllocation allocation,
    List<Room> rooms,
    List<EnglishClass> classes,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Sửa',
          onPressed: _isWorking
              ? null
              : () => _openAllocationForm(rooms, classes, allocation),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Hủy lịch',
          onPressed: _isWorking ? null : () => _deleteAllocation(allocation),
          icon: const Icon(Icons.event_busy_outlined),
        ),
      ],
    );
  }

  Widget _loadError(
    Object error, {
    required String source,
    required String subject,
  }) {
    _debugLogLoadError(source, error);
    return RoomAllocationMessageState(
      icon: Icons.cloud_off_outlined,
      message: roomAllocationLoadErrorMessage(error, subject),
      onRetry: () => setState(_reload),
    );
  }
}

class _RoomFormDialog extends StatefulWidget {
  const _RoomFormDialog({this.room});

  final Room? room;

  @override
  State<_RoomFormDialog> createState() => _RoomFormDialogState();
}

class _RoomFormDialogState extends State<_RoomFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;
  late String _status;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.room?.name);
    _capacityController = TextEditingController(
      text: widget.room?.capacity.toString(),
    );
    _status = widget.room?.status ?? 'active';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final input = RoomInput.tryParse(
      name: _nameController.text,
      capacity: _capacityController.text,
      status: _status,
    );
    if (input != null) Navigator.pop(context, input);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.room == null ? 'Thêm phòng học' : 'Sửa phòng học'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Tên/mã phòng'),
                validator: RoomInput.validateName,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _capacityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sức chứa tối đa'),
                validator: RoomInput.validateCapacity,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Trạng thái'),
                items: const [
                  DropdownMenuItem(
                    value: 'active',
                    child: Text('Đang hoạt động'),
                  ),
                  DropdownMenuItem(
                    value: 'inactive',
                    child: Text('Ngừng hoạt động'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) _status = value;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Lưu')),
      ],
    );
  }
}

class _AllocationFormDialog extends StatefulWidget {
  const _AllocationFormDialog({
    required this.rooms,
    required this.classes,
    required this.onSave,
    this.allocation,
  });

  final List<Room> rooms;
  final List<EnglishClass> classes;
  final RoomAllocation? allocation;
  final Future<void> Function(RoomAllocationInput input) onSave;

  @override
  State<_AllocationFormDialog> createState() => _AllocationFormDialogState();
}

class _AllocationFormDialogState extends State<_AllocationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _roomId;
  late String _classId;
  late int _weekday;
  var _saving = false;
  String? _error;

  EnglishClass get _selectedClass =>
      widget.classes.firstWhere((item) => item.id == _classId);
  ClassShift get _selectedShift =>
      ClassShift.fromCode(_selectedClass.shiftCode)!;
  List<int> get _availableWeekdays =>
      ClassSchedule.weekdaysFor(_selectedClass.studyPattern);

  @override
  void initState() {
    super.initState();
    final allocation = widget.allocation;
    _roomId = widget.rooms.any((room) => room.id == allocation?.roomId)
        ? allocation!.roomId
        : widget.rooms.first.id;
    _classId = widget.classes.any((item) => item.id == allocation?.classId)
        ? allocation!.classId
        : widget.classes.first.id;
    final allowedWeekdays = _availableWeekdays;
    _weekday =
        allocation != null && allowedWeekdays.contains(allocation.weekday)
        ? allocation.weekday
        : allowedWeekdays.first;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final input = RoomAllocationInput(
      roomId: _roomId,
      classId: _classId,
      weekday: _weekday,
      startMinute: _selectedShift.startMinute,
      endMinute: _selectedShift.endMinute,
    );
    try {
      await widget.onSave(input);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StateError
              ? error.message.toString()
              : 'Không thể kiểm tra xung đột. Lịch chưa được lưu.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.allocation == null ? 'Phân bổ phòng' : 'Sửa lịch phân bổ',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _classId,
                  decoration: const InputDecoration(labelText: 'Lớp học'),
                  items: widget.classes
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _classId = value;
                              _weekday = _availableWeekdays.first;
                              _error = null;
                            });
                          }
                        },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _roomId,
                  decoration: const InputDecoration(labelText: 'Phòng học'),
                  items: widget.rooms
                      .map(
                        (room) => DropdownMenuItem(
                          value: room.id,
                          child: Text('${room.name} (${room.capacity})'),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _roomId = value;
                              _error = null;
                            });
                          }
                        },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _weekday,
                  decoration: const InputDecoration(
                    labelText: 'Thứ trong tuần',
                  ),
                  items: _availableWeekdays
                      .map(
                        (weekday) => DropdownMenuItem(
                          value: weekday,
                          child: Text(weekdayName(weekday)),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _weekday = value;
                              _error = null;
                            });
                          }
                        },
                ),
                const SizedBox(height: 16),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Lịch và ca học',
                  ),
                  child: Text(
                    '${_selectedClass.studyPatternLabel} · '
                    '${_selectedClass.shiftLabel}',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                if (_saving) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleWidget = Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        );
        final button = FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.add),
          label: Text(buttonLabel),
        );
        return constraints.maxWidth >= 520
            ? Row(
                children: [
                  Expanded(child: titleWidget),
                  button,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [titleWidget, const SizedBox(height: 12), button],
              );
      },
    );
  }
}

class _RoomStatus extends StatelessWidget {
  const _RoomStatus({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(room.statusLabel),
      visualDensity: VisualDensity.compact,
    );
  }
}

class RoomAllocationMessageState extends StatelessWidget {
  const RoomAllocationMessageState({
    super.key,
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
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ],
      ),
    );
  }
}

class _MissingRoomNotice extends StatelessWidget {
  const _MissingRoomNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Chưa có phòng học. Hãy mở tab Phòng học và tạo ít nhất một phòng '
          'đang hoạt động trước khi phân bổ.',
        ),
      ),
    );
  }
}
