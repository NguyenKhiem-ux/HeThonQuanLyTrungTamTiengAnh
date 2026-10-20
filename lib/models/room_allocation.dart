class RoomAllocation {
  const RoomAllocation({
    required this.id,
    required this.roomId,
    required this.classId,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
  });

  final String id;
  final String roomId;
  final String classId;
  final int weekday;
  final int startMinute;
  final int endMinute;

  String get weekdayLabel => weekdayName(weekday);
  String get timeLabel =>
      '${formatMinute(startMinute)}–${formatMinute(endMinute)}';

  bool conflictsWith(RoomAllocation other) =>
      weekday == other.weekday &&
      (roomId == other.roomId || classId == other.classId) &&
      timeRangesOverlap(
        startMinute,
        endMinute,
        other.startMinute,
        other.endMinute,
      );

  factory RoomAllocation.fromMap(String id, Map<String, dynamic> data) {
    final roomId = data['roomId'];
    final classId = data['classId'];
    final weekday = data['weekday'];
    final startMinute = data['startMinute'];
    final endMinute = data['endMinute'];
    if (roomId is! String ||
        roomId.trim().isEmpty ||
        classId is! String ||
        classId.trim().isEmpty ||
        weekday is! int ||
        weekday < 1 ||
        weekday > 7 ||
        startMinute is! int ||
        endMinute is! int ||
        !isValidTimeRange(startMinute, endMinute)) {
      throw const FormatException('Dữ liệu phân bổ phòng không hợp lệ.');
    }
    return RoomAllocation(
      id: id,
      roomId: roomId.trim(),
      classId: classId.trim(),
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
    );
  }
}

class RoomAllocationInput {
  const RoomAllocationInput({
    required this.roomId,
    required this.classId,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
  });

  final String roomId;
  final String classId;
  final int weekday;
  final int startMinute;
  final int endMinute;

  bool get isValid =>
      roomId.trim().isNotEmpty &&
      classId.trim().isNotEmpty &&
      weekday >= 1 &&
      weekday <= 7 &&
      isValidTimeRange(startMinute, endMinute);

  bool conflictsWith(RoomAllocation other) =>
      weekday == other.weekday &&
      (roomId == other.roomId || classId == other.classId) &&
      timeRangesOverlap(
        startMinute,
        endMinute,
        other.startMinute,
        other.endMinute,
      );
}

bool isValidTimeRange(int startMinute, int endMinute) =>
    startMinute >= 0 && startMinute < endMinute && endMinute <= 1440;

bool timeRangesOverlap(int startA, int endA, int startB, int endB) =>
    startA < endB && startB < endA;

String weekdayName(int weekday) => switch (weekday) {
  1 => 'Thứ Hai',
  2 => 'Thứ Ba',
  3 => 'Thứ Tư',
  4 => 'Thứ Năm',
  5 => 'Thứ Sáu',
  6 => 'Thứ Bảy',
  7 => 'Chủ Nhật',
  _ => 'Không hợp lệ',
};

String formatMinute(int minute) {
  final hours = minute ~/ 60;
  final minutes = minute % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}
