//
//  AppDelegate.swift
//  QuickShareMac
//
//  Created by Grishka on 08.04.2023.
//

import Cocoa
import NearbyShare
import ServiceManagement
import UserNotifications

@main
class AppDelegate: NSObject, NSApplicationDelegate, MainAppDelegate, NSMenuItemValidation, UNUserNotificationCenterDelegate{
	private var statusItem:NSStatusItem?
	private let statusMenu=StatusBarMenu()
	private var mainWindow:NSWindow?
	private var settingsWindow:NSWindow?
	private let windowController=MainWindowViewController()
	private let settingsController=SettingsViewController()
	private let availability=ReceivingAvailability()
	private let updates=UpdateChecker()
	private var checkUpdatesMenuItem:NSMenuItem?
	private let updateResults=UpdateResultPresenter()
	private var wakeObserver:NSObjectProtocol?
	private var activeIncomingTransfers:[String:TransferInfo]=[:]
	private var recentlyFinishedTransfers:[String:IncomingTransferDisplay]=[:]
	private var recentTransferOrder:[String]=[]
	private let startReceivingKey="StartReceivingOnLaunch"
	private let rememberedDevicesKey="RememberedDeviceNames"
	private var rememberedDevices:Set<String>=[]
	private let notifications=UNUserNotificationCenter.current()
	private var notificationsAuthorized=false
	private var notificationPermissionRequested=false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
		UserDefaults.standard.register(defaults: [startReceivingKey:true])
		rememberedDevices=Set(UserDefaults.standard.stringArray(forKey: rememberedDevicesKey) ?? [])
		if let appIcon=NSImage(named: "QuickShareMacBrandIcon"){
			appIcon.isTemplate=false
			NSApplication.shared.applicationIconImage=appIcon
		}
		let appMenu=NSMenu(title: "QuickShareMac")
		let settingsItem=appMenu.addItem(withTitle: NSLocalizedString("Settings", value: "Settings…", comment: ""), action: #selector(showSettings(_:)), keyEquivalent: ",")
		settingsItem.target=self
		checkUpdatesMenuItem=appMenu.addItem(withTitle: NSLocalizedString("CheckForUpdates", value: "Check for Updates…", comment: ""), action: #selector(checkForUpdates(_:)), keyEquivalent: "")
		checkUpdatesMenuItem?.target=self
		appMenu.addItem(.separator())
		appMenu.addItem(withTitle: NSLocalizedString("Quit", value: "Quit QuickShareMac", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		let appMenuItem=NSMenuItem(title: "QuickShareMac", action: nil, keyEquivalent: "")
		appMenuItem.submenu=appMenu
		let mainMenu=NSMenu()
		mainMenu.addItem(appMenuItem)
		let fileMenu=NSMenu(title: NSLocalizedString("FileMenu", value: "File", comment: ""))
		let sendFiles=fileMenu.addItem(withTitle: NSLocalizedString("SendFiles", value: "Send files…", comment: ""), action: #selector(sendFiles(_:)), keyEquivalent: "o")
		sendFiles.target=self
		let fileMenuItem=NSMenuItem(title: fileMenu.title, action: nil, keyEquivalent: "")
		fileMenuItem.submenu=fileMenu
		mainMenu.addItem(fileMenuItem)
		let editMenu=NSMenu(title: NSLocalizedString("EditMenu", value: "Edit", comment: ""))
		editMenu.addItem(withTitle: NSLocalizedString("Cut", value: "Cut", comment: ""), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
		editMenu.addItem(withTitle: NSLocalizedString("Copy", value: "Copy", comment: ""), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
		editMenu.addItem(withTitle: NSLocalizedString("Paste", value: "Paste", comment: ""), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
		editMenu.addItem(withTitle: NSLocalizedString("SelectAll", value: "Select All", comment: ""), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
		let editMenuItem=NSMenuItem(title: editMenu.title, action: nil, keyEquivalent: "")
		editMenuItem.submenu=editMenu
		mainMenu.addItem(editMenuItem)
		let windowMenu=NSMenu(title: NSLocalizedString("Window", value: "Window", comment: ""))
		windowMenu.addItem(withTitle: NSLocalizedString("Minimize", value: "Minimize", comment: ""), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
		windowMenu.addItem(withTitle: NSLocalizedString("Close", value: "Close", comment: ""), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
		let windowMenuItem=NSMenuItem(title: windowMenu.title, action: nil, keyEquivalent: "")
		windowMenuItem.submenu=windowMenu
		mainMenu.addItem(windowMenuItem)
		NSApplication.shared.windowsMenu=windowMenu
		NSApplication.shared.mainMenu=mainMenu
		statusItem=NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		statusMenu.stateProvider={ [weak self] in
			guard let self=self else {return StatusBarMenu.State(receiving: false, canSendFiles: false)}
			return StatusBarMenu.State(receiving: NearbyConnectionManager.shared.isReceiving, canSendFiles: !self.windowController.sendController.sender.isTransferring, deviceName: LocalDeviceIdentity.shared.deviceName, duration: self.availability.duration, expiresAt: self.availability.expiresAt, checkingForUpdates: self.updates.isChecking, availableUpdateVersion: self.updates.availableRelease?.tagName)
		}
		statusMenu.onShow={ [weak self] in self?.showMainWindow(nil) }
		statusMenu.onSendFiles={ [weak self] in self?.sendFiles(nil) }
		statusMenu.onToggleReceiving={ [weak self] in self?.setReceiving(!NearbyConnectionManager.shared.isReceiving) }
		statusMenu.onDurationChange={ [weak self] duration in self?.availability.select(duration) }
		statusMenu.onWillOpen={ [weak self] in self?.availability.checkExpiration() }
		statusMenu.onSettings={ [weak self] in self?.showSettings(nil) }
		statusMenu.onCheckForUpdates={ [weak self] in self?.checkForUpdates(nil) }
		statusMenu.onViewRelease={ [weak self] in self?.viewUpdateRelease() }
		statusMenu.onQuit={NSApplication.shared.terminate(nil)}
		if let statusItem=statusItem{statusMenu.attach(to: statusItem)}
		statusItem?.behavior = .removalAllowed
		let window=NSWindow(contentRect: NSRect(origin: .zero, size: MainWindowViewController.defaultSize),
							styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
		window.title="QuickShareMac"
		window.contentViewController=windowController
		window.isReleasedWhenClosed=false
		window.contentMinSize=MainWindowViewController.minimumSize
		window.setFrameAutosaveName("QuickShareMacMainWindow")
		if !window.setFrameUsingName("QuickShareMacMainWindow"){window.center()}
		windowController.setAlwaysOnTop(UserDefaults.standard.bool(forKey: "AlwaysOnTop"))
		windowController.onAlwaysOnTopChange={enabled in UserDefaults.standard.set(enabled, forKey: "AlwaysOnTop")}
		mainWindow=window
		windowController.onReceivingChange={ [weak self] enabled in self?.setReceiving(enabled) }
		windowController.onDurationChange={ [weak self] duration in self?.availability.select(duration) }
		availability.onExpiration={ [weak self] in self?.setReceiving(false) }
		availability.onChange={ [weak self] in self?.refreshWindow() }
		wakeObserver=NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main){ [weak self] _ in
			self?.availability.checkExpiration()
			self?.updates.checkAutomaticallyIfDue()
			self?.refreshWindow()
		}
		windowController.onOpenSettings={ [weak self] in self?.showSettings(nil) }
		windowController.onOpenReceivedFiles={ [weak self] in self?.openReceivedFilesFolder() }
		settingsController.onStartReceivingOnLaunchChange={ [weak self] enabled in
			guard let self=self else {return}
			UserDefaults.standard.set(enabled, forKey: self.startReceivingKey)
			self.refreshWindow()
		}
		settingsController.onLaunchAtLoginChange={ [weak self] enabled in self?.setLaunchAtLogin(enabled) }
		settingsController.onOpenLoginItems={ [weak self] in self?.openLoginItems(nil) }
		settingsController.onCheckForUpdates={ [weak self] in self?.checkForUpdates(nil) }
		settingsController.onViewRelease={ [weak self] in self?.viewUpdateRelease() }
		settingsController.onUpdateCheckFrequencyChange={ [weak self] frequency in self?.updates.setFrequency(frequency) }
		updates.onChange={ [weak self] in self?.refreshWindow() }
		updates.onResult={ [weak self] result, manual in
			guard let self=self, manual else {return}
			self.updateResults.show(result, currentVersion: self.updates.currentVersion)
		}
		settingsController.onDeviceNameChange={ [weak self] name in
			try LocalDeviceIdentity.shared.setCustomName(name)
			NearbyConnectionManager.shared.refreshDeviceName()
			self?.refreshWindow()
		}
		windowController.onTransferDecision={ [weak self] id, accepted in
			self?.respondToIncomingTransfer(id: id, decision: accepted)
		}
		settingsController.onForgetRememberedDevices={ [weak self] in self?.forgetRememberedDevices() }
		settingsController.onChooseReceivedFilesFolder={ [weak self] in self?.chooseReceivedFilesFolder() }
		settingsController.onUseDownloadsFolder={ [weak self] in self?.setReceivedFilesFolder(nil) }
		windowController.onRevealTransfer={ [weak self] id in
			guard let transfer=self?.recentlyFinishedTransfers[id], transfer.state == .completed else {return}
			let urls=transfer.savedFileURLs.filter {FileManager.default.fileExists(atPath: $0.path)}
			if !urls.isEmpty{NSWorkspace.shared.activateFileViewerSelecting(urls)}
			else{NSWorkspace.shared.open(ReceivedFilesFolder.currentURL)}
		}
		windowController.onDismissTransfer={ [weak self] id in
			self?.recentlyFinishedTransfers.removeValue(forKey: id)
			self?.recentTransferOrder.removeAll {$0==id}
			self?.refreshWindow()
		}
		windowController.onClearRecentTransfers={ [weak self] in
			self?.recentlyFinishedTransfers.removeAll()
			self?.recentTransferOrder.removeAll()
			self?.refreshWindow()
		}
		NearbyConnectionManager.shared.mainAppDelegate=self
		NearbyConnectionManager.shared.incomingDownloadDirectory=ReceivedFilesFolder.currentURL
		if UserDefaults.standard.bool(forKey: startReceivingKey){setReceiving(true)}
		notifications.delegate=self
		refreshNotificationAuthorization()
		refreshWindow()
		showMainWindow(nil)
		updates.start()
	}

	@objc private func showMainWindow(_ sender:Any?){
		refreshWindow()
		mainWindow?.makeKeyAndOrderFront(sender)
		NSApplication.shared.activate(ignoringOtherApps: true)
	}

	/// The notification permission is requested the first time receiving turns
	/// on so the system prompt has context. The status decides whether incoming
	/// requests are announced with a banner or by bringing the window forward.
	private func refreshNotificationAuthorization(){
		notifications.getNotificationSettings{ [weak self] settings in
			DispatchQueue.main.async{
				guard let self=self else{return}
				switch settings.authorizationStatus{
				case .authorized, .provisional, .ephemeral:
					self.notificationsAuthorized=true
				case .notDetermined:
					self.notificationsAuthorized=false
					if NearbyConnectionManager.shared.isReceiving{self.requestNotificationAuthorization()}
				default:
					self.notificationsAuthorized=false
				}
			}
		}
	}

	private func requestNotificationAuthorization(){
		guard !notificationPermissionRequested else {return}
		notificationPermissionRequested=true
		notifications.requestAuthorization(options: [.alert, .sound]){ [weak self] granted, _ in
			DispatchQueue.main.async{
				guard let self=self else{return}
				self.notificationsAuthorized=granted
				self.refreshWindow()
			}
		}
	}

	private static func notificationIdentifier(for transferID:String) -> String{"transfer-\(transferID)"}

	private func postIncomingTransferNotification(id:String, deviceName:String, description:String){
		let text=IncomingTransferNotification.make(deviceName: deviceName, description: description, transferID: id)
		let content=UNMutableNotificationContent()
		content.title=text.title
		content.body=text.body
		content.sound = .default
		content.userInfo=["transferID": text.transferID]
		notifications.add(UNNotificationRequest(identifier: Self.notificationIdentifier(for: id), content: content, trigger: nil))
	}

	private func removeTransferNotification(_ id:String){
		let identifiers=[Self.notificationIdentifier(for: id)]
		notifications.removeDeliveredNotifications(withIdentifiers: identifiers)
		notifications.removePendingNotificationRequests(withIdentifiers: identifiers)
	}

	func userNotificationCenter(_ center:UNUserNotificationCenter, willPresent notification:UNNotification, withCompletionHandler completionHandler:@escaping (UNNotificationPresentationOptions)->Void){
		// Requests are only announced with a banner while the app is in the
		// background; if one arrives while the app is frontmost, the window is
		// already on screen showing the approval card.
		completionHandler([])
	}

	func userNotificationCenter(_ center:UNUserNotificationCenter, didReceive response:UNNotificationResponse, withCompletionHandler completionHandler:@escaping ()->Void){
		if response.notification.request.content.userInfo["transferID"] != nil{
			DispatchQueue.main.async{ [weak self] in self?.showMainWindow(nil) }
		}
		completionHandler()
	}

	@objc private func sendFiles(_ sender:Any?){
		showMainWindow(sender)
		windowController.showSend()
		windowController.sendController.chooseFiles(sender)
	}
	func applicationWillTerminate(_ notification:Notification){
		updates.shutdown()
		availability.stopped()
		if let observer=wakeObserver{NSWorkspace.shared.notificationCenter.removeObserver(observer)}
		windowController.sendController.sender.shutdown()
	}
	func validateMenuItem(_ item:NSMenuItem) -> Bool{
		if item.action == #selector(checkForUpdates(_:)){return !updates.isChecking}
		if item.action == #selector(sendFiles(_:)){return !windowController.sendController.sender.isTransferring}
		return true
	}

	@objc private func showSettings(_ sender:Any?){
		if settingsWindow==nil{
			let window=NSWindow(contentRect: NSRect(origin: .zero, size: SettingsViewController.defaultSize), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
			window.contentMinSize=NSSize(width: 520, height: 500)
			window.title=NSLocalizedString("SettingsTitle", value: "QuickShareMac Settings", comment: "")
			window.contentViewController=settingsController
			window.isReleasedWhenClosed=false
			window.center()
			settingsWindow=window
		}
		refreshWindow()
		settingsWindow?.makeKeyAndOrderFront(sender)
		NSApplication.shared.activate(ignoringOtherApps: true)
	}

	@objc private func openLoginItems(_ sender:Any?){
		if #available(macOS 13.0, *){SMAppService.openSystemSettingsLoginItems()}
		else{NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.users")!)}
	}

	private func setReceiving(_ enabled:Bool){
		if enabled{
			do{
				let wasReceiving=NearbyConnectionManager.shared.isReceiving
				try NearbyConnectionManager.shared.startReceiving()
				if !wasReceiving || !availability.active{availability.started()}
				refreshNotificationAuthorization()
			}catch{
				showError(error)
			}
		}else{
			NearbyConnectionManager.shared.stopReceiving()
			availability.stopped()
		}
		refreshWindow()
	}

	func receivingStopped(with error:Error){
		availability.stopped()
		refreshWindow()
		showError(error)
	}

	private func setLaunchAtLogin(_ enabled:Bool){
		if #available(macOS 13.0, *){
			do{
				if enabled{
					try SMAppService.mainApp.register()
				}else{
					try SMAppService.mainApp.unregister()
				}
			}catch{
				showError(error)
			}
		}
		refreshWindow()
	}

	private func showError(_ error:Error){
		let alert=NSAlert(error: error)
		if let window=mainWindow, window.isVisible{
			alert.beginSheetModal(for: window)
		}else{
			alert.runModal()
		}
	}

	@objc private func checkForUpdates(_ sender:Any?){
		if updateResults.activateExistingAlert(){return}
		updates.check()
	}
	private func viewUpdateRelease(){
		guard let release=updates.availableRelease, release.isValid else {return}
		NSWorkspace.shared.open(release.pageURL)
	}

	private func openReceivedFilesFolder(){NSWorkspace.shared.open(ReceivedFilesFolder.currentURL)}

	private func chooseReceivedFilesFolder(){
		guard let window=settingsWindow ?? mainWindow else {return}
		let panel=NSOpenPanel()
		panel.canChooseFiles=false
		panel.canChooseDirectories=true
		panel.allowsMultipleSelection=false
		panel.canCreateDirectories=true
		panel.prompt=NSLocalizedString("ChooseFolderPrompt", value: "Choose", comment: "")
		panel.directoryURL=ReceivedFilesFolder.currentURL
		panel.beginSheetModal(for: window){ [weak self] response in
			guard response == .OK, let url=panel.url else {return}
			self?.setReceivedFilesFolder(url)
		}
	}

	private func setReceivedFilesFolder(_ url:URL?){
		do{
			try ReceivedFilesFolder.set(url)
			NearbyConnectionManager.shared.incomingDownloadDirectory=ReceivedFilesFolder.currentURL
			refreshWindow()
		}catch{
			showError(error)
		}
	}

	private func refreshWindow(){
		NearbyConnectionManager.shared.incomingDownloadDirectory=ReceivedFilesFolder.currentURL
		availability.checkExpiration()
		let isReceiving=NearbyConnectionManager.shared.isReceiving
		statusMenu.refresh()
		checkUpdatesMenuItem?.title=updates.isChecking ? NSLocalizedString("CheckingForUpdates", value: "Checking for updates…", comment: "") : NSLocalizedString("CheckForUpdates", value: "Check for Updates…", comment: "")
		statusItem?.button?.toolTip=statusMenu.toolTip
		statusItem?.button?.setAccessibilityLabel(statusItem?.button?.toolTip)
		let launchAtLogin:Bool
		let requiresLoginApproval:Bool
		if #available(macOS 13.0, *){
			launchAtLogin=SMAppService.mainApp.status == .enabled
			requiresLoginApproval=SMAppService.mainApp.status == .requiresApproval
		}else{
			launchAtLogin=false
			requiresLoginApproval=false
		}
		let active=activeIncomingTransfers.map { id, info -> IncomingTransferDisplay in
			let progress:Double?
			let status:String
			if !info.accepted{
				progress=info.totalBytes>0 ? 0 : nil
				status=NSLocalizedString("WaitingForApproval", value: "Waiting for approval", comment: "")
			}else if info.totalBytes>0{
				let fraction=min(1, Double(info.receivedBytes)/Double(info.totalBytes))
				progress=fraction
				if info.receivedBytes>=info.totalBytes{
					status=NSLocalizedString("FinishingTransfer", value: "Finishing transfer…", comment: "")
				}else{
					var line=String(format: NSLocalizedString("ReceivingPercent", value: "Receiving · %d%%", comment: ""), Int(fraction*100))
					if let rate=info.rateEstimator.rate, rate>0, let remaining=info.rateEstimator.estimatedRemaining(totalBytes: Double(info.totalBytes)){
						line += " · \(TransferRateFormat.speed(rate)) · \(TransferRateFormat.remaining(remaining))"
					}
					status=line
				}
			}else{
				progress=nil
				status=NSLocalizedString("Receiving", value: "Receiving…", comment: "")
			}
			let description=info.totalBytes>0 ? "\(info.description) · \(ByteCountFormatter.string(fromByteCount: info.totalBytes, countStyle: .file))" : info.description
			return IncomingTransferDisplay(id: id, deviceName: info.device.name, description: description, status: status,
									   state: info.accepted ? .receiving : .awaitingApproval, progress: progress, pinCode: info.transfer.pinCode,
									   remembered: rememberedDevices.contains(rememberedKey(for: info.device)), receivedBytes: info.receivedBytes, totalBytes: info.totalBytes, savedFileURLs: info.transfer.savedFileURLs)
		}
		let orderedActive=active.sorted {
			if ($0.state == .awaitingApproval) != ($1.state == .awaitingApproval){return $0.state == .awaitingApproval}
			return (activeIncomingTransfers[$0.id]?.createdAt ?? .distantPast) < (activeIncomingTransfers[$1.id]?.createdAt ?? .distantPast)
		}
		windowController.update(receiving: isReceiving,
								 transfers: orderedActive+recentTransferOrder.compactMap {recentlyFinishedTransfers[$0]}, deviceName: LocalDeviceIdentity.shared.deviceName, duration: availability.duration, expiresAt: availability.expiresAt)
		if settingsWindow != nil{
			settingsController.update(startReceivingOnLaunch: UserDefaults.standard.bool(forKey: startReceivingKey), launchAtLogin: launchAtLogin, requiresLoginApproval: requiresLoginApproval, rememberedDeviceCount: rememberedDevices.count, customDeviceName: LocalDeviceIdentity.shared.customName, receivedFilesFolderName: ReceivedFilesFolder.displayName, receivedFilesFolderIsCustom: ReceivedFilesFolder.isCustom)
			settingsController.updateUpdates(frequency: updates.frequency, checking: updates.isChecking, currentVersion: updates.currentVersion, availableRelease: updates.availableRelease, status: updates.statusText)
		}
	}
	
	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		statusItem?.isVisible=true
		showMainWindow(nil)
		return true
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool {
		return false
	}

	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		return true
	}

	private func rememberedKey(for device:RemoteDeviceInfo) -> String{
		return "\(device.type.rawValue):\(device.name)"
	}

	private func respondToIncomingTransfer(id:String, decision:TransferDecision){
		guard let transfer=activeIncomingTransfers[id], !transfer.accepted else {return}
		let accepted=decision != .decline
		removeTransferNotification(id)
		NearbyConnectionManager.shared.submitUserConsent(transferID: id, accept: accepted)
		if accepted{
			activeIncomingTransfers[id]?.accepted=true
			if decision == .acceptAndRemember{
				rememberedDevices.insert(rememberedKey(for: transfer.device))
				UserDefaults.standard.set(rememberedDevices.sorted(), forKey: rememberedDevicesKey)
			}
		}else{
			activeIncomingTransfers.removeValue(forKey: id)
		}
		refreshWindow()
	}

	private func forgetRememberedDevices(){
		guard !rememberedDevices.isEmpty else {return}
		let alert=NSAlert()
		alert.messageText=NSLocalizedString("ForgetDevicesTitle", value: "Forget remembered device names?", comment: "")
		alert.informativeText=NSLocalizedString("ForgetDevicesMessage", value: "Future transfers will still ask for approval. You can remember a name again when accepting a transfer.", comment: "")
		alert.addButton(withTitle: NSLocalizedString("ForgetDevices", value: "Forget all", comment: ""))
		alert.addButton(withTitle: NSLocalizedString("Cancel", value: "Cancel", comment: ""))
		guard alert.runModal() == .alertFirstButtonReturn else {return}
		rememberedDevices.removeAll()
		UserDefaults.standard.removeObject(forKey: rememberedDevicesKey)
		refreshWindow()
	}
	
	func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo) {
		let fileStr:String
		if let textTitle=transfer.textDescription{
			fileStr=textTitle
		}else if transfer.files.count==1{
			fileStr=transfer.files[0].name
		}else{
			fileStr=String.localizedStringWithFormat(NSLocalizedString("NFiles", value: "%d files", comment: ""), transfer.files.count)
		}
		var totalBytes:Int64=0
		for file in transfer.files{
			let (sum, overflow)=totalBytes.addingReportingOverflow(max(0, file.size))
			totalBytes=overflow ? Int64.max : sum
		}
		self.activeIncomingTransfers[transfer.id]=TransferInfo(device: device, transfer: transfer, description: fileStr, totalBytes: totalBytes)
		windowController.showReceive()
		switch IncomingRequestPresentation.preferred(appIsActive: NSApplication.shared.isActive, canDeliverNotifications: notificationsAuthorized){
		case .showWindow:
			showMainWindow(nil)
		case .notify:
			// Announce without stealing focus; the transfer waits until the
			// user opens the window and verifies the PIN.
			postIncomingTransferNotification(id: transfer.id, deviceName: device.name, description: fileStr)
			_=NSApplication.shared.requestUserAttention(.informationalRequest)
		}
	}

	func incomingTransfer(id:String, didReceiveBytes count:Int64){
		guard var info=activeIncomingTransfers[id] else {return}
		let previousPercent=info.totalBytes>0 ? Int(Double(info.receivedBytes)/Double(info.totalBytes)*100) : 0
		let (sum, overflow)=info.receivedBytes.addingReportingOverflow(count)
		info.receivedBytes=min(info.totalBytes, overflow ? Int64.max : sum)
		info.rateEstimator.update(bytes: Double(info.receivedBytes))
		activeIncomingTransfers[id]=info
		let currentPercent=info.totalBytes>0 ? Int(Double(info.receivedBytes)/Double(info.totalBytes)*100) : 0
		if mainWindow?.isVisible == true && currentPercent != previousPercent{refreshWindow()}
	}
	
	func incomingTransfer(id: String, didFinishWith error: Error?) {
		guard let transfer=self.activeIncomingTransfers[id] else {return}
		self.activeIncomingTransfers.removeValue(forKey: id)
		removeTransferNotification(id)
		let completed=transfer.accepted && error==nil && (transfer.totalBytes==0 || transfer.receivedBytes>=transfer.totalBytes)
		let status:String
		if completed{
			status=NSLocalizedString("TransferFinished", value: "Transfer finished", comment: "")
		}else if let error=error{
			status=String(format: NSLocalizedString("TransferFailedReason", value: "Transfer failed: %@", comment: ""), error.localizedDescription)
		}else{
			status=NSLocalizedString("TransferInterrupted", value: "Transfer interrupted", comment: "")
		}
		recentlyFinishedTransfers[id]=IncomingTransferDisplay(id: id, deviceName: transfer.device.name, description: transfer.description, status: status, state: completed ? .completed : .failed, progress: nil, pinCode: nil, remembered: false, receivedBytes: transfer.receivedBytes, totalBytes: transfer.totalBytes, savedFileURLs: completed ? transfer.transfer.savedFileURLs : [])
		recentTransferOrder.insert(id, at: 0)
		refreshWindow()
		if error != nil{showMainWindow(nil)}
	}
}

struct TransferInfo{
	let device:RemoteDeviceInfo
	let transfer:TransferMetadata
	let description:String
	let totalBytes:Int64
	var receivedBytes:Int64=0
	var accepted:Bool=false
	let createdAt=Date()
	let rateEstimator=TransferRateEstimator()
}
