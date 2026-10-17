import Cocoa

final class StatusBarMenu:NSObject, NSMenuDelegate{
	struct TransferSummary{
		enum Direction:Equatable{case incoming, outgoing}
		enum Phase:Equatable{case connecting, awaitingApproval, transferring, awaitingReview}
		let id:String
		let direction:Direction
		let deviceName:String
		let phase:Phase
		let progress:Double?
	}

	struct State{
		let receiving:Bool
		let canSendFiles:Bool
		var deviceName:String="QuickShareMac"
		var duration:ReceivingDuration = .indefinitely
		var expiresAt:Date?
		var checkingForUpdates=false
		var availableUpdateVersion:String?
		var transfers:[TransferSummary]=[]
	}
	let menu=NSMenu()
	var stateProvider:()->State = {State(receiving: false, canSendFiles: true)}
	var onShow:(()->Void)?
	var onSendFiles:(()->Void)?
	var onOpenReceivedFiles:(()->Void)?
	var onToggleReceiving:(()->Void)?
	var onDurationChange:((ReceivingDuration)->Void)?
	var onReviewIncoming:((String)->Void)?
	var onCancelTransfer:(()->Void)?
	var onSettings:(()->Void)?
	var onCheckForUpdates:(()->Void)?
	var onViewRelease:(()->Void)?
	var onQuit:(()->Void)?
	var onWillOpen:(()->Void)?
	private(set) var toolTip="QuickShareMac"
	private weak var statusItem:NSStatusItem?
	private let receivingItem=NSMenuItem()
	private let sendItem=NSMenuItem()
	private let deviceItem=NSMenuItem()
	private let visibilityItem=NSMenuItem()
	private let expiryItem=NSMenuItem()
	private let durationItem=NSMenuItem()
	private let durationMenu=NSMenu()
	private let checkUpdatesItem=NSMenuItem()
	private let updateAvailableItem=NSMenuItem()
	private let statusSeparator=NSMenuItem.separator()
	private let cancelTransferItem=NSMenuItem()
	private var transferItems:[NSMenuItem]=[]
	private var transferRowItems:[NSMenuItem]=[]
	private var transferSignature=""

