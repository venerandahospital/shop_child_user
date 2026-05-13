import '../models/item.dart';

/// One fuzzy match: catalog item + score.
class ItemSearchResult {
  final Item item;
  final double score;

  ItemSearchResult({required this.item, required this.score});
}

/// In-memory fuzzy search over [Item] rows (name, codes, category, units, alias barcodes).
class ItemFuzzySearch {
  ItemFuzzySearch._(this._entries);

  factory ItemFuzzySearch.fromItems(
    List<Item> items,
    Map<int, List<String>> barcodeAliases,
  ) {
    final entries = <_ItemSearchEntry>[];
    for (final item in items) {
      final aliases = barcodeAliases[item.id ?? -1] ?? const <String>[];
      entries.add(_ItemSearchEntry(item, _buildSearchText(item, aliases)));
    }
    return ItemFuzzySearch._(entries);
  }

  final List<_ItemSearchEntry> _entries;

  static String _buildSearchText(Item item, List<String> extraBarcodes) {
    final parts = <String>[
      item.name,
      item.sku ?? '',
      item.barcode ?? '',
      item.category ?? '',
      item.unit ?? '',
      item.unitShort ?? '',
      item.variantGroup ?? '',
      ...extraBarcodes,
    ];
    return parts.where((s) => s.trim().isNotEmpty).join(' ').toLowerCase();
  }

  List<ItemSearchResult> search(
    String query, {
    int limit = 8,
    double threshold = 0.2,
  }) {
    if (query.trim().isEmpty) return [];

    final queryTokens = _tokenize(query.toLowerCase());
    if (queryTokens.isEmpty) return [];

    final results = <ItemSearchResult>[];

    for (final entry in _entries) {
      final score = _score(queryTokens, entry.searchText);
      if (score >= threshold) {
        results.add(ItemSearchResult(item: entry.item, score: score));
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(limit).toList();
  }

  double _score(List<String> queryTokens, String searchText) {
    final productTokens = _tokenize(searchText);

    double totalScore = 0.0;

    for (final qToken in queryTokens) {
      double best = 0.0;

      for (final pToken in productTokens) {
        if (qToken == pToken) {
          best = 1.0;
          break;
        }

        if (pToken.startsWith(qToken) && qToken.length >= 2) {
          best = best < 0.85 ? 0.85 : best;
          continue;
        }

        if (pToken.contains(qToken) && qToken.length >= 3) {
          best = best < 0.70 ? 0.70 : best;
          continue;
        }

        final trigramScore = _trigramSimilarity(qToken, pToken);
        if (trigramScore > best) {
          best = trigramScore * 0.65;
        }
      }

      totalScore += best;
    }

    return totalScore / queryTokens.length;
  }

  double _trigramSimilarity(String a, String b) {
    if (a.length < 2 || b.length < 2) {
      return _shortStringSimilarity(a, b);
    }

    final trigramsA = _trigrams(a);
    final trigramsB = _trigrams(b);

    if (trigramsA.isEmpty || trigramsB.isEmpty) return 0.0;

    var intersection = 0;
    for (final t in trigramsA) {
      if (trigramsB.contains(t)) intersection++;
    }

    return (2 * intersection) / (trigramsA.length + trigramsB.length);
  }

  Set<String> _trigrams(String s) {
    final padded = ' $s ';
    final result = <String>{};
    for (var i = 0; i < padded.length - 2; i++) {
      result.add(padded.substring(i, i + 3));
    }
    return result;
  }

  double _shortStringSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    var matches = 0;
    for (final char in a.split('')) {
      if (b.contains(char)) matches++;
    }
    return matches / (a.length > b.length ? a.length : b.length);
  }

  List<String> _tokenize(String text) {
    const stopwords = {
      'the', 'a', 'an', 'and', 'or', 'of', 'in', 'for', 'to', 'with',
      'is', 'it', 'on', 'at', 'by', 'from', 'this', 'that',
    };

    return text
        .toLowerCase()
        .split(RegExp(r'[\s\-_/,\.]+'))
        .where((t) => t.length >= 2)
        .where((t) => !stopwords.contains(t))
        .toList();
  }
}

class _ItemSearchEntry {
  _ItemSearchEntry(this.item, this.searchText);

  final Item item;
  final String searchText;
}
