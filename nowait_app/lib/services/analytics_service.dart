import '../models/models.dart';
import 'api_client.dart';

class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._();
  AnalyticsService._();

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<AnalyticsSummary> getSummary(
    String shopId, {
    String period = 'today',
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final res = await ApiClient.instance.get(
      '/analytics/shops/$shopId/summary',
      query: {
        'period': period,
        if (fromDate != null) 'from_date': _ymd(fromDate),
        if (toDate != null) 'to_date': _ymd(toDate),
      },
    );
    return AnalyticsSummary.fromJson(res);
  }

  Future<List<Map<String, dynamic>>> getHourlyStats(
    String shopId, {
    int days = 7,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final res = await ApiClient.instance.get(
      '/analytics/shops/$shopId/hourly',
      query: {
        'days': days.toString(),
        if (fromDate != null) 'from_date': _ymd(fromDate),
        if (toDate != null) 'to_date': _ymd(toDate),
      },
    );
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getStaffPerformance(String shopId) async {
    final res = await ApiClient.instance.get('/analytics/shops/$shopId/staff');
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }
}
