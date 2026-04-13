import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../app/globals.dart';
import '../services/google_drive_service.dart';
import 'drive_file_drag_data.dart';

class _FolderCrumb {
  const _FolderCrumb({required this.id, required this.name});

  final String id;
  final String name;
}

/// Painel lateral (estilo Canva): pastas, miniaturas e arrastar imagens para a secção.
/// Mantém estado enquanto estiver na árvore (use [Offstage] para esconder sem descartar).
class DriveImagePanel extends StatefulWidget {
  const DriveImagePanel({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  State<DriveImagePanel> createState() => _DriveImagePanelState();
}

class _DriveImagePanelState extends State<DriveImagePanel> {
  static const _folderMime = 'application/vnd.google-apps.folder';

  final List<_FolderCrumb> _stack = [
    const _FolderCrumb(id: kGoogleDriveRootId, name: 'Meu Drive'),
  ];

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<drive.File> _items = [];
  String? _nextPageToken;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  final ScrollController _scrollController = ScrollController();

  _FolderCrumb get _current => _stack.last;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset, String? pageToken}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _nextPageToken = null;
        if (pageToken == null) _items = [];
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final q = _searchController.text.trim();
      final result = await appDriveService.listFolderContents(
        _current.id,
        pageToken: pageToken,
        pageSize: 50,
        nameContains: q.isEmpty ? null : q,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _error = 'Não foi possível aceder ao Google Drive.';
          _loading = false;
          _loadingMore = false;
        });
        return;
      }
      setState(() {
        if (reset && pageToken == null) {
          _items = List<drive.File>.from(result.files);
        } else {
          _items = [..._items, ...result.files];
        }
        _nextPageToken = result.nextPageToken;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _openFolder(drive.File f) {
    final id = f.id;
    if (id == null) return;
    setState(() {
      _stack.add(_FolderCrumb(id: id, name: f.name ?? 'Pasta'));
    });
    _load(reset: true);
  }

  void _goBack() {
    if (_stack.length <= 1) {
      widget.onClose();
      return;
    }
    setState(() {
      _stack.removeLast();
    });
    _load(reset: true);
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _load(reset: true);
    });
  }

  bool _isFolder(drive.File f) => f.mimeType == _folderMime;

  List<drive.File> get _folders =>
      _items.where((f) => _isFolder(f) && f.id != null).toList();

  List<drive.File> get _images =>
      _items.where((f) => !_isFolder(f)).toList();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _goBack,
                  tooltip: _stack.length > 1 ? 'Pasta anterior' : 'Fechar painel',
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Google Drive',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        _stack.map((c) => c.name).join(' › '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                  tooltip: 'Fechar',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Pesquisar em ${_current.name}…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _load(reset: true);
                        },
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Arraste as imagens para a secção de dados',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              ),
            )
          else if (_items.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Nenhuma pasta ou imagem nesta localização.'),
              ),
            )
          else
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  if (_folders.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Pastas',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.95,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final f = _folders[index];
                            return InkWell(
                              onTap: () => _openFolder(f),
                              borderRadius: BorderRadius.circular(8),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.amber.shade50,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.folder,
                                      size: 36,
                                      color: Colors.amber[800],
                                    ),
                                    const SizedBox(height: 6),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      child: Text(
                                        f.name ?? f.id ?? '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: _folders.length,
                        ),
                      ),
                    ),
                  ],
                  if (_images.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Imagens',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.85,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final f = _images[index];
                            final id = f.id ?? '';
                            return _DraggableDriveThumb(
                              file: f,
                              name: f.name ?? id,
                            );
                          },
                          childCount: _images.length,
                        ),
                      ),
                    ),
                  ],
                  if (_nextPageToken != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Center(
                          child: _loadingMore
                              ? const CircularProgressIndicator()
                              : OutlinedButton(
                                  onPressed: () => _load(
                                    reset: false,
                                    pageToken: _nextPageToken,
                                  ),
                                  child: const Text('Carregar mais'),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DraggableDriveThumb extends StatelessWidget {
  const _DraggableDriveThumb({
    required this.file,
    required this.name,
  });

  final drive.File file;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Draggable<DriveFileDragData>(
      data: DriveFileDragData(file),
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 96,
          height: 96,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _DrivePickerThumb(file: file),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _cell(),
      ),
      child: _cell(),
    );
  }

  Widget _cell() {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              child: _DrivePickerThumb(file: file),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}

/// Miniatura com OAuth: [Image.network] no web não envia token.
class _DrivePickerThumb extends StatelessWidget {
  const _DrivePickerThumb({super.key, required this.file});

  final drive.File file;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: appDriveService.thumbnailBytesForPicker(file),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: Color(0xFFE8E8E8),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _iconFallback(file),
          );
        }
        return _iconFallback(file);
      },
    );
  }

  Widget _iconFallback(drive.File f) {
    final icon = f.iconLink;
    if (icon != null && icon.isNotEmpty) {
      return Image.network(
        icon,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _greyPlaceholder(),
      );
    }
    return _greyPlaceholder();
  }

  Widget _greyPlaceholder() {
    return const ColoredBox(
      color: Color(0xFFE0E0E0),
      child: Icon(Icons.image, color: Colors.black45, size: 28),
    );
  }
}
