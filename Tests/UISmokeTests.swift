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
		let window=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 680), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
		window.contentViewController=controller
		window.setContentSize(NSSize(width: 520, height: 680))
		controller.update(receiving: true, transfers: [])
		layout(window)
		controller.update(receiving: true, transfers: [], deviceName: "Studio Mac")
		expect(visible(controller.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Studio Mac"}), "The main header must use the configured device name")
		expect(visible(controller.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue.contains("choose “Studio Mac”")}), "Receiving instructions must match the configured advertised name")
		let duration=visible(controller.view).compactMap {$0 as? NSPopUpButton}.first!
		expect(duration.selectedItem?.title=="Indefinitely", "Receiving duration must default to Indefinitely")
		var selected:ReceivingDuration?
		controller.onDurationChange={selected=$0}
		duration.selectItem(withTag: ReceivingDuration.thirtyMinutes.rawValue)
		NSApp.sendAction(duration.action!, to: duration.target, from: duration)
		expect(selected == .thirtyMinutes, "The availability dropdown must forward duration changes")
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
		let settingsWindow=NSWindow(contentRect: NSRect(origin: .zero, size: SettingsViewController.defaultSize), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
		settingsWindow.contentViewController=settings
		settings.update(startReceivingOnLaunch: true, launchAtLogin: false, requiresLoginApproval: false, rememberedDeviceCount: 0)
		settings.updateUpdates(automatic: false, checking: false, currentVersion: "1.0.0", availableRelease: nil, status: "")
		layout(settingsWindow)
		expect(settings.selectedSection == .general, "Settings must open on General by default")
		expect(!visible(settings.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Check for Updates…"}), "Update controls must not clutter General settings")
		expect(visible(settings.view).compactMap({$0 as? CardView}).count==3, "General settings must group device name, startup, and remembered names")
		snapshot(settingsWindow, "settings-general")
		let sections=descendants(settings.view).compactMap {$0 as? NSSegmentedControl}.first!
		expect((0..<sections.segmentCount).map({sections.label(forSegment: $0)!})==["General","Updates","About"], "Settings must expose General, Updates, and About sections")
		sections.selectedSegment=SettingsViewController.Section.about.rawValue
		NSApp.sendAction(sections.action!, to: sections.target, from: sections)
		layout(settingsWindow)
		expect(settings.selectedSection == .about, "The native section control must switch Settings pages")
		for credit in ["Developed by Mark Andrey · github.com/markandreydc", "Based on NearDrop by grishka · github.com/grishka/NearDrop"]{
			let label=visible(settings.view).compactMap {$0 as? NSTextField}.first(where: {$0.stringValue==credit})
			expect(label != nil, "Settings must display the developer and upstream credits")
			if let label=label{expect(settings.view.bounds.contains(label.convert(label.bounds, to: settings.view)), "Settings credits must fit inside the window")}
		}
		expect(visible(settings.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Version 1.0.0"}), "About must show the installed app version")
		snapshot(settingsWindow, "settings-about")
		settings.show(.general)
		layout(settingsWindow)
		expect(!button("Forget all", in: settings.view).isEnabled, "Forget must be disabled when no names are stored")
		settings.update(startReceivingOnLaunch: false, launchAtLogin: false, requiresLoginApproval: true, rememberedDeviceCount: 3)
		expect(button("Forget all", in: settings.view).isEnabled, "Stored names should be forgettable")
		_ = button("Set up login item in System Settings…", in: settings.view)
		settings.show(.updates)
		layout(settingsWindow)
		expect(!visible(settings.view).compactMap({$0 as? NSTextField}).contains(where: {$0.identifier?.rawValue=="CustomDeviceName"}), "Device-name editing must stay on General")
		var updateChecks=0
		settings.onCheckForUpdates={updateChecks+=1}
		button("Check for Updates…", in: settings.view).performClick(nil)
		expect(updateChecks==1, "Settings must wire manual update checks")
		let automatic=button("Automatically check for updates daily", in: settings.view)
		expect(automatic.state == .off, "Automatic update checks must be opt-in")
		var automaticEnabled=false
		settings.onAutomaticUpdateChecksChange={automaticEnabled=$0}
		automatic.performClick(nil)
		expect(automaticEnabled, "Settings must forward the automatic-check preference")
		settings.updateUpdates(automatic: true, checking: true, currentVersion: "1.0.0", availableRelease: nil, status: "Checking for updates…")
		expect(!button("Checking for updates…", in: settings.view).isEnabled, "A pending check must disable duplicate manual checks")
		let release=UpdateRelease(tagName: "v1.1.0", pageURL: URL(string: "https://github.com/markandreydc/QuickShareMac/releases/tag/v1.1.0")!)
		settings.updateUpdates(automatic: true, checking: false, currentVersion: "1.0.0", availableRelease: release, status: "Update available: v1.1.0")
		var viewed=false
		settings.onViewRelease={viewed=true}
		button("View Release", in: settings.view).performClick(nil)
		expect(viewed, "Settings must expose a release-page action for an available update")
		layout(settingsWindow)
		for title in ["Check for Updates…", "View Release", "Automatically check for updates daily"]{
			let control=button(title, in: settings.view)
			expect(settings.view.bounds.contains(control.convert(control.bounds, to: settings.view)), "Update controls must fit in Settings")
		}
		snapshot(settingsWindow, "settings")
		snapshot(settingsWindow, "settings-updates")
		settings.update(startReceivingOnLaunch: false, launchAtLogin: false, requiresLoginApproval: true, rememberedDeviceCount: 3)
		expect(settings.selectedSection == .updates, "State refreshes must preserve the selected Settings section")
		settings.show(.general)
		layout(settingsWindow)
		let nameField=descendants(settings.view).compactMap {$0 as? NSTextField}.first(where: {$0.identifier?.rawValue=="CustomDeviceName"})!
		var savedNames:[String?]=[]
		settings.onDeviceNameChange={savedNames.append($0)}
		nameField.stringValue="  Studio Mac  "
		settingsWindow.makeFirstResponder(nameField)
		expect(nameField.currentEditor() != nil, "The device name field must be focused before testing save")
		button("Save name", in: settings.view).performClick(nil)
		expect(savedNames.count==1 && savedNames[0]=="Studio Mac", "Settings must trim and save a custom device name once; got \(savedNames)")
		expect(nameField.currentEditor()==nil, "Saving a valid name must remove focus from the field")
		expect(nameField.stringValue=="Studio Mac", "The saved field must display the trimmed name")
		nameField.stringValue="bad\nname"
		settingsWindow.makeFirstResponder(nameField)
		button("Save name", in: settings.view).performClick(nil)
		expect(savedNames.count==1, "Invalid names must not be saved")
		expect(nameField.currentEditor() != nil, "Invalid names must retain focus for correction")
		settingsWindow.setContentSize(NSSize(width: 520, height: 500))
		layout(settingsWindow)
		let settingsScroll=visible(settings.view).compactMap {$0 as? NSScrollView}.first!
		expect(settingsScroll.documentView!.frame.width==settingsScroll.contentView.bounds.width, "Settings pages must fit horizontally at minimum size")
		expect(settingsScroll.documentView!.frame.height>settingsScroll.contentView.bounds.height, "Expanded validation messages must scroll rather than clip at minimum size")
		snapshot(settingsWindow, "settings-validation")
		button("Use Mac’s name", in: settings.view).performClick(nil)
		expect(savedNames.count==2 && savedNames[1]==nil, "Reset must restore the system name rather than save an empty name")
		settingsWindow.setContentSize(NSSize(width: 700, height: 650))
		settings.view.appearance=NSAppearance(named: .darkAqua)
		settings.show(.updates)
		layout(settingsWindow)
		expect(button("Check for Updates…", in: settings.view).isEnabled, "Settings actions must remain usable after resizing and changing appearance")
		snapshot(settingsWindow, "settings-dark-updates")

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
		testUpdateResultPresentation()
		testIdentityAndAvailability()
		print("Passed \(checks) UI smoke checks")
	}

	static func testStatusBarMenu(){
		let controller=StatusBarMenu()
		var receiving=false
		var canSendFiles=true
		var duration:ReceivingDuration = .indefinitely
		var expiresAt:Date?
		var checkingForUpdates=false
		var updateVersion:String?
		controller.stateProvider={StatusBarMenu.State(receiving: receiving, canSendFiles: canSendFiles, deviceName: "Studio Mac", duration: duration, expiresAt: expiresAt, checkingForUpdates: checkingForUpdates, availableUpdateVersion: updateVersion)}
		let item=NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		defer{NSStatusBar.system.removeStatusItem(item)}
		controller.attach(to: item)
		expect(item.menu === controller.menu, "A native status-item menu must handle normal clicks")
		expect(item.button?.action==nil && item.button?.target==nil, "Status clicks must not use a custom window-opening action")
		expect(item.button?.image?.isTemplate==true, "The menu bar icon must let macOS choose its tint")
		expect(controller.menu.appearance==nil, "The status menu must not force a light or dark appearance")
		expect(controller.menu.items.allSatisfy({$0.view==nil && $0.attributedTitle==nil}), "Menu items must use native views and text colors")
		controller.menuNeedsUpdate(controller.menu)
		let device=controller.menu.items.first(where: {$0.title=="Device: Studio Mac"})!
		expect(!device.isEnabled && device.action==nil, "The status menu must display the device name read-only")
		expect(controller.menu.items.contains(where: {$0.title=="Not visible · Receiving off" && !$0.isEnabled}), "The visibility label must not imply discovery is enabled when receiving is off")
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
		expect(controller.menu.items.contains(where: {$0.title=="Visible to everyone on your network" && !$0.isEnabled && $0.action==nil}), "Visibility must be a read-only informational item")
		controller.onDurationChange={duration=$0; expiresAt=$0 == .indefinitely ? nil : Date().addingTimeInterval(TimeInterval($0.rawValue))}
		let durations=controller.menu.items.first(where: {$0.submenu != nil})!.submenu!
		expect(durations.items.map(\.title)==["10 minutes","30 minutes","1 hour","Indefinitely"], "The native duration submenu must expose all requested choices")
		durations.performActionForItem(at: durations.indexOfItem(withTitle: "10 minutes"))
		expect(duration == .tenMinutes && durations.item(at: 0)?.state == .on, "Menu duration changes must update the selected checkmark")
		expect(controller.menu.items.contains(where: {$0.title.hasPrefix("Available until ") && !$0.isHidden && !$0.isEnabled}), "Timed receiving must show its deadline read-only")
		durations.performActionForItem(at: durations.indexOfItem(withTitle: "Indefinitely"))
		expect(duration == .indefinitely && controller.menu.items.filter({$0.title.hasPrefix("Available until ")}).allSatisfy(\.isHidden), "Indefinite receiving must hide the obsolete deadline")
		expect(controller.toolTip.contains("Click for menu") && !controller.toolTip.contains("right-click"), "The tooltip must describe the new click behavior")
		var settings=false
		controller.onSettings={settings=true}
		controller.menu.performActionForItem(at: controller.menu.indexOfItem(withTitle: "Settings…"))
		expect(settings, "Settings must remain available in the native menu")
		var updateChecks=0
		controller.onCheckForUpdates={updateChecks+=1}
		let checkIndex=controller.menu.indexOfItem(withTitle: "Check for Updates…")
		controller.menu.performActionForItem(at: checkIndex)
		expect(updateChecks==1, "The status menu must wire manual update checks")
		checkingForUpdates=true
		controller.refresh()
		expect(!controller.menu.item(at: checkIndex)!.isEnabled, "The status menu must disable checks while one is pending")
		controller.menu.performActionForItem(at: checkIndex)
		expect(updateChecks==1, "Repeated actions must not start overlapping checks")
		checkingForUpdates=false
		updateVersion="v1.1.0"
		controller.refresh()
		let available=controller.menu.items.first(where: {$0.title=="Update available: v1.1.0"})!
		expect(!available.isHidden, "A background update must be visible without an interrupting dialog")
		var opened=false
		controller.onViewRelease={opened=true}
		controller.menu.performActionForItem(at: controller.menu.index(of: available))
		expect(opened, "The available-update item must open the release page")
		updateVersion=nil
		controller.refresh()
		expect(available.isHidden, "The menu must hide update availability when none is known")
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

	static func testUpdateResultPresentation(){
		let settings=SettingsViewController()
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: SettingsViewController.defaultSize), styleMask: [.titled], backing: .buffered, defer: false)
		window.contentViewController=settings
		settings.show(.about)
		defer{window.orderOut(nil)}
		let release=UpdateRelease(tagName: "v1.1.0", pageURL: URL(string: "https://github.com/markandreydc/QuickShareMac/releases/tag/v1.1.0")!)
		let cases:[(Result<UpdateChecker.Outcome,UpdateCheckError>,String,Bool,URL?)]=[
			(.success(.upToDate),"You're up to date.",false,nil),
			(.success(.noRelease),"No published stable release is available yet.",false,nil),
			(.failure(.offline),"Couldn't check for updates",false,nil),
			(.success(.available(release)),"A QuickShareMac update is available",false,nil),
			(.success(.available(release)),"A QuickShareMac update is available",true,release.pageURL),
			(.failure(.server),"Couldn't check for updates",true,UpdateChecker.releasesURL)
		]
		for (index,test) in cases.enumerated(){
			// Also cover an already-open Settings window: checking must neither
			// navigate away from About nor attach a sheet to it.
			if index==cases.count-1{window.orderFront(nil)}
			let settingsWasVisible=window.isVisible
			let presenter=UpdateResultPresenter()
			var opened:[URL]=[]
			presenter.openURL={opened.append($0)}
			var inspected=false
			let dismiss=Timer(timeInterval: 0.05, repeats: false){ _ in
				guard let alert=presenter.alert else {fatalError("The update result must display an alert")}
				inspected=true
				expect(alert.messageText==test.1, "Manual check results must retain the correct message")
				expect(alert.window.isVisible && alert.window.sheetParent==nil, "Update results must use a standalone native dialog, not a Settings sheet")
				expect(window.isVisible==settingsWasVisible && window.attachedSheet==nil, "Checking for updates must not open Settings or attach a sheet to it")
				expect(settings.selectedSection == .about, "Update results must not navigate Settings to another section")
				presenter.show(test.0, currentVersion: "1.0.0")
				expect(presenter.alert === alert, "Repeated checks must reuse the existing result dialog")
				let button=test.2 ? alert.buttons[0] : alert.buttons.last!
				button.performClick(nil)
			}
			RunLoop.main.add(dismiss, forMode: .modalPanel)
			presenter.show(test.0, currentVersion: "1.0.0")
			dismiss.invalidate()
			expect(inspected && presenter.alert==nil, "Dismissing a result must clear its presentation state")
			expect(opened==(test.3.map {[$0]} ?? []), "Only View Release may open the expected GitHub page")
		}
	}

	static func testIdentityAndAvailability(){
		let domain="QuickShareMac.Tests."+UUID().uuidString
		let preferences=UserDefaults(suiteName: domain)!
		defer{preferences.removePersistentDomain(forName: domain)}
		let identity=LocalDeviceIdentity(preferences: preferences, systemName: {"System Mac"})
		expect(identity.deviceName=="System Mac" && identity.customName==nil, "An unset device name must follow the Mac's system name")
		try! identity.setCustomName("  Travel Mac 🖥️  ")
		expect(identity.deviceName=="Travel Mac 🖥️", "Unicode device names must be stored without surrounding whitespace")
		expect(LocalDeviceIdentity(preferences: UserDefaults(suiteName: domain)!).customName=="Travel Mac 🖥️", "The custom name must persist across identity instances")
		for invalid in ["   ","bad\u{0000}name",String(repeating: "😀", count: 64),String(repeating: "a", count: LocalDeviceIdentity.maximumNameBytes+1)]{
			do{try identity.setCustomName(invalid); expect(false, "Invalid device name was accepted")}
			catch{expect(identity.deviceName=="Travel Mac 🖥️", "Invalid input must preserve the existing name")}
		}
		try! identity.setCustomName(nil)
		expect(identity.deviceName=="System Mac", "Reset must remove the override")
		let longSystem=LocalDeviceIdentity(preferences: preferences, systemName: {String(repeating: "😀", count: 100)})
		expect(longSystem.deviceName.utf8.count<=LocalDeviceIdentity.maximumNameBytes && longSystem.deviceName.allSatisfy({$0=="😀"}), "System-name truncation must preserve UTF-8 character boundaries")
		var now=Date(timeIntervalSince1970: 100000)
		let availability=ReceivingAvailability(preferences: preferences, now: {now})
		var expirations=0
		availability.onExpiration={expirations+=1}
		expect(availability.duration == .indefinitely, "Fresh installations must remain available indefinitely by default")
		availability.started()
		expect(availability.expiresAt==nil, "Indefinite receiving must not schedule an expiration")
		availability.select(.tenMinutes)
		expect(availability.expiresAt==now.addingTimeInterval(600), "Selecting 10 minutes while receiving must start a new deadline")
		now=now.addingTimeInterval(599)
		availability.checkExpiration()
		expect(availability.active && expirations==0, "Receiving must stay enabled before its deadline")
		now=now.addingTimeInterval(1)
		availability.checkExpiration()
		availability.checkExpiration()
		expect(!availability.active && expirations==1, "Expiry must stop receiving exactly once, including after a delayed wake")
		availability.select(.thirtyMinutes)
		expect(!availability.active && availability.expiresAt==nil, "Changing duration while off must not enable receiving")
		availability.started()
		expect(availability.expiresAt==now.addingTimeInterval(1800), "A new session must use the selected duration")
		availability.select(.oneHour)
		expect(availability.expiresAt==now.addingTimeInterval(3600), "Changing duration must replace the previous deadline")
		now=now.addingTimeInterval(4000)
		availability.checkExpiration()
		expect(expirations==2, "A deadline passed during sleep must expire immediately when checked")
		availability.started()
		availability.select(.indefinitely)
		now=now.addingTimeInterval(100000)
		availability.checkExpiration()
		expect(availability.active && availability.expiresAt==nil && expirations==2, "Choosing Indefinitely must cancel the old timer")
		availability.stopped()
		availability.select(.tenMinutes)
		expect(ReceivingAvailability(preferences: preferences).duration == .tenMinutes, "The selected duration must persist, without persisting a live receiving session")
	}

	static func testMainWindowSending(){
		let service=FakeSendingService()
		let main=MainWindowViewController()
		main.sendController.sender.service=service
		let window=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 680), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
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
