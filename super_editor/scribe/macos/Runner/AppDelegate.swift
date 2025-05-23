import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.scribe.clipboard/native"
     private var clipboardChannel: FlutterMethodChannel?

     override public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
       return true
     }

     override public func applicationDidFinishLaunching(_ notification: Notification) {
       // Access the FlutterViewController through self.mainFlutterWindow, a property of FlutterAppDelegate
       guard let flutterViewController = self.mainFlutterWindow?.contentViewController as? FlutterViewController else {
         fatalError("Failed to get FlutterViewController from mainFlutterWindow. Ensure mainFlutterWindow is set up correctly.")
       }
       
       clipboardChannel = FlutterMethodChannel(name: channelName,
                                               binaryMessenger: flutterViewController.engine.binaryMessenger)

       clipboardChannel?.setMethodCallHandler({
         [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
         guard call.method == "getHtmlContent" else {
           result(FlutterMethodNotImplemented)
           return
         }
         self?.getHtmlFromPasteboard(result: result)
       })
     }

     private func getHtmlFromPasteboard(result: @escaping FlutterResult) {
       let pasteboard = NSPasteboard.general
       // NSPasteboard.PasteboardType.html is the most common type for HTML
       // NSPasteboard.PasteboardType.string can sometimes contain HTML if .html is not available
       // You might also want to check for "public.html" specifically if needed
       if let htmlString = pasteboard.string(forType: .html) {
         print("Native macOS: Found HTML content via NSPasteboard.PasteboardType.html")
         result(htmlString)
       } else if let plainString = pasteboard.string(forType: .string) {
         // Fallback: Check if the plain string itself might be HTML
         // This is a basic check; more sophisticated checks might be needed
         if plainString.range(of: "<html", options: .caseInsensitive) != nil || 
            plainString.range(of: "<body", options: .caseInsensitive) != nil ||
            (plainString.range(of: "<", options: .caseInsensitive) != nil && plainString.range(of: ">", options: .caseInsensitive) != nil && plainString.contains("</")) {
             print("Native macOS: Found HTML-like content in NSPasteboard.PasteboardType.string")
             result(plainString)
         } else {
             print("Native macOS: No HTML content found via .html or .string that looks like HTML")
             result(nil)
         }
       }
       else {
         print("Native macOS: No HTML content found in pasteboard for .html or .string types")
         result(nil)
       }
     }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
