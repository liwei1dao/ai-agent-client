/// Stub of `htmltopdfwidgets` for the legacy meeting module port.
///
/// PDF generation is disabled in `ai-agent-client`. This stub mirrors the
/// minimal surface used in the source code.
import 'dart:typed_data';

class Document {
  void addPage(dynamic page) {}
  Future<Uint8List> save() async => Uint8List(0);
}

abstract class Widget {}

class _StubWidget implements Widget {}

class Page {
  Page(
      {dynamic build,
      dynamic margin,
      dynamic theme,
      dynamic header,
      dynamic footer});
}

class MultiPage {
  MultiPage({
    List<Widget> Function(dynamic)? build,
    dynamic margin,
    dynamic theme,
    dynamic header,
    dynamic footer,
  });
}

class PdfPageFormat {
  static const PdfPageFormat a4 = PdfPageFormat();
  const PdfPageFormat();
}

class Font {
  static Font ttf(dynamic bytes) => Font();
}

class HTMLToPdf {
  Future<Document> convert(String html, {dynamic config}) async => Document();

  Future<List<Widget>> convertMarkdown(
    String markdown, {
    List<Font>? fontFallback,
    dynamic config,
  }) async =>
      <Widget>[];
}

Future<List<Widget>> htmlToPdfWidgets(String html, {dynamic config}) async =>
    <Widget>[];
