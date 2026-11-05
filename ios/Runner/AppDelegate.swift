import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let files = FlutterMethodChannel(
      name: "nazzelha/ios_files",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    files.setMethodCallHandler { call, result in
      guard call.method == "show_files",
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String,
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let root = documents.appendingPathComponent("Nazzelha").resolvingSymlinksInPath()
      let target = URL(fileURLWithPath: path).resolvingSymlinksInPath()
      guard target.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: target.path) else {
        result(FlutterError(code: "INVALID_PATH", message: "Invalid download location.", details: nil))
        return
      }
      DispatchQueue.main.async {
        guard var presenter = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })?
          .windows.first(where: { $0.isKeyWindow })?.rootViewController else {
          result(FlutterError(code: "NO_WINDOW", message: "Could not open Files.", details: nil))
          return
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        let picker = UIDocumentPickerViewController(forExporting: [target], asCopy: true)
        presenter.present(picker, animated: true)
        result(true)
      }
    }
  }
}
