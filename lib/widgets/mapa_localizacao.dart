import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:latlong2/latlong.dart';

import '../services/geocoding_service.dart';

/// Botão que abre um modal para definir a localização do imóvel no mapa.
/// No modal: digite o endereço, busque e arraste o marcador para ajustar.
class MapaLocalizacao extends StatelessWidget {
  final TextEditingController enderecoController;
  final double? lat;
  final double? lng;
  final void Function(double lat, double lng)? onLatLngChanged;

  const MapaLocalizacao({
    super.key,
    required this.enderecoController,
    this.lat,
    this.lng,
    this.onLatLngChanged,
  });

  Future<void> _abrirModal(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ModalMapaLocalizacao(
        enderecoInicial: enderecoController.text,
        latInicial: lat,
        lngInicial: lng,
        onConfirmar: (lat, lng, endereco) {
          onLatLngChanged?.call(lat, lng);
          // Não altera o campo de endereço - são coisas diferentes
          Navigator.of(ctx).pop();
        },
        onCancelar: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final temLocalizacao = lat != null && lng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Localização no mapa',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000080),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _abrirModal(context),
          icon: Icon(temLocalizacao ? Icons.edit_location_alt : Icons.add_location_alt, size: 20),
          label: Text(
            temLocalizacao
                ? 'Alterar localização no mapa'
                : 'Definir localização no mapa',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF000080),
            side: const BorderSide(color: Color(0xFF00C896)),
          ),
        ),
        if (temLocalizacao)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Lat: ${lat!.toStringAsFixed(6)}, Lng: ${lng!.toStringAsFixed(6)}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ),
      ],
    );
  }
}

class _ModalMapaLocalizacao extends StatefulWidget {
  final String enderecoInicial;
  final double? latInicial;
  final double? lngInicial;
  final void Function(double lat, double lng, String? endereco) onConfirmar;
  final VoidCallback onCancelar;

  const _ModalMapaLocalizacao({
    required this.enderecoInicial,
    this.latInicial,
    this.lngInicial,
    required this.onConfirmar,
    required this.onCancelar,
  });

  @override
  State<_ModalMapaLocalizacao> createState() => _ModalMapaLocalizacaoState();
}

class _ModalMapaLocalizacaoState extends State<_ModalMapaLocalizacao> {
  late final TextEditingController _enderecoController;
  final _focusNode = FocusNode();
  late LatLng _markerPoint;
  final _mapController = MapController();
  bool _isBuscarLoading = false;
  String? _buscarError;

  static const _defaultCenter = LatLng(-26.9908, -48.6359); // Balneário Camboriú

  @override
  void initState() {
    super.initState();
    // Campo de busca inicia vazio - é apenas para buscar localizações no mapa
    _enderecoController = TextEditingController();
    _markerPoint = widget.latInicial != null && widget.lngInicial != null
        ? LatLng(widget.latInicial!, widget.lngInicial!)
        : _defaultCenter;
  }

  @override
  void dispose() {
    _enderecoController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _aoSelecionarSugestao(SugestaoLocalizacao s) {
    setState(() => _markerPoint = LatLng(s.lat, s.lng));
    _mapController.move(_markerPoint, 17);
  }

  Future<void> _buscarEndereco() async {
    final endereco = _enderecoController.text.trim();
    if (endereco.isEmpty) {
      setState(() => _buscarError = 'Digite o endereço antes de buscar.');
      return;
    }
    setState(() {
      _isBuscarLoading = true;
      _buscarError = null;
    });
    try {
      final coords = await GeocodingService.buscarCoordenadas(endereco);
      if (!mounted) return;
      
      if (coords == null) {
        setState(() {
          _isBuscarLoading = false;
          _buscarError = 'Não foi possível localizar o endereço. Verifique sua conexão com a internet e tente novamente.';
        });
        return;
      }
      setState(() {
        _markerPoint = LatLng(coords.lat, coords.lng);
        _isBuscarLoading = false;
        _buscarError = null;
      });
      _mapController.move(_markerPoint, 17);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBuscarLoading = false;
          _buscarError = 'Erro ao buscar localização: ${e.toString()}';
        });
      }
    }
  }

  void _onMarkerDragUpdate(LatLng latLng) {
    _markerPoint = latLng;
    setState(() {});
  }

  void _confirmar() {
    widget.onConfirmar(
      _markerPoint.latitude,
      _markerPoint.longitude,
      null, // Não passa endereço - o campo de busca é apenas para localizar no mapa
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, color: Color(0xFF00C896), size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Definir localização do imóvel',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF000080),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onCancelar,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              RawAutocomplete<SugestaoLocalizacao>(
                textEditingController: _enderecoController,
                focusNode: _focusNode,
                displayStringForOption: (s) => s.displayName,
                optionsBuilder: (value) async {
                  final texto = value.text.trim();
                  if (texto.length < 2) return const Iterable<SugestaoLocalizacao>.empty();
                  return GeocodingService.buscarSugestoes(
                    texto,
                    latBias: _markerPoint.latitude,
                    lonBias: _markerPoint.longitude,
                  );
                },
                onSelected: _aoSelecionarSugestao,
                fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Endereço',
                      hintText: 'Digite e veja sugestões...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280, maxWidth: 560),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final s = options.elementAt(index);
                            return InkWell(
                              onTap: () => onSelected(s),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00C896).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.place, color: Color(0xFF00C896), size: 22),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        s.displayName,
                                        style: const TextStyle(fontSize: 14, height: 1.3),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isBuscarLoading ? null : _buscarEndereco,
                    icon: _isBuscarLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search, size: 18),
                    label: Text(_isBuscarLoading ? 'Buscando...' : 'Buscar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF000080),
                      side: const BorderSide(color: Color(0xFF00C896)),
                    ),
                  ),
                ],
              ),
              if (_buscarError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _buscarError!,
                  style: TextStyle(fontSize: 12, color: Colors.red[700]),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Arraste o marcador vermelho para ajustar a posição exata.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      color: Colors.grey.shade100,
                    ),
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _markerPoint,
                        initialZoom: 17,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.vistoria_pdf',
                        ),
                        DragMarkers(
                          markers: [
                            DragMarker(
                              point: _markerPoint,
                              size: const Size(48, 48),
                              offset: const Offset(0, -32),
                              builder: (context, latLng, isDragging) => const Icon(
                                Icons.location_on,
                                size: 48,
                                color: Colors.red,
                              ),
                              onDragUpdate: (_, latLng) {
                                setState(() => _onMarkerDragUpdate(latLng));
                              },
                              scrollMapNearEdge: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onCancelar,
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _confirmar,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Confirmar localização'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00C896),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
