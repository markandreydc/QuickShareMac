import Cocoa
import NearbyShare
import Vision
import Network

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
		testMainWindowSending()
		testStatusBarMenu()
		print("Passed \(checks) UI smoke checks")
	}

	static func testStatusBarMenu(){
		let controller=StatusBarMenu()
		var receiving=false
		var canSendFiles=true
		controller.stateProvider={StatusBarMenu.State(receiving: receiving, canSendFiles: canSendFiles)}
		let item=NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		defer{NSStatusBar.system.removeStatusItem(item)}
		controller.attach(to: item)
		expect(item.menu === controller.menu, "A native status-item menu must handle normal clicks")
		expect(item.button?.action==nil && item.button?.target==nil, "Status clicks must not use a custom window-opening action")
		expect(item.button?.image?.isTemplate==true, "The menu bar icon must let macOS choose its tint")
		expect(controller.menu.appearance==nil, "The status menu must not force a light or dark appearance")
		expect(controller.menu.items.allSatisfy({$0.view==nil && $0.attributedTitle==nil}), "Menu items must use native views and text colors")
		controller.menuNeedsUpdate(controller.menu)
		let off=controller.menu.items.first(where: {$0.title=="Receiving: Off"})!
		expect(off.state == .off, "The menu must show receiving off without a checkmark")
		var showed=false
		controller.onShow={showed=true}
		controller.menu.performActionForItem(at: controller.menu.indexOfItem(withTitle: "Show QuickShareMac"))
		expect(showed, "Showing the window must remain available as a menu action")
		var sends=0
		controller.onSendFiles={sends+=1}
		let sendIndex=controller.menu.indexOfItem(withTitle: "Send files…")
		controller.menu.performActionForItem(at: sendIndex)
		expect(sends==1, "The status menu's Send files action must be wired")
		canSendFiles=false
		controller.menuNeedsUpdate(controller.menu)
		expect(!controller.menu.item(at: sendIndex)!.isEnabled, "Opening the menu during a transfer must disable another send")
		controller.menu.performActionForItem(at: sendIndex)
		expect(sends==1, "A disabled send action must not start another transfer")
		controller.onToggleReceiving={receiving.toggle()}
		controller.menu.performActionForItem(at: controller.menu.index(of: off))
		expect(receiving && off.state == .on && off.title=="Receiving: On", "Receiving controls must refresh their title and checkmark")
		expect(controller.toolTip.contains("Click for menu") && !controller.toolTip.contains("right-click"), "The tooltip must describe the new click behavior")
		var settings=false
		controller.onSettings={settings=true}
		controller.menu.performActionForItem(at: controller.menu.indexOfItem(withTitle: "Settings…"))
		expect(settings, "Settings must remain available in the native menu")
		var quit=false
		controller.onQuit={quit=true}
		controller.menu.performActionForItem(at: controller.menu.indexOfItem(withTitle: "Quit QuickShareMac"))
		expect(quit, "Quit must remain available in the native menu")
		let original=NSApp.appearance
		defer{NSApp.appearance=original}
		for appearance in [NSAppearance.Name.aqua, .darkAqua]{
			NSApp.appearance=NSAppearance(named: appearance)
			controller.menuNeedsUpdate(controller.menu)
			expect(controller.menu.appearance==nil && item.button?.image?.isTemplate==true, "System appearance changes must not install custom menu colors or icon tints")
		}
	}

	static func testMainWindowSending(){
		let service=FakeSendingService()
		let main=MainWindowViewController()
		main.sendController.sender.service=service
		let window=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
		window.contentViewController=main
		main.update(receiving: true, transfers: [])
		main.showSend()
		layout(window)
		_ = button("Send files…", in: main.view)
		expect(!visible(main.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Share link…" || $0.title=="Choose link"}), "The Send tab must not expose link-sharing controls")
		expect(!visible(main.view).compactMap({$0 as? NSTextField}).contains(where: {$0.placeholderString=="https://example.com"}), "The Send tab must not expose link input")
		expect(service.discoveryStarts==0, "Opening Send without items must not start discovery")
		let url=URL(string: "https://example.com/share")!
		expect(!main.sendController.selectItems([url]), "The main Send flow must reject web links")
		expect(service.discoveryStarts==0, "Rejected web links must not start discovery")
		let file=FileManager.default.temporaryDirectory.appendingPathComponent("quickshare-send-test-\(UUID().uuidString).txt")
		try! Data().write(to: file)
		defer{try? FileManager.default.removeItem(at: file)}
		expect(main.sendController.selectItems([file]), "Selecting a file must prepare the Send flow")
		expect(service.discoveryStarts==1 && service.attempts.isEmpty, "Choosing items must discover, not automatically send (discovery: \(service.discoveryStarts), transfers: \(service.attempts.count))")
		expect(!main.sendController.selectItems([URL(fileURLWithPath: "/")]), "Folders must be rejected before connecting")
		expect(!main.sendController.selectItems([URL(string: "mailto:someone@example.com")!]), "Unsupported link schemes must be rejected")
		expect(!main.sendController.selectItems([URL(string: "https://user:password@example.com")!]), "Links containing credentials must be rejected")
		let device=RemoteDeviceInfo(name: "Android test phone", type: .phone, id: "test-device")
		service.discoveryDelegate?.addDevice(device: device)
		service.discoveryDelegate?.addDevice(device: device)
		let collection=visible(main.view).compactMap {$0 as? NSCollectionView}.first!
		expect(collection.numberOfItems(inSection: 0)==1, "Discovery must deduplicate device updates")
		main.sendController.sender.selectDevice(device)
		expect(main.sendController.sender.state == .connecting && service.attempts.count==1, "Choosing a device must start a transfer")
		expect(!(main.view as! SendDropView).acceptsItems, "The window must not advertise replacement drops during an active transfer")
		expect(!main.sendController.selectItems([file]), "Choosing replacement items during a transfer must be blocked")
		let oldAttempt=service.attempts[0]
		oldAttempt.connectionWasEstablished(pinCode: "2468")
		expect(main.sendController.sender.state == .awaitingApproval, "Established connections must wait for approval")
		expect(visible(main.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="2468"}), "Sending must show the verification PIN")
		main.showReceive()
		main.sendController.sender.viewWillDisappear()
		expect(service.cancellations==0 && main.sendController.sender.isTransferring, "Switching to Receive must not cancel a send")
		main.showSend()
		main.sendController.sender.cancel(nil)
		expect(service.cancellations==1 && main.sendController.recentTransfers.first?.state == .canceled, "Cancel must stop sending and record its result")
		main.sendController.sender.retry(nil)
		expect(main.sendController.sender.state == .choosingDevice && service.attempts.count==1, "Retry must rediscover rather than automatically resend")
		main.sendController.sender.selectDevice(device)
		oldAttempt.transferFinished()
		oldAttempt.connectionFailed(with: NearbyError.inputOutput)
		expect(main.sendController.sender.state == .connecting, "Late callbacks from canceled attempts must not affect a retry")
		let currentAttempt=service.attempts[1]
		currentAttempt.connectionWasEstablished(pinCode: "1357")
		currentAttempt.transferAccepted()
		currentAttempt.transferProgress(progress: .nan)
		currentAttempt.transferProgress(progress: .infinity)
		currentAttempt.transferProgress(progress: 0.5)
		expect(main.sendController.sender.state == .sending, "Accepted transfers must report sending progress")
		main.showReceive()
		currentAttempt.transferFinished()
		expect(main.sendController.recentTransfers.count==2 && main.sendController.recentTransfers.first?.state == .completed, "Background completion must remain in outgoing history")
		expect((main.view as! SendDropView).acceptsItems, "The window must accept drops again after a transfer finishes")
		currentAttempt.transferFinished()
		expect(main.sendController.recentTransfers.count==2, "Duplicate completion callbacks must not duplicate history")
		main.showSend()
		layout(window)
		snapshot(window, "main-send-complete")
		button("Send again…", in: main.view).performClick(nil)
		expect(main.sendController.sender.state == .choosingDevice && service.attempts.count==2, "History Send again must ask for a recipient")
		service.canStart=false
		main.sendController.sender.selectDevice(device)
		expect(main.sendController.sender.state == .failed, "A vanished recipient must fail immediately rather than hang")
		expect(main.sendController.recentTransfers.first?.state == .failed, "Failed sends must be retained in history")
		let pasteboard=NSPasteboard.withUniqueName()
		pasteboard.setString("https://example.com", forType: .string)
		expect(SendDropView.urls(from: pasteboard).isEmpty, "Dropped web-link text must not enter the file-only Send flow")
		pasteboard.clearContents()
		pasteboard.writeObjects([url as NSURL])
		expect(SendDropView.urls(from: pasteboard).isEmpty, "Dragged web-link objects must also be rejected")
		pasteboard.clearContents()
		pasteboard.setString("not a link", forType: .string)
		expect(SendDropView.urls(from: pasteboard).isEmpty, "Arbitrary text must not be treated as a URL")
		pasteboard.clearContents()
		pasteboard.writeObjects([NSURL(fileURLWithPath: "/Users/Shared/first.txt"), NSURL(fileURLWithPath: "/Users/Shared/second.txt")])
		expect(SendDropView.urls(from: pasteboard).count==2, "Finder-style multi-file drags must preserve all file URLs")
		pasteboard.releaseGlobally()
		expect(main.sendController.selectItems([file]), "An empty regular file must be selectable")
		expect(!main.sendController.selectItems([file,url]), "Mixed files and web links must not be silently truncated")
		main.sendController.sender.shutdown()
		expect(main.sendController.sender.state == .idle && !main.sendController.sender.hasItems, "Shutdown must release the selection")
		main.showReceive()
		expect((main.view as! SendDropView).onURLs?([file])==true, "Dropping files on Receive must route them to Send")
		expect(visible(main.view).compactMap({$0 as? NSSegmentedControl}).first?.selectedSegment==1, "Dropping files must select the Send tab")
		main.sendController.sender.shutdown()
		testConnectionErrorUI()
	}

	static func testConnectionErrorUI(){
		let sender=SendTransferViewController()
		let service=FakeSendingService()
		sender.service=service
		let window=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
		window.contentViewController=sender
		try! sender.configureItems([URL(string: "https://example.com")!])
		let device=RemoteDeviceInfo(name: "Test phone", type: .phone, id: "policy-test")
		sender.selectDevice(device)
		service.attempts[0].connectionFailed(with: NearbyError.localNetworkDenied)
		expect(sender.state == .failed, "Permission denial must leave Connecting immediately")
		expect(visible(sender.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="macOS blocked local-network access."}), "Permission failures must explain the actual blockage")
		expect(visible(sender.view).filter({$0 is NSProgressIndicator}).isEmpty, "Permission failures must not leave a progress animation")
		var opened=false
		sender.onOpenNetworkSettings={opened=true}
		button("Open Network Settings…", in: sender.view).performClick(nil)
		expect(opened, "Permission failure must offer a working Settings action")
		snapshot(window, "local-network-blocked")
		sender.retry(nil)
		expect(!visible(sender.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Open Network Settings…"}), "Retry must reset permission-specific controls")
		sender.selectDevice(device)
		service.attempts[1].connectionFailed(with: NWError.posix(.ECONNREFUSED))
		expect(visible(sender.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="The receiving device refused the connection."}), "A phone refusing a connection must not be blamed on Mac permission")
		expect(!visible(sender.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Open Network Settings…"}), "Refused connections must not show irrelevant permission controls")
		sender.shutdown()
	}
}

private final class FakeSendingService:SendingService{
	var discoveryStarts=0
	var discoveryStops=0
	var cancellations=0
	var canStart=true
	weak var discoveryDelegate:ShareExtensionDelegate?
	var attempts:[ShareExtensionDelegate]=[]
	func startDeviceDiscovery(){discoveryStarts+=1}
	func stopDeviceDiscovery(){discoveryStops+=1}
	func addShareExtensionDelegate(_ delegate:ShareExtensionDelegate){discoveryDelegate=delegate}
	func removeShareExtensionDelegate(_ delegate:ShareExtensionDelegate){discoveryDelegate=nil}
	func startOutgoingTransfer(deviceID:String, delegate:ShareExtensionDelegate, urls:[URL]) -> Bool{
		if canStart{attempts.append(delegate)}
		return canStart
	}
	func cancelOutgoingTransfer(id:String){cancellations+=1}
	func generateQrCodeKey() -> String{String(repeating: "A", count: 48)}
	func clearQrCodeKey(){}
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
