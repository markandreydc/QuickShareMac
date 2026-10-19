//
//  IncomingRequestNotifications.swift
//  QuickShareMac
//

import Foundation

/// Decides how an incoming transfer request is announced. When the app is not
/// in the foreground and notifications are available, the request is announced
/// without interrupting whatever the user is doing. Otherwise the main window
/// is brought forward so a pending approval can never be missed.
enum IncomingRequestPresentation:Equatable{
	case showWindow
	case notify

	static func preferred(appIsActive:Bool, canDeliverNotifications:Bool)->IncomingRequestPresentation{
		guard !appIsActive else{return .showWindow}
		return canDeliverNotifications ? .notify : .showWindow
	}
}

/// The user-visible text of an incoming-request notification. Kept separate
/// from UserNotifications so it can be tested without a notification center
/// and so its wording matches the approval card in the main window.
struct IncomingTransferNotification:Equatable{
	let title:String
	let body:String
	let transferID:String

	static func make(deviceName:String, description:String, transferID:String)->IncomingTransferNotification{
		let title=String(format: NSLocalizedString("TransferNotificationTitle", value: "Transfer request from %@", comment: ""), deviceName)
		let body=String(format: NSLocalizedString("TransferNotificationBody", value: "%@. Open QuickShareMac to check the PIN, then accept or decline.", comment: ""), description)
		return IncomingTransferNotification(title: title, body: body, transferID: transferID)
	}
}

/// Completion banners are separate from approval requests, so ending a request
/// cannot remove its success notification. One batch produces one banner.
struct TransferSuccessNotification:Equatable{
	enum Direction:String{case sent, received}
	let transferID:String
	let direction:Direction
	let deviceName:String
	let itemDescription:String
	var identifier:String{"transfer-success-\(direction.rawValue)-\(transferID)"}
	var title:String{
		direction == .sent
			? NSLocalizedString("TransferSentNotificationTitle", value: "Transfer sent", comment: "")
			: NSLocalizedString("TransferReceivedNotificationTitle", value: "Transfer received", comment: "")
	}
	var body:String{
		String(format: direction == .sent
			? NSLocalizedString("TransferSentNotificationBody", value: "%@ sent to %@.", comment: "")
			: NSLocalizedString("TransferReceivedNotificationBody", value: "%@ received from %@.", comment: ""), itemDescription, deviceName)
	}
}

/// Authorization and delivery are injected to keep tests away from the user's
/// notification permissions and Notification Center.
final class TransferSuccessNotifier{
	private let authorize:(@escaping (Bool)->Void)->Void
	private let deliver:(TransferSuccessNotification)->Void
	private var announced=Set<String>()
	init(authorize:@escaping (@escaping (Bool)->Void)->Void, deliver:@escaping (TransferSuccessNotification)->Void){
		self.authorize=authorize
		self.deliver=deliver
	}
	func notify(_ notification:TransferSuccessNotification){
		guard announced.insert(notification.identifier).inserted else{return}
		authorize{ [weak self] granted in
			guard granted else{return}
			self?.deliver(notification)
		}
	}
}
