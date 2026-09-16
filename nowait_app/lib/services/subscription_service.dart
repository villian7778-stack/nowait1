import 'api_client.dart';

class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  Future<Map<String, dynamic>> getSubscription(String shopId) async {
    return await ApiClient.instance.get('/subscriptions/shop/$shopId');
  }

  Future<Map<String, dynamic>> createSubscription(
    String shopId, {
    String plan = 'basic',
    int durationDays = 30,
  }) async {
    return await ApiClient.instance.post('/subscriptions/shop/$shopId', body: {
      'plan': plan,
      'duration_days': durationDays,
    });
  }

  Future<Map<String, dynamic>> cancelSubscription(String shopId) async {
    return await ApiClient.instance.delete('/subscriptions/shop/$shopId');
  }

  /// Creates a Razorpay order for a subscription payment. Returns
  /// {order_id, amount, currency, key_id}.
  Future<Map<String, dynamic>> createPaymentOrder(
    String shopId, {
    required String plan,
    required int durationDays,
  }) async {
    return await ApiClient.instance.post('/payments/subscription/shop/$shopId/create-order', body: {
      'plan': plan,
      'duration_days': durationDays,
    });
  }

  /// Verifies the Razorpay payment signature and, if valid, activates the subscription.
  Future<Map<String, dynamic>> verifyPaymentAndActivate(
    String shopId, {
    required String plan,
    required int durationDays,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    return await ApiClient.instance.post('/payments/subscription/shop/$shopId/verify', body: {
      'plan': plan,
      'duration_days': durationDays,
      'razorpay_order_id': razorpayOrderId,
      'razorpay_payment_id': razorpayPaymentId,
      'razorpay_signature': razorpaySignature,
    });
  }
}
