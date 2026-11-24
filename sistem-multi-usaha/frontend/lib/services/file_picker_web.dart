import 'dart:async';
import 'dart:html' as html;

Future<String?> pickCsvText() {
  final completer = Completer<String?>();
  final input = html.FileUploadInputElement()..accept = '.csv,text/csv';
  input.click();
  input.onChange.listen((_) {
    final file = input.files?.isEmpty == false ? input.files!.first : null;
    if (file == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.readAsText(file);
    reader.onLoadEnd.listen((_) {
      if (!completer.isCompleted) completer.complete(reader.result as String?);
    });
    reader.onError.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError('Gagal membaca file CSV.');
      }
    });
  });
  return completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () => null,
  );
}
