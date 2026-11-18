import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A shop photo from the server, kept on the phone after the first view (lists and shop pages
/// then show it at once instead of downloading it again), and decoded at the size it is shown -
/// a 68 px thumbnail doesn't decode a full-size photo.
class ShopPhoto extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Shown when the photo can't be loaded.
  final Widget Function() fallback;

  /// Shown while it loads (default: nothing - the space stays empty).
  final Widget Function()? loading;

  const ShopPhoto(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    required this.fallback,
    this.loading,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) { // no file cache on the web: the browser caches it
      return Image.network(url, width: width, height: height, fit: fit, errorBuilder: (_, _, _) => fallback());
    }
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final w = width;
    // full-width photos (width: double.infinity) decode at the screen's width
    final decodeWidth = w == null ? null : ((w.isFinite ? w : MediaQuery.sizeOf(context).width) * ratio).round();
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: decodeWidth,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: loading == null ? null : (_, _) => loading!(),
      errorWidget: (_, _, _) => fallback(),
    );
  }
}
