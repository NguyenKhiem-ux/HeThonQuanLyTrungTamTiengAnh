import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/course.dart';

class CourseService {
  CourseService._();

  static final instance = CourseService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<Course>> watchCourses() => _firestore
      .collection('courses')
      .orderBy('name')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((document) => Course.fromMap(document.id, document.data()))
            .toList(),
      );

  Future<void> addCourse(CourseInput input) async {
    final timestamp = FieldValue.serverTimestamp();
    await _firestore.collection('courses').add({
      ...input.toFirestore(),
      'createdAt': timestamp,
      'updatedAt': timestamp,
    });
  }

  Future<void> updateCourse(String courseId, CourseInput input) async {
    await _firestore.collection('courses').doc(courseId).update({
      ...input.toFirestore(),
      'durationHours': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> hasClasses(String courseId) async {
    final snapshot = await _firestore
        .collection('classes')
        .where('courseId', isEqualTo: courseId)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  Future<void> deleteCourse(String courseId) =>
      _firestore.collection('courses').doc(courseId).delete();
}
