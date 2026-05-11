import '../models/models.dart';
import 'api_client.dart';

class ReviewService {
  static final ReviewService instance = ReviewService._();
  ReviewService._();

  final Map<String, Map<String, dynamic>> _summaryCache = {};

  Future<ReviewModel> submitReview({
    required String shopId,
    required String queueEntryId,
    required int rating,
    String? review,
  }) async {
    final json = await ApiClient.instance.post(
      '/reviews/shops/$shopId',
      body: {
        'queue_entry_id': queueEntryId,
        'rating': rating,
        if (review != null && review.isNotEmpty) 'review': review,
      },
    );
    return ReviewModel.fromJson(json as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getReviews(
    String shopId, {
    int page = 1,
    int limit = 20,
  }) async {
    final json = await ApiClient.instance.get(
      '/reviews/shops/$shopId?page=$page&limit=$limit',
    );
    final data = json as Map<String, dynamic>;
    final reviews = (data['reviews'] as List? ?? [])
        .map((r) => ReviewModel.fromJson(r as Map<String, dynamic>))
        .toList();
    return {
      'reviews': reviews,
      'total': data['total'] ?? 0,
      'page': data['page'] ?? 1,
      'has_more': data['has_more'] ?? false,
      'avg_rating': (data['avg_rating'] as num?)?.toDouble() ?? 0.0,
    };
  }

  Future<Map<String, dynamic>> getReviewSummary(String shopId) async {
    if (_summaryCache.containsKey(shopId)) return _summaryCache[shopId]!;
    final json = await ApiClient.instance.get('/reviews/shops/$shopId/summary');
    final result = json as Map<String, dynamic>;
    _summaryCache[shopId] = result;
    return result;
  }

  void invalidateSummaryCache(String shopId) => _summaryCache.remove(shopId);
}
