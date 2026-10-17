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
class AppDelegate: NSObject, NSApplicationDelegate, MainAppDelegate{
	private var statusItem:NSStatusItem?
	private var mainWindow:NSWindow?
	private let windowController=MainWindowViewController()
	private var activeIncomingTransfers:[String:TransferInfo]=[:]
	private var recentlyFinishedTransfers:[String:IncomingTransferDisplay]=[:]
	private let startReceivingKey="StartReceivingOnLaunch"
	private let rememberedDevicesKey="RememberedDeviceNames"
	private var rememberedDevices:Set<String>=[]

    func applicationDidFinishLaunching(_ aNotification: Notification) {
		UserDefaults.standard.register(defaults: [startReceivingKey:true])
		rememberedDevices=Set(UserDefaults.standard.stringArray(forKey: rememberedDevicesKey) ?? [])
		let appMenu=NSMenu(title: "QuickShareMac")
		appMenu.addItem(withTitle: NSLocalizedString("Quit", value: "Quit QuickShareMac", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		let appMenuItem=NSMenuItem(title: "QuickShareMac", action: nil, keyEquivalent: "")
		appMenuItem.submenu=appMenu
		let mainMenu=NSMenu()
		mainMenu.addItem(appMenuItem)
		NSApplication.shared.mainMenu=mainMenu
		statusItem=NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		statusItem?.button?.image=NSImage(named: "MenuBarIcon")
		statusItem?.button?.target=self
		statusItem?.button?.action=#selector(statusBarClicked(_:))
		statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
		statusItem?.behavior = .removalAllowed
		let window=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
							styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
		window.title="QuickShareMac"
		window.contentViewController=windowController
		window.isReleasedWhenClosed=false
		window.center()
		mainWindow=window
		windowController.onReceivingChange={ [weak self] enabled in self?.setReceiving(enabled) }
		windowController.onStartReceivingOnLaunchChange={ [weak self] enabled in
			guard let self=self else {return}
			UserDefaults.standard.set(enabled, forKey: self.startReceivingKey)
			self.refreshWindow()
		}
		windowController.onLaunchAtLoginChange={ [weak self] enabled in self?.setLaunchAtLogin(enabled) }
		windowController.onOpenLoginItems={
			NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.users")!)
		}
		windowController.onQuit={NSApplication.shared.terminate(nil)}
		windowController.onTransferDecision={ [weak self] id, accepted in
			self?.respondToIncomingTransfer(id: id, decision: accepted)
		}
		windowController.onForgetRememberedDevices={ [weak self] in self?.forgetRememberedDevices() }
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

	@objc private func statusBarClicked(_ sender:NSStatusBarButton){
		guard NSApp.currentEvent?.type == .rightMouseUp, let event=NSApp.currentEvent else {
			showMainWindow(sender)
			return
		}
		let menu=NSMenu()
		let showItem=menu.addItem(withTitle: NSLocalizedString("ShowApp", value: "Show QuickShareMac", comment: ""), action: #selector(showMainWindow(_:)), keyEquivalent: "")
		showItem.target=self
		let loginItem:NSMenuItem
		if #available(macOS 13.0, *){
			loginItem=menu.addItem(withTitle: NSLocalizedString("LaunchAtLogin", value: "Launch at login", comment: ""), action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
			loginItem.state=SMAppService.mainApp.status == .enabled ? .on : .off
		}else{
			loginItem=menu.addItem(withTitle: NSLocalizedString("SetUpLoginItem", value: "Set up login item in System Settings…", comment: ""), action: #selector(openLoginItems(_:)), keyEquivalent: "")
		}
		loginItem.target=self
		menu.addItem(.separator())
		let quitItem=menu.addItem(withTitle: NSLocalizedString("Quit", value: "Quit QuickShareMac", comment: ""), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
		quitItem.target=NSApplication.shared
		NSMenu.popUpContextMenu(menu, with: event, for: sender)
	}

	@objc private func toggleLaunchAtLogin(_ sender:NSMenuItem){setLaunchAtLogin(sender.state != .on)}
	@objc private func openLoginItems(_ sender:NSMenuItem){
		NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.users")!)
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
		statusItem?.button?.alphaValue=isReceiving ? 1 : 0.5
		let launchAtLogin:Bool
		if #available(macOS 13.0, *){
			launchAtLogin=SMAppService.mainApp.status == .enabled
		}else{
			launchAtLogin=false
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
			return IncomingTransferDisplay(deviceName: info.device.name, description: info.description, status: status, progress: progress,
										   pendingID: info.accepted ? nil : id, pinCode: info.accepted ? nil : info.transfer.pinCode,
										   remembered: rememberedDevices.contains(rememberedKey(for: info.device)))
		}
		let orderedActive=active.sorted {
			if ($0.pendingID != nil) != ($1.pendingID != nil){return $0.pendingID != nil}
			return $0.deviceName < $1.deviceName
		}
		windowController.update(receiving: isReceiving,
								 startReceivingOnLaunch: UserDefaults.standard.bool(forKey: startReceivingKey),
								 launchAtLogin: launchAtLogin,
								 rememberedDeviceCount: rememberedDevices.count,
								 transfers: orderedActive+recentlyFinishedTransfers.values.sorted(by: {$0.deviceName < $1.deviceName}))
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
		let completed=error==nil && (transfer.totalBytes==0 || transfer.receivedBytes>=transfer.totalBytes)
		let status:String
		if completed{
			status=NSLocalizedString("TransferFinished", value: "Transfer finished", comment: "")
		}else if let error=error{
			status=String(format: NSLocalizedString("TransferFailedReason", value: "Transfer failed: %@", comment: ""), error.localizedDescription)
		}else{
			status=NSLocalizedString("TransferInterrupted", value: "Transfer interrupted", comment: "")
		}
		recentlyFinishedTransfers[id]=IncomingTransferDisplay(deviceName: transfer.device.name, description: transfer.description, status: status, progress: completed ? 1 : 0, pendingID: nil, pinCode: nil, remembered: false)
		refreshWindow()
		if error != nil{showMainWindow(nil)}
		DispatchQueue.main.asyncAfter(deadline: .now()+(completed ? 5 : 15)) {
			self.recentlyFinishedTransfers.removeValue(forKey: id)
			self.refreshWindow()
		}
	}
}

struct TransferInfo{
	let device:RemoteDeviceInfo
	let transfer:TransferMetadata
	let description:String
	let totalBytes:Int64
	var receivedBytes:Int64=0
	var accepted:Bool=false
}
