import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import 'api_client.dart';

class ShopService {
  static final ShopService instance = ShopService._();
  ShopService._();

  Future<List<ShopModel>> listShops({
    String? city,
    String? category,
    bool openOnly = false,
  }) async {
    final res = await ApiClient.instance.get('/shops', query: {
      if (city != null && city.isNotEmpty) 'city': city,
      if (category != null) 'category': category,
      if (openOnly) 'open_only': 'true',
    });
    return (res['shops'] as List).map((s) => ShopModel.fromJson(s)).toList();
  }

  Future<List<String>> getCities() async {
    final res = await ApiClient.instance.get('/shops/cities');
    return (res as List).map((e) => e.toString()).toList();
  }

  Future<ShopModel> getShop(String shopId) async {
    final res = await ApiClient.instance.get('/shops/$shopId');
    return ShopModel.fromJson(res);
  }

  Future<ShopModel?> getMyShop() async {
    try {
      final res = await ApiClient.instance.get('/shops/my');
      return ShopModel.fromJson(res);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<ShopModel> createShop({
    required String name,
    required String category,
    required String address,
    required String city,
    int avgWaitMinutes = 10,
    List<Map<String, dynamic>> services = const [],
    String? openingHours,
  }) async {
    final res = await ApiClient.instance.post('/shops', body: {
      'name': name,
      'category': category,
      'address': address,
      'city': city,
      'avg_wait_minutes': avgWaitMinutes,
      'services': services,
      if (openingHours != null) 'opening_hours': openingHours,
    });
    return ShopModel.fromJson(res);
  }

  Future<ShopModel> updateShop(
    String shopId, {
    String? name,
    String? category,
    String? address,
    String? city,
    int? avgWaitMinutes,
    String? openingHours,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (category != null) 'category': category,
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (avgWaitMinutes != null) 'avg_wait_minutes': avgWaitMinutes,
      if (openingHours != null) 'opening_hours': openingHours,
    };
    final res = await ApiClient.instance.put('/shops/$shopId', body: body);
    return ShopModel.fromJson(res);
  }

  Future<ShopModel> toggleOpen(String shopId) async {
    await ApiClient.instance.post('/shops/$shopId/toggle-open');
    return getShop(shopId);
  }

  /// Uploads a single image to the shop. Returns the new public URL.
  Future<String> uploadImage(String shopId, XFile file) async {
    final bytes = await file.readAsBytes();
    final filename = file.name.isNotEmpty ? file.name : 'image.jpg';
    final mimeType = _mimeFromFilename(filename);
    final res = await ApiClient.instance.multipartPost(
      '/shops/$shopId/images',
      fileBytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );
    return res['url'] as String;
  }

  /// Deletes an image URL from the shop.
  Future<List<String>> deleteImage(String shopId, String imageUrl) async {
    final res = await ApiClient.instance.delete(
      '/shops/$shopId/images',
      body: {'image_url': imageUrl},
    );
    return List<String>.from(res['images'] as List);
  }

  String _mimeFromFilename(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }
}
