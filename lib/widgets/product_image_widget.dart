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
    // 1. Vérification du fichier local
    final bool hasLocalFile = localPath != null &&
        localPath!.isNotEmpty &&
        localPath != "null" &&
        File(localPath!).existsSync();

    // 2. Vérification de l'URL réseau
    final bool hasNetworkUrl = networkUrl.isNotEmpty &&
        networkUrl != "null" &&
        networkUrl.startsWith("http");

    Widget content;

    if (hasLocalFile) {
      // 💡 Astuce radicale : On vide explicitement le cache de l'image locale
      // pour obliger Flutter à recharger physiquement le fichier du disque à chaque affichage.
      final file = File(localPath!);
      final fileImage = FileImage(file);
      fileImage.evict(); // Supprime l'ancienne image du cache Flutter

      content = Image(
        image: fileImage,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildErrorPlaceholder(),
      );
    } else if (hasNetworkUrl) {
      content = CachedNetworkImage(
        imageUrl: networkUrl,
        cacheKey: networkUrl, // Force le rafraîchissement si l'URL change
        fit: BoxFit.cover,
        placeholder: (context, url) => const Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)
          ),
        ),
        errorWidget: (context, url, error) => _buildErrorPlaceholder(),
      );
    } else {
      content = _buildErrorPlaceholder();
    }

    // Application du clip et des dimensions
    final Widget container = SizedBox(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      child: borderRadius != null
          ? ClipRRect(borderRadius: borderRadius!, child: content)
          : content,
    );

    // Retourner le conteneur enveloppé dans un KeyedSubtree unique basé sur le chemin et la date du fichier
    return KeyedSubtree(
      key: ValueKey("${localPath ?? ''}_${hasLocalFile ? File(localPath!).lastModifiedSync().millisecondsSinceEpoch : 0}_$networkUrl"),
      child: container,
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      color: Colors.grey[100],
      child: const Icon(Icons.image_not_supported, color: Colors.grey),
    );
  }
}