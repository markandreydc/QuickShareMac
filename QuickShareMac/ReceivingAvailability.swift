import Foundation

enum ReceivingDuration:Int, CaseIterable{
	case tenMinutes=600, thirtyMinutes=1800, oneHour=3600, indefinitely=0
	var title:String{
		switch self{
		case .tenMinutes: return NSLocalizedString("AvailableTenMinutes", value: "10 minutes", comment: "")
		case .thirtyMinutes: return NSLocalizedString("AvailableThirtyMinutes", value: "30 minutes", comment: "")
		case .oneHour: return NSLocalizedString("AvailableOneHour", value: "1 hour", comment: "")
		case .indefinitely: return NSLocalizedString("AvailableIndefinitely", value: "Indefinitely", comment: "")
		}
	}
}

final class ReceivingAvailability{
	private let preferences:UserDefaults
	private let now:()->Date
	private var timer:Timer?
	private(set) var duration:ReceivingDuration
	private(set) var expiresAt:Date?
	private(set) var active=false
	var onExpiration:(()->Void)?
	var onChange:(()->Void)?

	init(preferences:UserDefaults = .standard, now:@escaping ()->Date = Date.init){
		self.preferences=preferences
		self.now=now
		duration=ReceivingDuration(rawValue: preferences.integer(forKey: "ReceivingDuration")) ?? .indefinitely
	}
	func select(_ duration:ReceivingDuration){
		self.duration=duration
		preferences.set(duration.rawValue, forKey: "ReceivingDuration")
		if active{started()}else{onChange?()}
	}
	func started(){
		active=true
		expiresAt=duration == .indefinitely ? nil : now().addingTimeInterval(TimeInterval(duration.rawValue))
		scheduleTimer()
		onChange?()
	}
	private func scheduleTimer(){
		timer?.invalidate()
		timer=nil
		if let deadline=expiresAt{
			let timer=Timer(timeInterval: max(0.01, deadline.timeIntervalSince(now())), repeats: false){ [weak self] _ in self?.checkExpiration() }
			self.timer=timer
			// Expiry must also run while a native menu is being tracked.
			RunLoop.main.add(timer, forMode: .common)
		}
	}
	func stopped(){
		timer?.invalidate()
		timer=nil
		active=false
		expiresAt=nil
		onChange?()
	}
	func checkExpiration(){
		guard active, let deadline=expiresAt else {return}
		guard now()>=deadline else {scheduleTimer(); return}
		stopped()
		onExpiration?()
	}
	deinit{timer?.invalidate()}
}
