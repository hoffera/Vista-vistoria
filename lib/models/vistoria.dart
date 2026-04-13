import 'assinatura.dart';
import 'dados.dart';
import 'legenda.dart';
import 'observacao_item.dart';
import 'pessoa.dart';

// Importar TipoLegenda

class Vistoria {
  /// Nome da vistoria
  final String nome;
  /// Número da vistoria (ex: 00001)
  final String numero;
  /// Dados do cabeçalho (preenchidos pelo usuário na tela)
  final String data;
  final String vistoriador;
  final String tipo;

  final String cliente;
  final String endereco;
  final String protocolo;

  /// Coordenadas para mapa do imóvel (opcional). Se preenchidas, o mapa é exibido no PDF.
  final double? mapaLat;
  final double? mapaLng;
  final String observacoes;
  final String mobiliado;
  final String quartos;
  final String banheiros;

  /// Texto de introdução da vistoria
  final String introducao;

  /// Legenda: cada item tem valor (título), cor e texto descritivo
  final List<Legenda> legendas;
  
  /// Tipo de legenda escolhido
  final TipoLegenda? tipoLegenda;

  /// Observações: lista de itens com texto e cor (cada item pode ter cor diferente)
  final List<ObservacaoItem> itensObservacao;

  /// Observação complementar
  final String observacaoComplementar;

  /// Inconformidades: subtópicos (SALA, COZINHA...) com itens e imagens
  final List<DadosSubtopico> inconformidades;

  /// Chaves: mesma estrutura de inconformidades
  final List<DadosSubtopico> chaves;

  /// Medidores: mesma estrutura de inconformidades
  final List<DadosSubtopico> medidores;

  /// Ambientes: mesma estrutura de inconformidades
  final List<DadosSubtopico> ambientes;

  /// Assinaturas: título e subtítulo, máx 2 por linha no PDF
  final List<Assinatura> assinaturas;

  final List<Pessoa> pessoas;

  Vistoria({
    this.nome = '',
    this.numero = '00001',
    required this.data,
    required this.vistoriador,
    required this.tipo,
    required this.cliente,
    required this.endereco,
    required this.protocolo,
    this.mapaLat,
    this.mapaLng,
    required this.observacoes,
    this.mobiliado = '',
    this.quartos = '',
    this.banheiros = '',
    this.introducao = '',
    List<Legenda>? legendas,
    this.tipoLegenda,
    List<ObservacaoItem>? itensObservacao,
    this.observacaoComplementar = '',
    List<DadosSubtopico>? inconformidades,
    List<DadosSubtopico>? chaves,
    List<DadosSubtopico>? medidores,
    List<DadosSubtopico>? ambientes,
    List<Assinatura>? assinaturas,
    List<Pessoa>? pessoas,
  })  : legendas = legendas ?? [],
        itensObservacao = itensObservacao ?? [],
        inconformidades = inconformidades ?? [],
        chaves = chaves ?? [],
        medidores = medidores ?? [],
        ambientes = ambientes ?? [],
        assinaturas = assinaturas ?? [],
        pessoas = pessoas ?? [];
}
