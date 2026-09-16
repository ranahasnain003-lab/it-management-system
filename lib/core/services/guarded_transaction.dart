import 'package:cloud_firestore/cloud_firestore.dart';

/// Runs a Firestore transaction whose validation errors are reported to the
/// caller WITHOUT being thrown out of the transaction handler.
///
/// Why: in the cloud_firestore method-channel implementation used by this
/// app, a handler that throws on an attempt the native SDK then retries
/// (transaction contention) completes an internal future twice and raises an
/// uncaught "Bad state: Future already completed" error. Capturing the error,
/// letting the attempt finish, and rethrowing afterwards avoids that.
///
/// CONTRACT: [handler] must perform all reads and validation before its
/// first `transaction.set/update/delete`. A handler that fails therefore has
/// no queued writes, so the finished attempt commits nothing.
Future<void> runGuardedTransaction(
  FirebaseFirestore firestore,
  Future<void> Function(Transaction transaction) handler,
) async {
  Object? failure;
  StackTrace? failureStack;

  await firestore.runTransaction((transaction) async {
    // Each (re)try starts clean; only the final attempt's outcome counts.
    failure = null;
    failureStack = null;

    try {
      await handler(transaction);
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
  });

  final error = failure;

  if (error != null) {
    Error.throwWithStackTrace(error, failureStack ?? StackTrace.current);
  }
}
