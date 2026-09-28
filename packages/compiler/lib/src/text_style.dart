import 'package:flutter2figma_ir/flutter2figma_ir.dart';

/// A partially specified Flutter `TextStyle`. Unset fields inherit.
class TextStyleSpec {
  const TextStyleSpec({
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.italic,
    this.color,
    this.height,
    this.letterSpacing,
    this.token,
  });

  final String? fontFamily;
  final double? fontSize;
  final int? fontWeight;
  final bool? italic;
  final IrColor? color;

  /// Line height as a multiple of [fontSize], like `TextStyle.height`.
  final double? height;
  final double? letterSpacing;

  /// The most specific named theme style this was derived from
  /// (`TextTheme/bodyMedium`). Confirmed against the final typography when a
  /// text node is built.
  final String? token;

  /// Values set on [other] win, like `TextStyle.merge`.
  TextStyleSpec merge(TextStyleSpec? other) {
    if (other == null) return this;
    return TextStyleSpec(
      fontFamily: other.fontFamily ?? fontFamily,
      fontSize: other.fontSize ?? fontSize,
      fontWeight: other.fontWeight ?? fontWeight,
      italic: other.italic ?? italic,
      color: other.color ?? color,
      height: other.height ?? height,
      letterSpacing: other.letterSpacing ?? letterSpacing,
      token: other.token ?? token,
    );
  }

  IrTextStyle resolve(String defaultFamily) {
    final size = fontSize ?? 14;
    return IrTextStyle(
      fontFamily: fontFamily ?? defaultFamily,
      fontSize: size,
      fontWeight: fontWeight ?? 400,
      italic: italic ?? false,
      color: color ?? IrColor.black,
      lineHeight: height == null ? null : _round(height! * size),
      letterSpacing: letterSpacing ?? 0,
      token: token,
    );
  }
}

double _round(double v) => (v * 100).roundToDouble() / 100;
