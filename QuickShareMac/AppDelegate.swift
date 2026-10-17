//
//  AppDelegate.swift
//  QuickShareMac
//
//  Created by Grishka on 08.04.2023.
//

import Cocoa
import NearbyShare
import ServiceManagement

@main
class AppDelegate: NSObject, NSApplicationDelegate, MainAppDelegate, NSMenuItemValidation{
	private var statusItem:NSStatusItem?
	private let statusMenu=StatusBarMenu()
	private var mainWindow:NSWindow?
	private var settingsWindow:NSWindow?
	private let windowController=MainWindowViewController()
	private let settingsController=SettingsViewController()
	private var activeIncomingTransfers:[String:TransferInfo]=[:]
	private var recentlyFinishedTransfers:[String:IncomingTransferDisplay]=[:]
	private var recentTransferOrder:[String]=[]
	private let startReceivingKey="StartReceivingOnLaunch"
	private let rememberedDevicesKey="RememberedDeviceNames"
	private var rememberedDevices:Set<String>=[]

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
			StatusBarMenu.State(receiving: NearbyConnectionManager.shared.isReceiving, canSendFiles: self?.windowController.sendController.sender.isTransferring != true)
		}
		statusMenu.onShow={ [weak self] in self?.showMainWindow(nil) }
		statusMenu.onSendFiles={ [weak self] in self?.sendFiles(nil) }
		statusMenu.onToggleReceiving={ [weak self] in self?.setReceiving(!NearbyConnectionManager.shared.isReceiving) }
		statusMenu.onSettings={ [weak self] in self?.showSettings(nil) }
		statusMenu.onQuit={NSApplication.shared.terminate(nil)}
		if let statusItem=statusItem{statusMenu.attach(to: statusItem)}
		statusItem?.behavior = .removalAllowed
		let window=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
							styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
		window.title="QuickShareMac"
		window.contentViewController=windowController
		window.isReleasedWhenClosed=false
		window.contentMinSize=NSSize(width: 520, height: 640)
		window.setFrameAutosaveName("QuickShareMacMainWindow")
		if !window.setFrameUsingName("QuickShareMacMainWindow"){window.center()}
		mainWindow=window
		windowController.onReceivingChange={ [weak self] enabled in self?.setReceiving(enabled) }
		windowController.onOpenSettings={ [weak self] in self?.showSettings(nil) }
		settingsController.onStartReceivingOnLaunchChange={ [weak self] enabled in
			guard let self=self else {return}
			UserDefaults.standard.set(enabled, forKey: self.startReceivingKey)
			self.refreshWindow()
		}
		settingsController.onLaunchAtLoginChange={ [weak self] enabled in self?.setLaunchAtLogin(enabled) }
		settingsController.onOpenLoginItems={ [weak self] in self?.openLoginItems(nil) }
		windowController.onTransferDecision={ [weak self] id, accepted in
			self?.respondToIncomingTransfer(id: id, decision: accepted)
		}
		settingsController.onForgetRememberedDevices={ [weak self] in self?.forgetRememberedDevices() }
		windowController.onRevealTransfer={ [weak self] id in
			guard let transfer=self?.recentlyFinishedTransfers[id], transfer.state == .completed else {return}
			let urls=transfer.savedFileURLs.filter {FileManager.default.fileExists(atPath: $0.path)}
			if !urls.isEmpty{NSWorkspace.shared.activateFileViewerSelecting(urls)}
			else if let downloads=FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first{NSWorkspace.shared.open(downloads)}
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
		if UserDefaults.standard.bool(forKey: startReceivingKey){setReceiving(true)}
		refreshWindow()
		showMainWindow(nil)
	}

	@objc private func showMainWindow(_ sender:Any?){
		refreshWindow()
		mainWindow?.makeKeyAndOrderFront(sender)
		NSApplication.shared.activate(ignoringOtherApps: true)
	}

	@objc private func sendFiles(_ sender:Any?){
		showMainWindow(sender)
		windowController.showSend()
		windowController.sendController.chooseFiles(sender)
	}
	func applicationWillTerminate(_ notification:Notification){windowController.sendController.sender.shutdown()}
	func validateMenuItem(_ item:NSMenuItem) -> Bool{
		if item.action == #selector(sendFiles(_:)){return !windowController.sendController.sender.isTransferring}
		return true
	}

	@objc private func showSettings(_ sender:Any?){
		if settingsWindow==nil{
			let window=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
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
				try NearbyConnectionManager.shared.startReceiving()
			}catch{
				showError(error)
			}
		}else{
			NearbyConnectionManager.shared.stopReceiving()
		}
		refreshWindow()
	}

	func receivingStopped(with error:Error){
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

	private func refreshWindow(){
		let isReceiving=NearbyConnectionManager.shared.isReceiving
		statusMenu.refresh()
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
				status=info.receivedBytes>=info.totalBytes
					? NSLocalizedString("FinishingTransfer", value: "Finishing transfer…", comment: "")
					: String(format: NSLocalizedString("ReceivingPercent", value: "Receiving · %d%%", comment: ""), Int(fraction*100))
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
								 transfers: orderedActive+recentTransferOrder.compactMap {recentlyFinishedTransfers[$0]})
		if settingsWindow != nil{
			settingsController.update(startReceivingOnLaunch: UserDefaults.standard.bool(forKey: startReceivingKey), launchAtLogin: launchAtLogin, requiresLoginApproval: requiresLoginApproval, rememberedDeviceCount: rememberedDevices.count)
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
		showMainWindow(nil)
	}

	func incomingTransfer(id:String, didReceiveBytes count:Int64){
		guard var info=activeIncomingTransfers[id] else {return}
		let previousPercent=info.totalBytes>0 ? Int(Double(info.receivedBytes)/Double(info.totalBytes)*100) : 0
		let (sum, overflow)=info.receivedBytes.addingReportingOverflow(count)
		info.receivedBytes=min(info.totalBytes, overflow ? Int64.max : sum)
		activeIncomingTransfers[id]=info
		let currentPercent=info.totalBytes>0 ? Int(Double(info.receivedBytes)/Double(info.totalBytes)*100) : 0
		if mainWindow?.isVisible == true && currentPercent != previousPercent{refreshWindow()}
	}
	
	func incomingTransfer(id: String, didFinishWith error: Error?) {
		guard let transfer=self.activeIncomingTransfers[id] else {return}
		self.activeIncomingTransfers.removeValue(forKey: id)
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
}
