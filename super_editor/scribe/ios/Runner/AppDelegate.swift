import Flutter
import UIKit
import UniformTypeIdentifiers   // iOS 14+ for UTType.html

@main
@objc class AppDelegate: FlutterAppDelegate {

  private let channelName = "com.scribe.clipboard/native"
  private var clipboardChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      print("iOS AppDelegate: FlutterViewController not found. Custom HTML paste will not be available.")
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Create the channel **and attach handler**
    clipboardChannel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.binaryMessenger
    )

    clipboardChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getHtmlContent" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.getHtmlFromPasteboard(result: result)
    }

    print("iOS AppDelegate: Clipboard method channel ready.")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Reads HTML-flavoured content from the system pasteboard and returns it to Dart.
  private func getHtmlFromPasteboard(result: @escaping FlutterResult) {

    let pasteboard = UIPasteboard.general

    // -- APPROACH 1 : real HTML on iOS 14+ -----------------------------------
    if #available(iOS 14.0, *) {
      let htmlUTI = UTType.html.identifier   // = "public.html"
      if pasteboard.contains(pasteboardTypes: [htmlUTI]),
         let htmlData = pasteboard.data(forPasteboardType: htmlUTI),
         let htmlString = String(data: htmlData, encoding: .utf8) {
        print("Native iOS 14+: Found HTML content via UTType.html")
        result(htmlString)
        return
      }
    }

    // -- APPROACH 2 : legacy UTI --------------------------------------------
    if let htmlString = pasteboard.value(forPasteboardType: "public.html") as? String {
      print("Native iOS: Found HTML content via public.html")
      result(htmlString)
      return
    }

    // -- APPROACH 3 : RTFD → HTML -------------------------------------------
    if pasteboard.contains(pasteboardTypes: ["com.apple.rtfd", "com.apple.flat-rtfd"]),
       let rtfdData = pasteboard.data(forPasteboardType: "com.apple.rtfd") ??
                      pasteboard.data(forPasteboardType: "com.apple.flat-rtfd") {

      let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
        .documentType: NSAttributedString.DocumentType.rtfd
      ]

      do {
        let attributed = try NSAttributedString(data: rtfdData,
                                                options: options,
                                                documentAttributes: nil)
        if let htmlData = try? attributed.data(
              from: NSRange(location: 0, length: attributed.length),
              documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
           let htmlString = String(data: htmlData, encoding: .utf8) {
          print("Native iOS: Converted RTFD to HTML")
          result(htmlString)
          return
        }
      } catch {
        print("Native iOS: Error converting RTFD to HTML: \(error)")
      }
    }

    // -- APPROACH 4 : plain text that *looks* like HTML ----------------------
    if let plain = pasteboard.string,
       plain.range(of: "<html", options: .caseInsensitive) != nil ||
       plain.range(of: "<body", options: .caseInsensitive) != nil ||
       (plain.contains("<") && plain.contains(">") && plain.contains("</")) {
      print("Native iOS: Found HTML-like content in plain string")
      result(plain)
      return
    }

    print("Native iOS: No HTML content found in pasteboard")
    result(nil)
  }
}
