import 'package:googleapis/drive/v3.dart' as drive;

/// Dados arrastados do painel Google Drive para uma zona de soltar na secção.
class DriveFileDragData {
  DriveFileDragData(this.file);

  final drive.File file;
}
