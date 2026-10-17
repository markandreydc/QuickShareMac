//
//  AppDelegate.swift
//  QuickShareMac
//
//  Created by Grishka on 08.04.2023.
//

import Cocoa
import UserNotifications
import NearbyShare
import ServiceManagement

@main
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, MainAppDelegate{
	private var statusItem:NSStatusItem?
	private var mainWindow:NSWindow?
	private let windowController=MainWindowViewController()
	private var activeIncomingTransfers:[String:TransferInfo]=[:]
	private var recentlyFinishedTransfers:[String:IncomingTransferDisplay]=[:]
	private let startReceivingKey="StartReceivingOnLaunch"

    func applicationDidFinishLaunching(_ aNotification: Notification) {
		UserDefaults.standard.register(defaults: [startReceivingKey:true])
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
		statusItem?.button?.action=#selector(showMainWindow(_:))
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
		
		let nc=UNUserNotificationCenter.current()
		nc.requestAuthorization(options: [.alert, .sound]) { granted, err in
			if !granted{
				DispatchQueue.main.async {
					self.showNotificationsDeniedAlert()
				}
			}
		}
		nc.delegate=self
		let incomingTransfersCategory=UNNotificationCategory(identifier: "INCOMING_TRANSFERS", actions: [
			UNNotificationAction(identifier: "ACCEPT", title: NSLocalizedString("Accept", comment: ""), options: UNNotificationActionOptions.authenticationRequired),
			UNNotificationAction(identifier: "DECLINE", title: NSLocalizedString("Decline", comment: ""))
		], intentIdentifiers: [])
		let errorsCategory=UNNotificationCategory(identifier: "ERRORS", actions: [], intentIdentifiers: [])
		nc.setNotificationCategories([incomingTransfersCategory, errorsCategory])
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
		let active=activeIncomingTransfers.values.map { info -> IncomingTransferDisplay in
			let progress:Double?
			let status:String
			if !info.accepted{
				progress=info.totalBytes>0 ? 0 : nil
				status=NSLocalizedString("WaitingForApproval", value: "Waiting for approval", comment: "")
			}else if info.totalBytes>0{
				let fraction=min(1, Double(info.receivedBytes)/Double(info.totalBytes))
				progress=fraction
				status=String(format: NSLocalizedString("ReceivingPercent", value: "Receiving · %d%%", comment: ""), Int(fraction*100))
			}else{
				progress=nil
				status=NSLocalizedString("Receiving", value: "Receiving…", comment: "")
			}
			return IncomingTransferDisplay(deviceName: info.device.name, description: info.description, status: status, progress: progress)
		}
		windowController.update(receiving: isReceiving,
								 startReceivingOnLaunch: UserDefaults.standard.bool(forKey: startReceivingKey),
								 launchAtLogin: launchAtLogin,
								 transfers: active.sorted(by: {$0.deviceName < $1.deviceName})+recentlyFinishedTransfers.values.sorted(by: {$0.deviceName < $1.deviceName}))
	}
	
	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		statusItem?.isVisible=true
		showMainWindow(nil)
		return true
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool {
		return false
	}

    func applicationWillTerminate(_ aNotification: Notification) {
		UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
	
	func showNotificationsDeniedAlert(){
		let alert=NSAlert()
		alert.alertStyle = .critical
		alert.messageText=NSLocalizedString("NotificationsDenied.Title", value: "Notification Permission Required", comment: "")
		alert.informativeText=NSLocalizedString("NotificationsDenied.Message", value: "QuickShareMac needs to be able to display notifications for incoming file transfers. Please allow notifications in System Settings.", comment: "")
		alert.addButton(withTitle: NSLocalizedString("NotificationsDenied.OpenSettings", value: "Open settings", comment: ""))
		alert.addButton(withTitle: NSLocalizedString("Quit", value: "Quit QuickShareMac", comment: ""))
		let result=alert.runModal()
		if result==NSApplication.ModalResponse.alertFirstButtonReturn{
			NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
		}else if result==NSApplication.ModalResponse.alertSecondButtonReturn{
			NSApplication.shared.terminate(nil)
		}
	}
	
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		DispatchQueue.main.async {
			guard let transferID=response.notification.request.content.userInfo["transferID"] as? String else {
				completionHandler()
				return
			}
			let accepted=response.actionIdentifier=="ACCEPT"
			NearbyConnectionManager.shared.submitUserConsent(transferID: transferID, accept: accepted)
			if accepted{
				self.activeIncomingTransfers[transferID]?.accepted=true
			}else{
				self.activeIncomingTransfers.removeValue(forKey: transferID)
			}
			self.refreshWindow()
			completionHandler()
		}
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
		let notificationContent=UNMutableNotificationContent()
		notificationContent.title="QuickShareMac"
		notificationContent.subtitle=String(format:NSLocalizedString("PinCode", value: "PIN: %@", comment: ""), arguments: [transfer.pinCode!])
		notificationContent.body=String(format: NSLocalizedString("DeviceSendingFiles", value: "%1$@ is sending you %2$@", comment: ""), arguments: [device.name, fileStr])
		notificationContent.sound = .default
		notificationContent.categoryIdentifier="INCOMING_TRANSFERS"
		notificationContent.userInfo=["transferID": transfer.id]
		if #available(macOS 11.0, *){
			QSMNotificationCenterHackery.removeDefaultAction(notificationContent)
		}
		let notificationReq=UNNotificationRequest(identifier: "transfer_"+transfer.id, content: notificationContent, trigger: nil)
		UNUserNotificationCenter.current().add(notificationReq)
		var totalBytes:Int64=0
		for file in transfer.files{
			let (sum, overflow)=totalBytes.addingReportingOverflow(max(0, file.size))
			totalBytes=overflow ? Int64.max : sum
		}
		self.activeIncomingTransfers[transfer.id]=TransferInfo(device: device, transfer: transfer, description: fileStr, totalBytes: totalBytes)
		refreshWindow()
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
		if let error=error{
			let notificationContent=UNMutableNotificationContent()
			notificationContent.title=String(format: NSLocalizedString("TransferError", value: "Failed to receive files from %@", comment: ""), arguments: [transfer.device.name])
			if let ne=(error as? NearbyError){
				switch ne{
				case .inputOutput:
					notificationContent.body="I/O Error";
				case .protocolError(_):
					notificationContent.body=NSLocalizedString("Error.Protocol", value: "Communication error", comment: "")
				case .requiredFieldMissing:
					notificationContent.body=NSLocalizedString("Error.Protocol", value: "Communication error", comment: "")
				case .ukey2:
					notificationContent.body=NSLocalizedString("Error.Crypto", value: "Encryption error", comment: "")
				case .canceled(reason: _):
					break; // can't happen for incoming transfers
				}
			}else{
				notificationContent.body=error.localizedDescription
			}
			notificationContent.categoryIdentifier="ERRORS"
			UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "transferError_"+id, content: notificationContent, trigger: nil))
		}
		UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_"+id])
		self.activeIncomingTransfers.removeValue(forKey: id)
		let completed=error==nil && (transfer.totalBytes==0 || transfer.receivedBytes>=transfer.totalBytes)
		let status=completed ? NSLocalizedString("TransferFinished", value: "Transfer finished", comment: "") : NSLocalizedString("TransferInterrupted", value: "Transfer interrupted", comment: "")
		recentlyFinishedTransfers[id]=IncomingTransferDisplay(deviceName: transfer.device.name, description: transfer.description, status: status, progress: completed ? 1 : 0)
		refreshWindow()
		DispatchQueue.main.asyncAfter(deadline: .now()+5) {
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
