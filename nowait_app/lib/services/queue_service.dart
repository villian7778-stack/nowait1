import '../models/models.dart';
import 'api_client.dart';

class QueueService {
  static final QueueService instance = QueueService._();
  QueueService._();

  Future<QueueEntry> joinQueue(String shopId, {String? serviceId}) async {
    final body = <String, dynamic>{'shop_id': shopId};
    if (serviceId != null) body['service_id'] = serviceId;
    final res = await ApiClient.instance.post('/queues/join', body: body);
    return QueueEntry.fromJson(res);
  }

  Future<List<QueueEntry>> getMyStatus({String? shopId}) async {
    final res = await ApiClient.instance.get(
      '/queues/status',
      query: shopId != null ? {'shop_id': shopId} : null,
    );
    return (res as List).map((e) => QueueEntry.fromJson(e)).toList();
  }

  Future<void> cancelQueue(String entryId) async {
    await ApiClient.instance.delete('/queues/$entryId/cancel');
  }

  Future<void> notifyComing(String entryId) async {
    await ApiClient.instance.post('/queues/$entryId/coming');
  }

  Future<Map<String, dynamic>> getShopQueue(String shopId) async {
    return await ApiClient.instance.get('/queues/shop/$shopId');
  }

  Future<Map<String, dynamic>> advanceQueue(String shopId) async {
    return await ApiClient.instance.post('/queues/shop/$shopId/next');
  }

  Future<void> skipCustomer(String entryId, {String? note}) async {
    final body = <String, dynamic>{};
    if (note != null && note.isNotEmpty) body['note'] = note;
    await ApiClient.instance.post('/queues/$entryId/skip',
        body: body.isNotEmpty ? body : null);
  }

  Future<void> pauseQueue(String shopId) async {
    await ApiClient.instance.post('/queues/shop/$shopId/pause');
  }

  Future<void> resumeQueue(String shopId) async {
    await ApiClient.instance.post('/queues/shop/$shopId/resume');
  }

  Future<void> setMaxSize(String shopId, int? maxSize) async {
    await ApiClient.instance.put('/queues/shop/$shopId/max-size', body: {'max_size': maxSize});
  }

  Future<List<VisitHistory>> getHistory() async {
    final res = await ApiClient.instance.get('/queues/history');
    return (res as List).map((e) => VisitHistory.fromJson(e)).toList();
  }
}
