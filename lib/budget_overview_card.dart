import 'package:flutter/material.dart';

enum _BudgetPeriod { monthly, yearly }

enum _BudgetChartType { donut, bars }

class BudgetOverviewCard extends StatefulWidget {
  const BudgetOverviewCard({
    required this.monthlyBudgetInPaise,
    required this.yearlyBudgetInPaise,
    required this.monthlySpentInPaise,
    required this.yearlySpentInPaise,
    required this.formatCurrency,
    super.key,
  });

  final int monthlyBudgetInPaise;
  final int yearlyBudgetInPaise;
  final int monthlySpentInPaise;
  final int yearlySpentInPaise;
  final String Function(int amountInPaise) formatCurrency;

  @override
  State<BudgetOverviewCard> createState() => _BudgetOverviewCardState();
}

class _BudgetOverviewCardState extends State<BudgetOverviewCard> {
  _BudgetPeriod _budgetPeriod = _BudgetPeriod.monthly;
  _BudgetChartType _budgetChartType = _BudgetChartType.donut;

  @override
  Widget build(BuildContext context) {
    final budgetInPaise = _budgetPeriod == _BudgetPeriod.monthly
        ? widget.monthlyBudgetInPaise
        : widget.yearlyBudgetInPaise;
    final spentInPaise = _budgetPeriod == _BudgetPeriod.monthly
        ? widget.monthlySpentInPaise
        : widget.yearlySpentInPaise;
    final hasBudget = budgetInPaise > 0;
    final progress = hasBudget
        ? (spentInPaise / budgetInPaise).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final isOverBudget = hasBudget && spentInPaise > budgetInPaise;
    final remainingInPaise = hasBudget
        ? (budgetInPaise - spentInPaise).clamp(0, budgetInPaise).toInt()
        : 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Budget overview',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_BudgetPeriod>(
              segments: const [
                ButtonSegment(
                  value: _BudgetPeriod.monthly,
                  label: Text('Monthly'),
                ),
                ButtonSegment(
                  value: _BudgetPeriod.yearly,
                  label: Text('Yearly'),
                ),
              ],
              selected: {_budgetPeriod},
              onSelectionChanged: (selection) {
                setState(() => _budgetPeriod = selection.first);
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<_BudgetChartType>(
              segments: const [
                ButtonSegment(
                  value: _BudgetChartType.donut,
                  label: Text('Donut'),
                  icon: Icon(Icons.donut_large),
                ),
                ButtonSegment(
                  value: _BudgetChartType.bars,
                  label: Text('Bars'),
                  icon: Icon(Icons.bar_chart),
                ),
              ],
              selected: {_budgetChartType},
              onSelectionChanged: (selection) {
                setState(() => _budgetChartType = selection.first);
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Total ${_budgetPeriod == _BudgetPeriod.monthly ? 'monthly' : 'yearly'} budget',
              style: const TextStyle(color: Color(0xFF687A74)),
            ),
            const SizedBox(height: 4),
            Text(
              hasBudget
                  ? '₹ ${widget.formatCurrency(budgetInPaise)}'
                  : 'No budget set',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_budgetChartType == _BudgetChartType.donut)
              _buildDonutChart(
                hasBudget: hasBudget,
                progress: progress,
                spentInPaise: spentInPaise,
                remainingInPaise: remainingInPaise,
                isOverBudget: isOverBudget,
              )
            else
              _buildBarChart(
                hasBudget: hasBudget,
                budgetInPaise: budgetInPaise,
                spentInPaise: spentInPaise,
              ),
            if (isOverBudget) ...[
              const SizedBox(height: 8),
              Text(
                'Over budget by ₹ ${widget.formatCurrency(spentInPaise - budgetInPaise)}',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDonutChart({
    required bool hasBudget,
    required double progress,
    required int spentInPaise,
    required int remainingInPaise,
    required bool isOverBudget,
  }) {
    final spentColor = isOverBudget ? Colors.red : const Color(0xFF147D64);
    return Row(
      children: [
        SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: hasBudget ? progress : 0,
                strokeWidth: 16,
                backgroundColor: const Color(0xFFE5ECE8),
                color: spentColor,
              ),
              Text(
                hasBudget ? '${(progress * 100).round()}%' : '—',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildChartLegend(
                color: spentColor,
                label: 'Spent',
                amountInPaise: spentInPaise,
              ),
              const SizedBox(height: 14),
              _buildChartLegend(
                color: const Color(0xFFE5ECE8),
                label: 'Remaining',
                amountInPaise: remainingInPaise,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBarChart({
    required bool hasBudget,
    required int budgetInPaise,
    required int spentInPaise,
  }) {
    final scale = (budgetInPaise > spentInPaise ? budgetInPaise : spentInPaise)
        .toDouble();
    return Column(
      children: [
        _buildBudgetBar(
          label: 'Budget',
          amountInPaise: budgetInPaise,
          scale: scale,
          color: const Color(0xFF97BDB1),
          enabled: hasBudget,
        ),
        const SizedBox(height: 16),
        _buildBudgetBar(
          label: 'Spent',
          amountInPaise: spentInPaise,
          scale: scale,
          color: hasBudget && spentInPaise > budgetInPaise
              ? Colors.red
              : const Color(0xFF147D64),
          enabled: true,
        ),
      ],
    );
  }

  Widget _buildBudgetBar({
    required String label,
    required int amountInPaise,
    required double scale,
    required Color color,
    required bool enabled,
  }) {
    final progress = enabled && scale > 0 ? amountInPaise / scale : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('₹ ${widget.formatCurrency(amountInPaise)}'),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: progress,
          minHeight: 12,
          color: color,
          backgroundColor: const Color(0xFFE5ECE8),
        ),
      ],
    );
  }

  Widget _buildChartLegend({
    required Color color,
    required String label,
    required int amountInPaise,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text('₹ ${widget.formatCurrency(amountInPaise)}'),
      ],
    );
  }
}
