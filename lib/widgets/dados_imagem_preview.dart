import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/globals.dart';
import '../models/dados.dart';

/// Miniatura de [DadosImagem] (URL HTTP ou Google Drive por miniatura/bytes).
class DadosImagemPreview extends StatelessWidget {
  const DadosImagemPreview({
    super.key,
    required this.img,
    this.width,
    this.height,
  });

  final DadosImagem img;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final w = width ?? 100;
    final h = height ?? 80;

    if (img.fonte == ImagemFonte.urlPublica &&
        (img.publicUrl != null && img.publicUrl!.trim().isNotEmpty)) {
      return Image.network(
        img.publicUrl!.trim(),
        width: w,
        height: h,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) => _placeholder(w, h),
      );
    }

    if (img.fonte == ImagemFonte.googleDrive &&
        (img.driveFileId != null && img.driveFileId!.trim().isNotEmpty)) {
      final thumb = img.driveThumbnailLink?.trim();
      if (thumb != null && thumb.isNotEmpty) {
        return Image.network(
          thumb,
          width: w,
          height: h,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) =>
              _DriveBytesPreview(fileId: img.driveFileId!.trim(), width: w, height: h),
        );
      }
      return _DriveBytesPreview(fileId: img.driveFileId!.trim(), width: w, height: h);
    }

    return _placeholder(w, h);
  }

  Widget _placeholder(double w, double h) {
    return Container(
      width: w,
      height: h,
      color: Colors.grey[300],
      child: const Icon(Icons.image_not_supported, size: 32),
    );
  }
}

class _DriveBytesPreview extends StatelessWidget {
  const _DriveBytesPreview({
    required this.fileId,
    required this.width,
    required this.height,
  });

  final String fileId;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: appDriveService.downloadFileBytes(fileId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: width,
            height: height,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final b = snapshot.data;
        if (b == null || b.isEmpty) {
          return Container(
            width: width,
            height: height,
            color: Colors.grey[300],
            child: const Icon(Icons.image_not_supported, size: 32),
          );
        }
        return Image.memory(
          b,
          width: width,
          height: height,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) => Container(
            width: width,
            height: height,
            color: Colors.grey[300],
            child: const Icon(Icons.image_not_supported, size: 32),
          ),
        );
      },
    );
  }
}
