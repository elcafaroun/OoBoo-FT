import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ProductImageWidget extends StatelessWidget {
  final String? localPath;
  final String networkUrl;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const ProductImageWidget({
    super.key,
    this.localPath,
    required this.networkUrl,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Assainissement du chemin local
    final String? cleanPath = (localPath != null &&
        localPath != "null" &&
        localPath!.trim().isNotEmpty)
        ? localPath!.trim()
        : null;

    bool hasValidLocalFile = false;
    File? imageFile;

    if (cleanPath != null) {
      try {
        final file = File(cleanPath);
        if (file.existsSync() && file.lengthSync() > 0) {
          hasValidLocalFile = true;
          imageFile = file;
        }
      } catch (_) {
        hasValidLocalFile = false;
      }
    }

    final bool hasNetworkUrl = networkUrl.isNotEmpty &&
        networkUrl != "null" &&
        networkUrl.startsWith("http");

    Widget content;

    if (hasValidLocalFile && imageFile != null) {
      content = Image.file(
        imageFile,
        key: ValueKey("file_${imageFile.path}_${imageFile.lastModifiedSync().millisecondsSinceEpoch}"),
        fit: BoxFit.cover,
        gaplessPlayback: true, // 🟢 Conserve l'image affichée lors du rebuild
        errorBuilder: (_, __, ___) => _buildNetworkOrPlaceholder(hasNetworkUrl),
      );
    } else if (hasNetworkUrl) {
      content = _buildCachedNetworkImage();
    } else {
      content = _buildErrorPlaceholder();
    }

    Widget container = SizedBox(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      child: content,
    );

    if (borderRadius != null) {
      container = ClipRRect(
        borderRadius: borderRadius!,
        child: container,
      );
    }

    return container;
  }

  Widget _buildNetworkOrPlaceholder(bool hasNetworkUrl) {
    if (hasNetworkUrl) {
      return _buildCachedNetworkImage();
    }
    return _buildErrorPlaceholder();
  }

  Widget _buildCachedNetworkImage() {
    return CachedNetworkImage(
      key: ValueKey("net_$networkUrl"),
      imageUrl: networkUrl,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => Container(
        color: Colors.grey[100],
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
          ),
        ),
      ),
      errorWidget: (context, url, error) => _buildErrorPlaceholder(),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      color: Colors.grey[100],
      child: const Center(
        child: Icon(Icons.image_not_supported_rounded, color: Colors.grey, size: 24),
      ),
    );
  }
}