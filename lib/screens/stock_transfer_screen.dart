import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';
import 'stock_transfers_list_screen.dart';

/// Prefer full unit name; fall back to short code only if name is missing.
String _itemUnitDisplay(Item? e) {
  if (e == null) return '';
  final name = (e.unit ?? '').trim();
  if (name.isNotEmpty) return name;
  return (e.unitShort ?? '').trim();
}

class _DestinationLeg {
  _DestinationLeg()
      : toQty = TextEditingController(),
        toSelling = TextEditingController(),
        toCost = TextEditingController();

  Item? toItem;
  final TextEditingController toQty;
  final TextEditingController toSelling;
  final TextEditingController toCost;

  void dispose() {
    toQty.dispose();
    toSelling.dispose();
    toCost.dispose();
  }
}

class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({super.key, this.initialFromItemId});

  final int? initialFromItemId;

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;
  final _notesController = TextEditingController();
  final _totalSourceQtyController = TextEditingController();
  final _fromUnitCostController = TextEditingController();

  List<Item> _items = [];
  Item? _fromItem;
  final List<_DestinationLeg> _legs = [];

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final leg in _legs) {
      leg.dispose();
    }
    _notesController.dispose();
    _totalSourceQtyController.dispose();
    _fromUnitCostController.dispose();
    super.dispose();
  }

  String _saleCategory(Item item) {
    final raw = (item.category ?? '').toLowerCase();
    if (raw.contains('sale: wholesale')) return 'wholesale';
    if (raw.contains('sale: retail')) return 'retail';
    return '';
  }

  bool _isWholesale(Item item) => _saleCategory(item) == 'wholesale';

  /// Any item except the source; wholesale sources still limited to wholesale/retail lines.
  List<Item> _destinationCandidatesFor(Item from, List<Item> items) {
    final fromIsWholesale = _isWholesale(from);
    return items.where((e) {
      if (e.id == from.id) return false;
      if (!fromIsWholesale) return true;
      final destSale = _saleCategory(e);
      return destSale == 'wholesale' || destSale == 'retail';
    }).toList();
  }

  List<Item> get _toCandidates {
    final from = _fromItem;
    if (from == null) return const [];
    return _destinationCandidatesFor(from, _items);
  }

  Set<int> _usedToItemIdsExceptLeg(int legIndex) {
    final used = <int>{};
    for (var i = 0; i < _legs.length; i++) {
      if (i == legIndex) continue;
      final id = _legs[i].toItem?.id;
      if (id != null) used.add(id);
    }
    return used;
  }

  List<Item> _candidatesForLeg(int legIndex) {
    final all = _toCandidates;
    final used = _usedToItemIdsExceptLeg(legIndex);
    return all.where((e) => e.id == null || !used.contains(e.id)).toList();
  }

  double _parseTotalSourceQty() =>
      double.tryParse(_totalSourceQtyController.text.replaceAll(',', '.')) ??
      0;

  double _fromQtyForLeg() {
    final total = _parseTotalSourceQty();
    if (_legs.length <= 1) return total;
    return total / _legs.length;
  }

  double _fromUnitCostForCalc() {
    final parsed =
        double.tryParse(_fromUnitCostController.text.replaceAll(',', '.')) ??
            0;
    if (parsed > 0) return parsed;
    return _fromItem?.costPrice ?? 0;
  }

  void _syncFromUnitCostField() {
    final from = _fromItem;
    if (from == null) return;
    final c = from.costPrice;
    if (c > 0) {
      _fromUnitCostController.text = formatDisplayNumber(
        c,
        fractionDigits: 6,
        fixedDecimals: false,
      );
    } else {
      _fromUnitCostController.clear();
    }
  }

  void _recomputeLegCost(_DestinationLeg leg) {
    final toItem = leg.toItem;
    final destUnitCost = toItem?.costPrice ?? 0;
    if (toItem != null && destUnitCost > 0) {
      leg.toCost.text = formatDisplayNumber(
        destUnitCost,
        fractionDigits: 6,
        fixedDecimals: false,
      );
      return;
    }

    final from = _fromItem;
    final fromQty = _fromQtyForLeg();
    final toQty = double.tryParse(leg.toQty.text.replaceAll(',', '.')) ?? 0;
    final fromUnitCost = _fromUnitCostForCalc();
    if (from == null || fromQty <= 0 || toQty <= 0) {
      leg.toCost.text = '';
      return;
    }
    final ratio = toQty / fromQty;
    if (ratio <= 0) {
      leg.toCost.text = '';
      return;
    }
    if (fromUnitCost <= 0) {
      leg.toCost.text = '';
      return;
    }
    final toCost = fromUnitCost / ratio;
    leg.toCost.text = formatDisplayNumber(
      toCost,
      fractionDigits: 6,
      fixedDecimals: false,
    );
  }

  void _prefillLegSellingFromToItem(_DestinationLeg leg) {
    final to = leg.toItem;
    if (to == null) {
      leg.toSelling.clear();
      return;
    }
    final sp = to.sellingPrice;
    if (sp > 0) {
      leg.toSelling.text = formatDisplayNumber(
        sp,
        fractionDigits: 6,
        fixedDecimals: false,
      );
    } else {
      leg.toSelling.clear();
    }
  }

  void _recomputeAllLegCosts() {
    for (var i = 0; i < _legs.length; i++) {
      _recomputeLegCost(_legs[i]);
      _prefillLegSellingFromToItem(_legs[i]);
    }
  }

  void _syncLegsAfterFromItemChange() {
    final candidates = _toCandidates;
    if (candidates.isEmpty) {
      for (final leg in _legs) {
        leg.toItem = null;
        leg.toSelling.clear();
      }
      _recomputeAllLegCosts();
      return;
    }
    final used = <int>{};
    for (final leg in _legs) {
      final current = leg.toItem;
      if (current != null &&
          current.id != null &&
          candidates.any((c) => c.id == current.id)) {
        used.add(current.id!);
        continue;
      }
      leg.toItem = null;
      leg.toSelling.clear();
    }
    for (final leg in _legs) {
      if (leg.toItem != null) continue;
      Item? pick;
      for (final c in candidates) {
        if (c.id != null && !used.contains(c.id!)) {
          pick = c;
          break;
        }
      }
      if (pick != null) {
        leg.toItem = pick;
        used.add(pick.id!);
      }
    }
    _recomputeAllLegCosts();
  }

  void _addLeg() {
    final leg = _DestinationLeg();
    final candidates = _candidatesForLeg(_legs.length);
    if (candidates.isNotEmpty) {
      final used = _usedToItemIdsExceptLeg(_legs.length);
      Item? pick;
      for (final c in candidates) {
        if (c.id != null && !used.contains(c.id!)) {
          pick = c;
          break;
        }
      }
      leg.toItem = pick;
    }
    setState(() {
      _legs.insert(0, leg);
    });
    _recomputeAllLegCosts();
  }

  void _removeLeg(int index) {
    if (_legs.length <= 1) return;
    setState(() {
      _legs[index].dispose();
      _legs.removeAt(index);
    });
    _recomputeAllLegCosts();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final isRemote = await _auth.isRemoteUser();
    final List<Item> items;
    if (isRemote) {
      items = await RemoteSyncService.instance.fetchItems();
    } else {
      await RemoteSyncService.instance.syncItems();
      items = await _db.getItems();
    }
    if (!mounted) return;
    Item? from = _fromItem;
    if (items.isNotEmpty && from == null) {
      from = widget.initialFromItemId == null
          ? items.first
          : items.firstWhere(
              (e) => e.id == widget.initialFromItemId,
              orElse: () => items.first,
            );
    }
    if (_legs.isEmpty) {
      _legs.add(_DestinationLeg());
    }
    setState(() {
      _items = items;
      _fromItem = from;
      _loading = false;
    });
    _syncLegsAfterFromItemChange();
    _syncFromUnitCostField();
    if (mounted) setState(() {});
  }

  double _totalTransferValueHint() {
    var sum = 0.0;
    for (final leg in _legs) {
      final toQty = double.tryParse(leg.toQty.text.replaceAll(',', '.')) ?? 0;
      sum += toQty * (leg.toItem?.sellingPrice ?? 0);
    }
    return sum;
  }

  Future<void> _save() async {
    final from = _fromItem;
    if (from == null || from.id == null) return;
    if (_legs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one destination')),
      );
      return;
    }

    final toCandidates = _toCandidates;
    if (toCandidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No other items to transfer into. Add another inventory line first.',
          ),
        ),
      );
      return;
    }

    final fromUnitCostEntered =
        double.tryParse(_fromUnitCostController.text.replaceAll(',', '.')) ??
            0;
    if (fromUnitCostEntered <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid source unit cost')),
      );
      return;
    }

    final seenTo = <int>{};
    for (var i = 0; i < _legs.length; i++) {
      final leg = _legs[i];
      final to = leg.toItem;
      final label = 'Destination ${i + 1}';
      if (to == null || to.id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: select a destination item')),
        );
        return;
      }
      if (to.id == from.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: source and destination must differ')),
        );
        return;
      }
      if (seenTo.contains(to.id!)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$label: each destination must be a different item in one batch.',
            ),
          ),
        );
        return;
      }
      seenTo.add(to.id!);

      final fromQty = _fromQtyForLeg();
      final toQty = double.tryParse(leg.toQty.text.replaceAll(',', '.')) ?? 0;
      if (fromQty <= 0 || toQty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$label: enter valid source and destination quantities',
            ),
          ),
        );
        return;
      }

      final toCostPrice =
          double.tryParse(leg.toCost.text.replaceAll(',', '.')) ?? 0;
      final toSellingPrice =
          double.tryParse(leg.toSelling.text.replaceAll(',', '.')) ?? 0;
      if (toCostPrice <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$label: enter a valid destination cost price',
            ),
          ),
        );
        return;
      }
      if (toSellingPrice <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label: enter a valid selling price')),
        );
        return;
      }
      if (toSellingPrice <= toCostPrice) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$label: selling price must be greater than cost price',
            ),
          ),
        );
        return;
      }
    }

    final totalSourceQty = _parseTotalSourceQty();
    if (totalSourceQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid source quantity to transfer'),
        ),
      );
      return;
    }
    if (totalSourceQty > from.stockQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Source quantity (${formatDisplayNumber(totalSourceQty)}) exceeds '
            'available stock (${formatDisplayNumber(from.stockQty)}).',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final isRemote = await _auth.isRemoteUser();
      for (var i = 0; i < _legs.length; i++) {
        final leg = _legs[i];
        final to = leg.toItem!;
        final fromQty = _fromQtyForLeg();
        final toQty = double.tryParse(leg.toQty.text.replaceAll(',', '.')) ?? 0;
        final factor = toQty / fromQty;
        final toCostPrice =
            double.tryParse(leg.toCost.text.replaceAll(',', '.')) ?? 0;
        final toSellingPrice =
            double.tryParse(leg.toSelling.text.replaceAll(',', '.')) ?? 0;

        Item currentFrom = from;
        if (!isRemote) {
          final refreshed = await _db.getItems();
          for (final e in refreshed) {
            if (e.id == from.id) {
              currentFrom = e;
              break;
            }
          }
        }

        if (currentFrom.stockQty < fromQty) {
          throw StateError(
            'Destination ${i + 1}: not enough source stock after previous '
            'transfers. Available: ${formatDisplayNumber(currentFrom.stockQty)}',
          );
        }

        if (isRemote) {
          final remote = await _auth.saveRemoteStockTransfer({
            'fromItemId': currentFrom.id,
            'toItemId': to.id,
            'fromQuantity': fromQty,
            'conversionFactor': factor,
            'toCostPrice': toCostPrice > 0 ? toCostPrice : null,
            'fromCostPrice': fromUnitCostEntered,
            'toSellingPrice': toSellingPrice,
            'storeId': currentFrom.storeId ?? to.storeId,
            'notes': _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          });
          if (remote['success'] != true) {
            throw Exception(
              (remote['message'] ?? 'Failed to sync transfer').toString(),
            );
          }
        } else {
          await _db.transferStock(
            fromItemId: currentFrom.id!,
            toItemId: to.id!,
            fromQuantity: fromQty,
            conversionFactor: factor,
            toCostPrice: toCostPrice > 0 ? toCostPrice : null,
            toSellingPrice: toSellingPrice,
            fromCostPrice: fromUnitCostEntered,
            storeId: currentFrom.storeId ?? to.storeId,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _legs.length == 1
                ? 'Transfer completed'
                : '${_legs.length} transfers completed',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Transfer failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = _settings.currencySymbol;
    final toCandidates = _toCandidates;

    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Transfer stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'All transfers',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const StockTransfersListScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.length < 2
              ? Center(
                  child: Text(
                    'Add at least two items to transfer stock.',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Source',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Item>(
                      initialValue: _fromItem,
                      decoration: const InputDecoration(
                        labelText: 'From item (source)',
                      ),
                      isExpanded: true,
                      items: _items
                          .map(
                            (e) => DropdownMenuItem<Item>(
                              value: e,
                              child: Text(
                                '${toTitleCaseWords(e.name)}  •  AV ${formatDisplayNumber(e.stockQty)} ${_itemUnitDisplay(e)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _fromItem = value;
                        });
                        _syncLegsAfterFromItemChange();
                        _syncFromUnitCostField();
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'All destinations below use this same source item.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fromUnitCostController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'From item unit cost',
                        prefixText: '$currency ',
                        helperText: 'Prefilled from the item; edit if needed.',
                      ),
                      onChanged: (_) => setState(_recomputeAllLegCosts),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _totalSourceQtyController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: _legs.length > 1
                            ? 'Total source quantity to transfer'
                            : 'Source quantity to transfer',
                        hintText: 'e.g 1 set, 1 carton, 1 bag',
                        helperText: _legs.length > 1
                            ? 'Split equally across ${_legs.length} destinations.'
                            : 'How much to move out of the source item.',
                      ),
                      onChanged: (_) {
                        setState(_recomputeAllLegCosts);
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Destinations',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor:
                                theme.colorScheme.primaryContainer,
                            foregroundColor:
                                theme.colorScheme.onPrimaryContainer,
                          ),
                          onPressed: toCandidates.isEmpty ? null : _addLeg,
                          icon: const Icon(Icons.add),
                          tooltip: 'Add another destination',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Several destinations each receive an equal share of the total above.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (toCandidates.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'No other item available to transfer into. Add another item first.',
                        ),
                      )
                    else
                      ...List.generate(_legs.length, (index) {
                        final leg = _legs[index];
                        final candidates = _candidatesForLeg(index);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          clipBehavior: Clip.antiAlias,
                          key: ObjectKey(leg),
                          child: ExpansionTile(
                            initiallyExpanded: index == 0,
                            expandedCrossAxisAlignment: CrossAxisAlignment.start,
                            title: Text(
                              'Destination ${index + 1}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: leg.toItem == null
                                ? null
                                : Text(
                                    toTitleCaseWords(leg.toItem!.name),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_legs.length > 1)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          onPressed: () => _removeLeg(index),
                                          icon: Icon(
                                            Icons.delete_outline,
                                            size: 20,
                                            color: theme.colorScheme.error,
                                          ),
                                          label: Text(
                                            'Remove destination',
                                            style: TextStyle(
                                              color: theme.colorScheme.error,
                                            ),
                                          ),
                                        ),
                                      ),
                                    DropdownButtonFormField<Item>(
                                      key: ValueKey(
                                        'to_${index}_${leg.toItem?.id}',
                                      ),
                                      initialValue: leg.toItem != null &&
                                              candidates.any(
                                                (c) => c.id == leg.toItem!.id,
                                              )
                                          ? leg.toItem
                                          : null,
                                      decoration: const InputDecoration(
                                        labelText: 'To item (destination)',
                                        contentPadding: EdgeInsets.only(
                                          top: 8,
                                          bottom: 4,
                                        ),
                                      ),
                                      isExpanded: true,
                                      items: candidates
                                          .map(
                                            (e) => DropdownMenuItem<Item>(
                                              value: e,
                                              child: Text(
                                                '${toTitleCaseWords(e.name)}  •  AV ${formatDisplayNumber(e.stockQty)} ${_itemUnitDisplay(e)}',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          leg.toItem = value;
                                        });
                                        _recomputeLegCost(leg);
                                        _prefillLegSellingFromToItem(leg);
                                        setState(() {});
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: leg.toQty,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Destination quantity to add',
                                        hintText:
                                            'e.g 12 for 1 carton, 24 for 2 cartons',
                                      ),
                                      onChanged: (_) {
                                        setState(() {
                                          _recomputeLegCost(leg);
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Destination increase: ${formatDisplayNumber(double.tryParse(leg.toQty.text.replaceAll(',', '.')) ?? 0)} ${_itemUnitDisplay(leg.toItem)}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: leg.toCost,
                                      enabled: leg.toItem != null,
                                      keyboardType: const TextInputType
                                          .numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        labelText: 'To item cost price',
                                        helperText: leg.toItem == null
                                            ? 'Choose a destination item first'
                                            : (leg.toItem!.costPrice > 0
                                                ? 'Prefilled from this item\'s saved cost; edit if needed.'
                                                : 'No saved cost — filled from source math; edit if needed.'),
                                        prefixText: '$currency ',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: leg.toSelling,
                                      enabled: leg.toItem != null,
                                      keyboardType: const TextInputType
                                          .numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        labelText: 'To item selling price',
                                        helperText: leg.toItem == null
                                            ? 'Choose a destination item first'
                                            : (leg.toItem!.sellingPrice > 0
                                                ? 'Prefilled from this item\'s saved price; edit if needed.'
                                                : 'No saved price on item — enter a selling price.'),
                                        prefixText: '$currency ',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        hintText: 'e.g 1 carton Coca Cola = 12 bottles',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Transfer value reference: $currency${formatMoney(_totalTransferValueHint())}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _saving || toCandidates.isEmpty ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.swap_horiz),
                        label: Text(
                          _saving
                              ? 'Transferring...'
                              : _legs.length > 1
                                  ? 'Complete ${_legs.length} transfers'
                                  : 'Complete transfer',
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
