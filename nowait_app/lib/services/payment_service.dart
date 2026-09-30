import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'api_client.dart';

class PaymentException implements Exception {
  final String message;
  PaymentException(this.message);
  @override
  String toString() => message;
}

/// Thrown when Razorpay delivers an error callback saying "order is already paid".
/// This happens with UPI: the UPI app captures the payment but Razorpay's checkout
/// then shows an error screen instead of calling the success handler. The payment
/// IS captured on Razorpay's end — the caller should reconcile rather than retry.
class PaymentAlreadyCaptured implements Exception {
  final String orderId;
  PaymentAlreadyCaptured(this.orderId);
}

/// Result of a successful Razorpay Standard Checkout payment, ready to be
/// sent to the backend's verify-payment endpoint.
class PaymentResult {
  final String orderId;
  final String paymentId;
  final String signature;
  PaymentResult({required this.orderId, required this.paymentId, required this.signature});
}

/// Wraps the razorpay_flutter plugin to open the native Razorpay Standard
/// Checkout modal and resolve with the payment result (or an error on
/// failure/cancellation).
class PaymentService {
  static final PaymentService instance = PaymentService._();
  PaymentService._();

  Razorpay? _razorpay;
  Completer<PaymentResult>? _completer;
  String? _orderId;
  String _purpose = 'subscription';

  Future<PaymentResult> openCheckout({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String name,
    required String description,
    String? contact,
    String? email,
    String purpose = 'subscription',
  }) {
    _razorpay?.clear();
    _orderId = orderId;
    _purpose = purpose;
    final completer = Completer<PaymentResult>();
    _completer = completer;

    final razorpay = Razorpay();
    _razorpay = razorpay;
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);

    razorpay.open({
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': 'NOWAIT',
      'description': description,
      // Prefilling contact/email skips Checkout's own contact-entry step.
      'prefill': {
        if (contact != null && contact.isNotEmpty) 'contact': contact,
        if (email != null && email.isNotEmpty) 'email': email,
      },
      'theme': {'color': '#1f4cdd'},
    });

    return completer.future.whenComplete(() {
      razorpay.clear();
      if (_razorpay == razorpay) _razorpay = null;
    });
  }

  void _onSuccess(PaymentSuccessResponse response) {
    _completer?.complete(PaymentResult(
      orderId: response.orderId ?? '',
      paymentId: response.paymentId ?? '',
      signature: response.signature ?? '',
    ));
  }

  void _onError(PaymentFailureResponse response) {
    // code == Razorpay.PAYMENT_CANCELLED when the user dismisses the modal.
    final cancelled = response.code == Razorpay.PAYMENT_CANCELLED;
    debugPrint('Razorpay failure: code=${response.code} message=${response.message} body=${response.error}');

    // "Order is already paid" means UPI captured the payment but Razorpay's checkout
    // delivered the error callback instead of success (common in UPI redirect flows on
    // Android). The money IS on Razorpay's end — tell the caller to reconcile.
    if (!cancelled && _isAlreadyPaid(response)) {
      debugPrint('Razorpay: order $_orderId is already paid — signalling reconcile');
      _completer?.completeError(PaymentAlreadyCaptured(_orderId ?? ''));
      return;
    }

    if (!cancelled) _reportFailure(response);
    _completer?.completeError(
      PaymentException(cancelled ? 'Payment cancelled' : describeFailure(response.message, response.error)),
    );
  }

  static bool _isAlreadyPaid(PaymentFailureResponse response) {
    final body = response.error;
    final err = body?['error'] is Map ? body!['error'] as Map : body;
    final description = (err?['description'] ?? '').toString().toLowerCase();
    final reason = (err?['reason'] ?? '').toString().toLowerCase();
    final message = (response.message ?? '').toLowerCase();
    return description.contains('already paid') ||
        reason.contains('already_paid') ||
        reason.contains('already paid') ||
        message.contains('already paid');
  }

  /// Checkout runs on the phone, so the server never sees Razorpay's failure reason.
  /// Send it to the backend so it appears in the server logs. Fire-and-forget.
  void _reportFailure(PaymentFailureResponse response) {
    final body = response.error;
    final err = body?['error'] is Map ? body!['error'] as Map : body;
    ApiClient.instance.post('/payments/report-failure', body: {
      'razorpay_order_id': _orderId,
      'purpose': _purpose,
      'step': 'checkout',
      'source': err?['source']?.toString() ?? 'razorpay_checkout',
      'code': (err?['code'] ?? response.code)?.toString(),
      'reason': err?['reason']?.toString(),
      'description': err?['description']?.toString(),
      'message': response.message,
      'raw': body?.toString(),
    }).catchError((Object e) {
      debugPrint('Could not report Razorpay failure: $e');
      return null;
    });
  }

  /// Razorpay often returns its reason as a JSON string ({"error":{"description":...,"reason":...}})
  /// or in the response body. Pull the human-readable parts out so the real cause is visible
  /// (e.g. "international_transaction_not_allowed") instead of a generic "Payment failed".
  @visibleForTesting
  static String describeFailure(String? message, Map<dynamic, dynamic>? body) {
    Map<dynamic, dynamic>? err = body?['error'] is Map ? body!['error'] as Map : body;
    if (err == null && message != null && message.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map) err = decoded['error'] is Map ? decoded['error'] as Map : decoded;
      } catch (_) {}
    }
    final description = err?['description']?.toString();
    final reason = err?['reason']?.toString();
    final code = err?['code']?.toString();
    final parts = <String>[
      if (description != null && description.isNotEmpty) description
      else if (message != null && message.isNotEmpty && !message.trim().startsWith('{')) message,
      if (reason != null && reason.isNotEmpty) '($reason)'
      else if (code != null && code.isNotEmpty) '($code)',
    ];
    return parts.isEmpty ? 'Payment failed' : 'Payment failed: ${parts.join(' ')}';
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    _completer?.completeError(PaymentException('Selected external wallet: ${response.walletName}'));
  }
}
