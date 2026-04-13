import '../services/google_drive_service.dart';

/// Instância compartilhada (OAuth / Drive) para toda a árvore de widgets.
final GoogleDriveService appDriveService = GoogleDriveService();

/// Definido em [HomePage] para abrir o painel Drive a partir de qualquer contexto (ex.: modais).
void Function()? openDrivePanelCallback;
