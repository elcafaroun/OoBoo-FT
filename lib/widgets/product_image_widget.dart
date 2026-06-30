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
    // On définit le widget de base
    Widget imageWidget = _buildImage();

    // Si on a un borderRadius, on encapsule dans un ClipRRect
    if (borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    // On force l'expansion si aucune dimension fixe n'est fournie
    if (width == null && height == null) {
      return SizedBox.expand(child: imageWidget);
    }

    return SizedBox(
      width: width,
      height: height,
      child: imageWidget,
    );
  }

  Widget _buildImage() {
    // 1. Image locale
    if (localPath != null && localPath!.isNotEmpty && File(localPath!).existsSync()) {
      return Image.file(
        File(localPath!),
        width: width ?? double.infinity,
        height: height ?? double.infinity,
        fit: BoxFit.cover, // "cover" assure le remplissage total sans déformation
      );
    }

    // 2. Image réseau
    return Image.network(
      networkUrl,
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      fit: BoxFit.cover, // "cover" assure le remplissage total sans déformation
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
      ),
    );
  }
}