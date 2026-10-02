/// Sample content for the showcase screens.
class Product {
  const Product({
    required this.name,
    required this.brand,
    required this.price,
    required this.image,
    this.oldPrice,
    this.rating = 4.5,
    this.reviews = 120,
  });

  final String name;
  final String brand;
  final double price;
  final double? oldPrice;
  final String image;
  final double rating;
  final int reviews;

  int? get discount =>
      oldPrice == null ? null : ((1 - price / oldPrice!) * 100).round();
}

const products = [
  Product(
    name: 'Aurora Headphones',
    brand: 'Sonic',
    price: 129,
    oldPrice: 159,
    image: 'assets/products/p1.png',
    rating: 4.8,
    reviews: 2310,
  ),
  Product(
    name: 'Ember Kettle',
    brand: 'Hearth',
    price: 79,
    image: 'assets/products/p2.png',
    rating: 4.4,
    reviews: 512,
  ),
  Product(
    name: 'Lagoon Bottle',
    brand: 'Hydra',
    price: 24,
    oldPrice: 32,
    image: 'assets/products/p3.png',
    rating: 4.6,
    reviews: 890,
  ),
  Product(
    name: 'Skyline Backpack',
    brand: 'Nomad',
    price: 98,
    image: 'assets/products/p4.png',
    rating: 4.7,
    reviews: 1204,
  ),
  Product(
    name: 'Bloom Candle',
    brand: 'Lumen',
    price: 18,
    image: 'assets/products/p5.png',
    rating: 4.2,
    reviews: 88,
  ),
  Product(
    name: 'Terra Mug',
    brand: 'Clay & Co',
    price: 22,
    oldPrice: 28,
    image: 'assets/products/p6.png',
    rating: 4.9,
    reviews: 341,
  ),
];

class Person {
  const Person(this.name, this.avatar, this.role);
  final String name;
  final String avatar;
  final String role;
}

const people = [
  Person('Maya Chen', 'assets/people/u1.png', 'Product designer'),
  Person('Leo Park', 'assets/people/u2.png', 'iOS engineer'),
  Person('Sara Diaz', 'assets/people/u3.png', 'Data analyst'),
  Person('Omar Haddad', 'assets/people/u4.png', 'Support lead'),
];

const categories = ['All', 'Audio', 'Kitchen', 'Outdoor', 'Home', 'Gifts'];