	override init(){
		super.init()
		menu.delegate=self
		menu.autoenablesItems=false
		// Leave appearance, font, colors and item views to AppKit. In particular,
		// do not inherit the status button's wallpaper-dependent appearance.
		for item in [deviceItem,visibilityItem,expiryItem]{item.isEnabled=false; menu.addItem(item)}
		menu.addItem(statusSeparator)
		addItem(NSLocalizedString("ShowApp", value: "Show QuickShareMac", comment: ""), action: #selector(showApp(_:)))
		addItem(NSLocalizedString("OpenReceivedFiles", value: "Open Received Files", comment: ""), action: #selector(openReceivedFiles(_:)))
		sendItem.title=NSLocalizedString("SendFiles", value: "Send files…", comment: "")
		sendItem.keyEquivalent="o"
		sendItem.target=self
		sendItem.action=#selector(sendFiles(_:))
		menu.addItem(sendItem)
		receivingItem.target=self
		receivingItem.action=#selector(toggleReceiving(_:))
		menu.addItem(receivingItem)
		durationMenu.autoenablesItems=false
		for duration in ReceivingDuration.allCases{
			let item=durationMenu.addItem(withTitle: duration.title, action: #selector(selectDuration(_:)), keyEquivalent: "")
			item.tag=duration.rawValue
			item.target=self
		}
		durationItem.submenu=durationMenu
		menu.addItem(durationItem)
		cancelTransferItem.title=NSLocalizedString("CancelTransfer", value: "Cancel Transfer", comment: "")
		cancelTransferItem.target=self
		cancelTransferItem.action=#selector(cancelTransfer(_:))
		cancelTransferItem.image=Self.menuImage("xmark.circle")
		menu.addItem(.separator())
		addItem(NSLocalizedString("Settings", value: "Settings…", comment: ""), action: #selector(settings(_:)), key: ",")
		checkUpdatesItem.target=self
		checkUpdatesItem.action=#selector(checkForUpdates(_:))
		menu.addItem(checkUpdatesItem)
		updateAvailableItem.target=self
		updateAvailableItem.action=#selector(viewRelease(_:))
		menu.addItem(updateAvailableItem)
		menu.addItem(.separator())
		addItem(NSLocalizedString("Quit", value: "Quit QuickShareMac", comment: ""), action: #selector(quit(_:)), key: "q")
		refresh()
	}

	func attach(to statusItem:NSStatusItem){
		// NSStatusItem owns menu presentation, highlighting, dismissal and both
		// mouse buttons. No custom click handler or contextual popup is needed.
		self.statusItem=statusItem
		statusItem.button?.target=nil
		statusItem.button?.action=nil
		statusItem.button?.imagePosition = .imageLeading
		statusItem.menu=menu
		refresh()
	}

	static func makeIcon() -> NSImage{makeIcon(dimmed: false, badge: false)}
	static func makeIcon(dimmed:Bool, badge:Bool) -> NSImage{
		let base=makeBaseIcon()
		guard dimmed || badge else{return base}
		let image=NSImage(size: base.size, flipped: false){ rect in
			base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.42 : 1)
			if badge{
				let unit=rect.width/18
				NSGraphicsContext.saveGraphicsState()
				NSGraphicsContext.current?.compositingOperation = .clear
				NSBezierPath(ovalIn: NSRect(x: rect.minX+10*unit, y: rect.minY+10*unit, width: 8*unit, height: 8*unit)).fill()
				NSGraphicsContext.restoreGraphicsState()
				NSColor.black.setFill()
				NSBezierPath(ovalIn: NSRect(x: rect.minX+11.5*unit, y: rect.minY+11.5*unit, width: 5*unit, height: 5*unit)).fill()
			}
			return true
		}
		image.size=base.size
		image.isTemplate=true
		return image
	}

	private static func makeBaseIcon() -> NSImage{
		let image:NSImage
		if #available(macOS 11.0, *), let symbol=NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "QuickShareMac"){
			image=symbol
		}else{
			// A monochrome fallback, not a template of the full-color app icon.
			image=NSImage(size: NSSize(width: 18, height: 18), flipped: false){ _ in
				NSColor.black.setStroke()
				let arrows=NSBezierPath()
				arrows.lineWidth=1.5
				arrows.lineCapStyle = .round
				arrows.lineJoinStyle = .round
				arrows.move(to: NSPoint(x: 2, y: 12))
				arrows.line(to: NSPoint(x: 16, y: 12))
				arrows.move(to: NSPoint(x: 12, y: 16))
				arrows.line(to: NSPoint(x: 16, y: 12))
				arrows.line(to: NSPoint(x: 12, y: 8))
				arrows.move(to: NSPoint(x: 16, y: 6))
				arrows.line(to: NSPoint(x: 2, y: 6))
				arrows.move(to: NSPoint(x: 6, y: 10))
				arrows.line(to: NSPoint(x: 2, y: 6))
				arrows.line(to: NSPoint(x: 6, y: 2))
				arrows.stroke()
				return true
			}
		}
		image.size=NSSize(width: 18, height: 18)
		image.isTemplate=true
		return image
	}

	private static func menuImage(_ name:String) -> NSImage?{
		guard let image=NSImage(systemSymbolName: name, accessibilityDescription: nil) else{return nil}
		image.size=NSSize(width: 16, height: 16)
		image.isTemplate=true
		return image
	}

	func menuNeedsUpdate(_ menu:NSMenu){onWillOpen?(); refresh()}
	func refresh(){
		let state=stateProvider()
		updateTransferItems(state.transfers)
		deviceItem.title=String(format: NSLocalizedString("StatusDeviceName", value: "Device: %@", comment: ""), state.deviceName)
		deviceItem.toolTip=state.deviceName
		visibilityItem.title=state.receiving ? NSLocalizedString("VisibleToEveryoneOnNetwork", value: "Visible to everyone on your network", comment: "") : NSLocalizedString("NotVisibleReceivingOff", value: "Not visible · Receiving off", comment: "")
		expiryItem.isHidden = !state.receiving || state.expiresAt==nil
		if let deadline=state.expiresAt{expiryItem.title=String(format: NSLocalizedString("AvailableUntil", value: "Available until %@", comment: ""), DateFormatter.localizedString(from: deadline, dateStyle: .none, timeStyle: .short))}
		durationItem.title=String(format: NSLocalizedString("StatusAvailableFor", value: "Available for: %@", comment: ""), state.duration.title)
		for item in durationMenu.items{item.state=item.tag==state.duration.rawValue ? .on : .off}
		sendItem.isEnabled=state.canSendFiles
		checkUpdatesItem.title=state.checkingForUpdates ? NSLocalizedString("CheckingForUpdates", value: "Checking for updates…", comment: "") : NSLocalizedString("CheckForUpdates", value: "Check for Updates…", comment: "")
		checkUpdatesItem.isEnabled = !state.checkingForUpdates
		updateAvailableItem.isHidden=state.availableUpdateVersion==nil
		if let version=state.availableUpdateVersion{updateAvailableItem.title=String(format: NSLocalizedString("UpdateAvailableStatus", value: "Update available: %@", comment: ""), version)}
		receivingItem.title=state.receiving ? NSLocalizedString("MenuReceivingOn", value: "Receiving: On", comment: "") : NSLocalizedString("MenuReceivingOff", value: "Receiving: Off", comment: "")
		receivingItem.state=state.receiving ? .on : .off
		toolTip=Self.toolTip(for: state)
		updateStatusItem(state)
	}

	private func updateTransferItems(_ transfers:[TransferSummary]){
		let ordered=transfers.filter {$0.direction == .outgoing}+transfers.filter {$0.direction == .incoming}
		let signature=ordered.map {"\($0.id)|\($0.direction)|\($0.phase)"}.joined(separator: "\u{1F}")
		if signature != transferSignature{
			transferSignature=signature
			rebuildTransferItems(ordered)
		}
		for (item, transfer) in zip(transferRowItems, ordered){item.title=Self.title(for: transfer)}
	}

	private func rebuildTransferItems(_ transfers:[TransferSummary]){
		for item in transferItems{menu.removeItem(item)}
		transferItems.removeAll()
		transferRowItems.removeAll()
		guard !transfers.isEmpty else{return}
		var index=menu.index(of: statusSeparator)
		if index<0{index=0}
		var cancelAdded=false
		for transfer in transfers{
			let item=NSMenuItem()
			item.target=self
			item.action = transfer.phase == .awaitingReview ? #selector(reviewIncoming(_:)) : #selector(showApp(_:))
			item.representedObject=transfer.id
			item.image=Self.transferImage(for: transfer)
			menu.insertItem(item, at: index)
			index += 1
			transferItems.append(item)
			transferRowItems.append(item)
			if transfer.direction == .outgoing && !cancelAdded{
				cancelTransferItem.isEnabled=true
				menu.insertItem(cancelTransferItem, at: index)
				index += 1
				transferItems.append(cancelTransferItem)
				cancelAdded=true
			}
		}
	}

	private func updateStatusItem(_ state:State){
		guard let button=statusItem?.button else{return}
		let single=state.transfers.count == 1 ? state.transfers.first : nil
		let percent=single.flatMap {Self.percent($0.progress)}
		let pending=state.transfers.contains {$0.phase == .awaitingReview}
		let badge=pending || state.availableUpdateVersion != nil || (!state.transfers.isEmpty && percent==nil)
		let dimmed = !state.receiving && state.transfers.isEmpty
		button.image=Self.makeIcon(dimmed: dimmed, badge: badge)
		button.imagePosition = .imageLeading
		button.title=percent.map {"\($0)%"} ?? ""
	}

	private static func percent(_ progress:Double?) -> Int?{
		guard let progress=progress, progress.isFinite else{return nil}
		return Int((max(0, min(1, progress))*100).rounded())
	}

	private static func title(for transfer:TransferSummary) -> String{
		switch transfer.phase{
		case .awaitingReview:
			return String(format: NSLocalizedString("MenuIncomingReview", value: "Incoming from %@ — Review request…", comment: ""), transfer.deviceName)
		case .connecting:
			return String(format: NSLocalizedString("MenuConnectingTo", value: "Connecting to %@…", comment: ""), transfer.deviceName)
		case .awaitingApproval:
			return String(format: NSLocalizedString("MenuWaitingForApproval", value: "Waiting for %@ to accept…", comment: ""), transfer.deviceName)
		case .transferring:
			if let percent=percent(transfer.progress){
				if transfer.direction == .outgoing{
					return String(format: NSLocalizedString("MenuSendingToPercent", value: "Sending to %@ · %d%%", comment: ""), transfer.deviceName, percent)
				}else{
					return String(format: NSLocalizedString("MenuReceivingFromPercent", value: "Receiving from %@ · %d%%", comment: ""), transfer.deviceName, percent)
				}
			}
			return transfer.direction == .outgoing
				? String(format: NSLocalizedString("MenuSendingTo", value: "Sending to %@…", comment: ""), transfer.deviceName)
				: String(format: NSLocalizedString("MenuReceivingFrom", value: "Receiving from %@…", comment: ""), transfer.deviceName)
		}
	}

	private static func toolTip(for state:State) -> String{
		if state.transfers.count == 1, let transfer=state.transfers.first{
			return String(format: NSLocalizedString("MenuTransferTooltip", value: "QuickShareMac · %@. Click for menu.", comment: ""), toolTipDescription(for: transfer))
		}
		if state.transfers.count>1{
			return String(format: NSLocalizedString("MenuTransfersTooltip", value: "QuickShareMac · %d active transfers. Click for menu.", comment: ""), state.transfers.count)
		}
		if let version=state.availableUpdateVersion{
			return String(format: NSLocalizedString("MenuUpdateTooltip", value: "QuickShareMac · Update %@ available. Click for menu.", comment: ""), version)
		}
		return state.receiving ? NSLocalizedString("MenuReceivingOnTooltip", value: "QuickShareMac · Receiving on. Click for menu.", comment: "") : NSLocalizedString("MenuReceivingOffTooltip", value: "QuickShareMac · Receiving off. Click for menu.", comment: "")
	}

	private static func toolTipDescription(for transfer:TransferSummary) -> String{
		switch transfer.phase{
		case .awaitingReview:
			return String(format: NSLocalizedString("MenuIncomingFromTooltip", value: "Incoming transfer from %@", comment: ""), transfer.deviceName)
		case .connecting:
			return String(format: NSLocalizedString("MenuConnectingTooltip", value: "Connecting to %@", comment: ""), transfer.deviceName)
		case .awaitingApproval:
			return String(format: NSLocalizedString("MenuWaitingForApprovalTooltip", value: "Waiting for %@ to accept", comment: ""), transfer.deviceName)
		case .transferring:
			if let percent=percent(transfer.progress){
				if transfer.direction == .outgoing{
					return String(format: NSLocalizedString("MenuSendingPercentTooltip", value: "Sending to %@ (%d%%)", comment: ""), transfer.deviceName, percent)
				}else{
					return String(format: NSLocalizedString("MenuReceivingPercentTooltip", value: "Receiving from %@ (%d%%)", comment: ""), transfer.deviceName, percent)
				}
			}
			return transfer.direction == .outgoing
				? String(format: NSLocalizedString("MenuSendingTooltip", value: "Sending to %@", comment: ""), transfer.deviceName)
				: String(format: NSLocalizedString("MenuReceivingTooltip", value: "Receiving from %@", comment: ""), transfer.deviceName)
		}
	}

	private static func transferImage(for transfer:TransferSummary) -> NSImage?{
		switch transfer.phase{
		case .awaitingReview:
			return menuImage("exclamationmark.circle.fill")
		case .connecting, .awaitingApproval:
			return menuImage(transfer.direction == .outgoing ? "arrow.up.circle" : "arrow.down.circle")
		case .transferring:
			return menuImage(transfer.direction == .outgoing ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
		}
	}

	private func addItem(_ title:String, action:Selector, key:String = ""){
		let item=menu.addItem(withTitle: title, action: action, keyEquivalent: key)
		item.target=self
	}
	@objc private func showApp(_ sender:NSMenuItem){onShow?()}
	@objc private func openReceivedFiles(_ sender:NSMenuItem){onOpenReceivedFiles?()}
	@objc private func sendFiles(_ sender:NSMenuItem){if stateProvider().canSendFiles{onSendFiles?()}}
	@objc private func toggleReceiving(_ sender:NSMenuItem){onToggleReceiving?(); refresh()}
	@objc private func selectDuration(_ sender:NSMenuItem){
		if let duration=ReceivingDuration(rawValue: sender.tag){onDurationChange?(duration); refresh()}
	}
	@objc private func reviewIncoming(_ sender:NSMenuItem){
		guard let id=sender.representedObject as? String else{return}
		onReviewIncoming?(id)
	}
	@objc private func cancelTransfer(_ sender:NSMenuItem){onCancelTransfer?()}
	@objc private func settings(_ sender:NSMenuItem){onSettings?()}
	@objc private func checkForUpdates(_ sender:NSMenuItem){if !stateProvider().checkingForUpdates{onCheckForUpdates?()}}
	@objc private func viewRelease(_ sender:NSMenuItem){if stateProvider().availableUpdateVersion != nil{onViewRelease?()}}
	@objc private func quit(_ sender:NSMenuItem){onQuit?()}
}
