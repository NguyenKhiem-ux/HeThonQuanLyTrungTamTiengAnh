import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/room.dart';
import 'firestore_stream.dart';

class RoomService {
  RoomService._();

  static final instance = RoomService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Query<Map<String, dynamic>> get _roomsQuery =>
      _firestore.collection('rooms').orderBy('name');

  Stream<List<Room>> watchRooms() {
    var isFirstSnapshot = true;
    return _roomsQuery
        .snapshots()
        .withInitialSnapshotTimeout(const Duration(seconds: 15), 'ROOM_DEBUG')
        .map((snapshot) {
          if (kDebugMode) {
            if (isFirstSnapshot) {
              isFirstSnapshot = false;
              debugPrint('[ROOM_DEBUG] first snapshot received');
            }
            debugPrint('[ROOM_DEBUG] documents count: ${snapshot.docs.length}');
          }
          return snapshot.docs
              .map((document) => Room.fromMap(document.id, document.data()))
              .toList();
        })
        .handleError((Object error, StackTrace stackTrace) {
          if (kDebugMode && error is FirebaseException) {
            debugPrint(
              '[ROOM_DEBUG] FirebaseException.code (snapshots): ${error.code}',
            );
            debugPrint(
              '[ROOM_DEBUG] FirebaseException.message (snapshots): '
              '${error.message}',
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  Future<void> debugRoomsServerRead() async {
    if (!kDebugMode) return;
    debugPrint('[ROOM_DEBUG] server get start');
    try {
      final snapshot = await _roomsQuery
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      debugPrint('[ROOM_DEBUG] server get succeeded');
      debugPrint(
        '[ROOM_DEBUG] server get documents count: ${snapshot.docs.length}',
      );
    } on FirebaseException catch (error) {
      debugPrint(
        '[ROOM_DEBUG] FirebaseException.code (server get): ${error.code}',
      );
      debugPrint(
        '[ROOM_DEBUG] FirebaseException.message (server get): '
        '${error.message}',
      );
    } on TimeoutException {
      debugPrint('[ROOM_DEBUG] timeout (server get)');
    } catch (error) {
      debugPrint(
        '[ROOM_DEBUG] server get error (${error.runtimeType}): $error',
      );
    }
  }

  Future<void> addRoom(RoomInput input) async {
    final timestamp = FieldValue.serverTimestamp();
    await _firestore.collection('rooms').add({
      'name': input.name,
      'capacity': input.capacity,
      'status': input.status,
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
  }

  Future<void> updateRoom(Room room, RoomInput input) async {
    if (input.capacity < room.capacity) {
      final requiredCapacity = await _largestAllocatedClass(room.id);
      if (input.capacity < requiredCapacity) {
        throw StateError(
          'Không thể giảm sức chứa dưới $requiredCapacity học viên vì phòng '
          'đang được phân bổ cho lớp có sĩ số tối đa tương ứng.',
        );
      }
    }
    await _firestore.collection('rooms').doc(room.id).update({
      'name': input.name,
      'capacity': input.capacity,
      'status': input.status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteRoom(Room room) async {
    final hasAllocations = await _hasAllocations(room.id);
    if (!room.canDelete(hasAllocations: hasAllocations)) {
      throw StateError(
        'Không thể xóa phòng đang có lịch phân bổ. Hãy hủy lịch trước.',
      );
    }
    await _firestore.collection('rooms').doc(room.id).delete();
  }

  Future<bool> _hasAllocations(String roomId) async {
    final snapshot = await _firestore
        .collection('room_allocations')
        .where('roomId', isEqualTo: roomId)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  Future<int> _largestAllocatedClass(String roomId) async {
    final allocations = await _firestore
        .collection('room_allocations')
        .where('roomId', isEqualTo: roomId)
        .get();
    final classIds = allocations.docs
        .map((document) => document.data()['classId'])
        .whereType<String>()
        .toSet();
    if (classIds.isEmpty) return 0;

    final classes = await Future.wait(
      classIds.map((id) => _firestore.collection('classes').doc(id).get()),
    );
    var largest = 0;
    for (final document in classes) {
      final maxStudents = document.data()?['maxStudents'];
      if (!document.exists || maxStudents is! int) {
        throw StateError('Không thể xác minh sĩ số lớp đã phân bổ.');
      }
      if (maxStudents > largest) largest = maxStudents;
    }
    return largest;
  }
}
