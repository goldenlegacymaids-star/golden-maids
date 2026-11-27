import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../domain/customer_document.dart';

/// A simple drawing of a document type (Emirates ID, passport, salary or
/// marriage certificate), marked SAMPLE, so customers see at a glance what
/// to upload. Generic shapes only: no real document, logo or emblem.
class DocumentSample extends StatelessWidget {
  const DocumentSample({super.key, required this.type, this.width = 80});

  final DocumentType type;
  final double width;

  /// The size the drawing is made at; it is scaled to [width].
  static const Size designSize = Size(96, 62);

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width * designSize.height / designSize.width,
        child: FittedBox(
          child: SizedBox.fromSize(
            size: designSize,
            child: CustomPaint(painter: _SamplePainter(type)),
          ),
        ),
      ),
    );
  }
}

class _SamplePainter extends CustomPainter {
  _SamplePainter(this.type);

  final DocumentType type;

  // Illustration colours (blue ID card, amber passport, white and pink
  // certificates).
  static const _blue50 = Color(0xFFE6F1FB);
  static const _blue100 = Color(0xFFB5D4F4);
  static const _blue200 = Color(0xFF85B7EB);
  static const _blue400 = Color(0xFF378ADD);
  static const _blue600 = Color(0xFF185FA5);
  static const _blue800 = Color(0xFF0C447C);
  static const _amber50 = Color(0xFFFAEEDA);
  static const _amber100 = Color(0xFFFAC775);
  static const _amber200 = Color(0xFFEF9F27);
  static const _amber600 = Color(0xFF854F0B);
  static const _amber800 = Color(0xFF633806);
  static const _gray100 = Color(0xFFD3D1C7);
  static const _gray200 = Color(0xFFB4B2A9);
  static const _gray600 = Color(0xFF5F5E5A);
  static const _green200 = Color(0xFF97C459);
  static const _green900 = Color(0xFF173404);
  static const _pink50 = Color(0xFFFBEAF0);
  static const _pink100 = Color(0xFFF4C0D1);
  static const _pink200 = Color(0xFFED93B1);
  static const _pink400 = Color(0xFFD4537E);
  static const _pink600 = Color(0xFF993556);
  static const _pink800 = Color(0xFF72243E);

  @override
  void paint(Canvas canvas, Size size) {
    switch (type) {
      case DocumentType.emiratesId:
        _idCard(canvas);
      case DocumentType.passport:
        _passport(canvas);
      case DocumentType.salaryCertificate:
        _salaryCertificate(canvas);
      case DocumentType.marriageCertificate:
        _marriageCertificate(canvas);
    }
  }

