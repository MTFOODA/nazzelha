import 'dart:io';
import 'package:image/image.dart' as img;

/// Export a smaller native splash input without changing the generated mark.
void main() {
  final logo =
      img.decodePng(File('assets/logo/nazzelha-v2.png').readAsBytesSync())!;
  final splash = img.copyResize(logo,
      width: 480, height: 480, interpolation: img.Interpolation.cubic);
  File('assets/logo/nazzelha_splash-v2.png')
      .writeAsBytesSync(img.encodePng(splash));
}
