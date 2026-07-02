import 'dart:io';
import 'package:flutter/material.dart';

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
    // 1. Vérification du fichier local de manière persistante
    final bool hasLocalFile = localPath != null &&
        localPath!.isNotEmpty &&
        localPath != "null" &&
        File(localPath!).existsSync();

    Widget content;

    if (hasLocalFile) {
      content = Image.file(File(localPath!), fit: BoxFit.cover);
    } else if (networkUrl.isNotEmpty && networkUrl != "null") {
      content = Image.network(
        networkUrl,
        fit: BoxFit.cover,
        // frameBuilder est la clé : il permet de conserver l'image précédente
        // ou d'afficher le contenu sans "saut" brutal lors du chargement.
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return frame != null
              ? child
              : const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
        },
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey[100],
          child: const Icon(Icons.image_not_supported, color: Colors.grey),
        ),
      );
    } else {
      content = Container(
        color: Colors.grey[100],
        child: const Icon(Icons.photo_size_select_actual_outlined, color: Colors.grey),
      );
    }

    // Application du clip et des dimensions
    return SizedBox(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      child: borderRadius != null
          ? ClipRRect(borderRadius: borderRadius!, child: content)
          : content,
    );
  }
}