import 'package:flutter/material.dart';

import '../data.dart';
import '../widgets/common.dart';

/// A product page: hero image with overlay buttons, details, options and a
/// sticky purchase bar.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    this.product = const Product(
      name: 'Aurora Headphones',
      brand: 'Sonic',
      price: 129,
      oldPrice: 159,
      image: 'assets/products/p1.png',
      rating: 4.8,
      reviews: 2310,
    ),
  });

  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _size = 1;
  int _quantity = 1;
  int _color = 0;

  static const _colors = [
    Color(0xFF7C4DFF),
    Color(0xFF263238),
    Color(0xFFE0E0E0),
    Color(0xFFFF7043),
  ];
  static const _sizes = ['S', 'M', 'L', 'XL'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final product = widget.product;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 340,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(product.image, fit: BoxFit.cover),
                Positioned(
                  left: 12,
                  top: 12,
                  child: IconButton.filledTonal(
                    onPressed: () {},
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () {},
                        icon: const Icon(Icons.share_outlined),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () {},
                        icon: const Icon(Icons.favorite),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Container(
                          width: i == 0 ? 20 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i == 0 ? Colors.white : Colors.white54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.brand,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(product.name, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    RatingStars(
                      rating: product.rating,
                      reviews: product.reviews,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'In stock',
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                PriceTag(
                  price: product.price,
                  oldPrice: product.oldPrice,
                  large: true,
                ),
                const Divider(height: 32),
                Text('Color', style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < _colors.length; i++)
                      GestureDetector(
                        onTap: () => setState(() => _color = i),
                        child: Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: _colors[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: i == _color
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              width: i == _color ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Size', style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < _sizes.length; i++)
                      ChoiceChip(
                        label: Text(_sizes[i]),
                        selected: i == _size,
                        onSelected: (_) => setState(() => _size = i),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('About', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  'Wireless over-ear headphones with adaptive noise cancelling, '
                  '40 hours of battery and a fold-flat design that fits any bag.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(() => _quantity--),
                      icon: const Icon(Icons.remove),
                    ),
                    Text('$_quantity', style: theme.textTheme.titleMedium),
                    IconButton(
                      onPressed: () => setState(() => _quantity++),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Add to bag'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