  void _idCard(Canvas canvas) {
    const card = Rect.fromLTWH(1, 1, 94, 60);
    _box(canvas, card, 7, _blue50, stroke: _blue200);
    // Header band with rounded top corners only.
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(card, const Radius.circular(7)))
      ..drawRect(const Rect.fromLTWH(1, 1, 94, 13), Paint()..color = _blue400)
      ..restore();
    _text(canvas, 'EMIRATES ID', const Offset(8, 3.5), 7, Colors.white,
        bold: true);
    _person(canvas, const Rect.fromLTWH(8, 20, 22, 28), _blue100, _blue200);
    _line(canvas, 36, 22, 44, 4, _blue200);
    _line(canvas, 36, 30, 34, 3, _blue100);
    _line(canvas, 36, 36, 40, 3, _blue100);
    _line(canvas, 36, 42, 26, 3, _blue100);
    _box(canvas, const Rect.fromLTWH(74, 44, 14, 10), 2,
        _amber200.withValues(alpha: 0.8));
    _text(canvas, 'SAMPLE', const Offset(48, 52.5), 5.5, _blue800,
        centered: true);
  }

  void _passport(Canvas canvas) {
    _box(canvas, const Rect.fromLTWH(1, 1, 94, 60), 5, _amber50,
        stroke: _amber200);
    _person(canvas, const Rect.fromLTWH(8, 10, 22, 28), _amber100, _amber200);
    _text(canvas, 'PASSPORT', const Offset(36, 5), 7, _amber800, bold: true);
    _line(canvas, 36, 17, 44, 3.5, _amber200.withValues(alpha: 0.7));
    _line(canvas, 36, 24, 36, 3, _amber100);
    _line(canvas, 36, 30, 40, 3, _amber100);
    _line(canvas, 36, 36, 28, 3, _amber100);
    // Machine-readable lines, as on a passport photo page.
    _text(canvas, 'P<SAMPLE<<<<<<<<<<<<<<<', const Offset(8, 44), 5,
        _amber600, mono: true);
    _text(canvas, '0000000<<<<<<<<<<<<<<<<', const Offset(8, 51), 5,
        _amber600, mono: true);
  }

  void _salaryCertificate(Canvas canvas) {
    _box(canvas, const Rect.fromLTWH(22, 1, 52, 60), 3, Colors.white,
        stroke: _gray200);
    _box(canvas, const Rect.fromLTWH(28, 6, 16, 5), 1.5, _blue400);
    _line(canvas, 28, 15, 40, 3, _gray600);
    _line(canvas, 28, 22, 40, 2, _gray100);
    _line(canvas, 28, 27, 36, 2, _gray100);
    _line(canvas, 28, 32, 38, 2, _gray100);
    _box(canvas, const Rect.fromLTWH(28, 37, 20, 5), 1.5, _green200);
    _text(canvas, 'AED', const Offset(38, 38.2), 3.5, _green900,
        centered: true);
    _signature(canvas, const Offset(30, 50), _blue600);
    // Round stamp, drawn as dots.
    final stamp = Paint()
      ..color = _blue400
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    canvas.drawPoints(PointMode.points, [
      for (var i = 0; i < 18; i++)
        Offset(62, 48) +
            Offset.fromDirection(i * 6.283185307 / 18, 6),
    ], stamp);
    _text(canvas, 'SAMPLE', const Offset(48, 55), 4.5, _gray600,
        centered: true);
  }

  void _marriageCertificate(Canvas canvas) {
    _box(canvas, const Rect.fromLTWH(22, 1, 52, 60), 3, _pink50,
        stroke: _pink200);
    final frame = Paint()
      ..color = _pink200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(25, 4, 46, 54),
        const Radius.circular(2),
      ),
      frame,
    );
    // Two rings.
    final ring = Paint()
      ..color = _pink400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas
      ..drawCircle(const Offset(44, 13), 4, ring)
      ..drawCircle(const Offset(51, 13), 4, ring);
    _line(canvas, 30, 22, 36, 3, _pink600.withValues(alpha: 0.7));
    _line(canvas, 31, 29, 34, 2, _pink100);
    _line(canvas, 33, 34, 30, 2, _pink100);
    _line(canvas, 31, 39, 34, 2, _pink100);
    _signature(canvas, const Offset(30, 47), _pink800);
    _signature(canvas, const Offset(53, 47), _pink800);
    _text(canvas, 'SAMPLE', const Offset(48, 52), 4.5, _pink600,
        centered: true);
  }

  // Drawing helpers --------------------------------------------------------

  void _box(
    Canvas canvas,
    Rect rect,
    double radius,
    Color fill, {
    Color? stroke,
  }) {
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(shape, Paint()..color = fill);
    if (stroke != null) {
      canvas.drawRRect(
        shape,
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
  }

  /// A rounded bar standing for a line of text.
  void _line(
    Canvas canvas,
    double x,
    double y,
    double width,
    double height,
    Color color,
  ) => _box(canvas, Rect.fromLTWH(x, y, width, height), height / 2, color);

  /// A photo box with a head-and-shoulders outline.
  void _person(Canvas canvas, Rect photo, Color background, Color figure) {
    _box(canvas, photo, 3, background);
    final paint = Paint()..color = figure;
    final head = Offset(photo.center.dx, photo.top + photo.height * 0.36);
    canvas.drawCircle(head, photo.width * 0.23, paint);
    final shoulders = Path()
      ..moveTo(photo.left + 3, photo.bottom - 2)
      ..quadraticBezierTo(
        photo.center.dx,
        photo.top + photo.height * 0.48,
        photo.right - 3,
        photo.bottom - 2,
      )
      ..close();
    canvas.drawPath(shoulders, paint);
  }

  void _signature(Canvas canvas, Offset start, Color color) {
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx + 3,
        start.dy - 4,
        start.dx + 5,
        start.dy + 2,
        start.dx + 8,
        start.dy - 1,
      )
      ..cubicTo(
        start.dx + 10,
        start.dy - 3,
        start.dx + 12,
        start.dy + 1,
        start.dx + 15,
        start.dy - 1,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    double fontSize,
    Color color, {
    bool bold = false,
    bool mono = false,
    bool centered = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          fontFamily: mono ? 'monospace' : null,
          letterSpacing: mono ? 0 : 0.3,
          height: 1,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = centered ? at - Offset(painter.width / 2, 0) : at;
    painter
      ..paint(canvas, offset)
      ..dispose();
  }

  @override
  bool shouldRepaint(_SamplePainter oldDelegate) => oldDelegate.type != type;
}
