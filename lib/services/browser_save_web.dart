import 'package:web/web.dart' as web;

void saveBrowserFile(Uri uri) {
  final link = web.HTMLAnchorElement()
    ..href = uri.toString()
    ..download = '';
  web.document.body!.append(link);
  link.click();
  link.remove();
}
