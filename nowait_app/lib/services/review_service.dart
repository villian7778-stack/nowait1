import '../models/models.dart';
import 'api_client.dart';

class ReviewService {
  static final ReviewService instance = ReviewService._();
  ReviewService._();

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
    };
  }

  Future<Map<String, dynamic>> getReviewSummary(String shopId) async {
    final json = await ApiClient.instance.get('/reviews/shops/$shopId/summary');
    return json as Map<String, dynamic>;
  }
}
