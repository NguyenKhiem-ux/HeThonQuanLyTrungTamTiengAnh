class Room {
  const Room({
    required this.id,
    required this.name,
    required this.capacity,
    required this.status,
  });

  static const validStatuses = {'active', 'inactive'};

  final String id;
  final String name;
  final int capacity;
  final String status;

  bool get isActive => status == 'active';
  bool canDelete({required bool hasAllocations}) => !hasAllocations;

  String get statusLabel => isActive ? 'Đang hoạt động' : 'Ngừng hoạt động';

  factory Room.fromMap(String id, Map<String, dynamic> data) {
    final name = data['name'];
    final capacity = data['capacity'];
    final status = data['status'];
    if (name is! String ||
        name.trim().isEmpty ||
        capacity is! int ||
        capacity <= 0 ||
        status is! String ||
        !validStatuses.contains(status)) {
      throw const FormatException('Dữ liệu phòng học không hợp lệ.');
    }

    return Room(id: id, name: name.trim(), capacity: capacity, status: status);
  }
}

class RoomInput {
  const RoomInput({
    required this.name,
    required this.capacity,
    required this.status,
  });

  final String name;
  final int capacity;
  final String status;

  static String? validateName(String? value) =>
      (value?.trim().isEmpty ?? true) ? 'Vui lòng nhập tên/mã phòng.' : null;

  static String? validateCapacity(String? value) {
    final capacity = int.tryParse(value?.trim() ?? '');
    return capacity == null || capacity <= 0
        ? 'Sức chứa phải là số nguyên lớn hơn 0.'
        : null;
  }

  static RoomInput? tryParse({
    required String name,
    required String capacity,
    required String status,
  }) {
    final parsedCapacity = int.tryParse(capacity.trim());
    if (name.trim().isEmpty ||
        parsedCapacity == null ||
        parsedCapacity <= 0 ||
        !Room.validStatuses.contains(status)) {
      return null;
    }
    return RoomInput(
      name: name.trim(),
      capacity: parsedCapacity,
      status: status,
    );
  }
}
