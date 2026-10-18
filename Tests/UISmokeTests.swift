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
	static func itemTable(in view:NSView)->SelectedItemsTableView{
		descendants(view).compactMap {$0 as? SelectedItemsTableView}.first!
	}
	static func itemNames(in view:NSView)->[NSTextField]{
		let table=itemTable(in: view)
		return (0..<table.numberOfRows).compactMap {row in
			(table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField
		}
	}
	static func button(_ title:String, in view:NSView) -> NSButton{
		guard let button=visible(view).compactMap({$0 as? NSButton}).first(where: {$0.title==title}) else {fatalError("Missing button: \(title)")}
		return button
	}
	static func layout(_ window:NSWindow){
		window.contentView?.needsLayout=true
		window.contentView?.layoutSubtreeIfNeeded()
	}
	@discardableResult static func waitUntil(timeout:TimeInterval = 15, _ condition:()->Bool)->Bool{
		let deadline=Date().addingTimeInterval(timeout)
		while !condition(){
			if Date()>deadline{return false}
			RunLoop.main.run(until: Date().addingTimeInterval(0.02))
		}
		return true
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
		// Standalone test executables do not have the app's asset catalog. Load
		// the unchanged brand artwork so snapshots exercise the actual header.
		let root=URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
		let brandImage=NSImage(contentsOf: root.appendingPathComponent("QuickShareMac/Assets.xcassets/QuickShareMacBrandIcon.imageset/QuickShareMacBrandIcon@2x.png"))!
		brandImage.setName("QuickShareMacBrandIcon")
		let controller=MainWindowViewController()
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowViewController.minimumSize), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
		window.contentViewController=controller
		window.setContentSize(MainWindowViewController.minimumSize)
		controller.update(receiving: true, transfers: [])
		layout(window)
		controller.update(receiving: true, transfers: [], deviceName: "Studio Mac")
		let pin=visible(controller.view).compactMap {$0 as? NSButton}.first(where: {$0.identifier?.rawValue=="AlwaysOnTopPin"})!
		func togglePin(){pin.performClick(nil)}
		let otherWindow=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
		var pinChanges:[Bool]=[]
		controller.onAlwaysOnTopChange={pinChanges.append($0)}
		expect(pin.state == .off && window.level == .normal && !controller.isAlwaysOnTop, "Always on top must be off by default")
		let pinFrame=pin.convert(pin.bounds, to: controller.view)
		expect(pinFrame.midX>controller.view.bounds.midX && pinFrame.midY>controller.view.bounds.maxY-72, "The pin button must sit at the upper-right of the main window")
		expect(pin.image != nil && pin.menu==nil && !visible(controller.view).contains(where: {$0.identifier?.rawValue=="MainOverflow"}), "Always on top must use a direct pin button instead of an overflow menu")
		togglePin()
		expect(pin.state == .on && controller.isAlwaysOnTop && window.level == .floating, "The pin button must keep the main window above normal windows")
		expect(pin.contentTintColor == .systemBlue, "The active pin must be highlighted blue")
		expect(pin.toolTip=="Turn off always on top" && otherWindow.level == .normal, "Pinning must explain how to turn it off and leave other windows unchanged")
		controller.showSend()
		controller.showReceive()
		expect(window.level == .floating && pin.state == .on, "Switching tabs must preserve the always-on-top state")
		togglePin()
		expect(pinChanges==[true,false] && window.level == .normal && pin.toolTip=="Keep window on top", "Clicking again must restore normal stacking and report each user change once")
		controller.setAlwaysOnTop(true)
		controller.viewDidAppear()
		expect(window.level == .floating && pinChanges==[true,false], "Restoring a saved pin setting must apply it without writing another user change")
		controller.setAlwaysOnTop(false)
		let settingsButton=button("Settings…", in: controller.view)
		let settingsFrame=settingsButton.convert(settingsButton.bounds, to: controller.view)
		expect(abs(settingsFrame.midY-pinFrame.midY)<1 && settingsFrame.maxX<pinFrame.minX, "Settings and the pin button must share the top-right toolbar")
		var openedSettings=false
		controller.onOpenSettings={openedSettings=true}
		settingsButton.performClick(nil)
		expect(openedSettings && settingsButton.image != nil, "The labeled Settings action must retain its callback and gear icon")
		let brand=visible(controller.view).compactMap {$0 as? NSImageView}.first(where: {$0.identifier?.rawValue=="MainBrandIcon"})!
		expect(brand.bounds.size==NSSize(width: 32, height: 32), "The original brand image must use the compact 32-point header size")
		expect(brand.image === brandImage, "The header must reuse the original brand artwork without replacement")
		let brandFrame=brand.convert(brand.bounds, to: controller.view)
		let appTitle=visible(controller.view).compactMap {$0 as? NSTextField}.first(where: {$0.identifier?.rawValue=="MainAppTitle"})!
		let titleFrame=appTitle.convert(appTitle.bounds, to: controller.view)
		expect(abs(brandFrame.minX-20)<1 && abs(brandFrame.midY-settingsFrame.midY)<1, "The compact brand must sit in the upper-left, on the Settings toolbar row")
		expect(appTitle.font?.pointSize==16 && titleFrame.minX>brandFrame.maxX && titleFrame.maxX<settingsFrame.minX, "The smaller app title must fit beside the logo without overlapping Settings")
		controller.update(receiving: true, transfers: [], deviceName: String(repeating: "Long Mac name ", count: 30))
		layout(window)
		let longTitleFrame=appTitle.convert(appTitle.bounds, to: controller.view)
		expect(longTitleFrame.maxX<settingsButton.convert(settingsButton.bounds, to: controller.view).minX && controller.view.bounds.contains(pin.convert(pin.bounds, to: controller.view)), "Long device names must not push toolbar actions out of the compact window")
		controller.update(receiving: true, transfers: [], deviceName: "Studio Mac")
		layout(window)
		let mode=visible(controller.view).compactMap {$0 as? NSSegmentedControl}.first!
		expect(mode.label(forSegment: 0)=="Send" && mode.label(forSegment: 1)=="Receive", "Transfer tabs must be arranged as Send then Receive")
		expect(mode.image(forSegment: 0) != nil && mode.image(forSegment: 1) != nil && mode.selectedSegment==1, "Both transfer tabs must have icons and keep Receive as the initial mode")
		expect(mode.segmentStyle == .smallSquare && settingsButton.bezelStyle == .regularSquare && pin.bezelStyle == .regularSquare, "Tabs and toolbar buttons must use less-rounded native styles")
		if #available(macOS 26.0, *){
			expect(mode.borderShape == .roundedRectangle && settingsButton.borderShape == .roundedRectangle && pin.borderShape == .roundedRectangle, "Modern macOS controls must use rounded rectangles rather than capsules")
		}
		expect((controller.view as? WindowBackgroundView)?.backgroundStyle == .soft, "The main window must use the shared soft background")
		let cards=visible(controller.view).compactMap {$0 as? CardView}
		expect(!cards.isEmpty && cards.allSatisfy(\.usesSoftAppearance), "Main window cards must use the rounded soft appearance")
		for appearance in [NSAppearance.Name.aqua,.darkAqua]{
			controller.view.appearance=NSAppearance(named: appearance)
			for card in cards{
				card.updateLayer()
				expect(card.layer?.cornerRadius==8 && card.layer?.borderWidth==1, "Soft cards must retain the reduced corner radius and border in both appearances")
			}
		}
		controller.view.appearance=nil
		let credit=visible(controller.view).compactMap {$0 as? NSTextField}.first(where: {$0.identifier?.rawValue=="MainDeveloperCreditFooter"})!
		func creditFrame()->NSRect{credit.convert(credit.bounds, to: controller.view)}
		expect(credit.stringValue=="Developed by Mark Andrey · github.com/markandreydc" && credit.alignment == .center, "The main window must show the centered developer credit")
		expect(abs(creditFrame().midX-controller.view.bounds.midX)<1 && abs(creditFrame().minY-controller.view.bounds.minY-20)<1, "The developer credit must sit at the bottom of the main window")
		var creditAncestor=credit.superview
		while let ancestor=creditAncestor{
			expect(!(ancestor is CardView) && !(ancestor is NSScrollView), "The main developer credit must sit outside cards and scrolling content")
			creditAncestor=ancestor.superview
		}
		controller.showSend()
		layout(window)
		expect(visible(controller.view).contains(where: {$0 === credit}) && abs(creditFrame().minY-controller.view.bounds.minY-20)<1, "The Send tab must keep the developer credit centered at the footer")
		controller.showReceive()
		layout(window)
		window.setContentSize(NSSize(width: 700, height: 640))
		layout(window)
		expect(abs(creditFrame().midX-controller.view.bounds.midX)<1 && abs(creditFrame().minY-controller.view.bounds.minY-20)<1, "The developer credit must stay centered at the bottom when the window resizes")
		window.setContentSize(MainWindowViewController.minimumSize)
		layout(window)
		let openReceived=button("Open Received Files", in: controller.view)
		let tabsControl=visible(controller.view).compactMap {$0 as? NSSegmentedControl}.first!
		let tabsFrame=tabsControl.convert(tabsControl.bounds, to: controller.view)
		let openFrame=openReceived.convert(openReceived.bounds, to: controller.view)
		expect(abs(openFrame.midY-tabsFrame.midY)<6 && openFrame.minX>tabsFrame.maxX && openFrame.midX>controller.view.bounds.midX, "Open Received Files must share the Receive/Send row on the right")
		expect(!visible(controller.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Open Downloads"}), "The old Open Downloads button must be removed")
		var openedReceived=false
		controller.onOpenReceivedFiles={openedReceived=true}
		openReceived.performClick(nil)
		expect(openedReceived, "Open Received Files must open the configured save folder")
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
		_ = accept.scrollToVisible(accept.bounds)
		layout(window)
		expect(accept.keyEquivalent.isEmpty, "Approval must not capture Return")
		expect(controller.view.bounds.contains(accept.convert(accept.bounds, to: controller.view)), "Approval controls must remain reachable by scrolling at the minimum window size")
		expect(abs(window.contentView!.bounds.height-MainWindowViewController.minimumSize.height)<1, "Incoming requests must scroll instead of expanding the window: actual \(window.contentView!.bounds.height), minimum \(MainWindowViewController.minimumSize.height)")
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
		_ = longAccept.scrollToVisible(longAccept.bounds)
		layout(window)
		let actionBounds=longAccept.convert(longAccept.bounds, to: controller.view)
		expect(controller.view.bounds.contains(actionBounds), "Long sender names and filenames must not push approval controls outside the window")
		expect(abs(window.contentView!.bounds.height-MainWindowViewController.minimumSize.height)<1, "Even long approval requests must not force the window taller")
		let history=(0..<20).map {transfer("history-\($0)", .completed)}
		controller.update(receiving: true, transfers: [transfer("active", .receiving)]+history)
		layout(window)
		let scroll=visible(controller.view).compactMap {$0 as? NSScrollView}.first!
		expect(scroll.documentView!.frame.height>scroll.contentView.bounds.height, "Recent transfers must scroll instead of expanding the window")
		scroll.contentView.scroll(to: NSPoint(x: 0, y: 150))
		let origin=scroll.contentView.bounds.origin
		controller.update(receiving: true, transfers: [transfer("active", .receiving, progress: 0.9)]+history)
		expect(scroll.contentView.bounds.origin==origin, "Progress updates must preserve scroll position")
		controller.update(receiving: true, transfers: [transfer("fresh", .awaitingApproval, pin: "1234"), transfer("active", .receiving)]+history)
		expect(scroll.contentView.bounds.origin == .zero, "A new approval request must scroll back to the top so its PIN is visible")
		window.setContentSize(NSSize(width: 760, height: 900))
		layout(window)
		expect(visible(controller.view).compactMap({$0 as? NSScrollView}).first!.frame.width>600, "Transfer list must expand with the window")

		let settings=SettingsViewController()
		let settingsWindow=NSWindow(contentRect: NSRect(origin: .zero, size: SettingsViewController.defaultSize), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
		settingsWindow.contentViewController=settings
		settings.update(startReceivingOnLaunch: true, launchAtLogin: false, requiresLoginApproval: false, rememberedDeviceCount: 0)
		settings.updateUpdates(frequency: .never, checking: false, currentVersion: "1.0.0", availableRelease: nil, status: "")
		layout(settingsWindow)
		expect(settings.selectedSection == .general, "Settings must open on General by default")
		expect(!visible(settings.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Check for Updates…"}), "Update controls must not clutter General settings")
		expect(visible(settings.view).compactMap({$0 as? CardView}).count==5, "General settings must group device name, startup, remembered names, received files, and sending")
		expect(visible(settings.view).compactMap({$0 as? CardView}).allSatisfy(\.usesSoftAppearance), "Settings cards must match the main window's soft appearance")
		let compress=button("Compress folders into ZIP files before sending", in: settings.view)
		expect(compress.state == .off, "Folder compression must default to off")
		var compressionChanges:[Bool]=[]
		settings.onCompressFoldersChange={compressionChanges.append($0)}
		compress.performClick(nil)
		expect(compressionChanges==[true], "The compression checkbox must forward changes")
		settings.update(startReceivingOnLaunch: true, launchAtLogin: false, requiresLoginApproval: false, rememberedDeviceCount: 0, compressFolders: false)
		expect(compress.state == .off, "Settings must display the saved compression choice")
		let folderLabel=visible(settings.view).compactMap({$0 as? NSTextField}).first(where: {$0.identifier?.rawValue=="ReceivedFilesFolder"})!
		expect(folderLabel.stringValue=="Downloads" && visible(settings.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Save received files to:"}), "Settings must show the received-files folder with Downloads as the default")
		expect(!visible(settings.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Use Downloads"}), "Use Downloads must stay hidden while the default folder is active")
		var folderChoices=0
		settings.onChooseReceivedFilesFolder={folderChoices+=1}
		button("Choose…", in: settings.view).performClick(nil)
		expect(folderChoices==1, "Choose… must open the folder picker through the settings callback")
		var folderResets=0
		settings.onUseDownloadsFolder={folderResets+=1}
		settings.update(startReceivingOnLaunch: true, launchAtLogin: false, requiresLoginApproval: false, rememberedDeviceCount: 0, receivedFilesFolderName: "Shared Inbox", receivedFilesFolderIsCustom: true)
		expect(folderLabel.stringValue=="Shared Inbox", "Settings must show the custom received-files folder")
		button("Use Downloads", in: settings.view).performClick(nil)
		expect(folderResets==1, "Use Downloads must reset through the settings callback")
		settings.update(startReceivingOnLaunch: true, launchAtLogin: false, requiresLoginApproval: false, rememberedDeviceCount: 0)
		expect(folderLabel.stringValue=="Downloads" && !visible(settings.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Use Downloads"}), "Settings must restore the default folder state")
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
		let developerFooter=visible(settings.view).compactMap {$0 as? NSTextField}.first(where: {$0.identifier?.rawValue=="DeveloperCreditFooter"})!
		for size in [SettingsViewController.defaultSize,NSSize(width: 520, height: 500),NSSize(width: 700, height: 650)]{
			settingsWindow.setContentSize(size)
			layout(settingsWindow)
			let frame=developerFooter.convert(developerFooter.bounds, to: settings.view)
			expect(developerFooter.alignment == .center && abs(frame.midX-settings.view.bounds.midX)<1, "The developer footer must remain horizontally centered when Settings resizes")
			expect(abs(frame.minY-settings.view.bounds.minY-20)<1, "The developer credit must use the same bottom inset as the main window")
		}
		var footerAncestor=developerFooter.superview
		while let ancestor=footerAncestor{
			expect(!(ancestor is CardView) && !(ancestor is NSScrollView), "The developer footer must sit outside credits cards and scrolling content")
			footerAncestor=ancestor.superview
		}
		settingsWindow.setContentSize(SettingsViewController.defaultSize)
		layout(settingsWindow)
		expect(visible(settings.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Version 1.0.0"}), "About must show the installed app version")
		snapshot(settingsWindow, "settings-about")
		settings.show(.general)
		layout(settingsWindow)
		expect(visible(settings.view).contains(where: {$0 === developerFooter}), "The shared developer footer must remain visible on General")
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
		let frequency=visible(settings.view).compactMap {$0 as? NSPopUpButton}.first(where: {$0.identifier?.rawValue=="UpdateCheckFrequency"})!
		expect(frequency.itemTitles==["Daily","Weekly","Monthly","Never"], "The update dropdown must offer all four frequencies in order")
		expect(frequency.selectedItem?.title=="Never", "Automatic update checks must default to Never")
		var selectedFrequency:UpdateCheckFrequency?
		settings.onUpdateCheckFrequencyChange={selectedFrequency=$0}
		for (index,value) in UpdateCheckFrequency.allCases.enumerated(){
			frequency.selectItem(at: index)
			NSApp.sendAction(frequency.action!, to: frequency.target, from: frequency)
			expect(selectedFrequency==value, "Settings must forward the selected update frequency: \(value)")
		}
		settings.updateUpdates(frequency: .weekly, checking: true, currentVersion: "1.0.0", availableRelease: nil, status: "Checking for updates…")
		expect(frequency.selectedItem?.title=="Weekly" && frequency.isEnabled, "A pending check must preserve the frequency and allow disabling future checks")
		expect(!button("Checking for updates…", in: settings.view).isEnabled, "A pending check must disable duplicate manual checks")
		let release=UpdateRelease(tagName: "v1.1.0", pageURL: URL(string: "https://github.com/markandreydc/QuickShareMac/releases/tag/v1.1.0")!)
		settings.updateUpdates(frequency: .monthly, checking: false, currentVersion: "1.0.0", availableRelease: release, status: "Update available: v1.1.0")
		expect(frequency.selectedItem?.title=="Monthly", "Refreshing Settings must display the saved update frequency")
		var viewed=false
		settings.onViewRelease={viewed=true}
		button("View Release", in: settings.view).performClick(nil)
		expect(viewed, "Settings must expose a release-page action for an available update")
		layout(settingsWindow)
		for title in ["Check for Updates…", "View Release"]{
			let control=button(title, in: settings.view)
			expect(settings.view.bounds.contains(control.convert(control.bounds, to: settings.view)), "Update controls must fit in Settings")
		}
		expect(settings.view.bounds.contains(frequency.convert(frequency.bounds, to: settings.view)), "The frequency dropdown must fit inside Settings")
		snapshot(settingsWindow, "settings")
		snapshot(settingsWindow, "settings-updates")
		settings.update(startReceivingOnLaunch: false, launchAtLogin: false, requiresLoginApproval: true, rememberedDeviceCount: 3)
		expect(settings.selectedSection == .updates, "State refreshes must preserve the selected Settings section")
		settings.show(.general)
		layout(settingsWindow)
		let nameField=descendants(settings.view).compactMap {$0 as? NSTextField}.first(where: {$0.identifier?.rawValue=="CustomDeviceName"})!
		let nameMessage=descendants(settings.view).compactMap {$0 as? NSTextField}.first(where: {$0.identifier?.rawValue=="DeviceNameMessage"})!
		let systemName=button("Use Mac’s name", in: settings.view)
		let customName=button("Use a custom name", in: settings.view)
		let saveName=button("Save changes", in: settings.view)
		let cancelName=button("Cancel", in: settings.view)
		var savedNames:[String?]=[]
		var storedName:String?
		func refreshNameSettings(){
			settings.update(startReceivingOnLaunch: false, launchAtLogin: false, requiresLoginApproval: true, rememberedDeviceCount: 3, customDeviceName: storedName, systemDeviceName: "System Mac")
		}
		func editName(_ value:String){
			settingsWindow.makeFirstResponder(nil)
			nameField.stringValue=value
			settings.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: nameField))
			settingsWindow.makeFirstResponder(nameField)
		}
		settings.onDeviceNameChange={name in
			savedNames.append(name)
			storedName=name
			refreshNameSettings() // Match the app's synchronous refresh after persistence.
		}
		refreshNameSettings()
		expect(systemName.state == .on && customName.state == .off && nameField.isHidden, "The default must explicitly select the Mac's name and hide custom input")
		expect(nameMessage.isHidden && !saveName.isEnabled && !cancelName.isEnabled, "Untouched name settings must not show an error or enable Save/Cancel")
		expect(visible(settings.view).compactMap({$0 as? NSTextField}).contains(where: {$0.identifier?.rawValue=="SystemDeviceName" && $0.stringValue=="System Mac"}), "The system-name option must show the actual advertised fallback")
		customName.performClick(nil)
		expect(customName.state == .on && systemName.state == .off && !nameField.isHidden, "Choosing Custom must reveal its input and deselect the system option")
		expect(nameField.stringValue=="System Mac" && saveName.isEnabled && savedNames.isEmpty, "Custom names must be prefilled without saving until explicitly approved")
		editName("  Studio Mac  ")
		expect(nameField.currentEditor() != nil, "The device name field must be focused before testing save")
		saveName.performClick(nil)
		expect(savedNames.count==1 && savedNames[0]=="Studio Mac", "Settings must trim and save a custom device name once; got \(savedNames)")
		expect(nameField.currentEditor()==nil, "Saving a valid name must remove focus from the field")
		expect(nameField.stringValue=="Studio Mac", "The saved field must display the trimmed name")
		expect(!saveName.isEnabled && !cancelName.isEnabled && nameMessage.stringValue=="Device name updated.", "Successful saves must confirm the change and clear dirty state")
		refreshNameSettings()
		expect(!nameMessage.isHidden && nameMessage.stringValue=="Device name updated.", "Background refreshes must preserve the save confirmation")
		editName("  Studio Mac  ")
		expect(!saveName.isEnabled && cancelName.isEnabled, "Whitespace-only differences must not enable a redundant save")
		cancelName.performClick(nil)
		editName("Uncommitted name")
		refreshNameSettings()
		expect(nameField.stringValue=="Uncommitted name", "Refreshes must preserve focused name drafts")
		settingsWindow.makeFirstResponder(nil)
		refreshNameSettings()
		expect(nameField.stringValue=="Uncommitted name" && savedNames.count==1, "Losing focus and refreshing must neither discard nor save a draft")
		settings.show(.updates)
		settings.show(.general)
		expect(nameField.stringValue=="Uncommitted name", "Switching Settings sections must preserve the draft without saving")
		cancelName.performClick(nil)
		expect(nameField.stringValue=="Studio Mac" && savedNames.count==1 && !cancelName.isEnabled, "Cancel must restore the saved name without a persistence callback")
		for blank in ["","   "]{
			editName(blank)
			expect(!saveName.isEnabled && cancelName.isEnabled, "Empty and whitespace-only custom names must disable Save")
			expect(!nameMessage.isHidden && nameMessage.stringValue=="Enter a name or select Use Mac’s name." && nameMessage.textColor == .secondaryLabelColor, "Blank custom input must show neutral guidance, not a technical validation error")
		}
		editName("bad\nname")
		settings.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: nameField))
		expect(!saveName.isEnabled && nameMessage.stringValue=="Remove line breaks or control characters.", "Invalid characters must get a specific inline message")
		editName(String(repeating: "😀", count: 43))
		expect(!saveName.isEnabled && nameMessage.stringValue=="Name is too long. Try a shorter name.", "Overlong Unicode names must get a friendly error while respecting the byte limit")
		expect(savedNames.count==1, "Invalid drafts must never be persisted")
		settingsWindow.setContentSize(NSSize(width: 520, height: 500))
		layout(settingsWindow)
		let settingsScroll=visible(settings.view).compactMap {$0 as? NSScrollView}.first!
		expect(settingsScroll.documentView!.frame.width==settingsScroll.contentView.bounds.width, "Settings pages must fit horizontally at minimum size")
		expect(settingsScroll.documentView!.frame.height>settingsScroll.contentView.bounds.height, "Expanded validation messages must scroll rather than clip at minimum size")
		snapshot(settingsWindow, "settings-validation")
		cancelName.performClick(nil)
		systemName.performClick(nil)
		expect(nameField.isHidden && saveName.isEnabled && savedNames.count==1, "Selecting the system name must be a draft, not an immediate reset")
		cancelName.performClick(nil)
		expect(customName.state == .on && nameField.stringValue=="Studio Mac" && !saveName.isEnabled, "Cancel must also restore the saved naming mode")
		systemName.performClick(nil)
		saveName.performClick(nil)
		expect(savedNames.count==2 && savedNames[1]==nil && nameField.isHidden, "Saving the system option must clear the custom name, not persist a copied system name")
		settings.onDeviceNameChange={_ in throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey:"Could not save the device name."])}
		customName.performClick(nil)
		editName("Retry this name")
		saveName.performClick(nil)
		expect(saveName.isEnabled && nameField.stringValue=="Retry this name" && nameMessage.stringValue=="Could not save the device name.", "Persistence failures must preserve the draft and report failure instead of success")
		cancelName.performClick(nil)
		expect(systemName.state == .on && nameField.isHidden && nameMessage.isHidden, "Cancel after a failed save must restore the persisted mode and clear feedback")
		storedName="Existing custom Mac"
		refreshNameSettings()
		expect(customName.state == .on && nameField.stringValue=="Existing custom Mac" && !saveName.isEnabled && !cancelName.isEnabled, "An existing saved custom name must load as a clean custom selection")
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
		let qrSender=SendTransferViewController()
		qrSender.service=FakeSendingService()
		sendWindow.contentViewController=qrSender
		try! qrSender.configureItems([URL(string: "https://example.com")!])
		expect(button("Connect with QR code…", in: qrSender.view).isEnabled, "QR connection must be enabled after loading attachments")
		qrSender.useQrCode(nil)
		expect(sendWindow.sheets.count==1, "QR connection should open a native sheet")
		if let sheet=sendWindow.sheets.first{
			layout(sheet)
			let image=descendants(sheet.contentView!).compactMap {$0 as? NSImageView}.first!.image!
			let request=VNDetectBarcodesRequest()
			try! VNImageRequestHandler(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!, options: [:]).perform([request])
			expect(request.results?.first?.payloadStringValue?.hasPrefix("https://quickshare.google/qrcode#key=")==true, "Generated QR code must be readable by a barcode scanner")
			snapshot(sheet, "qr-connection")
		}
		qrSender.dismissQrCodeSheet(nil)
		expect(sendWindow.sheets.isEmpty, "Cancel must dismiss the QR sheet")
		qrSender.shutdown()
		let folderSender=FolderShareController()
		sendWindow.contentViewController=folderSender
		expect(waitUntil{folderSender.handedOff != nil}, "The Share extension must hand folders to the main app instead of transferring them itself")
		expect(folderSender.handedOff == .files([URL(fileURLWithPath: "/")]), "The extension must hand over exactly the shared folder URLs")
		expect(folderSender.completed, "The Share panel must complete its request after the handoff")
		expect(visible(folderSender.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue.contains("Opening QuickShareMac")}), "The Share panel must explain that the main window opens")
		snapshot(sendWindow, "share-handoff-folder")
		let linkSender=LinkShareController()
		sendWindow.contentViewController=linkSender
		expect(waitUntil{linkSender.handedOff != nil}, "The Share extension must hand links to the main app")
		expect(linkSender.handedOff == .link(URL(string: "https://example.com")!), "A shared link must keep its exact URL")
		expect(linkSender.completed, "The Share panel must complete its request after handing over a link")
		expect(visible(linkSender.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="https://example.com"}), "The Share panel must preview the shared link")
		let unsupportedSender=UnsupportedShareController()
		sendWindow.contentViewController=unsupportedSender
		expect(waitUntil{visible(unsupportedSender.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Can’t send these items"})}, "Unsupported share attachments must be reported in the panel")
		expect(unsupportedSender.handOffCalls==0, "Unsupported share attachments must never reach the main app")
		expect(!visible(unsupportedSender.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Retry"}), "Unsupported items must not offer a retry that cannot succeed")
		button("Cancel", in: unsupportedSender.view).performClick(nil)
		expect(unsupportedSender.canceled, "Cancel must abort the share request")
		let failingSender=FailingShareController()
		sendWindow.contentViewController=failingSender
		expect(waitUntil{visible(failingSender.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Couldn’t open QuickShareMac"})}, "A failed handoff must be reported in the panel")
		expect(visible(failingSender.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Simulated failure"}), "A failed handoff must show the underlying reason")
		button("Retry", in: failingSender.view).performClick(nil)
		expect(waitUntil{failingSender.completed}, "Retry must attempt the handoff again and dismiss when it succeeds")
		expect(failingSender.handOffCalls==2, "Retry must not hand off more than one additional time")
		controller.view.appearance=NSAppearance(named: .darkAqua)
		controller.update(receiving: true, transfers: [transfer("dark", .awaitingApproval), transfer("done", .completed)])
		layout(window)
		snapshot(window, "dark-approval")
		expect(button("Accept", in: controller.view).isEnabled, "Approval must remain usable in dark mode")
		testMainWindowSending()
		testShareHandoff()
		testSelectedItemList()
		testSelectedItemActions()
		testRemoveAllSelectedItems()
		testFolderCompression()
		testFolderSendingWithoutCompression()
		testFileDropExperience()
		testTransferRateEstimator()
		testIncomingRequestPresentation()
		testStatusBarMenu()
		testUpdateResultPresentation()
		testIdentityAndAvailability()
		testReceivedFilesFolder()
		testSettingsDefaults()
		testDynamicWindowHeight()
		testMainWindowAppearance()
		testCompactReceiveInstructions()
		testSettingsAppearance()
		print("Passed \(checks) UI smoke checks")
	}

	static func testMainWindowAppearance(){
		let main=MainWindowViewController()
		main.sendController.sender.service=FakeSendingService()
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowViewController.defaultSize), styleMask: [.titled,.resizable], backing: .buffered, defer: false)
		window.contentViewController=main
		let background=main.view as! WindowBackgroundView
		var colors:[CGColor]=[]
		for (appearance,name) in [(NSAppearance.Name.aqua,"light"),(.darkAqua,"dark")]{
			background.appearance=NSAppearance(named: appearance)
			main.showReceive()
			main.update(receiving: true, transfers: [], deviceName: "Studio Mac")
			main.fitWindowToContent()
			background.updateLayer()
			let card=visible(main.view).compactMap {$0 as? CardView}.first!
			card.updateLayer()
			colors.append(card.layer!.backgroundColor!)
			snapshot(window, "window-receive-\(name)")
			main.showSend()
			main.fitWindowToContent()
			let choose=button("Send files…", in: main.view)
			expect(choose.bezelColor == .systemBlue, "The primary send action must stay blue in both appearances")
			if #available(macOS 26.0, *){expect(choose.borderShape == .roundedRectangle, "The primary send action must use the reduced-rounding native shape")}
			expect((main.sendController.view as? WindowBackgroundView)?.backgroundStyle == .transparent, "The embedded Send surface must not cover the soft window background")
			let title=visible(main.view).compactMap {$0 as? NSTextField}.first {$0.identifier?.rawValue=="SendSelectionTitle"}!
			let icon=visible(main.view).first {$0.identifier?.rawValue=="SendDropIcon"}!
			for width in [MainWindowViewController.minimumSize.width,MainWindowViewController.defaultSize.width,760]{
				window.setContentSize(NSSize(width: width, height: 500))
				main.fitWindowToContent()
				layout(window)
				let center=main.view.bounds.midX
				let buttonFrame=choose.convert(choose.bounds, to: main.view)
				expect(abs(buttonFrame.midX-center)<1 && abs(icon.convert(icon.bounds, to: main.view).midX-center)<1, "The empty drop icon and Send files button must stay centered as the window resizes")
				expect(title.alignment == .center && abs(title.convert(title.bounds, to: main.view).midX-center)<1, "The empty drop heading must be centered across the card")
				expect(main.view.hitTest(NSPoint(x: buttonFrame.midX, y: buttonFrame.midY)) === choose, "The dashed drop outline must not intercept clicks on Send files")
			}
			window.setContentSize(MainWindowViewController.defaultSize)
			main.fitWindowToContent()
			snapshot(window, "window-send-\(name)")
		}
		expect(colors[0] != colors[1], "Card colors must resolve separately for light and dark appearances")
	}

	static func testCompactReceiveInstructions(){
		let main=MainWindowViewController()
		main.sendController.sender.service=FakeSendingService()
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowViewController.defaultSize), styleMask: [.titled,.resizable], backing: .buffered, defer: false)
		window.contentViewController=main
		for appearance in [NSAppearance.Name.aqua,.darkAqua]{
			main.view.appearance=NSAppearance(named: appearance)
			for width in [MainWindowViewController.minimumSize.width,MainWindowViewController.defaultSize.width]{
				window.setContentSize(NSSize(width: width, height: 500))
				main.update(receiving: true, transfers: [], deviceName: "Studio Mac")
				main.fitWindowToContent()
				layout(window)
				let labels=visible(main.view).compactMap {$0 as? NSTextField}
				let row=visible(main.view).first {$0.identifier?.rawValue=="ReceiveIdleInstructions"}!
				let instructions=labels.first {$0.identifier?.rawValue=="ReceiveInstructions"}!
				expect(labels.filter {$0.stringValue=="Ready to receive"}.count==1, "The Receive tab must show Ready to receive only once")
				expect(labels.filter {$0.stringValue.contains("choose “Studio Mac”")}.count==1 && instructions.font?.pointSize==12, "Receive instructions must appear once with compact, readable typography")
				expect(row.bounds.height<=64 && instructions.alignment == .left, "Receive guidance must use a compact horizontal row rather than a large centered empty state")
				expect(window.contentView!.bounds.height<=400 && main.view.bounds.contains(row.convert(row.bounds, to: main.view)), "The idle Receive window must fit its compact instructions without clipping")
			}
		}
		main.update(receiving: false, transfers: [])
		main.fitWindowToContent()
		var enabled=false
		main.onReceivingChange={enabled=$0}
		button("Enable receiving", in: main.view).performClick(nil)
		expect(enabled, "Compacting the paused state must preserve the Enable receiving action")
		main.update(receiving: true, transfers: [transfer("compact-request", .awaitingApproval)])
		main.fitWindowToContent()
		expect(!visible(main.view).contains {$0.identifier?.rawValue=="ReceiveIdleInstructions"} && button("Accept", in: main.view).isEnabled, "Incoming requests must replace the compact idle guidance with approval controls")
	}

	static func testSettingsAppearance(){
		let settings=SettingsViewController()
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: SettingsViewController.defaultSize), styleMask: [.titled,.resizable], backing: .buffered, defer: false)
		window.contentViewController=settings
		settings.update(startReceivingOnLaunch: true, launchAtLogin: false, requiresLoginApproval: false, rememberedDeviceCount: 2, customDeviceName: "Studio Mac", receivedFilesFolderName: "A very long custom received-files folder name that must truncate instead of pushing its controls outside the window", receivedFilesFolderIsCustom: true)
		settings.updateUpdates(frequency: .weekly, checking: false, currentVersion: "1.0.0", availableRelease: nil, status: "")
		let brand=descendants(settings.view).compactMap {$0 as? NSImageView}.first {$0.identifier?.rawValue=="SettingsBrandIcon"}!
		let navigation=descendants(settings.view).compactMap {$0 as? NSSegmentedControl}.first!
		let footer=descendants(settings.view).first {$0.identifier?.rawValue=="DeveloperCreditFooter"}!
		expect((settings.view as? WindowBackgroundView)?.backgroundStyle == .soft, "Settings must reuse the main window's soft background")
		expect(brand.image === NSImage(named: "QuickShareMacBrandIcon"), "The Settings header must reuse the unchanged logo artwork")
		expect((0..<navigation.segmentCount).allSatisfy {navigation.image(forSegment: $0) != nil} && navigation.controlSize == .large && navigation.selectedSegmentBezelColor == .systemBlue, "Settings navigation must match the main window's icon tabs and blue selection")
		var cardColors:[CGColor]=[]
		for (appearance,name) in [(NSAppearance.Name.aqua,"light"),(.darkAqua,"dark")]{
			settings.view.appearance=NSAppearance(named: appearance)
			for size in [SettingsViewController.minimumSize,SettingsViewController.defaultSize]{
				window.setContentSize(size)
				for section in [SettingsViewController.Section.general,.updates,.about]{
					settings.show(section)
					layout(window)
					let brandFrame=brand.convert(brand.bounds, to: settings.view)
					let navigationFrame=navigation.convert(navigation.bounds, to: settings.view)
					let footerFrame=footer.convert(footer.bounds, to: settings.view)
					expect(brand.bounds.size==NSSize(width: 32, height: 32) && abs(brandFrame.minX-20)<1 && brandFrame.minY>navigationFrame.maxY, "Settings must use a compact upper-left brand header above navigation")
					expect(abs(navigationFrame.minX-20)<1 && settings.view.bounds.contains(navigationFrame), "Icon tabs must align with the main window's 20-point content inset")
					expect(!footer.isHiddenOrHasHiddenAncestor && abs(footerFrame.minY-20)<1 && abs(footerFrame.midX-settings.view.bounds.midX)<1, "The developer footer must stay fixed on every Settings page")
					let cards=visible(settings.view).compactMap {$0 as? CardView}
					expect(!cards.isEmpty && cards.allSatisfy(\.usesSoftAppearance), "Every Settings page must use the same soft cards as Send/Receive")
					for card in cards{
						card.updateLayer()
						expect(card.layer?.cornerRadius==8 && card.layer?.borderWidth==1, "Settings cards must retain the reduced corner radius and subtle borders in both appearances")
					}
					if section == .general{
						let scroll=visible(settings.view).compactMap {$0 as? NSScrollView}.first!
						expect(scroll.documentView!.bounds.height>scroll.contentView.bounds.height, "General settings must scroll instead of pushing the header and footer outside the window")
						expect(button("Save changes", in: settings.view).bezelColor == .systemBlue, "Saving a device name must use the shared blue primary action")
						let folder=visible(settings.view).compactMap {$0 as? NSTextField}.first {$0.identifier?.rawValue=="ReceivedFilesFolder"}!
						expect(folder.maximumNumberOfLines==1 && folder.lineBreakMode == .byTruncatingMiddle && folder.toolTip==folder.stringValue, "Long folder names must truncate and remain available in a tooltip")
						let choose=button("Choose…", in: settings.view)
						let reset=button("Use Downloads", in: settings.view)
						let row=choose.superview!
						expect(row.bounds.contains(choose.convert(choose.bounds, to: row)) && row.bounds.contains(reset.convert(reset.bounds, to: row)), "Folder actions must stay inside their row at the minimum Settings width")
						let origin=scroll.contentView.bounds.origin
						scroll.contentView.scroll(to: NSPoint(x: 0, y: 80))
						expect(brand.convert(brand.bounds, to: settings.view)==brandFrame && footer.convert(footer.bounds, to: settings.view)==footerFrame, "Scrolling Settings must leave the header and footer fixed")
						scroll.contentView.scroll(to: origin)
						cardColors.append(cards[0].layer!.backgroundColor!)
					}else if section == .updates{
						expect(button("Check for Updates…", in: settings.view).bezelColor == .systemBlue, "Manual update checks must use the shared blue primary action")
					}
					if size==SettingsViewController.defaultSize{snapshot(window, "settings-\(section.rawValue)-\(name)")}
				}
			}
		}
		expect(cardColors.first != cardColors.last, "Settings card colors must resolve separately for light and dark mode")
	}

	static func testSettingsDefaults(){
		let suite="QuickShareMac-reset-tests-\(UUID().uuidString)"
		let defaults=UserDefaults(suiteName: suite)!
		defer{defaults.removePersistentDomain(forName: suite)}
		defaults.set(false, forKey: "StartReceivingOnLaunch")
		defaults.set(true, forKey: "AlwaysOnTop")
		defaults.set(true, forKey: SendPreferences.compressFoldersKey)
		defaults.set(600, forKey: "ReceivingDuration")
		defaults.set("daily", forKey: "UpdateCheckFrequency")
		defaults.set(true, forKey: "AutomaticallyCheckForUpdates")
		defaults.set(Data([1]), forKey: ReceivedFilesFolder.bookmarkDefaultsKey)
		defaults.set(["Phone"], forKey: "RememberedDeviceNames")
		defaults.set("keep", forKey: "CachedUpdateRelease")
		AppSettingsDefaults.restore(in: defaults)
		expect(defaults.bool(forKey: "StartReceivingOnLaunch") && !defaults.bool(forKey: "AlwaysOnTop") && !SendPreferences.compressFolders(in: defaults), "Reset must restore launch receiving, pinning off, and compression off")
		expect(defaults.integer(forKey: "ReceivingDuration")==0 && defaults.string(forKey: "UpdateCheckFrequency")=="never", "Reset must restore indefinite availability and manual-only update checks")
		expect(defaults.object(forKey: ReceivedFilesFolder.bookmarkDefaultsKey)==nil && defaults.object(forKey: "AutomaticallyCheckForUpdates")==nil, "Reset must remove custom folder and obsolete update preferences")
		expect(defaults.stringArray(forKey: "RememberedDeviceNames")==["Phone"] && defaults.string(forKey: "CachedUpdateRelease")=="keep", "Reset must preserve remembered devices and unrelated app data")
		let settings=SettingsViewController()
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: SettingsViewController.defaultSize), styleMask: [.titled], backing: .buffered, defer: false)
		window.contentViewController=settings
		settings.update(startReceivingOnLaunch: false, launchAtLogin: true, requiresLoginApproval: false, rememberedDeviceCount: 1, customDeviceName: "Custom Mac", receivedFilesFolderName: "Inbox", receivedFilesFolderIsCustom: true, compressFolders: true)
		var resets=0
		settings.onResetToDefaults={
			resets+=1
			settings.update(startReceivingOnLaunch: true, launchAtLogin: false, requiresLoginApproval: false, rememberedDeviceCount: 1)
		}
		button("Reset to defaults…", in: settings.view).performClick(nil)
		expect(waitUntil{window.attachedSheet != nil} && resets==0, "Reset must ask for confirmation without changing preferences")
		let cancelSheet=window.attachedSheet!
		expect(button("Reset to defaults", in: cancelSheet.contentView!).keyEquivalent.isEmpty, "Return must not accidentally confirm resetting settings")
		button("Cancel", in: cancelSheet.contentView!).performClick(nil)
		expect(waitUntil{window.attachedSheet==nil} && resets==0, "Cancel must leave settings untouched")
		button("Reset to defaults…", in: settings.view).performClick(nil)
		expect(waitUntil{window.attachedSheet != nil}, "Reset confirmation must be reopenable")
		button("Reset to defaults", in: window.attachedSheet!.contentView!).performClick(nil)
		expect(waitUntil{resets==1}, "Confirmed reset must call the restore action exactly once")
		expect(button("Compress folders into ZIP files before sending", in: settings.view).state == .off && button("Use Mac’s name", in: settings.view).state == .on, "Reset must immediately display default compression and device-name controls")
		expect(!visible(settings.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Use Downloads"}), "Reset must restore the Downloads destination display")
	}

	static func testDynamicWindowHeight(){
		let main=MainWindowViewController()
		let service=FakeSendingService()
		main.sendController.sender.service=service
		let screen=NSScreen.main!.visibleFrame
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowViewController.defaultSize), styleMask: [.titled,.resizable], backing: .buffered, defer: false)
		window.contentViewController=main
		window.setFrameTopLeftPoint(NSPoint(x: screen.minX+20, y: screen.maxY-20))
		main.update(receiving: true, transfers: [])
		main.fitWindowToContent(visibleFrame: screen)
		let readyHeight=window.contentView!.bounds.height
		expect(readyHeight<600 && readyHeight>=MainWindowViewController.minimumSize.height, "Receive must start compact, not at the old fixed 680-point height: \(readyHeight)")
		let top=window.frame.maxY
		main.showSend()
		main.fitWindowToContent(visibleFrame: screen)
		let emptySendHeight=window.contentView!.bounds.height
		expect(emptySendHeight<500 && emptySendHeight>=MainWindowViewController.minimumSize.height && abs(window.frame.maxY-top)<1, "An empty Send tab must stay compact while preserving the title-bar position")
		let directory=FileManager.default.temporaryDirectory.appendingPathComponent("quickshare-fit-tests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer{main.sendController.sender.shutdown(); try? FileManager.default.removeItem(at: directory)}
		let files=(0..<30).map {directory.appendingPathComponent("File \($0).txt")}
		for file in files{try! Data().write(to: file)}
		_ = main.sendController.selectItems([files[0]])
		main.fitWindowToContent(visibleFrame: screen)
		expect(window.contentView!.bounds.height>emptySendHeight, "Selecting a file must grow the window to fit recipient controls")
		let qr=button("Connect with QR code…", in: main.view)
		expect(main.view.bounds.contains(qr.convert(qr.bounds, to: main.view)), "The send actions must fit without scrolling on a screen with enough room")
		let sendScroll=main.sendController.view.subviews.compactMap {$0 as? NSScrollView}.first!
		expect(sendScroll.documentView!.bounds.height<=sendScroll.contentView.bounds.height+1, "Auto-fit must show the full Send content when the screen has room")
		_ = main.sendController.selectItems(Array(files.prefix(5)))
		main.fitWindowToContent(visibleFrame: screen)
		let fiveHeight=window.frame.height
		_ = main.sendController.selectItems(files)
		main.fitWindowToContent(visibleFrame: screen)
		expect(abs(window.frame.height-fiveHeight)<1, "More than five selected filenames must not increase the auto-fitted height")
		let compactScreen=NSRect(x: screen.minX, y: screen.minY, width: screen.width, height: min(540,screen.height))
		main.fitWindowToContent(visibleFrame: compactScreen)
		expect(compactScreen.contains(window.frame), "Auto-fitting must keep the entire window inside the available screen")
		expect(sendScroll.documentView!.bounds.height>sendScroll.contentView.bounds.height, "When content exceeds the screen, the Send tab must remain scrollable")
		main.showReceive()
		main.update(receiving: true, transfers: [transfer("approval", .awaitingApproval)])
		main.fitWindowToContent(visibleFrame: screen)
		let accept=button("Accept", in: main.view)
		expect(main.view.bounds.contains(accept.convert(accept.bounds, to: main.view)), "Auto-fitting must expose incoming approval controls")
		let history=(0..<20).map {transfer("fit-\($0)", .completed)}
		main.update(receiving: true, transfers: history)
		main.fitWindowToContent(visibleFrame: compactScreen)
		expect(compactScreen.contains(window.frame), "Long history must not grow the window past the screen")
		main.update(receiving: true, transfers: [])
		main.fitWindowToContent(visibleFrame: screen)
		expect(abs(window.contentView!.bounds.height-readyHeight)<1, "Clearing transfers must shrink the window back to the compact ready state")
		main.automaticallyFitsContent=true
		main.showSend()
		_ = main.sendController.selectItems([files[0]])
		expect(waitUntil{window.contentView!.bounds.height>readyHeight}, "Selection changes must schedule automatic height fitting without a manual call")
		let stableFrame=window.frame
		main.fitWindowToContent()
		expect(window.frame==stableFrame, "Repeated layout with unchanged content must not make the window jump")
		main.automaticallyFitsContent=false
	}

	static func testStatusBarMenu(){
		let controller=StatusBarMenu()
		var receiving=false
		var canSendFiles=true
		var duration:ReceivingDuration = .indefinitely
		var expiresAt:Date?
		var checkingForUpdates=false
		var updateVersion:String?
		var transfers:[StatusBarMenu.TransferSummary]=[]
		controller.stateProvider={StatusBarMenu.State(receiving: receiving, canSendFiles: canSendFiles, deviceName: "Studio Mac", duration: duration, expiresAt: expiresAt, checkingForUpdates: checkingForUpdates, availableUpdateVersion: updateVersion, transfers: transfers)}
		let item=NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		defer{NSStatusBar.system.removeStatusItem(item)}
		controller.attach(to: item)
		expect(item.menu === controller.menu, "A native status-item menu must handle normal clicks")
		expect(item.button?.action==nil && item.button?.target==nil, "Status clicks must not use a custom window-opening action")
		expect(item.button?.image?.isTemplate==true, "The menu bar icon must let macOS choose its tint")
		expect(item.button?.title=="", "An idle status item must not show transfer text")
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
		var openedReceived=false
		controller.onOpenReceivedFiles={openedReceived=true}
		controller.menu.performActionForItem(at: controller.menu.indexOfItem(withTitle: "Open Received Files"))
		expect(openedReceived, "Opening the received files folder must remain available from the menu")
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
		transfers=[StatusBarMenu.TransferSummary(id: "outgoing", direction: .outgoing, deviceName: "Pixel 8", phase: .transferring, progress: 0.42)]
		controller.refresh()
		expect(item.button?.title=="42%", "The status item must show transfer progress at a glance")
		expect(controller.menu.items.contains(where: {$0.title=="Sending to Pixel 8 · 42%" && $0.isEnabled}), "Active outgoing transfers must appear in the menu")
		expect(controller.toolTip.contains("Sending to Pixel 8 (42%)"), "The tooltip must include transfer progress")
		transfers=[StatusBarMenu.TransferSummary(id: "outgoing", direction: .outgoing, deviceName: "Pixel 8", phase: .transferring, progress: 0.57)]
		controller.refresh()
		expect(item.button?.title=="57%" && controller.menu.items.contains(where: {$0.title=="Sending to Pixel 8 · 57%"}), "Live progress must update the existing transfer row")
		var cancelled=false
		controller.onCancelTransfer={cancelled=true}
		controller.menu.performActionForItem(at: controller.menu.indexOfItem(withTitle: "Cancel Transfer"))
		expect(cancelled, "Cancel Transfer must cancel the active outgoing transfer")
		transfers=[StatusBarMenu.TransferSummary(id: "incoming", direction: .incoming, deviceName: "Tab S9", phase: .awaitingReview, progress: nil)]
		controller.refresh()
		expect(item.button?.title=="", "A pending request must not display a transfer percentage")
		let review=controller.menu.items.first(where: {$0.title=="Incoming from Tab S9 — Review request…"})!
		expect(review.isEnabled && review.action != nil, "Pending requests must have a review action")
		var reviewed:String?
		controller.onReviewIncoming={reviewed=$0}
		controller.menu.performActionForItem(at: controller.menu.index(of: review))
		expect(reviewed=="incoming", "Reviewing a pending request must identify the transfer")
		transfers=[StatusBarMenu.TransferSummary(id: "receiving", direction: .incoming, deviceName: "Tab S9", phase: .transferring, progress: 0.5)]
		controller.refresh()
		expect(controller.menu.items.contains(where: {$0.title=="Receiving from Tab S9 · 50%"}), "Active incoming transfers must appear in the menu")
		expect(controller.menu.indexOfItem(withTitle: "Cancel Transfer") == -1, "Incoming transfers must not offer outgoing cancellation")
		transfers=[]
		controller.refresh()
		expect(item.button?.title=="", "Idle status items must clear transfer progress")
		expect(!controller.menu.items.contains(where: {$0.title.hasPrefix("Sending to") || $0.title.hasPrefix("Receiving from") || $0.title=="Cancel Transfer"}), "Transfer rows must disappear when idle")
		expect(StatusBarMenu.makeIcon(dimmed: true, badge: false).isTemplate && StatusBarMenu.makeIcon(dimmed: false, badge: true).isTemplate, "Icon variants must remain template images")
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
		expect(identity.systemDeviceName=="System Mac", "The system-name option must show the fallback even while a custom override is active")
		expect(LocalDeviceIdentity(preferences: UserDefaults(suiteName: domain)!).customName=="Travel Mac 🖥️", "The custom name must persist across identity instances")
		for invalid in ["   ","bad\u{0000}name",String(repeating: "😀", count: 64),String(repeating: "a", count: LocalDeviceIdentity.maximumNameBytes+1)]{
			do{try identity.setCustomName(invalid); expect(false, "Invalid device name was accepted")}
			catch{expect(identity.deviceName=="Travel Mac 🖥️", "Invalid input must preserve the existing name")}
		}
		for (input,message) in [("   ","Enter a device name."),("bad\nname","Remove line breaks or control characters."),(String(repeating: "😀", count: 43),"Name is too long. Try a shorter name.")]{
			do{_ = try LocalDeviceIdentity.validate(input); expect(false, "Invalid names must fail validation")}
			catch{expect(error.localizedDescription==message, "Each invalid input must have a specific nontechnical explanation")}
		}
		let boundaryName=String(repeating: "😀", count: 42)+"abc"
		expect((try? LocalDeviceIdentity.validate(boundaryName))==boundaryName, "Valid Unicode names at the discovery byte limit must remain accepted")
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

	static func testReceivedFilesFolder(){
		let suiteName="quickshare-received-folder-tests-\(UUID().uuidString)"
		let folderDefaults=UserDefaults(suiteName: suiteName)!
		ReceivedFilesFolder.defaults=folderDefaults
		ReceivedFilesFolder.resetCache()
		defer{
			ReceivedFilesFolder.defaults = .standard
			ReceivedFilesFolder.resetCache()
			folderDefaults.removePersistentDomain(forName: suiteName)
		}
		expect(ReceivedFilesFolder.currentURL==ReceivedFilesFolder.defaultURL && !ReceivedFilesFolder.isCustom && ReceivedFilesFolder.displayName=="Downloads", "The save folder must default to Downloads")
		let directory=FileManager.default.temporaryDirectory.appendingPathComponent("quickshare-shared-inbox-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer{try? FileManager.default.removeItem(at: directory)}
		try! ReceivedFilesFolder.set(directory)
		expect(ReceivedFilesFolder.currentURL.resolvingSymlinksInPath()==directory.resolvingSymlinksInPath() && ReceivedFilesFolder.isCustom, "A chosen folder must become the save destination")
		expect(ReceivedFilesFolder.displayName==directory.lastPathComponent, "The chosen folder name must be shown in Settings and the Receive footer")
		ReceivedFilesFolder.resetCache()
		expect(ReceivedFilesFolder.currentURL.resolvingSymlinksInPath()==directory.resolvingSymlinksInPath(), "The chosen folder must survive a relaunch")
		try! ReceivedFilesFolder.set(ReceivedFilesFolder.defaultURL)
		expect(!ReceivedFilesFolder.isCustom && ReceivedFilesFolder.currentURL==ReceivedFilesFolder.defaultURL, "Choosing Downloads itself must restore the default")
		try! ReceivedFilesFolder.set(directory)
		try! ReceivedFilesFolder.set(nil)
		expect(!ReceivedFilesFolder.isCustom, "Resetting must clear the custom folder")
		let missing=FileManager.default.temporaryDirectory.appendingPathComponent("quickshare-missing-\(UUID().uuidString)")
		expect((try? ReceivedFilesFolder.set(missing))==nil, "Missing folders must be rejected")
	}

	static func testMainWindowSending(){
		let service=FakeSendingService()
		let main=MainWindowViewController()
		main.setCompressFolders(true)
		main.sendController.sender.service=service
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowViewController.defaultSize), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
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
		let folder=FileManager.default.temporaryDirectory.appendingPathComponent("quickshare-send-folder-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		try! Data("inside".utf8).write(to: folder.appendingPathComponent("inside.txt"))
		defer{try? FileManager.default.removeItem(at: folder)}
		expect(main.sendController.selectItems([folder]), "Folders must be accepted by compressing them into a ZIP")
		expect(main.sendController.sender.state == .compressing, "Folder selections must compress before discovery")
		expect(waitUntil{main.sendController.sender.state == .choosingDevice}, "Folder compression must finish and prepare the ZIP for sending")
		expect(main.sendController.sender.preparedItems.count==1 && main.sendController.sender.preparedItems[0].pathExtension=="zip", "The folder must be replaced by a ZIP before sending")
		expect(service.discoveryStarts==2, "The compressed folder must go through discovery like any other selection")
		expect(!main.sendController.selectItems([URL(string: "mailto:someone@example.com")!]), "Unsupported link schemes must be rejected")
		expect(!main.sendController.selectItems([URL(string: "https://user:password@example.com")!]), "Links containing credentials must be rejected")
		let device=RemoteDeviceInfo(name: "Android test phone", type: .phone, id: "test-device")
		service.discoveryDelegate?.addDevice(device: device)
		service.discoveryDelegate?.addDevice(device: device)
		let collection=visible(main.view).compactMap {$0 as? NSCollectionView}.first!
		expect(collection.numberOfItems(inSection: 0)==1, "Discovery must deduplicate device updates")
		main.sendController.sender.selectDevice(device)
		expect(main.sendController.sender.state == .connecting && service.attempts.count==1, "Choosing a device must start a transfer")
		expect(service.attemptURLs.last?.first?.pathExtension=="zip", "The transfer must send the compressed ZIP rather than the folder")
		let sendProgress=visible(main.view).compactMap {$0 as? NSProgressIndicator}.first!
		expect(sendProgress.style == .bar && !sendProgress.isIndeterminate && sendProgress.doubleValue==0, "Sending must use an empty determinate bar, not a loading animation")
		expect(!(main.view as! SendDropView).acceptsItems, "The window must not advertise replacement drops during an active transfer")
		expect(!main.sendController.selectItems([file]), "Choosing replacement items during a transfer must be blocked")
		expect(!main.sendController.selectLink(URL(string: "https://example.com/other")!), "A link handed over during a transfer must be blocked too")
		expect(main.sendController.sender.preparedItems.first?.pathExtension=="zip", "A blocked handoff must keep the in-flight selection")
		expect(visible(main.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Finish or cancel the current transfer before choosing other items."}), "A blocked handoff must explain why the selection was not replaced")
		let oldAttempt=service.attempts[0]
		oldAttempt.connectionWasEstablished(pinCode: "2468")
		expect(main.sendController.sender.state == .awaitingApproval, "Established connections must wait for approval")
		expect(sendProgress.isHidden, "Approval must show the PIN rather than transfer progress")
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
		expect(!sendProgress.isHidden && !sendProgress.isIndeterminate && sendProgress.doubleValue==0, "Retry must reset sending progress to an empty determinate bar")
		oldAttempt.transferFinished()
		oldAttempt.connectionFailed(with: NearbyError.inputOutput)
		expect(main.sendController.sender.state == .connecting, "Late callbacks from canceled attempts must not affect a retry")
		let currentAttempt=service.attempts[1]
		currentAttempt.connectionWasEstablished(pinCode: "1357")
		currentAttempt.transferAccepted()
		expect(!sendProgress.isHidden && !sendProgress.isIndeterminate && sendProgress.doubleValue==0, "Accepted transfers must start at zero percent")
		currentAttempt.transferProgress(progress: .nan)
		currentAttempt.transferProgress(progress: .infinity)
		expect(sendProgress.doubleValue==0, "Invalid progress must not change the bar")
		currentAttempt.transferProgress(progress: 0.25)
		expect(sendProgress.doubleValue==25, "The send bar must fill to the actual transfer percentage")
		currentAttempt.transferProgress(progress: 0.5)
		expect(sendProgress.doubleValue==50 && !sendProgress.isIndeterminate, "Half-complete transfers must show a half-filled bar, not a loading animation")
		expect(main.sendController.sender.state == .sending, "Accepted transfers must report sending progress")
		main.showReceive()
		currentAttempt.transferFinished()
		expect(!sendProgress.isHidden && !sendProgress.isIndeterminate && sendProgress.doubleValue==100, "Successful transfers must leave the send bar completely full")
		expect(main.sendController.recentTransfers.count==2 && main.sendController.recentTransfers.first?.state == .completed, "Background completion must remain in outgoing history")
		expect((main.view as! SendDropView).acceptsItems, "The window must accept drops again after a transfer finishes")
		currentAttempt.transferFinished()
		expect(main.sendController.recentTransfers.count==2, "Duplicate completion callbacks must not duplicate history")
		main.showSend()
		layout(window)
		snapshot(window, "main-send-complete")
		button("Send again…", in: main.view).performClick(nil)
		expect(waitUntil{main.sendController.sender.state == .choosingDevice}, "Send again must recompress the folder and ask for a recipient")
		expect(service.attempts.count==2, "Send again must not automatically resend")
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
		expect(main.sendController.selectLink(url), "A link handed over by the Share menu must be accepted by the Send tab")
		expect(main.sendController.sender.preparedItems==[url] && main.sendController.sender.state == .choosingDevice, "Handing over a link must prepare it and start discovery")
		layout(window)
		expect(visible(main.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue==url.absoluteString}), "The Send tab must show the shared link instead of a path fragment")
		expect(!main.sendController.selectLink(URL(string: "mailto:someone@example.com")!), "Unsupported link schemes must not be handed to the Send flow")
		main.sendController.sender.shutdown()
		expect(main.sendController.sender.state == .idle && !main.sendController.sender.hasItems, "Shutdown must release the selection")
		main.showReceive()
		expect((main.view as! SendDropView).onURLs?([file])==true, "Dropping files on Receive must route them to Send")
		expect(visible(main.view).compactMap({$0 as? NSSegmentedControl}).first?.selectedSegment==0, "Dropping files must select the Send tab")
		main.sendController.sender.shutdown()
		testConnectionErrorUI()
	}

	static func testFileDropExperience(){
		let service=FakeSendingService()
		let main=MainWindowViewController()
		main.setCompressFolders(true)
		main.sendController.sender.service=service
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowViewController.defaultSize), styleMask: [.titled,.resizable], backing: .buffered, defer: false)
		window.contentViewController=main
		main.update(receiving: true, transfers: [])
		let drop=main.view as! SendDropView
		let directory=FileManager.default.temporaryDirectory.appendingPathComponent("quickshare-drop-tests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let first=directory.appendingPathComponent("first.txt")
		let second=directory.appendingPathComponent("second.txt")
		try! Data("first".utf8).write(to: first)
		try! Data("second".utf8).write(to: second)
		let pasteboard=NSPasteboard.withUniqueName()
		defer{
			main.sendController.sender.shutdown()
			pasteboard.releaseGlobally()
			try? FileManager.default.removeItem(at: directory)
		}
		func write(_ urls:[URL]){
			pasteboard.clearContents()
			pasteboard.writeObjects(urls.map {$0 as NSURL})
		}
		func shows(_ text:String)->Bool{visible(drop).compactMap {$0 as? NSTextField}.contains {$0.stringValue==text}}
		func selectionTitle()->String{
			descendants(main.sendController.view).compactMap {$0 as? NSTextField}.first(where: {$0.identifier?.rawValue=="SendSelectionTitle"})!.stringValue
		}
		write([first])
		expect(drop.previewDrop(from: pasteboard) == .copy, "A valid file hover must advertise a copy operation")
		expect(drop.dropFeedback == .ready([first]) && shows("Drop to send") && shows("Choose a nearby device next") && shows("first.txt"), "The overlay must explain the next step and preview the dragged filename")
		expect(service.discoveryStarts==0 && service.attempts.isEmpty, "Hovering must neither start discovery nor send files")
		expect(visible(main.view).compactMap({$0 as? NSSegmentedControl}).first?.selectedSegment==1, "Hovering must not switch away from Receive")
		let overlay=visible(drop).first(where: {$0.identifier?.rawValue=="FileDropOverlay"})!
		expect(drop.subviews.last === overlay && overlay.hitTest(.zero)==nil, "A single window-wide overlay must stay above content without intercepting events")
		for size in [MainWindowViewController.minimumSize,MainWindowViewController.defaultSize,NSSize(width: 700, height: 800)]{
			window.setContentSize(size)
			layout(window)
			expect(overlay.frame==drop.bounds.insetBy(dx: 12, dy: 12), "The drag overlay must fill the whole window on resize, not just the Send card")
		}
		snapshot(window, "drop-ready-receive")
		drop.appearance=NSAppearance(named: .darkAqua)
		snapshot(window, "drop-ready-dark")
		drop.appearance=nil
		_ = drop.previewDrop(from: pasteboard)
		expect(descendants(drop).filter({$0.identifier?.rawValue=="FileDropOverlay"}).count==1, "Dragging updates must reuse the overlay rather than stack new views")
		drop.draggingExited(nil)
		expect(drop.dropFeedback==nil && overlay.isHidden && service.attempts.isEmpty, "Leaving or canceling a drag must dismiss the overlay without doing work")
		_ = drop.previewDrop(from: pasteboard)
		expect(drop.receiveDrop(from: pasteboard), "Dropping a valid file on Receive must prepare Send")
		layout(window)
		expect(drop.dropFeedback==nil && overlay.isHidden, "The overlay must disappear after a drop")
		expect(visible(main.view).compactMap({$0 as? NSSegmentedControl}).first?.selectedSegment==0, "A successful drop must switch to Send")
		expect(selectionTitle()=="1 file ready to send" && shows("first.txt") && shows("Choose a nearby device. Nothing is sent until you choose a recipient."), "A single dropped file must show a summary, filename row, and recipient-selection instruction")
		expect(service.discoveryStarts==1 && service.attempts.isEmpty && main.sendController.sender.state == .choosingDevice, "Dropping must discover devices but never select a recipient or send automatically")
		write([first,second])
		expect(drop.previewDrop(from: pasteboard) == .copy && shows("2 files"), "Multi-file drags must preview their file count")
		expect(drop.receiveDrop(from: pasteboard) && selectionTitle()=="2 files ready to send", "Multiple dropped files must show a ready-to-send summary")
		func listedNames()->[NSTextField]{itemNames(in: main.sendController.view)}
		expect(listedNames().map(\.stringValue)==["first.txt","second.txt"], "Multiple selected items must list every filename in selection order")
		expect(listedNames().map(\.toolTip)==[first.path,second.path] && itemTable(in: main.view).allowsEmptySelection, "Listed filenames must use selectable rows and reveal their full paths on hover")
		let list=visible(main.sendController.view).first {$0.identifier?.rawValue=="SendSelectionList"}!
		expect(descendants(list).compactMap {$0 as? NSImageView}.count==2, "Each listed item must have a file icon")
		layout(window)
		expect(listedNames().allSatisfy {$0.bounds.width>0 && $0.bounds.height>0}, "Every selected-item row must have a usable layout")
		snapshot(window, "send-selected-items")
		expect(descendants(main.view).compactMap({$0 as? SendDropView}).count==1, "Send must not introduce a nested drag target that limits the overlay to its card")
		main.showReceive()
		let startsBeforeFolderDrop=service.discoveryStarts
		write([directory])
		expect(drop.previewDrop(from: pasteboard) == .copy && drop.dropFeedback == .folder([directory]), "Folder drags must be accepted for automatic compression")
		expect(shows("Compress & send") && shows("Folders are compressed into ZIP files before sending.") && shows(directory.lastPathComponent), "Folder drops must explain the ZIP behavior and preview the folder name")
		snapshot(window, "drop-folder")
		expect(drop.receiveDrop(from: pasteboard), "Dropping a folder must start compression and prepare Send")
		expect(listedNames().map(\.stringValue)==["first.txt","second.txt",directory.lastPathComponent], "A folder drop must append its original name while preserving existing file rows")
		expect(visible(main.view).compactMap({$0 as? NSSegmentedControl}).first?.selectedSegment==0, "A folder drop must switch to Send")
		expect(waitUntil{main.sendController.sender.state == .choosingDevice}, "Dropping a folder must finish compressing before discovery")
		expect(selectionTitle()=="3 files ready to send" && listedNames().map(\.stringValue)==["first.txt","second.txt",directory.lastPathComponent], "Compressing an appended folder must preserve the complete original-item list")
		expect(service.discoveryStarts>startsBeforeFolderDrop, "The compressed folder must start discovery")
		write([first,directory])
		expect(drop.previewDrop(from: pasteboard) == .copy && drop.dropFeedback == .folder([first,directory]), "A mixed file/folder drag must be accepted")
		expect(shows("2 items"), "Mixed drags must preview how many items are being sent")
		expect(drop.receiveDrop(from: pasteboard), "A mixed file/folder drop must keep files and compress folders")
		expect(listedNames().map(\.stringValue)==["first.txt","second.txt",directory.lastPathComponent], "Repeated file/folder drops must not duplicate existing items")
		expect(selectionTitle()=="3 files ready to send", "A duplicate drop must leave the prepared selection unchanged")
		write([first,URL(string: "https://example.com")!])
		expect(drop.previewDrop(from: pasteboard).isEmpty && drop.dropFeedback == .unsupported && shows("Files only"), "Mixed web links and files must not be silently truncated")
		pasteboard.clearContents()
		pasteboard.setString("unsupported text", forType: .string)
		expect(drop.previewDrop(from: pasteboard).isEmpty && shows("Drop files here to send"), "Unsupported content must explain the accepted input")
		write([directory.appendingPathComponent("missing.txt")])
		expect(drop.previewDrop(from: pasteboard).isEmpty && drop.dropFeedback == .unreadable, "Missing or unreadable files must not advertise a valid drop")
		write([first])
		expect(drop.previewDrop(from: pasteboard, sourceOperationMask: .move).isEmpty, "A source that forbids copying must not advertise a copy operation")
		expect(!drop.receiveDrop(from: pasteboard, sourceOperationMask: .move), "Drops must never request a destructive move of source files")
		let disappearing=directory.appendingPathComponent("disappearing.txt")
		try! Data().write(to: disappearing)
		write([disappearing])
		expect(drop.previewDrop(from: pasteboard) == .copy, "A file must initially be accepted while it exists")
		try! FileManager.default.removeItem(at: disappearing)
		expect(!drop.receiveDrop(from: pasteboard) && overlay.isHidden, "A file deleted after hover must be revalidated at drop time")
		write([first])
		_ = drop.previewDrop(from: pasteboard)
		main.sendController.sender.selectDevice(RemoteDeviceInfo(name: "Test phone", type: .phone, id: "drop-phone"))
		expect(!drop.acceptsItems && drop.dropFeedback == .busy && shows("Finish or cancel the current transfer first."), "A transfer starting during a hover must immediately update the overlay to its blocked state")
		expect(!drop.receiveDrop(from: pasteboard) && service.attempts.count==1, "Busy drops must not replace or start another transfer")
		_ = drop.previewDrop(from: pasteboard)
		snapshot(window, "drop-busy")
		main.sendController.sender.cancel(nil)
		expect(drop.acceptsItems && drop.dropFeedback == .ready([first]), "Finishing or canceling a transfer must immediately restore an in-progress drag preview")
		drop.concludeDragOperation(nil)
		expect(overlay.isHidden && drop.dropFeedback==nil, "Concluding a drag must always clear its preview")
		_ = drop.previewDrop(from: pasteboard)
		window.contentViewController=nil
		expect(overlay.isHidden && drop.dropFeedback==nil, "Removing the view from its window must clear an abandoned preview")
	}

	static func testSelectedItemList(){
		let controller=SendViewController()
		controller.compressFolders=true
		let service=FakeSendingService()
		controller.sender.service=service
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowViewController.minimumSize), styleMask: [.titled,.resizable], backing: .buffered, defer: false)
		window.contentViewController=controller
		let directory=FileManager.default.temporaryDirectory.appendingPathComponent("quickshare-list-tests-\(UUID().uuidString)")
		try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer{controller.sender.shutdown(); try? FileManager.default.removeItem(at: directory)}
		let files=(0..<30).map {directory.appendingPathComponent("Selected item \($0).\(["txt","png","docx"][$0 % 3])")}
		for file in files{try! Data().write(to: file)}
		func names()->[NSTextField]{itemNames(in: controller.view)}
		expect(controller.selectItems(Array(files.prefix(5))), "A five-item selection must be accepted")
		layout(window)
		let selectionTitle=visible(controller.view).compactMap {$0 as? NSTextField}.first {$0.identifier?.rawValue=="SendSelectionTitle"}!
		expect(selectionTitle.alignment == .left && !visible(controller.view).contains {$0.identifier?.rawValue=="SendDropIcon"}, "Selecting items must restore the left-aligned list heading and hide the empty drop illustration")
		let outer=controller.view.subviews.compactMap {$0 as? NSScrollView}.first!
		let fiveItemHeight=outer.documentView!.bounds.height
		let originalFrame=window.frame
		expect(controller.selectItems(files), "A large mixed-type selection must be accepted")
		layout(window)
		expect(!visible(controller.view).contains {$0.identifier?.rawValue=="OutgoingAttachmentSummary"}, "The main window must not repeat the attachment summary above the nearby-device heading")
		expect(visible(controller.view).compactMap {$0 as? NSTextField}.contains {$0.stringValue=="30 files ready to send"}, "Removing the duplicate summary must preserve the count above the selected-items list")
		expect(names().map(\.stringValue)==files.map(\.lastPathComponent), "The item list must show all items without a preview limit")
		let scroll=visible(controller.view).compactMap {$0 as? NSScrollView}.first {$0.identifier?.rawValue=="SendSelectionScroll"}!
		expect(scroll !== outer && scroll.bounds.height==140 && scroll.hasVerticalScroller, "The filename list must have its own scroll area capped at five rows")
		expect(!scroll.autohidesScrollers && scroll.scrollerStyle == .legacy && scroll.verticalScroller?.isHidden==false, "The selected-items scrollbar must stay visible regardless of the system overlay preference")
		expect(scroll.verticalScroller?.isEnabled==true && (scroll.verticalScroller?.knobProportion ?? 1)<1, "An overflowing item list must expose an enabled scrollbar with a usable thumb")
		expect(itemTable(in: controller.view).usesAlternatingRowBackgroundColors, "The item table must use native alternating row colors")
		expect(scroll.documentView!.bounds.height>scroll.contentView.bounds.height, "Long item lists must scroll inside their own bounded area")
		expect(outer.documentView!.bounds.height==fiveItemHeight && window.frame==originalFrame, "Adding more than five filenames must not enlarge the card, tab, or window")
		expect(scroll.documentView!.bounds.width==scroll.contentView.bounds.width, "The filename list must fit horizontally without scrolling sideways")
		let last=names().last!
		last.scrollToVisible(last.bounds)
		layout(window)
		expect(last.convert(last.bounds, to: scroll.documentView!).intersects(scroll.documentVisibleRect), "The final selected item must be reachable by scrolling")
		expect(!controller.selectItems([directory.appendingPathComponent("missing.txt")]), "An unreadable replacement must fail")
		expect(names().count==files.count, "A rejected selection must preserve the existing item list")
		expect(controller.selectItems([files[1],files[0]]), "A replacement multi-selection must be accepted")
		expect(names().map(\.stringValue)==[files[1].lastPathComponent,files[0].lastPathComponent], "Replacing items must remove old rows and reflect the new order")
		layout(window)
		expect(scroll.bounds.height==56 && scroll.documentVisibleRect.minY==0, "Short replacement lists must shrink to their rows and reset scrolling")
		expect(controller.selectItems([files[0]]) && names().map(\.stringValue)==[files[0].lastPathComponent], "A single file must use the same item list as a multi-selection")
		layout(window)
		expect(!scroll.isHidden && scroll.bounds.height==28 && scroll.verticalScroller?.isHidden==false, "A single-file list must fit one row and retain its scrollbar")
		itemTable(in: controller.view).selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		expect(names().first?.toolTip==files[0].path && itemTable(in: controller.view).selectedRow==0, "A single file row must support native selection and retain its full-path tooltip")
		_ = controller.selectItems(files)
		expect(controller.selectLink(URL(string: "https://example.com")!) && names().map(\.stringValue)==["https://example.com"], "A shared link must replace file rows with a single link row")
		expect(names().first?.toolTip=="https://example.com", "A link row must show its full URL on hover")
		_ = controller.selectItems(files)
		controller.sender.shutdown()
		expect(names().isEmpty, "Releasing the selection must hide stale item rows")
	}

	static func testSelectedItemActions(){
		let main=MainWindowViewController()
		let controller=main.sendController
		let service=FakeSendingService()
		controller.sender.service=service
		main.setCompressFolders(false)
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowViewController.defaultSize), styleMask: [.titled,.resizable], backing: .buffered, defer: false)
		window.contentViewController=main
		main.update(receiving: true, transfers: [])
		let drop=main.view as! SendDropView
		let root=FileManager.default.temporaryDirectory.appendingPathComponent("quickshare-item-actions-\(UUID().uuidString)")
		let folder=root.appendingPathComponent("Original folder")
		try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let files=(0..<8).map {root.appendingPathComponent("Item \($0).txt")}
		for file in files+[folder.appendingPathComponent("Inside.txt")]{try! Data("item".utf8).write(to: file)}
		let pasteboard=NSPasteboard.withUniqueName()
		defer{controller.sender.shutdown(); pasteboard.releaseGlobally(); try? FileManager.default.removeItem(at: root)}
		let table=itemTable(in: main.view)
		func removeButton(_ row:Int)->NSButton{
			let cell=table.view(atColumn: 0, row: row, makeIfNecessary: true)!
			return descendants(cell).compactMap {$0 as? NSButton}.first {$0.identifier?.rawValue=="SendSelectionRemove"}!
		}
		func perform(_ item:NSMenuItem){NSApp.sendAction(item.action!, to: item.target, from: item)}
		func addDrop(_ urls:[URL])->Bool{
			pasteboard.clearContents()
			pasteboard.writeObjects(urls.map {$0 as NSURL})
			return drop.receiveDrop(from: pasteboard)
		}
		var opened:[URL]=[]
		var revealed:[URL]=[]
		controller.onOpenItem={opened.append($0); return true}
		controller.onRevealItem={revealed.append($0)}
		expect(addDrop([files[0]]), "An initial drop must populate the item table")
		expect(addDrop([files[1],files[0],files[1]]) && controller.sender.originalItems==Array(files.prefix(2)), "A second drop must append unique originals in order")
		let starts=service.discoveryStarts
		expect(addDrop([files[0]]) && service.discoveryStarts==starts, "A duplicate-only drop must not restart device discovery")
		expect(!controller.appendItems([root.appendingPathComponent("missing")]) && controller.sender.originalItems==Array(files.prefix(2)), "Invalid additions must preserve the complete current selection")
		table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
		layout(window)
		let clickedRow=table.rect(ofRow: 1)
		let location=table.convert(NSPoint(x: clickedRow.midX, y: clickedRow.midY), to: nil)
		let rightClick=NSEvent.mouseEvent(with: .rightMouseDown, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
		let menu=table.menu(for: rightClick)!
		expect(table.selectedRow==1 && menu.items.map(\.title)==["Open","Reveal in Finder"], "Right-clicking another row must select it and offer file actions")
		perform(menu.items[0]); perform(menu.items[1])
		expect(opened==[files[1]] && revealed==[files[1]], "Context actions must target the clicked file, not the prior selection")
		expect(table.contextMenu(forRow: -1)==nil && table.contextMenu(forRow: table.numberOfRows)==nil, "Right-clicking empty space must not reuse a prior row's menu")
		layout(window)
		let remove=removeButton(0)
		let removeFrame=remove.convert(remove.bounds, to: table)
		expect(table.bounds.maxX-removeFrame.maxX<12, "Each remove button must align at the right edge of its item row")
		remove.performClick(nil)
		expect(controller.sender.originalItems==[files[1]] && FileManager.default.fileExists(atPath: files[0].path), "Removing a row must update the send selection without deleting the source file")
		expect(table.selectedRow==0, "Removing a different row must preserve selection of the remaining URL")
		perform(menu.items[0])
		expect(opened.last==files[1], "A context action must retain its URL when another row is removed")
		let removedMenu=table.contextMenu(forRow: 0)!
		removeButton(0).performClick(nil)
		expect(controller.sender.state == .idle && table.numberOfRows==0 && !controller.sender.hasItems, "Removing the last item must stop discovery and restore the empty Send state")
		let openCount=opened.count
		perform(removedMenu.items[0])
		expect(opened.count==openCount, "An old menu action must not open an item removed from the list")
		expect(service.attempts.isEmpty, "Adding, selecting, opening, and removing items must never send automatically")

		_ = controller.selectItems(Array(files.prefix(2)))
		let missingMenu=table.contextMenu(forRow: 0)!
		try! FileManager.default.removeItem(at: files[0])
		expect(table.contextMenu(forRow: 0)!.items.allSatisfy {!$0.isEnabled}, "Missing files must disable both context actions")
		perform(missingMenu.items[0])
		expect(opened.count==openCount, "Files removed after opening a menu must be revalidated before launching")
		try! Data().write(to: files[0])
		controller.onOpenItem={_ in false}
		perform(table.contextMenu(forRow: 0)!.items[0])
		expect(visible(controller.view).compactMap {$0 as? NSTextField}.contains {$0.stringValue=="This item could not be opened with its default app."}, "Default-app launch failures must show an explanation without discarding items")
		controller.onOpenItem={opened.append($0); return true}
		let staleRemove=removeButton(0)
		controller.sender.selectDevice(RemoteDeviceInfo(name: "Test phone", type: .phone, id: "item-action-phone"))
		expect(!removeButton(0).isEnabled && !removeButton(1).isEnabled && !drop.acceptsItems, "Active outgoing transfers must disable every remove button and further drops")
		NSApp.sendAction(staleRemove.action!, to: staleRemove.target, from: staleRemove)
		expect(!controller.appendItems([files[2]]) && controller.sender.originalItems==Array(files.prefix(2)), "Mutation guards must also reject stale button callbacks and direct additions during a transfer")
		controller.sender.cancel(nil)
		expect(removeButton(0).isEnabled && drop.acceptsItems, "Canceling a transfer must restore list editing")

		let link=URL(string: "https://example.com/shared")!
		_ = controller.selectLink(link)
		let linkMenu=table.contextMenu(forRow: 0)!
		expect(linkMenu.items.map(\.title)==["Open"], "Shared links must offer Open without a Finder action")
		perform(linkMenu.items[0])
		expect(opened.last==link && !addDrop([files[0]]) && controller.sender.originalItems==[link], "Links must open their exact URL and must not silently mix with dropped files")
		removeButton(0).performClick(nil)
		expect(addDrop([files[0]]), "Files must be addable after removing a shared link")

		_ = controller.selectItems(Array(files.prefix(6)))
		layout(window)
		table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
		table.scrollRowToVisible(5)
		let listScroll=table.enclosingScrollView!
		let origin=listScroll.contentView.bounds.origin
		main.showReceive()
		expect(addDrop([files[6]]) && controller.sender.originalItems==Array(files.prefix(7)), "Dropping while Receive is selected must append to the existing Send list")
		layout(window)
		expect(table.selectedRow==2 && listScroll.contentView.bounds.origin==origin, "Appending items must preserve row selection and the list scroll position")
		for (appearance,name) in [(NSAppearance.Name.aqua,"light"),(.darkAqua,"dark")]{
			main.view.appearance=NSAppearance(named: appearance)
			main.fitWindowToContent()
			expect(table.usesAlternatingRowBackgroundColors && !listScroll.autohidesScrollers && listScroll.verticalScroller?.isHidden==false, "Alternating colors and a persistent scrollbar must remain enabled in both appearances")
			snapshot(window, "selected-items-\(name)")
		}
		main.view.appearance=nil

		_ = controller.selectItems([folder])
		expect(controller.sender.state == .preparing && controller.appendItems([files[0]]), "Appending during folder enumeration must safely rebuild the original-item selection")
		expect(controller.sender.originalItems==[folder,files[0]], "An expanding folder must stay one original row when files are appended")
		removeButton(0).performClick(nil)
		expect(waitUntil{controller.sender.state == .choosingDevice} && controller.sender.preparedItems==[files[0]], "Removing a folder during enumeration must discard it and its prepared contents")
		RunLoop.main.run(until: Date().addingTimeInterval(0.05))
		expect(controller.sender.originalItems==[files[0]] && controller.sender.parentFolders.isEmpty, "Late enumeration callbacks must not restore removed folder contents")

		main.setCompressFolders(true)
		let compressor=DeferredFolderCompressor()
		controller.sender.folderCompressor=compressor
		_ = controller.selectItems([folder])
		expect(controller.sender.state == .compressing && compressor.completions.count==1, "Folder compression must expose the original folder while work is pending")
		perform(table.contextMenu(forRow: 0)!.items[1])
		expect(revealed.last==folder, "Finder actions must reveal the original folder rather than a temporary ZIP")
		expect(controller.appendItems([files[1]]) && compressor.completions.count==2 && controller.sender.originalItems==[folder,files[1]], "Appending during compression must restart preparation from the original folder")
		compressor.completions[0](.failure(CocoaError(.userCancelled)))
		expect(controller.sender.state == .compressing && table.numberOfRows==2, "A stale compression callback must not clear the rebuilt list")
		removeButton(0).performClick(nil)
		compressor.completions[1](.failure(CocoaError(.userCancelled)))
		expect(controller.sender.state == .choosingDevice && controller.sender.originalItems==[files[1]] && controller.sender.preparedItems==[files[1]], "Removing a compressing folder must ignore its late callback and keep the remaining file")
		expect(FileManager.default.fileExists(atPath: folder.path), "Removing a folder row must never delete the original folder")
	}

	static func testRemoveAllSelectedItems(){
		let controller=SendViewController()
		let service=FakeSendingService()
		controller.sender.service=service
		controller.compressFolders=false
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowViewController.defaultSize), styleMask: [.titled,.resizable], backing: .buffered, defer: false)
		window.contentViewController=controller
		controller.setActive(true)
		let table=itemTable(in: controller.view)
		let removeAll=descendants(controller.view).compactMap {$0 as? NSButton}.first {$0.identifier?.rawValue=="SendSelectionRemoveAll"}!
		let root=FileManager.default.temporaryDirectory.appendingPathComponent("quickshare-remove-all-\(UUID().uuidString)")
		let folder=root.appendingPathComponent("Folder")
		try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let files=[root.appendingPathComponent("One.txt"),root.appendingPathComponent("Two.txt")]
		for file in files+[folder.appendingPathComponent("Inside.txt")]{try! Data("contents".utf8).write(to: file)}
		defer{controller.sender.shutdown(); try? FileManager.default.removeItem(at: root)}
		expect(removeAll.isHidden && !removeAll.isEnabled, "Remove All must be hidden and disabled when the selection is empty")
		_ = controller.selectItems(files)
		layout(window)
		let heading=descendants(controller.view).compactMap {$0 as? NSTextField}.first {$0.identifier?.rawValue=="SendSelectionTitle"}!
		let headingFrame=heading.convert(heading.bounds, to: controller.view)
		let buttonFrame=removeAll.convert(removeAll.bounds, to: controller.view)
		expect(!removeAll.isHidden && removeAll.isEnabled && buttonFrame.minX>headingFrame.maxX && abs(buttonFrame.midY-headingFrame.midY)<1, "Remove All must appear beside the item count")
		removeAll.performClick(nil)
		expect(controller.sender.state == .idle && controller.sender.originalItems.isEmpty && table.numberOfRows==0, "Remove All must clear the complete selection and restore the idle state")
		expect(removeAll.isHidden && !removeAll.isEnabled && table.enclosingScrollView!.isHidden && service.discoveryStarts==service.discoveryStops, "Clearing all items must hide the table and action and stop discovery")
		expect(files.allSatisfy {FileManager.default.fileExists(atPath: $0.path)}, "Remove All must never delete source files")
		_ = controller.selectItems(files)
		controller.sender.selectDevice(RemoteDeviceInfo(name: "Test phone", type: .phone, id: "remove-all-phone"))
		expect(!removeAll.isEnabled, "Remove All must be disabled during an active transfer")
		NSApp.sendAction(removeAll.action!, to: removeAll.target, from: removeAll)
		expect(controller.sender.isTransferring && controller.sender.originalItems==files && service.cancellations==0, "A stale Remove All callback must not cancel a transfer or alter its files")
		controller.sender.cancel(nil)
		expect(removeAll.isEnabled && controller.recentTransfers.count==1, "Remove All must be restored after cancellation")
		removeAll.performClick(nil)
		expect(controller.recentTransfers.count==1 && controller.sender.state == .idle, "Clearing the current selection must preserve transfer history")
		_ = controller.selectItems([folder])
		expect(controller.sender.isPreparing && removeAll.isEnabled, "Remove All must be available while gathering folder contents")
		removeAll.performClick(nil)
		RunLoop.main.run(until: Date().addingTimeInterval(0.05))
		expect(controller.sender.state == .idle && controller.sender.preparedItems.isEmpty && table.numberOfRows==0, "Clearing during enumeration must ignore late callbacks")
		controller.compressFolders=true
		let compressor=DeferredFolderCompressor()
		controller.sender.folderCompressor=compressor
		_ = controller.selectItems([folder])
		expect(controller.sender.state == .compressing && removeAll.isEnabled, "Remove All must be available while compressing a folder")
		removeAll.performClick(nil)
		compressor.completions[0](.failure(CocoaError(.userCancelled)))
		expect(controller.sender.state == .idle && controller.sender.originalItems.isEmpty && table.numberOfRows==0 && FileManager.default.fileExists(atPath: folder.path), "Clearing compression must discard late callbacks without deleting the source folder")
		_ = controller.selectLink(URL(string: "https://example.com")!)
		removeAll.performClick(nil)
		expect(controller.sender.state == .idle && table.numberOfRows==0 && removeAll.isHidden, "Remove All must also clear a shared link")
	}

	static func testShareHandoff(){
		let link=URL(string: "https://example.com/a?b=c#d")!
		expect(ShareHandoff.isSupportedLink(link), "Plain HTTP and HTTPS links must be shareable")
		expect(!ShareHandoff.isSupportedLink(URL(string: "ftp://example.com")!) && !ShareHandoff.isSupportedLink(URL(string: "mailto:someone@example.com")!), "Only HTTP and HTTPS links may be shared")
		expect(!ShareHandoff.isSupportedLink(URL(string: "https://user:password@example.com")!), "Links containing credentials must not be shared")
		guard let handoff=ShareHandoff.handoffURL(for: link) else{fatalError("A supported link must have a handoff URL")}
		expect(handoff.scheme==ShareHandoff.scheme && handoff.host==ShareHandoff.host, "Link handoffs must use the quicksharemac:// scheme")
		expect(ShareHandoff.link(fromHandoffURL: handoff)==link, "The handoff URL must round-trip the exact link, including its query and fragment")
		expect(ShareHandoff.handoffURL(for: URL(string: "ftp://example.com")!)==nil, "Unsupported links must not produce a handoff URL")
		expect(ShareHandoff.link(fromHandoffURL: URL(string: "quicksharemac://send?url=ftp%3A%2F%2Fexample.com")!)==nil, "Handoff URLs must reject unsupported links")
		expect(ShareHandoff.link(fromHandoffURL: URL(string: "https://example.com")!)==nil, "Ordinary links must not be mistaken for handoff URLs")
		expect(ShareHandoff.link(fromHandoffURL: URL(string: "quicksharemac://other?url=https%3A%2F%2Fexample.com")!)==nil, "Only the send host may be handled")
		let file=URL(fileURLWithPath: "/tmp/example.txt")
		let folder=URL(fileURLWithPath: "/tmp/example-folder")
		expect(ShareHandoff.payload(for: [file,folder]) == .files([file,folder]), "File and folder shares must be handed over as files")
		expect(ShareHandoff.payload(for: [link]) == .link(link), "A single link must be handed over as a link")
		expect(ShareHandoff.payload(for: [file,link])==nil, "Mixed shares must be rejected rather than silently truncated")
		expect(ShareHandoff.payload(for: [])==nil && ShareHandoff.payload(for: [URL(string: "mailto:someone@example.com")!])==nil, "Empty or unsupported shares must not reach the main app")
		let burstStart=Date()
		expect(ShareHandoff.mergedHandoffURLs(previous: [], previousEvent: burstStart.addingTimeInterval(-5), new: [file], now: burstStart, window: 2)==[file], "A new Share-menu handoff must replace the previous selection")
		let merged=ShareHandoff.mergedHandoffURLs(previous: [file], previousEvent: burstStart, new: [folder], now: burstStart.addingTimeInterval(0.4), window: 2)
		expect(merged==[file,folder], "Open events from one Share-menu handoff must merge instead of replacing each other")
		expect(ShareHandoff.mergedHandoffURLs(previous: merged, previousEvent: burstStart.addingTimeInterval(0.4), new: [folder], now: burstStart.addingTimeInterval(0.6), window: 2)==merged, "Repeated items in one handoff must not be duplicated")
		expect(ShareHandoff.mergedHandoffURLs(previous: merged, previousEvent: burstStart.addingTimeInterval(0.4), new: [file], now: burstStart.addingTimeInterval(3), window: 2)==[file], "A later handoff must replace the previous selection")
	}

	static func testFolderCompression(){
		let root=FileManager.default.temporaryDirectory.appendingPathComponent("quickshare-zip-tests-\(UUID().uuidString)")
		let folder=root.appendingPathComponent("Projects")
		try! FileManager.default.createDirectory(at: folder.appendingPathComponent("Nested"), withIntermediateDirectories: true)
		try! Data("notes".utf8).write(to: folder.appendingPathComponent("notes.txt"))
		try! Data("deep".utf8).write(to: folder.appendingPathComponent("Nested/deep.txt"))
		let destination=root.appendingPathComponent("out")
		defer{try? FileManager.default.removeItem(at: root)}
		let compressor=DittoFolderCompressor()
		var result:Result<URL,Error>?
		compressor.compress(folder: folder, into: destination){result=$0}
		expect(waitUntil{result != nil}, "Compressing a folder must finish")
		guard case .success(let zip)=result! else {fatalError("Folder compression failed: \(String(describing: result))")}
		expect(zip.lastPathComponent=="Projects.zip", "The ZIP must be named after the folder")
		expect(FileManager.default.fileExists(atPath: zip.path), "The ZIP must exist in the requested directory")
		let data=try! Data(contentsOf: zip)
		expect(data.count>0 && data.prefix(2)==Data([0x50,0x4B]), "Folder compression must produce a real ZIP archive")
		expect(data.range(of: Data("Projects/".utf8)) != nil, "The ZIP must contain the folder itself, not just its contents")
		expect(data.range(of: Data("notes.txt".utf8)) != nil, "The ZIP must contain the folder contents")
		var failure:Result<URL,Error>?
		compressor.compress(folder: root.appendingPathComponent("Missing"), into: destination){failure=$0}
		expect(waitUntil{failure != nil}, "Compressing a missing folder must finish with a failure")
		if case .failure(let error)=failure!{
			expect((try? failure!.get())==nil && error.localizedDescription.contains("Missing"), "Compression failures must name the folder and not report success")
		}else{
			expect(false, "Compressing a missing folder must fail")
		}
	}

	static func testFolderSendingWithoutCompression(){
		let suite="QuickShareMac-folder-settings-tests-\(UUID().uuidString)"
		let defaults=UserDefaults(suiteName: suite)!
		defer{defaults.removePersistentDomain(forName: suite)}
		expect(!SendPreferences.compressFolders(in: defaults), "New installs must send folders without ZIP compression by default")
		defaults.set(false, forKey: SendPreferences.compressFoldersKey)
		expect(!SendPreferences.compressFolders(in: UserDefaults(suiteName: suite)!), "Turning compression off must persist across preference instances")
		defaults.set(true, forKey: SendPreferences.compressFoldersKey)
		expect(SendPreferences.compressFolders(in: defaults), "Compression must be re-enableable")

		let root=FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("quickshare-direct-folder-\(UUID().uuidString)")
		let folder=root.appendingPathComponent("Album")
		let nested=folder.appendingPathComponent("2023")
		let empty=folder.appendingPathComponent("Empty")
		try! FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
		try! FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
		defer{try? FileManager.default.removeItem(at: root)}
		let first=folder.appendingPathComponent("one.txt")
		let second=nested.appendingPathComponent("one.txt")
		let hidden=folder.appendingPathComponent(".notes")
		let zero=folder.appendingPathComponent("zero.txt")
		let loose=root.appendingPathComponent("loose.txt")
		for file in [first,second,hidden,loose]{try! Data("contents".utf8).write(to: file)}
		try! Data().write(to: zero)
		try! FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("loop"), withDestinationURL: folder)
		try! FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("outside"), withDestinationURL: loose)
		let main=MainWindowViewController()
		let service=FakeSendingService()
		main.sendController.sender.service=service
		main.setCompressFolders(false)
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowViewController.minimumSize), styleMask: [.titled,.resizable], backing: .buffered, defer: false)
		window.contentViewController=main
		main.showSend()
		defer{main.sendController.sender.shutdown()}
		let sender=main.sendController.sender
		let drop=main.view as! SendDropView
		func normalized(_ urls:[URL])->Set<URL>{Set(urls.map {$0.resolvingSymlinksInPath()})}
		func parent(_ url:URL, in parents:[URL:String])->String?{
			parents.first {$0.key.resolvingSymlinksInPath()==url.resolvingSymlinksInPath()}?.value
		}
		expect(sender.folderHandling == .sendContents && !drop.compressFolders, "Live settings must update both sending and drag preview")
		let choose=button("Send files…", in: main.view)
		expect(choose.toolTip=="Choose files or folders to send", "The single chooser must explain that it accepts files and folders")
		expect(!visible(main.view).compactMap({$0 as? NSButton}).contains(where: {$0.title=="Send folder…"}), "Sending files and folders must use one picker, not a second button")
		expect(main.sendController.selectItems([folder,loose]), "Mixed folders and files must be accepted without compression")
		expect(sender.state == .preparing && service.discoveryStarts==0 && !choose.isEnabled, "Folder gathering must be asynchronous and finish before discovery")
		expect(visible(main.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Gathering files from “Album”…"}), "The Send tab must show folder preparation rather than ZIP compression")
		main.setCompressFolders(true)
		expect(sender.state == .preparing, "Changing settings must not restart the current preparation")
		expect(waitUntil{sender.state == .choosingDevice}, "Folder gathering must finish")
		expect(normalized(sender.preparedItems)==normalized([first,second,hidden,zero,loose]), "Gathering must include nested, hidden, and zero-byte files without following symbolic links")
		expect(parent(first, in: sender.parentFolders)=="Album" && parent(second, in: sender.parentFolders)=="Album/2023", "Attachments must retain their root folder and relative subfolder paths")
		expect(parent(loose, in: sender.parentFolders)==nil, "Loose files must remain outside the selected folders")
		expect(choose.isEnabled && service.discoveryStarts==1 && service.attempts.isEmpty, "Gathering must discover recipients without automatically sending")
		let listed=itemNames(in: main.view)
		expect(listed.map(\.stringValue)==["Album","loose.txt"], "The selected-item list must retain the user's original folder and file names")
		let device=RemoteDeviceInfo(name: "Test phone", type: .phone, id: "direct-folder-device")
		sender.selectDevice(device)
		expect(normalized(service.attemptURLs.last!)==normalized([first,second,hidden,zero,loose]), "Uncompressed folder transfers must send original files, not folders or ZIPs")
		expect(service.attemptParentFolders.last==sender.parentFolders, "Relative folder paths must reach the sending service")
		main.setCompressFolders(false)
		expect(sender.state == .connecting, "Changing compression must not interrupt an active transfer")
		sender.cancel(nil)
		let added=nested.appendingPathComponent("new.txt")
		try! Data("new".utf8).write(to: added)
		sender.retry(nil)
		expect(sender.state == .preparing, "Retry must gather the original folders again")
		expect(waitUntil{sender.state == .choosingDevice} && normalized(sender.preparedItems).contains(added.resolvingSymlinksInPath()), "Retry must include changes made to the original folder")
		expect(service.attempts.count==1, "Retry must require selecting a recipient again")

		let pasteboard=NSPasteboard.withUniqueName()
		defer{pasteboard.releaseGlobally()}
		pasteboard.writeObjects([folder as NSURL])
		_ = drop.previewDrop(from: pasteboard)
		expect(visible(drop).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Send folder"}), "Folder previews must not promise compression when disabled")
		main.setCompressFolders(true)
		expect(visible(drop).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue=="Compress & send"}), "Changing the setting must refresh an already-visible folder preview")
		drop.endDropPreview()
		expect(main.sendController.selectItems([folder]), "The same folder must be selectable after re-enabling compression")
		expect(sender.state == .compressing && waitUntil{sender.state == .choosingDevice}, "Re-enabling compression must prepare a ZIP")
		expect(sender.preparedItems.first?.pathExtension=="zip" && sender.parentFolders.isEmpty, "ZIP selections must clear old folder metadata")
		main.setCompressFolders(false)
		expect(main.sendController.selectItems([folder]) && sender.state == .preparing, "Selecting the same folder after changing modes must not reuse its ZIP")
		expect(waitUntil{sender.state == .choosingDevice} && normalized(sender.preparedItems).contains(first.resolvingSymlinksInPath()), "The next selection must honor disabled compression")
		expect(main.sendController.selectItems([loose]) && sender.parentFolders.isEmpty, "Replacing a folder with a file must remove folder metadata")
		expect(!main.sendController.selectItems([root.appendingPathComponent("missing")]) && sender.preparedItems==[loose], "An invalid replacement must preserve the existing selection")
		_ = main.sendController.selectItems([folder])
		_ = main.sendController.selectItems([loose])
		RunLoop.main.run(until: Date().addingTimeInterval(0.05))
		expect(sender.preparedItems==[loose] && sender.parentFolders.isEmpty, "A late gathering callback must not overwrite a replacement")
		_ = main.sendController.selectItems([folder])
		sender.shutdown()
		RunLoop.main.run(until: Date().addingTimeInterval(0.05))
		expect(sender.state == .idle && sender.preparedItems.isEmpty && sender.parentFolders.isEmpty, "Shutdown must cancel pending gathering and discard late callbacks")
		expect(main.sendController.selectItems([empty]), "Empty folders must be validated during background gathering")
		expect(waitUntil{sender.state == .idle}, "An empty folder must fail preparation, not start an empty transfer")
		expect(visible(main.view).compactMap({$0 as? NSTextField}).contains(where: {$0.stringValue.contains("doesn’t contain files to send")}), "Empty folders must explain how to use ZIP mode instead")

		func expand(_ items:[URL])->Result<FolderExpansionTask.Selection,Error>{
			var result:Result<FolderExpansionTask.Selection,Error>?
			FolderExpansionTask().start(items: items){result=$0}
			expect(waitUntil{result != nil}, "Background folder enumeration must always finish")
			return result!
		}
		let other=root.appendingPathComponent("other/Album")
		try! FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
		let otherFile=other.appendingPathComponent("one.txt")
		try! Data().write(to: otherFile)
		let duplicate=try! expand([folder,other]).get()
		expect(parent(first, in: duplicate.parentFolders)=="Album" && parent(otherFile, in: duplicate.parentFolders)=="Album (2)", "Same-named root folders must get distinct receiver paths")
		for name in ["a?","a:"]{
			let subfolder=other.appendingPathComponent(name)
			try! FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
			try! Data().write(to: subfolder.appendingPathComponent("file.txt"))
		}
		let sanitized=try! expand([other]).get()
		expect(Set(sanitized.parentFolders.values).count==3, "Folder names that sanitize identically must not merge receiver directories")
		let restricted=other.appendingPathComponent("restricted.txt")
		try! Data().write(to: restricted)
		try! FileManager.default.setAttributes([.posixPermissions:0], ofItemAtPath: restricted.path)
		if case .failure=expand([other]){expect(true, "Unreadable child rejected")}
		else{expect(false, "An unreadable child must fail preparation rather than silently disappear")}
		try! FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath: restricted.path)
		let task=FolderExpansionTask()
		task.cancel()
		var cancellation:Result<FolderExpansionTask.Selection,Error>?
		task.start(items: [folder]){cancellation=$0}
		expect(waitUntil{cancellation != nil}, "Canceled enumeration must finish")
		if case .failure(let error)=cancellation!{expect((error as NSError).code==NSUserCancelledError, "Canceled enumeration must report cancellation")}
		else{expect(false, "Canceled enumeration must not produce a selection")}
	}

	static func testTransferRateEstimator(){
		let estimator=TransferRateEstimator()
		expect(estimator.rate==nil, "No rate must be reported before samples arrive")
		expect(estimator.update(bytes: 0, at: 100)==nil, "The first sample must only establish a baseline")
		let first=estimator.update(bytes: 1_000_000, at: 101)
		expect(first != nil && abs(first!-1_000_000)<1, "One second of progress must report its exact rate")
		expect(estimator.estimatedRemaining(totalBytes: 3_000_000).map {abs($0-2)<0.01}==true, "Remaining time must divide the remaining bytes by the rate")
		expect(estimator.update(bytes: 1_500_000, at: 101.1)==first, "Samples closer than a quarter second must be ignored")
		let smoothed=estimator.update(bytes: 4_000_000, at: 102)
		expect(smoothed != nil && abs(smoothed!-1_600_000)<1000, "Instantaneous spikes must be smoothed into the reported rate")
		expect(estimator.update(bytes: 0, at: 103)==nil, "Restarting a transfer must clear the old rate")
		expect(estimator.estimatedRemaining(totalBytes: 3_000_000)==nil, "A restarted transfer must not report a stale estimate")
		expect(TransferRateFormat.speed(1_500_000).hasSuffix("/s"), "Speed must be presented per second")
		expect(TransferRateFormat.remaining(45)=="About 45 sec remaining", "Short estimates must round to seconds")
		expect(TransferRateFormat.remaining(120)=="About 2 min remaining", "Longer estimates must round to minutes")
		expect(TransferRateFormat.remaining(7200)=="About 2 h remaining", "Hours-long estimates must round to hours")
		expect(TransferRateFormat.remaining(-5)=="About 1 sec remaining", "Absurd estimates must stay readable")
	}

	static func testIncomingRequestPresentation(){
		expect(IncomingRequestPresentation.preferred(appIsActive: true, canDeliverNotifications: true) == .showWindow, "An active app must show the approval card directly")
		expect(IncomingRequestPresentation.preferred(appIsActive: true, canDeliverNotifications: false) == .showWindow, "Without notifications the window must always come forward")
		expect(IncomingRequestPresentation.preferred(appIsActive: false, canDeliverNotifications: true) == .notify, "A background app with notifications must not steal focus")
		expect(IncomingRequestPresentation.preferred(appIsActive: false, canDeliverNotifications: false) == .showWindow, "Without notifications a pending request must never be missed")
		let notification=IncomingTransferNotification.make(deviceName: "Pixel 8", description: "holiday.jpg", transferID: "abc-123")
		expect(notification.title.contains("Pixel 8"), "The notification must name the sending device")
		expect(notification.body.contains("holiday.jpg") && notification.body.contains("PIN"), "The notification must describe the items and point at the PIN check")
		expect(notification.transferID=="abc-123", "The notification must carry the transfer ID so it can be cleared when the request ends")
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

private final class DeferredFolderCompressor:FolderCompressing{
	var completions:[(Result<URL,Error>)->Void]=[]
	func compress(folder:URL, into directory:URL, completion:@escaping (Result<URL,Error>)->Void){completions.append(completion)}
	func cancel(){}
}

private final class FakeSendingService:SendingService{
	var discoveryStarts=0
	var discoveryStops=0
	var cancellations=0
	var canStart=true
	weak var discoveryDelegate:ShareExtensionDelegate?
	var attempts:[ShareExtensionDelegate]=[]
	var attemptURLs:[[URL]]=[]
	var attemptParentFolders:[[URL:String]]=[]
	func startDeviceDiscovery(){discoveryStarts+=1}
	func stopDeviceDiscovery(){discoveryStops+=1}
	func addShareExtensionDelegate(_ delegate:ShareExtensionDelegate){discoveryDelegate=delegate}
	func removeShareExtensionDelegate(_ delegate:ShareExtensionDelegate){discoveryDelegate=nil}
	func startOutgoingTransfer(deviceID:String, delegate:ShareExtensionDelegate, urls:[URL], parentFolders:[URL:String]) -> Bool{
		if canStart{attempts.append(delegate); attemptURLs.append(urls); attemptParentFolders.append(parentFolders)}
		return canStart
	}
	func cancelOutgoingTransfer(id:String){cancellations+=1}
	func generateQrCodeKey() -> String{String(repeating: "A", count: 48)}
	func clearQrCodeKey(){}
}

private final class PreviewShareController:SendTransferViewController{
	// Build the real view without loading attachments or starting discovery.
	override func viewDidLoad(){}
}

private final class FolderShareController:ShareViewController{
	private let context=FolderExtensionContext()
	var handedOff:ShareHandoff.Payload?
	var completed:Bool{context.completed}
	override var extensionContext:NSExtensionContext? {context}
	// Observe the handoff instead of opening another app.
	override func handOff(_ payload:ShareHandoff.Payload, completion:@escaping (Error?) -> Void){
		handedOff=payload
		completion(nil)
	}
}

private final class FolderExtensionContext:NSExtensionContext{
	var completed=false
	var canceled=false
	override var inputItems:[Any]{
		let item=NSExtensionItem()
		item.attachments=[NSItemProvider(object: NSURL(fileURLWithPath: "/"))]
		return [item]
	}
	override func completeRequest(returningItems items:[Any]?, completionHandler completion:((Bool) -> Void)? = nil){completed=true; completion?(true)}
	override func cancelRequest(withError error:Error){canceled=true}
}

private final class LinkShareController:ShareViewController{
	private let context=LinkExtensionContext()
	var handedOff:ShareHandoff.Payload?
	var completed:Bool{context.completed}
	override var extensionContext:NSExtensionContext? {context}
	override func handOff(_ payload:ShareHandoff.Payload, completion:@escaping (Error?) -> Void){
		handedOff=payload
		completion(nil)
	}
}

private final class LinkExtensionContext:NSExtensionContext{
	var completed=false
	override var inputItems:[Any]{
		let item=NSExtensionItem()
		item.attachments=[NSItemProvider(object: NSURL(string: "https://example.com")!)]
		return [item]
	}
	override func completeRequest(returningItems items:[Any]?, completionHandler completion:((Bool) -> Void)? = nil){completed=true; completion?(true)}
	override func cancelRequest(withError error:Error){}
}

private final class UnsupportedShareController:ShareViewController{
	private let context=UnsupportedExtensionContext()
	var handOffCalls=0
	var canceled:Bool{context.canceled}
	override var extensionContext:NSExtensionContext? {context}
	override func handOff(_ payload:ShareHandoff.Payload, completion:@escaping (Error?) -> Void){
		handOffCalls+=1
		completion(nil)
	}
}

private final class UnsupportedExtensionContext:NSExtensionContext{
	var canceled=false
	override var inputItems:[Any]{
		let item=NSExtensionItem()
		item.attachments=[NSItemProvider(object: NSURL(string: "mailto:someone@example.com")!)]
		return [item]
	}
	override func cancelRequest(withError error:Error){canceled=true}
}

private final class FailingShareController:ShareViewController{
	private let context=LinkExtensionContext()
	var handOffCalls=0
	var completed:Bool{context.completed}
	override var extensionContext:NSExtensionContext? {context}
	override func handOff(_ payload:ShareHandoff.Payload, completion:@escaping (Error?) -> Void){
		handOffCalls+=1
		completion(handOffCalls==1 ? NSError(domain: "QuickShareMac.Tests", code: 1, userInfo: [NSLocalizedDescriptionKey:"Simulated failure"]) : nil)
	}
}
