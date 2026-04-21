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
}
