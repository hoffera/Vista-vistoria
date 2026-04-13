import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// Cores predefinidas para a legenda
const List<Color> coresLegendaPredefinidas = [
  Colors.green,
  Colors.blue,
  Colors.yellow,
  Colors.grey,
  Colors.red,
];

/// Widget isolado para seleção de cor da legenda.
/// Mantém a cor em estado próprio para evitar rebuild do formulário inteiro.
class SeletorCoresLegenda extends StatefulWidget {
  final Color corInicial;
  final ValueChanged<Color> onCorChanged;

  const SeletorCoresLegenda({
    super.key,
    required this.corInicial,
    required this.onCorChanged,
  });

  @override
  State<SeletorCoresLegenda> createState() => _SeletorCoresLegendaState();
}

class _SeletorCoresLegendaState extends State<SeletorCoresLegenda> {
  late Color _cor;

  @override
  void initState() {
    super.initState();
    _cor = widget.corInicial;
  }

  @override
  void didUpdateWidget(SeletorCoresLegenda oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.corInicial != oldWidget.corInicial) {
      _cor = widget.corInicial;
    }
  }

  void _aplicarCor(Color c) {
    setState(() => _cor = c);
    widget.onCorChanged(c);
  }
  bool _corEhPredefinida(Color c) =>
      coresLegendaPredefinidas.any((predef) => predef == c);

  Color _contrasteCor(Color cor) {
    final l = cor.computeLuminance();
    return l > 0.5 ? Colors.black : Colors.white;
  }

  void _mostrarColorPicker() {
    Color pickerColor = _cor;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Escolher cor'),
          content: BlockPicker(
            pickerColor: pickerColor,
            onColorChanged: (c) {
              pickerColor = c;
              setDialogState(() {});
            },
            availableColors: [
              ...coresLegendaPredefinidas,
              Colors.black,
              Colors.grey,
              Colors.teal,
              Colors.pink,
              Colors.amber,
              Colors.indigo,
              Colors.cyan,
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                _aplicarCor(pickerColor);
                Navigator.pop(context);
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...coresLegendaPredefinidas.map((c) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _aplicarCor(c),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _cor == c ? Colors.black : Colors.grey,
                      width: _cor == c ? 3 : 1,
                    ),
                  ),
                ),
              ),
            )),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: _mostrarColorPicker,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _corEhPredefinida(_cor) ? Colors.grey[200] : _cor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: !_corEhPredefinida(_cor) ? Colors.black : Colors.grey,
                  width: !_corEhPredefinida(_cor) ? 3 : 1,
                ),
              ),
              child: Icon(
                Icons.palette_outlined,
                size: 16,
                color: _corEhPredefinida(_cor)
                    ? Colors.grey[600]
                    : _contrasteCor(_cor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
