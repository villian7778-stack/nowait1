import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
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
    String state = '',
    int avgWaitMinutes = 10,
    List<Map<String, dynamic>> services = const [],
    String? openingHours,
    double? latitude,
    double? longitude,
  }) async {
    final res = await ApiClient.instance.post('/shops', body: {
      'name': name,
      'category': category,
      'address': address,
      'city': city,
      'state': state,
      'avg_wait_minutes': avgWaitMinutes,
      'services': services,
      if (openingHours != null) 'opening_hours': openingHours,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
    return ShopModel.fromJson(res);
  }

  Future<ShopModel> updateShop(
    String shopId, {
    String? name,
    String? category,
    String? address,
    String? city,
    String? state,
    int? avgWaitMinutes,
    String? openingHours,
    double? latitude,
    double? longitude,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (category != null) 'category': category,
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (state != null) 'state': state,
      if (avgWaitMinutes != null) 'avg_wait_minutes': avgWaitMinutes,
      if (openingHours != null) 'opening_hours': openingHours,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
    final res = await ApiClient.instance.put('/shops/$shopId', body: body);
    return ShopModel.fromJson(res);
  }

  Future<void> addService(String shopId, {required String name, required double price, int durationMinutes = 20}) async {
    await ApiClient.instance.post('/shops/$shopId/services', body: {
      'name': name,
      'price': price,
      'duration_minutes': durationMinutes,
      'description': '',
    });
  }

  Future<void> deleteService(String serviceId) async {
    await ApiClient.instance.delete('/shops/services/$serviceId');
  }

  Future<ShopModel> toggleOpen(String shopId) async {
    await ApiClient.instance.post('/shops/$shopId/toggle-open');
    return getShop(shopId);
  }

  /// Uploads a single image to the shop. Returns the new public URL.
  Future<String> uploadImage(String shopId, XFile file) async {
    final original = await file.readAsBytes();
    var filename = file.name.isNotEmpty ? file.name : 'image.jpg';
    var mimeType = _mimeFromFilename(filename);
    final bytes = await _compress(original);
    if (bytes.lengthInBytes > _maxImageBytes) {
      throw ApiException(
        413,
        'Photo "$filename" is too large even after compression (max 0.5 MB each, 5 photos = 2.5 MB). Please choose a different photo.',
      );
    }
    if (!identical(bytes, original)) {
      // Compressed output is always JPEG.
      filename = '${filename.split('.').first}.jpg';
      mimeType = 'image/jpeg';
    }
    final res = await ApiClient.instance.multipartPost(
      '/shops/$shopId/images',
      fileBytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );
    return res['url'] as String;
  }

  static const _maxImageBytes = 512 * 1024; // 0.5 MB per image

  /// Shrinks [input] to at most ~0.5 MB (JPEG), lowering quality then
  /// dimensions until it fits. Returns [input] unchanged if already small
  /// enough or if compression fails.
  Future<Uint8List> _compress(Uint8List input) async {
    if (input.lengthInBytes <= _maxImageBytes) return input;
    try {
      var quality = 85;
      var side = 1920;
      Uint8List out = input;
      for (var i = 0; i < 8; i++) {
        out = await FlutterImageCompress.compressWithList(
          input,
          minWidth: side,
          minHeight: side,
          quality: quality,
          format: CompressFormat.jpeg,
        );
        if (out.lengthInBytes <= _maxImageBytes) return out;
        if (quality > 50) {
          quality -= 10;
        } else {
          side = (side * 0.8).round();
        }
      }
      return out;
    } catch (_) {
      return input;
    }
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
