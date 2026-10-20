import 'package:cloud_firestore/cloud_firestore.dart';

class LearningResult {
  const LearningResult({
    required this.id,
    required this.classId,
    required this.studentId,
    required this.midtermScore,
    required this.finalScore,
    required this.comment,
    required this.updatedAt,
  });

  final String id;
  final String classId;
  final String studentId;
  final double? midtermScore;
  final double? finalScore;
  final String comment;
  final DateTime? updatedAt;

  static String documentId(String classId, String studentId) =>
      '${classId}_$studentId';

  static bool isValidScore(num? score) =>
      score == null || (score.isFinite && score >= 0 && score <= 10);

  static String scoreLabel(double? score) {
    if (score == null) return 'Chưa nhập';
    return score == score.roundToDouble()
        ? score.toInt().toString()
        : score.toString();
  }

  factory LearningResult.fromMap(String id, Map<String, dynamic> data) {
    final classId = data['classId'];
    final studentId = data['studentId'];
    final midtermScore = data['midtermScore'];
    final finalScore = data['finalScore'];
    final comment = data['comment'];
    final updatedAt = data['updatedAt'];
    final parsedMidterm = midtermScore is num ? midtermScore : null;
    final parsedFinal = finalScore is num ? finalScore : null;
    if (classId is! String ||
        classId.trim().isEmpty ||
        studentId is! String ||
        studentId.trim().isEmpty ||
        id != documentId(classId, studentId) ||
        (midtermScore != null && midtermScore is! num) ||
        (finalScore != null && finalScore is! num) ||
        !isValidScore(parsedMidterm) ||
        !isValidScore(parsedFinal) ||
        comment is! String ||
        comment.length > 1000 ||
        (updatedAt != null && updatedAt is! Timestamp)) {
      throw const FormatException('Dữ liệu kết quả học tập không hợp lệ.');
    }
    return LearningResult(
      id: id,
      classId: classId.trim(),
      studentId: studentId.trim(),
      midtermScore: parsedMidterm?.toDouble(),
      finalScore: parsedFinal?.toDouble(),
      comment: comment.trim(),
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
    );
  }
}

class LearningResultInput {
  const LearningResultInput({
    required this.studentId,
    required this.midtermScore,
    required this.finalScore,
    required this.comment,
  });

  final String studentId;
  final double? midtermScore;
  final double? finalScore;
  final String comment;

  bool get hasContent =>
      midtermScore != null || finalScore != null || comment.isNotEmpty;

  static String? validateScore(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final score = double.tryParse(text);
    return score != null && LearningResult.isValidScore(score)
        ? null
        : 'Điểm phải là số từ 0 đến 10.';
  }

  static String? validateComment(String? value) => (value?.length ?? 0) <= 1000
      ? null
      : 'Nhận xét không được vượt quá 1000 ký tự.';

  static LearningResultInput? tryCreate({
    required String studentId,
    required String midtermScore,
    required String finalScore,
    required String comment,
  }) {
    if (studentId.trim().isEmpty ||
        validateScore(midtermScore) != null ||
        validateScore(finalScore) != null ||
        validateComment(comment) != null) {
      return null;
    }
    return LearningResultInput(
      studentId: studentId.trim(),
      midtermScore: midtermScore.trim().isEmpty
          ? null
          : double.parse(midtermScore.trim()),
      finalScore: finalScore.trim().isEmpty
          ? null
          : double.parse(finalScore.trim()),
      comment: comment.trim(),
    );
  }
}

class LearningResultPolicy {
  const LearningResultPolicy._();

  static bool canTeacherManage({
    required bool isAssignedTeacher,
    required bool hasActiveEnrollment,
  }) => isAssignedTeacher && hasActiveEnrollment;

  static bool canStudentView({
    required String profileStudentId,
    required String resultStudentId,
  }) => profileStudentId == resultStudentId;
}
