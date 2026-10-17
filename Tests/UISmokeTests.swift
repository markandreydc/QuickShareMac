import Cocoa
import NearbyShare
import Vision

// Standalone AppKit smoke tests; no receiver or device discovery is started.
// Build the app, then run Tests/run-ui-smoke-tests.sh.
@main
struct UISmokeTests{
	static var checks=0
	static func expect(_ condition:@autoclosure ()->Bool, _ message:String){
		checks+=1
		precondition(condition(), message)
	}
	static func descendants(_ view:NSView) -> [NSView]{[view]+view.subviews.flatMap(descendants)}
	static func visible(_ view:NSView) -> [NSView]{descendants(view).filter {!$0.isHiddenOrHasHiddenAncestor}}
	static func button(_ title:String, in view:NSView) -> NSButton{
		guard let button=visible(view).compactMap({$0 as? NSButton}).first(where: {$0.title==title}) else {fatalError("Missing button: \(title)")}
		return button
	}
	static func layout(_ window:NSWindow){
		window.contentView?.needsLayout=true
		window.contentView?.layoutSubtreeIfNeeded()
	}
	static func transfer(_ id:String, _ state:IncomingTransferState, pin:String = "1234", remembered:Bool = false, progress:Double = 0.5) -> IncomingTransferDisplay{
		IncomingTransferDisplay(id: id, deviceName: "Android \(id)", description: "A photograph with a longer filename.jpg · 10 MB", status: state == .failed ? "The connection was interrupted before the transfer could finish." : "Transfer status", state: state, progress: state == .receiving ? progress : nil, pinCode: pin, remembered: remembered, receivedBytes: Int64(progress*10000000), totalBytes: 10000000, savedFileURLs: [URL(fileURLWithPath: "/Users/Shared/photo.jpg")])
	}
	static func snapshot(_ window:NSWindow, _ name:String){
		layout(window)
		window.contentView?.displayIfNeeded()
		RunLoop.main.run(until: Date().addingTimeInterval(0.02))
		guard let directory=ProcessInfo.processInfo.environment["UI_SNAPSHOT_DIR"], let view=window.contentView, let bitmap=view.bitmapImageRepForCachingDisplay(in: view.bounds) else {return}
		view.cacheDisplay(in: view.bounds, to: bitmap)
		if let data=bitmap.representation(using: .png, properties: [:]){try? data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name+".png"))}
	}
	static func main(){
		_ = NSApplication.shared
		NSApp.setActivationPolicy(.prohibited)
		let controller=MainWindowViewController()
		let window=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
		window.contentViewController=controller
		window.setContentSize(NSSize(width: 520, height: 640))
		controller.update(receiving: true, transfers: [])
		layout(window)
		expect(visible(controller.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue.contains("same Wi-Fi")}), "Empty state must explain network requirements")
		expect(!visible(controller.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Launch at login"}), "Startup options belong in Settings")
		snapshot(window, "ready")
		var enabled=false
		controller.onReceivingChange={enabled=$0}
		controller.update(receiving: false, transfers: [])
		button("Enable receiving", in: controller.view).performClick(nil)
		expect(enabled, "Empty-state receiving action must enable receiving")

		var decision:(String,TransferDecision)?
		controller.onTransferDecision={decision=($0,$1)}
		controller.update(receiving: true, transfers: [transfer("a", .awaitingApproval), transfer("b", .receiving)])
		layout(window)
		let remember=button("Remember this device name", in: controller.view)
		remember.state = .on
		let accept=button("Accept", in: controller.view)
		expect(accept.keyEquivalent.isEmpty, "Approval must not capture Return")
		expect(accept.convert(accept.bounds, to: controller.view).minY>=0, "Approval controls must fit at the minimum window size")
		expect(visible(controller.view).filter({$0 is NSProgressIndicator}).count==1, "Only active transfers should show progress")
		controller.update(receiving: true, transfers: [transfer("a", .awaitingApproval), transfer("b", .receiving, progress: 0.8)])
		expect(button("Remember this device name", in: controller.view) === remember, "Progress updates must preserve approval controls")
		expect(remember.state == .on, "Progress updates must preserve checkbox selection")
		button("Accept", in: controller.view).performClick(nil)
		expect(decision?.0=="a" && decision?.1 == .acceptAndRemember, "Remember checkbox must affect acceptance")
		snapshot(window, "approval")
		controller.update(receiving: true, transfers: [transfer("c", .awaitingApproval, pin: "9876"), transfer("a", .completed)])
		layout(window)
		expect(visible(controller.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="9876"}), "Next request must replace the previous PIN")
		expect(button("Remember this device name", in: controller.view).state == .off, "Remember choice must not leak to another sender")
		controller.update(receiving: true, transfers: [transfer("c", .awaitingApproval, remembered: true)])
		expect(!visible(controller.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Remember this device name"}), "Remembered names should not show another remember checkbox")
		controller.update(receiving: true, transfers: [transfer("c", .awaitingApproval)])
		expect(button("Remember this device name", in: controller.view).state == .off, "Forgetting names should update an existing request")
		controller.update(receiving: true, transfers: [transfer("a", .completed), transfer("b", .failed)])
		layout(window)
		expect(visible(controller.view).filter({$0 is NSProgressIndicator}).isEmpty, "Finished and failed transfers must not show progress bars")
		var revealed:String?
		controller.onRevealTransfer={revealed=$0}
		button("Show in Finder", in: controller.view).performClick(nil)
		expect(revealed=="a", "Finder action must identify the completed transfer")
		var dismissed:String?
		controller.onDismissTransfer={dismissed=$0}
		button("Dismiss", in: controller.view).performClick(nil)
		expect(dismissed=="a", "Dismiss action must identify the completed transfer")
		var cleared=false
		controller.onClearRecentTransfers={cleared=true}
		button("Clear", in: controller.view).performClick(nil)
		expect(cleared, "Clear history action must be wired")
		snapshot(window, "recent")
		controller.update(receiving: true, transfers: [transfer("one", .awaitingApproval), transfer("two", .awaitingApproval)])
		layout(window)
		expect(visible(controller.view).compactMap({$0 as? NSButton}).filter({$0.title=="Accept"}).count==1, "Only the pinned request should expose approval controls")
		let longRequest=IncomingTransferDisplay(id: "long", deviceName: String(repeating: "Long device name ", count: 16), description: String(repeating: "Long filename ", count: 30)+".jpg", status: "Waiting for approval", state: .awaitingApproval, progress: nil, pinCode: "9876", remembered: false, receivedBytes: 0, totalBytes: 10, savedFileURLs: [])
		controller.update(receiving: true, transfers: [longRequest])
		layout(window)
		let longAccept=button("Accept", in: controller.view)
		let actionBounds=longAccept.convert(longAccept.bounds, to: controller.view)
		expect(controller.view.bounds.contains(actionBounds), "Long sender names and filenames must not push approval controls outside the window")
		let history=(0..<20).map {transfer("history-\($0)", .completed)}
		controller.update(receiving: true, transfers: [transfer("active", .receiving)]+history)
		layout(window)
		let scroll=visible(controller.view).compactMap {$0 as? NSScrollView}.first!
		expect(scroll.documentView!.frame.height>scroll.contentView.bounds.height, "Recent transfers must scroll instead of expanding the window")
		scroll.contentView.scroll(to: NSPoint(x: 0, y: 150))
		let origin=scroll.contentView.bounds.origin
		controller.update(receiving: true, transfers: [transfer("active", .receiving, progress: 0.9)]+history)
		expect(scroll.contentView.bounds.origin==origin, "Progress updates must preserve scroll position")
		window.setContentSize(NSSize(width: 760, height: 900))
		layout(window)
		expect(visible(controller.view).compactMap({$0 as? NSScrollView}).first!.frame.width>600, "Transfer list must expand with the window")

		let settings=SettingsViewController()
		let settingsWindow=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
		settingsWindow.contentViewController=settings
		settings.update(startReceivingOnLaunch: true, launchAtLogin: false, requiresLoginApproval: false, rememberedDeviceCount: 0)
		layout(settingsWindow)
		expect(!button("Forget all", in: settings.view).isEnabled, "Forget must be disabled when no names are stored")
		settings.update(startReceivingOnLaunch: false, launchAtLogin: false, requiresLoginApproval: true, rememberedDeviceCount: 3)
		expect(button("Forget all", in: settings.view).isEnabled, "Stored names should be forgettable")
		_ = button("Set up login item in System Settings…", in: settings.view)
		snapshot(settingsWindow, "settings")

		let sender=PreviewShareController()
		let sendWindow=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
		sendWindow.contentViewController=sender
		layout(sendWindow)
		_ = button("Connect with QR code…", in: sender.view)
		snapshot(sendWindow, "send-discovery")
		sender.connectionWasEstablished(pinCode: "4321")
		sender.transferAccepted()
		sender.transferProgress(progress: 0.5)
		sender.transferFinished()
		_ = button("Done", in: sender.view)
		let failedSender=PreviewShareController()
		sendWindow.contentViewController=failedSender
		failedSender.connectionFailed(with: NearbyError.canceled(reason: .timedOut))
		layout(sendWindow)
		expect(visible(failedSender.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Timed out"}), "Send failures must show a readable reason")
		_ = button("Close", in: failedSender.view)
		expect(visible(failedSender.view).filter({$0 is NSProgressIndicator}).isEmpty, "Failed sending must not show progress")
		snapshot(sendWindow, "send-failure")
		RunLoop.main.run(until: Date().addingTimeInterval(2.2))
		_ = button("Close", in: failedSender.view)
		let folderSender=FolderShareController()
		sendWindow.contentViewController=folderSender
		RunLoop.main.run(until: Date().addingTimeInterval(0.5))
		expect(visible(folderSender.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue.contains("Compress the folder")}), "Folder input should explain how to share a ZIP instead")
		let linkSender=LinkShareController()
		sendWindow.contentViewController=linkSender
		RunLoop.main.run(until: Date().addingTimeInterval(0.5))
		expect(linkSender.ready, "Link attachments must load before discovery starts")
		expect(button("Connect with QR code…", in: linkSender.view).isEnabled, "QR connection must be enabled after loading attachments")
		linkSender.useQrCode(nil)
		expect(sendWindow.sheets.count==1, "QR connection should open a native sheet")
		if let sheet=sendWindow.sheets.first{
			layout(sheet)
			let image=descendants(sheet.contentView!).compactMap {$0 as? NSImageView}.first!.image!
			let request=VNDetectBarcodesRequest()
			try! VNImageRequestHandler(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!, options: [:]).perform([request])
			expect(request.results?.first?.payloadStringValue?.hasPrefix("https://quickshare.google/qrcode#key=")==true, "Generated QR code must be readable by a barcode scanner")
			snapshot(sheet, "qr-connection")
		}
		linkSender.dismissQrCodeSheet(nil)
		expect(sendWindow.sheets.isEmpty, "Cancel must dismiss the QR sheet")
		controller.view.appearance=NSAppearance(named: .darkAqua)
		controller.update(receiving: true, transfers: [transfer("dark", .awaitingApproval), transfer("done", .completed)])
		layout(window)
		snapshot(window, "dark-approval")
		expect(button("Accept", in: controller.view).isEnabled, "Approval must remain usable in dark mode")
		print("Passed \(checks) UI smoke checks")
	}
}

private final class PreviewShareController:ShareViewController{
	// Build the real view without loading attachments or starting discovery.
	override func viewDidLoad(){}
}

private final class FolderShareController:ShareViewController{
	private let context=FolderExtensionContext()
	override var extensionContext:NSExtensionContext? {context}
}

private final class FolderExtensionContext:NSExtensionContext{
	override var inputItems:[Any]{
		let item=NSExtensionItem()
		item.attachments=[NSItemProvider(object: NSURL(fileURLWithPath: "/"))]
		return [item]
	}
}

private final class LinkShareController:ShareViewController{
	private let context=LinkExtensionContext()
	var ready=false
	override var extensionContext:NSExtensionContext? {context}
	override func beginDiscovery(){ready=true}
}

private final class LinkExtensionContext:NSExtensionContext{
	override var inputItems:[Any]{
		let item=NSExtensionItem()
		item.attachments=[NSItemProvider(object: NSURL(string: "https://example.com")!)]
		return [item]
	}
}
