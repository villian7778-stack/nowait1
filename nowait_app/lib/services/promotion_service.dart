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
    // The API wraps the list: {"promotions": [...]}
    final list = res is Map ? res['promotions'] : res;
    if (list is List) {
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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

  Future<Map<String, dynamic>> updatePromotion(
    String promotionId, {
    String? title,
    String? description,
    String? validUntil,
  }) async {
    return await ApiClient.instance.put('/promotions/$promotionId', body: {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (validUntil != null) 'valid_until': validUntil,
    });
  }

  Future<void> deletePromotion(String promotionId) async {
    await ApiClient.instance.delete('/promotions/$promotionId');
  }

  /// Creates a Razorpay order for a Featured Promotion payment. Returns
  /// {order_id, amount, currency, key_id}.
  /// [days] is 3, 7 or 15; the server works out the price (₹10 a day), title and
  /// end date from it.
  Future<Map<String, dynamic>> createPaymentOrder(String shopId, {required int days}) async {
    return await ApiClient.instance.post('/payments/promotion/shop/$shopId/create-order', body: {'days': days});
  }

  /// Verifies the Razorpay payment signature and, if valid, creates the promotion.
  Future<Map<String, dynamic>> verifyPaymentAndActivate(
    String shopId, {
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    return await ApiClient.instance.post('/payments/promotion/shop/$shopId/verify', body: {
      'razorpay_order_id': razorpayOrderId,
      'razorpay_payment_id': razorpayPaymentId,
      'razorpay_signature': razorpaySignature,
    });
  }
}
