import 'package:flutter/material.dart';

import '../data.dart';

/// A checkout form: progress steps, address fields, delivery options,
/// payment and an order summary.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  int _delivery = 0;
  bool _saveAddress = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = products.take(2).toList();
    final subtotal = items.fold(0.0, (sum, p) => sum + p.price);
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              for (final (i, step) in [
                'Address',
                'Delivery',
                'Payment',
              ].indexed) ...[
                if (i > 0)
                  Expanded(
                    child: Divider(
                      color: i == 1 ? scheme.primary : scheme.outlineVariant,
                    ),
                  ),
                CircleAvatar(
                  radius: 14,
                  backgroundColor: i < 2
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  child: i == 0
                      ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                      : Text(
                          '${i + 1}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: i < 2
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(width: 6),
                Text(step, style: theme.textTheme.labelMedium),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Text('Shipping address', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Street address',
              prefixIcon: Icon(Icons.home_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'City',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'ZIP',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Save this address'),
            value: _saveAddress,
            onChanged: (v) => setState(() => _saveAddress = v!),
          ),
          const SizedBox(height: 8),
          Text('Delivery', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final (i, (title, eta, price)) in [
            ('Standard', '3–5 business days', 'Free'),
            ('Express', 'Tomorrow by 8 pm', '\$9.99'),
          ].indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _delivery = i),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: i == _delivery
                          ? scheme.primary
                          : scheme.outlineVariant,
                      width: i == _delivery ? 2 : 1,
                    ),
                    color: i == _delivery
                        ? scheme.primaryContainer.withValues(alpha: 0.4)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        i == 0 ? Icons.local_shipping_outlined : Icons.bolt,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: theme.textTheme.titleSmall),
                            Text(eta, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Text(price, style: theme.textTheme.titleSmall),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Card(
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final p in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              p.image,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p.name,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            '\$${p.price.toStringAsFixed(2)}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  _SummaryRow('Subtotal', '\$${subtotal.toStringAsFixed(2)}'),
                  const _SummaryRow('Shipping', 'Free'),
                  const Divider(),
                  _SummaryRow(
                    'Total',
                    '\$${subtotal.toStringAsFixed(2)}',
                    strong: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {},
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Place order'),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, {this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = strong
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
