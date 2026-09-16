import 'api_client.dart';

class PromotionService {
  static final PromotionService instance = PromotionService._();
  PromotionService._();

  Future<List<Map<String, dynamic>>> getPromotions(
    String shopId, {
    bool activeOnly = false,
  }) async {
    final res = await ApiClient.instance.get(
      '/promotions/shop/$shopId',
      query: activeOnly ? {'active_only': 'true'} : null,
    );
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> createPromotion(
    String shopId, {
    required String title,
    required String description,
    required String validUntil,
  }) async {
    return await ApiClient.instance.post('/promotions/shop/$shopId', body: {
      'title': title,
      'description': description,
      'valid_until': validUntil,
    });
  }

  Future<void> deletePromotion(String promotionId) async {
    await ApiClient.instance.delete('/promotions/$promotionId');
  }

  /// Creates a Razorpay order for a Featured Promotion payment. Returns
  /// {order_id, amount, currency, key_id}.
  Future<Map<String, dynamic>> createPaymentOrder(
    String shopId, {
    required String title,
    required String description,
    required String validUntil,
  }) async {
    return await ApiClient.instance.post('/payments/promotion/shop/$shopId/create-order', body: {
      'title': title,
      'description': description,
      'valid_until': validUntil,
    });
  }

  /// Verifies the Razorpay payment signature and, if valid, creates the promotion.
  Future<Map<String, dynamic>> verifyPaymentAndActivate(
    String shopId, {
    required String title,
    required String description,
    required String validUntil,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    return await ApiClient.instance.post('/payments/promotion/shop/$shopId/verify', body: {
      'title': title,
      'description': description,
      'valid_until': validUntil,
      'razorpay_order_id': razorpayOrderId,
      'razorpay_payment_id': razorpayPaymentId,
      'razorpay_signature': razorpaySignature,
    });
  }
}
