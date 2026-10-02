import 'package:flutter/material.dart';

import '../data.dart';

/// "Title ........ See all" row above a section.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action = 'See all',
  });

  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          TextButton(onPressed: () {}, child: Text(action)),
        ],
      ),
    );
  }
}

/// Five stars filled up to [rating], with the review count.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.reviews});

  final double rating;
  final int? reviews;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating
                ? Icons.star_rounded
                : i - rating < 1
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded,
            size: 16,
            color: const Color(0xFFFFB300),
          ),
        const SizedBox(width: 4),
        Text(
          reviews == null ? rating.toString() : '$rating ($reviews)',
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

/// Current price, with the old price struck through when discounted.
class PriceTag extends StatelessWidget {
  const PriceTag({
    super.key,
    required this.price,
    this.oldPrice,
    this.large = false,
  });

  final double price;
  final double? oldPrice;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '\$${price.toStringAsFixed(0)}',
          style:
              (large
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.titleMedium)
                  ?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
        ),
        if (oldPrice != null) ...[
          const SizedBox(width: 6),
          Text(
            '\$${oldPrice!.toStringAsFixed(0)}',
            style: theme.textTheme.bodySmall?.copyWith(
              decoration: TextDecoration.lineThrough,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}

/// A product in a grid: image with discount badge and favorite button,
/// then brand, name, price and rating.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(product.image, fit: BoxFit.cover),
                if (product.discount != null)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '-${product.discount}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onError,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton.filledTonal(
                    onPressed: () {},
                    icon: const Icon(Icons.favorite_border, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.brand.toUpperCase(),
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                PriceTag(price: product.price, oldPrice: product.oldPrice),
                const SizedBox(height: 4),
                RatingStars(rating: product.rating),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A round avatar from an asset, with an optional online dot.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.person,
    this.size = 40,
    this.online = false,
  });

  final Person person;
  final double size;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          CircleAvatar(
            radius: size / 2,
            backgroundImage: AssetImage(person.avatar),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size / 4,
                height: size / 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
