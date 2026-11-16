import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'finance_models.dart';

/// One board's chunk of the donut and its row in the list below.
class _Slice {
  final String label;
  final int amountMinor;
  final Color color;

  const _Slice(this.label, this.amountMinor, this.color);
}

const _chartSize = 220.0;
const _stroke = 28.0;

/// How far a selected chunk slides out from the ring.
const _pull = 10.0;

/// The ring's radius, leaving room for a chunk to slide outward.
const _ringRadius = _chartSize / 2 - _stroke / 2 - _pull;

/// Shows this month's spending per board as a donut and a list.
/// Tapping a chunk or a row slides that chunk out and shows it in the centre.
class SpendingBreakdownScreen extends StatefulWidget {
  final FinanceState state;
  final DateTime month;

  const SpendingBreakdownScreen({
    super.key,
    required this.state,
    required this.month,
  });

  @override
  State<SpendingBreakdownScreen> createState() =>
      _SpendingBreakdownScreenState();
}

class _SpendingBreakdownScreenState extends State<SpendingBreakdownScreen>
    with TickerProviderStateMixin {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _defaultAccent = 0xFF147D64;

  // Boards still on the default accent colour get one of these instead,
  // so their chunks don't merge into one block. Custom colours are kept.
  static const _boardPalette = [
    Color(0xFF147D64), // green
    Color(0xFFE07A2F), // orange
    Color(0xFF7B5EA7), // purple
    Color(0xFFD64F7A), // pink
    Color(0xFFE0B03A), // amber
    Color(0xFF2F8FD6), // blue
    Color(0xFFA0522D), // brown
    Color(0xFF6B8E23), // olive
  ];

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  late final Animation<double> _sweepCurve = CurvedAnimation(
    parent: _sweep,
    curve: Curves.easeOutCubic,
  );

  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final Animation<double> _popCurve = CurvedAnimation(
    parent: _pop,
    curve: Curves.easeOutCubic,
  );

  int? _selected;
  int? _previous;

  @override
  void dispose() {
    _sweep.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _toggle(int? index) {
    final next = index == _selected ? null : index;
    if (next == _selected) return;
    setState(() {
      _previous = _selected;
      _selected = next;
    });
    _pop.forward(from: 0);
  }

  /// Which chunk, if any, sits under [position] inside the chart box.
  int? _sliceAt(Offset position, List<_Slice> slices, int total) {
    if (total <= 0) return null;
    final offset = position - const Offset(_chartSize / 2, _chartSize / 2);
    if ((offset.distance - _ringRadius).abs() > _stroke / 2 + _pull) {
      return null;
    }
    // Angle measured clockwise from 12 o'clock, like the painter.
    final angle =
        (math.atan2(offset.dy, offset.dx) + math.pi / 2) % (2 * math.pi);
    var start = 0.0;
    for (var i = 0; i < slices.length; i++) {
      final sweep = 2 * math.pi * slices[i].amountMinor / total;
      if (angle < start + sweep) return i;
      start += sweep;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final month = widget.month;
    final scheme = Theme.of(context).colorScheme;
    final currency = state.profile?.currency ?? 'INR';
    final period = periodOf(month);

    final slices = <_Slice>[
      for (final (index, board) in state.boards.indexed)
        _Slice(
          board.name,
          state.spentFor(board.id, period: period),
          board.accentColor == _defaultAccent
              ? _boardPalette[index % _boardPalette.length]
              : Color(board.accentColor),
        ),
    ].where((s) => s.amountMinor > 0).toList();
    final totalSpent = slices.fold<int>(0, (sum, s) => sum + s.amountMinor);
    String percentOf(int amount) =>
        '${(amount * 100 / totalSpent).toStringAsFixed(0)}%';

    final selected = (_selected != null && _selected! < slices.length)
        ? slices[_selected!]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Spending · ${_months[month.month - 1]} ${month.year}'),
      ),
      body: totalSpent <= 0
          ? Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'Not enough data yet. Add your income and expenses to see your financial insights.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
              children: [
                Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) => _toggle(
                      _sliceAt(details.localPosition, slices, totalSpent),
                    ),
                    child: SizedBox.square(
                      dimension: _chartSize,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_sweepCurve, _popCurve]),
                        builder: (context, child) => CustomPaint(
                          painter: _DonutPainter(
                            slices: slices,
                            total: totalSpent,
                            trackColor: scheme.surfaceContainerHighest,
                            sweep: _sweepCurve.value,
                            pop: _popCurve.value,
                            selected: _selected,
                            previous: _previous,
                          ),
                          child: child,
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Column(
                              key: ValueKey(_selected),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  selected?.label ?? 'Spent',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  Money.format(
                                    selected?.amountMinor ?? totalSpent,
                                    currency: currency,
                                  ),
                                  key: const Key('breakdown-center-amount'),
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (selected != null)
                                  Text(
                                    percentOf(selected.amountMinor),
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                for (final (index, slice) in slices.indexed)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    selected: index == _selected,
                    selectedTileColor: slice.color.withValues(alpha: 0.12),
                    selectedColor: scheme.onSurface,
                    onTap: () => _toggle(index),
                    leading: CircleAvatar(
                      radius: 6,
                      backgroundColor: slice.color,
                    ),
                    title: Text(
                      slice.label,
                      style: TextStyle(
                        fontWeight: index == _selected
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: Text(
                      '${Money.format(slice.amountMinor, currency: currency)}'
                      ' · ${percentOf(slice.amountMinor)}',
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<_Slice> slices;
  final int total;
  final Color trackColor;

  /// 0→1 as the ring sweeps in on open.
  final double sweep;

  /// 0→1 as the newly selected chunk slides out (and the old one slides back).
  final double pop;
  final int? selected;
  final int? previous;

  _DonutPainter({
    required this.slices,
    required this.total,
    required this.trackColor,
    required this.sweep,
    required this.pop,
    required this.selected,
    required this.previous,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: _ringRadius,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = trackColor);
    if (total <= 0) return;
    final limit = 2 * math.pi * sweep;
    var start = 0.0;
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      final full = 2 * math.pi * slice.amountMinor / total;
      final visible = math.min(full, limit - start);
      if (visible <= 0) break;
      // Slide along the chunk's middle angle, away from the centre.
      final out = _pull *
          ((i == selected ? pop : 0.0) + (i == previous ? 1 - pop : 0.0));
      final middle = start + full / 2 - math.pi / 2;
      final shift = Offset(math.cos(middle), math.sin(middle)) * out;
      final dimmed = selected != null && i != selected;
      canvas.drawArc(
        rect.shift(shift),
        start - math.pi / 2,
        visible,
        false,
        paint
          ..color = dimmed ? slice.color.withValues(alpha: 0.35) : slice.color,
      );
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.slices != slices ||
      old.total != total ||
      old.trackColor != trackColor ||
      old.sweep != sweep ||
      old.pop != pop ||
      old.selected != selected ||
      old.previous != previous;
}
