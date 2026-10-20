import 'dart:async';

import 'package:flutter/foundation.dart';

extension InitialSnapshotTimeout<T> on Stream<T> {
  Stream<T> withInitialSnapshotTimeout([
    Duration duration = const Duration(seconds: 15),
    String? debugName,
  ]) => Stream<T>.multi((controller) {
    Timer? timer;
    var awaitingInitialEvent = true;
    var cancellationLogged = false;

    void debugLog(String message) {
      if (kDebugMode && debugName != null) {
        debugPrint('[$debugName] $message');
      }
    }

    void logCancellation() {
      if (!cancellationLogged) {
        cancellationLogged = true;
        debugLog('subscription cancelled');
      }
    }

    debugLog('start query');
    late StreamSubscription<T> subscription;
    subscription = listen(
      (value) {
        awaitingInitialEvent = false;
        timer?.cancel();
        controller.add(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        awaitingInitialEvent = false;
        timer?.cancel();
        controller.addError(error, stackTrace);
      },
      onDone: () {
        awaitingInitialEvent = false;
        timer?.cancel();
        controller.close();
      },
    );
    if (awaitingInitialEvent) {
      timer = Timer(duration, () {
        debugLog('timeout');
        controller.addError(
          TimeoutException('Firestore did not return an initial snapshot.'),
        );
        controller.close();
        logCancellation();
        subscription.cancel();
      });
    }
    controller.onCancel = () {
      timer?.cancel();
      logCancellation();
      return subscription.cancel();
    };
  }, isBroadcast: isBroadcast);
}
