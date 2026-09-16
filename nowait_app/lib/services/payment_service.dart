import 'dart:async';
import 'package:razorpay_flutter/razorpay_flutter.dart';

class PaymentException implements Exception {
  final String message;
  PaymentException(this.message);
  @override
  String toString() => message;
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

  Future<PaymentResult> openCheckout({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String name,
    required String description,
  }) {
    _razorpay?.clear();
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
      'prefill': {},
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
    _completer?.completeError(
      PaymentException(cancelled ? 'Payment cancelled' : (response.message ?? 'Payment failed')),
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    _completer?.completeError(PaymentException('Selected external wallet: ${response.walletName}'));
  }
}
