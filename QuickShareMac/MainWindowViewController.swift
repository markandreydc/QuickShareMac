import Cocoa
import NearbyShare

enum TransferDecision:Equatable{
	case accept, acceptAndRemember, decline
}

enum IncomingTransferState{
	case awaitingApproval, receiving, completed, failed
}

struct IncomingTransferDisplay{
	let id:String
	let deviceName:String
	let description:String
	let status:String
	let state:IncomingTransferState
	let progress:Double?
	let pinCode:String?
	let remembered:Bool
	let receivedBytes:Int64
	let totalBytes:Int64
	let savedFileURLs:[URL]
}

enum WindowUI{
	static func stack(_ orientation:NSUserInterfaceLayoutOrientation = .vertical, spacing:CGFloat = 8) -> NSStackView{
		let stack=NSStackView()
		stack.orientation=orientation
		stack.alignment=orientation == .vertical ? .leading : .centerY
		stack.spacing=spacing
		stack.detachesHiddenViews=true
		return stack
	}

	static func label(_ text:String, size:CGFloat = 13, weight:NSFont.Weight = .regular, secondary:Bool = false) -> NSTextField{
		let label=NSTextField(wrappingLabelWithString: text)
		label.font=NSFont.systemFont(ofSize: size, weight: weight)
		label.textColor=secondary ? .secondaryLabelColor : .labelColor
		label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		return label
	}

	static func fill(_ child:NSView, in stack:NSStackView){
		stack.addArrangedSubview(child)
		child.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -stack.edgeInsets.left-stack.edgeInsets.right).isActive=true
	}

	static func pin(_ child:NSView, to parent:NSView, inset:CGFloat){
		child.translatesAutoresizingMaskIntoConstraints=false
		parent.addSubview(child)
		NSLayoutConstraint.activate([
			child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
			child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
			child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
			child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
		])
	}

	static func spacer() -> NSView{
		let spacer=NSView()
		spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
		return spacer
	}

	static func symbol(_ name:String, description:String) -> NSImageView{
		let image:NSImage?
		if #available(macOS 11.0, *){
			image=NSImage(systemSymbolName: name, accessibilityDescription: description)
		}else{
			image=NSImage(named: NSImage.multipleDocumentsName)
		}
		let view=NSImageView(image: image ?? NSImage())
		view.imageScaling = .scaleProportionallyUpOrDown
		view.setAccessibilityLabel(description)
		return view
	}
}

class CardView:NSView{
	override var wantsUpdateLayer:Bool { true }
	override func updateLayer(){
		layer?.backgroundColor=NSColor.controlBackgroundColor.cgColor
		layer?.cornerRadius=12
		layer?.borderColor=NSColor.separatorColor.withAlphaComponent(0.35).cgColor
		layer?.borderWidth=1
	}
	override func viewDidChangeEffectiveAppearance(){
		super.viewDidChangeEffectiveAppearance()
		needsDisplay=true
	}
}

final class FlippedDocumentView:NSView{
	override var isFlipped:Bool { true }
}

class WindowBackgroundView:NSView{
	override var wantsUpdateLayer:Bool {true}
	override func updateLayer(){layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor}
	override func viewDidChangeEffectiveAppearance(){
		super.viewDidChangeEffectiveAppearance()
		needsDisplay=true
	}
}

private final class TransferRowView:CardView{
	private let content=WindowUI.stack(spacing: 8)
	private let name=WindowUI.label("", size: 14, weight: .semibold)
	private let details=WindowUI.label("")
	private let status=WindowUI.label("", size: 12, secondary: true)
	private let progress=NSProgressIndicator()
	private let remember=NSButton(checkboxWithTitle: NSLocalizedString("RememberDeviceName", value: "Remember this device name", comment: ""), target: nil, action: nil)
	private var transfer:IncomingTransferDisplay?
	private var prominent=false
	var onDecision:((String,TransferDecision)->Void)?
	var onReveal:((String)->Void)?
	var onDismiss:((String)->Void)?

	init(){
		super.init(frame: .zero)
		wantsLayer=true
		name.maximumNumberOfLines=2
		details.maximumNumberOfLines=3
		WindowUI.pin(content, to: self, inset: 16)
	}
	required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}

	func update(_ transfer:IncomingTransferDisplay, prominent:Bool = false){
		let rebuild=self.transfer?.id != transfer.id || self.transfer?.state != transfer.state || self.transfer?.remembered != transfer.remembered || self.transfer?.pinCode != transfer.pinCode || self.prominent != prominent
		self.transfer=transfer
		self.prominent=prominent
		name.stringValue=transfer.deviceName
		name.toolTip=transfer.deviceName
		details.stringValue=transfer.description
		details.toolTip=transfer.description
		status.stringValue=transfer.status
		if rebuild{rebuildContent()}
		if transfer.state == .receiving{
			progress.isIndeterminate=transfer.progress==nil
			if let fraction=transfer.progress{
				progress.stopAnimation(nil)
				progress.doubleValue=max(0, min(1, fraction))*100
			}else{
				progress.startAnimation(nil)
			}
			if transfer.totalBytes>0{
				let received=ByteCountFormatter.string(fromByteCount: transfer.receivedBytes, countStyle: .file)
				let total=ByteCountFormatter.string(fromByteCount: transfer.totalBytes, countStyle: .file)
				status.stringValue="\(transfer.status) · \(received) / \(total)"
			}
		}
	}

	private func rebuildContent(){
		guard let transfer=transfer else {return}
		progress.stopAnimation(nil)
		for child in content.arrangedSubviews{content.removeArrangedSubview(child); child.removeFromSuperview()}
		let heading=WindowUI.stack(.horizontal)
		let symbolName=transfer.state == .completed ? "checkmark.circle.fill" : transfer.state == .failed ? "exclamationmark.triangle.fill" : "arrow.down.doc"
		let symbol=WindowUI.symbol(symbolName, description: transfer.status)
		symbol.contentTintColor=transfer.state == .completed ? .systemGreen : transfer.state == .failed ? .systemOrange : .secondaryLabelColor
		NSLayoutConstraint.activate([symbol.widthAnchor.constraint(equalToConstant: 22), symbol.heightAnchor.constraint(equalToConstant: 22)])
		heading.addArrangedSubview(symbol)
		heading.addArrangedSubview(name)
		heading.addArrangedSubview(WindowUI.spacer())
		WindowUI.fill(heading, in: content)
		WindowUI.fill(details, in: content)
		if transfer.state == .awaitingApproval && prominent{
			if transfer.remembered{
				WindowUI.fill(WindowUI.label(NSLocalizedString("PreviouslySeenName", value: "Name seen before · always verify the PIN", comment: ""), size: 12, secondary: true), in: content)
			}
			let pin=WindowUI.label(transfer.pinCode ?? "—", size: 28, weight: .semibold)
			pin.font=NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
			pin.setAccessibilityLabel(NSLocalizedString("VerificationPIN", value: "Verification PIN", comment: ""))
			WindowUI.fill(pin, in: content)
			WindowUI.fill(WindowUI.label(NSLocalizedString("VerifyPin", value: "Check that the PIN matches on the sending device.", comment: ""), size: 12, secondary: true), in: content)
			if !transfer.remembered{
				remember.state = .off
				remember.toolTip=NSLocalizedString("RememberNameExplanation", value: "Remembering a name does not verify identity or skip approval. Always check the PIN.", comment: "")
				WindowUI.fill(remember, in: content)
				WindowUI.fill(WindowUI.label(NSLocalizedString("RememberNameExplanation", value: "Remembering a name does not verify identity or skip approval. Always check the PIN.", comment: ""), size: 11, secondary: true), in: content)
			}
			let actions=WindowUI.stack(.horizontal)
			actions.addArrangedSubview(WindowUI.spacer())
			let decline=NSButton(title: NSLocalizedString("Decline", value: "Decline", comment: ""), target: self, action: #selector(decline(_:)))
			decline.bezelStyle = .rounded
			actions.addArrangedSubview(decline)
			let accept=NSButton(title: NSLocalizedString("Accept", value: "Accept", comment: ""), target: self, action: #selector(accept(_:)))
			accept.bezelStyle = .rounded
			accept.bezelColor = .controlAccentColor
			// Deliberately no Return shortcut: an incoming request must not capture a stray keystroke.
			actions.addArrangedSubview(accept)
			WindowUI.fill(actions, in: content)
		}else{
			if transfer.state == .receiving{
				progress.style = .bar
				progress.controlSize = .small
				progress.minValue=0
				progress.maxValue=100
				WindowUI.fill(progress, in: content)
			}
			WindowUI.fill(status, in: content)
			if transfer.state == .failed{
				WindowUI.fill(WindowUI.label(NSLocalizedString("IncomingFailureHelp", value: "Ask the sender to try again. Keep both devices on the same Wi-Fi network and check available disk space.", comment: ""), size: 12, secondary: true), in: content)
			}
			if transfer.state == .completed || transfer.state == .failed{
				let actions=WindowUI.stack(.horizontal)
				if transfer.state == .completed && !transfer.savedFileURLs.isEmpty{
					let reveal=NSButton(title: NSLocalizedString("ShowInFinder", value: "Show in Finder", comment: ""), target: self, action: #selector(reveal(_:)))
					reveal.bezelStyle = .inline
					actions.addArrangedSubview(reveal)
				}
				actions.addArrangedSubview(WindowUI.spacer())
				let dismiss=NSButton(title: NSLocalizedString("Dismiss", value: "Dismiss", comment: ""), target: self, action: #selector(dismiss(_:)))
				dismiss.bezelStyle = .inline
				actions.addArrangedSubview(dismiss)
				WindowUI.fill(actions, in: content)
			}
		}
	}

	@objc private func accept(_ sender:NSButton){
		guard let transfer=transfer else {return}
		onDecision?(transfer.id, !transfer.remembered && remember.state == .on ? .acceptAndRemember : .accept)
	}
	@objc private func decline(_ sender:NSButton){if let id=transfer?.id{onDecision?(id, .decline)}}
	@objc private func reveal(_ sender:NSButton){if let id=transfer?.id{onReveal?(id)}}
	@objc private func dismiss(_ sender:NSButton){if let id=transfer?.id{onDismiss?(id)}}
}

final class MainWindowViewController:NSViewController{
	static let defaultSize=NSSize(width: 560, height: 480)
	static let minimumSize=NSSize(width: 520, height: 480)
	let sendController=SendViewController()
	private let tabs=NSSegmentedControl(labels: [NSLocalizedString("ReceiveTab", value: "Receive", comment: ""), NSLocalizedString("SendTab", value: "Send", comment: "")], trackingMode: .selectOne, target: nil, action: nil)
	private let receiveContent=WindowUI.stack(spacing: 16)
	var onReceivingChange:((Bool)->Void)?
	var onDurationChange:((ReceivingDuration)->Void)?
	var onOpenSettings:(()->Void)?
	var onAlwaysOnTopChange:((Bool)->Void)?
	private(set) var isAlwaysOnTop=false
	private let pinButton=NSButton()
	var onTransferDecision:((String,TransferDecision)->Void)?
	var onRevealTransfer:((String)->Void)?
	var onDismissTransfer:((String)->Void)?
	var onClearRecentTransfers:(()->Void)?
	private let receivingSwitch=NSSwitch()
	private let deviceNameLabel=WindowUI.label("", size: 12, secondary: true)
	private let durationPopup=NSPopUpButton(frame: .zero, pullsDown: false)
	private let expiryLabel=WindowUI.label("", size: 11, secondary: true)
	private let statusLabel=WindowUI.label("", size: 15, weight: .semibold)
	private let visibilityLabel=WindowUI.label("", size: 12, secondary: true)
	private let approvalTitle=WindowUI.label("", size: 13, weight: .semibold)
	private let approvalRow=TransferRowView()
	private let approvalStack=WindowUI.stack(spacing: 8)
	private let scrollView=NSScrollView()
	private let rows=WindowUI.stack(spacing: 12)
	private let empty=WindowUI.stack(spacing: 10)
	private let emptyTitle=WindowUI.label("", size: 16, weight: .semibold)
	private let emptyDetail=WindowUI.label("", secondary: true)
	private let enableButton=NSButton(title: NSLocalizedString("EnableReceiving", value: "Enable receiving", comment: ""), target: nil, action: nil)
	private var transferRows:[String:TransferRowView]=[:]
	private var listKeys:[String]=[]
	private var pendingApprovalID:String?
	private let recentHeading=WindowUI.stack(.horizontal)
	private let activeHeading=WindowUI.label(NSLocalizedString("IncomingTransfers", value: "Incoming transfers", comment: ""), size: 13, weight: .semibold)
	private var receiving=false

	override func loadView(){
		let drop=SendDropView(frame: NSRect(origin: .zero, size: Self.defaultSize))
		drop.onURLs={ [weak self] urls in
			guard let self=self else {return false}
			self.showSend()
			return self.sendController.selectItems(urls)
		}
		view=drop
		view.wantsLayer=true
		let content=WindowUI.stack(spacing: 16)
		WindowUI.pin(content, to: view, inset: 20)
		let header=WindowUI.stack(.horizontal, spacing: 12)
		let icon=NSImageView(image: NSImage(named: "QuickShareMacBrandIcon") ?? NSImage())
		icon.imageScaling = .scaleProportionallyUpOrDown
		NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 36), icon.heightAnchor.constraint(equalToConstant: 36)])
		header.addArrangedSubview(icon)
		let titles=WindowUI.stack(spacing: 2)
		titles.addArrangedSubview(WindowUI.label("QuickShareMac", size: 19, weight: .semibold))
		deviceNameLabel.maximumNumberOfLines=1
		deviceNameLabel.lineBreakMode = .byTruncatingMiddle
		deviceNameLabel.stringValue=LocalDeviceIdentity.shared.deviceName
		WindowUI.fill(deviceNameLabel, in: titles)
		header.addArrangedSubview(titles)
		header.addArrangedSubview(WindowUI.spacer())
		let settings=NSButton(title: NSLocalizedString("Settings", value: "Settings…", comment: ""), target: self, action: #selector(openSettings(_:)))
		settings.bezelStyle = .inline
		header.addArrangedSubview(settings)
		pinButton.identifier=NSUserInterfaceItemIdentifier("AlwaysOnTopPin")
		pinButton.setButtonType(.pushOnPushOff)
		pinButton.isBordered=false
		pinButton.imagePosition = .imageOnly
		pinButton.setAccessibilityLabel(NSLocalizedString("AlwaysOnTop", value: "Always on top", comment: ""))
		pinButton.target=self
		pinButton.action=#selector(toggleAlwaysOnTop(_:))
		NSLayoutConstraint.activate([pinButton.widthAnchor.constraint(equalToConstant: 28),pinButton.heightAnchor.constraint(equalToConstant: 28)])
		header.addArrangedSubview(pinButton)
		updatePinButton()
		WindowUI.fill(header, in: content)
		tabs.selectedSegment=0
		tabs.target=self
		tabs.action=#selector(tabChanged(_:))
		tabs.setAccessibilityLabel(NSLocalizedString("TransferMode", value: "Transfer mode", comment: ""))
		content.addArrangedSubview(tabs)
		let tabHost=NSView()
		WindowUI.fill(tabHost, in: content)
		tabHost.setContentHuggingPriority(.defaultLow, for: .vertical)
		WindowUI.pin(receiveContent, to: tabHost, inset: 0)
		sendController.onTransferActivityChange={ [weak drop] active in drop?.acceptsItems = !active }
		addChild(sendController)
		WindowUI.pin(sendController.view, to: tabHost, inset: 0)
		sendController.view.isHidden=true

		let developerCredit=WindowUI.label(NSLocalizedString("DeveloperCredit", value: "Developed by Mark Andrey · github.com/markandreydc", comment: ""), size: 11, secondary: true)
		developerCredit.identifier=NSUserInterfaceItemIdentifier("MainDeveloperCreditFooter")
		developerCredit.alignment = .center
		developerCredit.setContentHuggingPriority(.required, for: .vertical)
		developerCredit.setContentCompressionResistancePriority(.required, for: .vertical)
		WindowUI.fill(developerCredit, in: content)

		let receiveCard=CardView()
		receiveCard.wantsLayer=true
		let receiveCardContent=WindowUI.stack(spacing: 5)
		WindowUI.pin(receiveCardContent, to: receiveCard, inset: 14)
		let receiveRow=WindowUI.stack(.horizontal)
		receiveRow.addArrangedSubview(statusLabel)
		receiveRow.addArrangedSubview(WindowUI.spacer())
		receivingSwitch.target=self
		receivingSwitch.action=#selector(receivingChanged(_:))
		receivingSwitch.setAccessibilityLabel(NSLocalizedString("ReceivingEnabled", value: "Receiving enabled", comment: ""))
		receiveRow.addArrangedSubview(receivingSwitch)
		WindowUI.fill(receiveRow, in: receiveCardContent)
		WindowUI.fill(visibilityLabel, in: receiveCardContent)
		let durationRow=WindowUI.stack(.horizontal)
		durationRow.addArrangedSubview(WindowUI.label(NSLocalizedString("AvailableFor", value: "Available for", comment: ""), size: 12, secondary: true))
		for duration in ReceivingDuration.allCases{durationPopup.addItem(withTitle: duration.title); durationPopup.lastItem?.tag=duration.rawValue}
		durationPopup.target=self
		durationPopup.action=#selector(durationChanged(_:))
		durationPopup.setAccessibilityLabel(NSLocalizedString("AvailableFor", value: "Available for", comment: ""))
		durationPopup.selectItem(withTag: ReceivingDuration.indefinitely.rawValue)
		durationRow.addArrangedSubview(durationPopup)
		durationRow.addArrangedSubview(expiryLabel)
		WindowUI.fill(durationRow, in: receiveCardContent)
		WindowUI.fill(receiveCard, in: receiveContent)
		WindowUI.fill(approvalTitle, in: approvalStack)
		WindowUI.fill(approvalRow, in: approvalStack)
		approvalRow.onDecision={ [weak self] id, decision in self?.onTransferDecision?(id, decision) }

		scrollView.hasVerticalScroller=true
		scrollView.autohidesScrollers=true
		scrollView.borderType = .noBorder
		scrollView.drawsBackground=false
		scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
		let document=FlippedDocumentView()
		document.translatesAutoresizingMaskIntoConstraints=false
		scrollView.documentView=document
		WindowUI.pin(rows, to: document, inset: 0)
		document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive=true
		WindowUI.fill(scrollView, in: receiveContent)
		scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive=true

		empty.alignment = .centerX
		let symbol=WindowUI.symbol("tray.and.arrow.down", description: NSLocalizedString("IncomingTransfers", value: "Incoming transfers", comment: ""))
		symbol.contentTintColor = .secondaryLabelColor
		NSLayoutConstraint.activate([symbol.widthAnchor.constraint(equalToConstant: 40), symbol.heightAnchor.constraint(equalToConstant: 40)])
		empty.addArrangedSubview(symbol)
		emptyTitle.alignment = .center
		emptyDetail.alignment = .center
		WindowUI.fill(emptyTitle, in: empty)
		WindowUI.fill(emptyDetail, in: empty)
		enableButton.bezelStyle = .rounded
		enableButton.target=self
		enableButton.action=#selector(enableReceiving(_:))
		empty.addArrangedSubview(enableButton)
		empty.edgeInsets=NSEdgeInsets(top: 24, left: 12, bottom: 24, right: 12)
		recentHeading.addArrangedSubview(WindowUI.label(NSLocalizedString("RecentTransfers", value: "Recent transfers · this session", comment: ""), size: 13, weight: .semibold))
		recentHeading.addArrangedSubview(WindowUI.spacer())
		let clear=NSButton(title: NSLocalizedString("ClearRecent", value: "Clear", comment: ""), target: self, action: #selector(clearRecent(_:)))
		clear.bezelStyle = .inline
		recentHeading.addArrangedSubview(clear)
		let footer=WindowUI.stack(.horizontal)
		footer.addArrangedSubview(WindowUI.label(NSLocalizedString("SavedToDownloads", value: "Received files are saved to Downloads", comment: ""), size: 11, secondary: true))
		footer.addArrangedSubview(WindowUI.spacer())
		let downloads=NSButton(title: NSLocalizedString("OpenDownloads", value: "Open Downloads", comment: ""), target: self, action: #selector(openDownloads(_:)))
		downloads.bezelStyle = .inline
		footer.addArrangedSubview(downloads)
		WindowUI.fill(footer, in: receiveContent)
	}

	override func viewDidAppear(){
		super.viewDidAppear()
		view.window?.level=isAlwaysOnTop ? .floating : .normal
		sendController.setActive(tabs.selectedSegment==1)
	}
	override func viewWillDisappear(){super.viewWillDisappear(); sendController.setActive(false)}
	func setAlwaysOnTop(_ enabled:Bool){
		isAlwaysOnTop=enabled
		_ = view
		view.window?.level=enabled ? .floating : .normal
		updatePinButton()
	}
	private func updatePinButton(){
		pinButton.state=isAlwaysOnTop ? .on : .off
		pinButton.image=NSImage(systemSymbolName: isAlwaysOnTop ? "pin.fill" : "pin", accessibilityDescription: nil)
		pinButton.contentTintColor=isAlwaysOnTop ? .controlAccentColor : .secondaryLabelColor
		pinButton.toolTip=isAlwaysOnTop ? NSLocalizedString("UnpinWindow", value: "Turn off always on top", comment: "") : NSLocalizedString("PinWindow", value: "Keep window on top", comment: "")
	}
	@objc private func toggleAlwaysOnTop(_ sender:NSButton){
		setAlwaysOnTop(!isAlwaysOnTop)
		onAlwaysOnTopChange?(isAlwaysOnTop)
	}
	func showReceive(){
		_ = view
		tabs.selectedSegment=0
		updateTab()
	}
	func showSend(){
		_ = view
		tabs.selectedSegment=1
		updateTab()
	}
	private func updateTab(){
		view.window?.makeFirstResponder(nil)
		receiveContent.isHidden=tabs.selectedSegment != 0
		sendController.view.isHidden=tabs.selectedSegment != 1
		sendController.setActive(tabs.selectedSegment==1)
	}
	@objc private func tabChanged(_ sender:NSSegmentedControl){updateTab()}

	func update(receiving:Bool, transfers:[IncomingTransferDisplay], deviceName:String = LocalDeviceIdentity.shared.deviceName, duration:ReceivingDuration = .indefinitely, expiresAt:Date?=nil){
		_ = view
		self.receiving=receiving
		deviceNameLabel.stringValue=deviceName
		deviceNameLabel.toolTip=deviceName
		durationPopup.selectItem(withTag: duration.rawValue)
		expiryLabel.isHidden = !receiving || expiresAt==nil
		if let deadline=expiresAt{expiryLabel.stringValue=String(format: NSLocalizedString("AvailableUntil", value: "Available until %@", comment: ""), DateFormatter.localizedString(from: deadline, dateStyle: .none, timeStyle: .short))}
		receivingSwitch.state=receiving ? .on : .off
		statusLabel.stringValue=receiving ? NSLocalizedString("ReadyToReceive", value: "Ready to receive", comment: "") : NSLocalizedString("ReceivingOff", value: "Receiving off", comment: "")
		visibilityLabel.stringValue=receiving ? NSLocalizedString("ReceivingVisibility", value: "Visible to everyone on your network while receiving.", comment: "") : NSLocalizedString("ReceivingOffDetail", value: "New requests are paused. Transfers in progress can finish.", comment: "")
		let pending=transfers.filter {$0.state == .awaitingApproval}
		let newApproval=pending.first?.id != nil && pending.first?.id != pendingApprovalID
		pendingApprovalID=pending.first?.id
		approvalStack.isHidden=pending.isEmpty
		if let first=pending.first{
			approvalTitle.stringValue=pending.count==1 ? NSLocalizedString("IncomingRequest", value: "Incoming request", comment: "") : String.localizedStringWithFormat(NSLocalizedString("PendingRequestCount", value: "Incoming request · %d waiting", comment: ""), pending.count)
			approvalRow.update(first, prominent: true)
		}
		let active=transfers.filter {$0.state == .receiving || ($0.state == .awaitingApproval && $0.id != pending.first?.id)}
		let recent=transfers.filter {$0.state == .completed || $0.state == .failed}
		let visible=active+recent
		let visibleIDs=Set(visible.map(\.id))
		for id in Array(transferRows.keys) where !visibleIDs.contains(id){
			transferRows.removeValue(forKey: id)?.removeFromSuperview()
		}
		for transfer in visible{
			let row=transferRows[transfer.id] ?? TransferRowView()
			row.onDecision={ [weak self] id, decision in self?.onTransferDecision?(id, decision) }
			row.onReveal={ [weak self] id in self?.onRevealTransfer?(id) }
			row.onDismiss={ [weak self] id in self?.onDismissTransfer?(id) }
			row.update(transfer)
			transferRows[transfer.id]=row
		}
		emptyTitle.stringValue=receiving ? NSLocalizedString("ReadyToReceive", value: "Ready to receive", comment: "") : NSLocalizedString("ReceivingOff", value: "Receiving off", comment: "")
		emptyDetail.stringValue=receiving ? String(format: NSLocalizedString("ReceiveInstructions", value: "Open Quick Share on your Android device and choose “%@”.\nBoth devices must be on the same Wi-Fi network.", comment: ""), deviceName) : NSLocalizedString("EnableReceivingHint", value: "Enable receiving to let nearby devices send files to this Mac.", comment: "")
		enableButton.isHidden=receiving
		var desired:[(String,NSView)]=[]
		if !pending.isEmpty{desired.append(("approval",approvalStack))}
		if transfers.isEmpty{desired.append(("empty",empty))}
		if !active.isEmpty{
			desired.append(("active",activeHeading))
			desired += active.compactMap { transfer in transferRows[transfer.id].map {("transfer:"+transfer.id,$0)} }
		}
		if !recent.isEmpty{
			desired.append(("recent",recentHeading))
			desired += recent.compactMap { transfer in transferRows[transfer.id].map {("transfer:"+transfer.id,$0)} }
		}
		if desired.map({$0.0}) != listKeys{
			for child in rows.arrangedSubviews{rows.removeArrangedSubview(child); child.removeFromSuperview()}
			for (_, child) in desired{WindowUI.fill(child, in: rows)}
			listKeys=desired.map {$0.0}
		}
		if newApproval{
			view.layoutSubtreeIfNeeded()
			scrollView.contentView.scroll(to: .zero)
			scrollView.reflectScrolledClipView(scrollView.contentView)
		}
	}

	@objc private func receivingChanged(_ sender:NSSwitch){onReceivingChange?(sender.state == .on)}
	@objc private func durationChanged(_ sender:NSPopUpButton){if let tag=sender.selectedItem?.tag, let duration=ReceivingDuration(rawValue: tag){onDurationChange?(duration)}}
	@objc private func enableReceiving(_ sender:NSButton){onReceivingChange?(true)}
	@objc private func openSettings(_ sender:NSButton){onOpenSettings?()}
	@objc private func clearRecent(_ sender:NSButton){onClearRecentTransfers?()}
	@objc private func openDownloads(_ sender:NSButton){
		if let url=FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first{NSWorkspace.shared.open(url)}
	}
}

final class SettingsViewController:NSViewController, NSTextFieldDelegate{
	enum Section:Int{case general, updates, about}
	static let defaultSize=NSSize(width: 560, height: 540)
	private(set) var selectedSection:Section = .general
	private let sections=NSSegmentedControl(labels: [NSLocalizedString("GeneralSettings", value: "General", comment: ""),NSLocalizedString("UpdatesSettings", value: "Updates", comment: ""),NSLocalizedString("AboutSettings", value: "About", comment: "")], trackingMode: .selectOne, target: nil, action: nil)
	private let pages=NSTabView()
	private let aboutVersionLabel=WindowUI.label("", size: 12, secondary: true)
	var onStartReceivingOnLaunchChange:((Bool)->Void)?
	var onLaunchAtLoginChange:((Bool)->Void)?
	var onOpenLoginItems:(()->Void)?
	var onForgetRememberedDevices:(()->Void)?
	var onDeviceNameChange:((String?) throws -> Void)?
	var onCheckForUpdates:(()->Void)?
	var onUpdateCheckFrequencyChange:((UpdateCheckFrequency)->Void)?
	var onViewRelease:(()->Void)?
	private let updateFrequency=NSPopUpButton(frame: .zero, pullsDown: false)
	private let checkUpdatesButton=NSButton(title: NSLocalizedString("CheckForUpdates", value: "Check for Updates…", comment: ""), target: nil, action: nil)
	private let viewReleaseButton=NSButton(title: NSLocalizedString("ViewRelease", value: "View Release", comment: ""), target: nil, action: nil)
	private let updateVersionLabel=WindowUI.label("", size: 12, secondary: true)
	private let updateStatusLabel=WindowUI.label("", size: 11, secondary: true)
	private let nameField=NSTextField(string: "")
	private let systemNameButton=NSButton(radioButtonWithTitle: NSLocalizedString("UseMacName", value: "Use Mac’s name", comment: ""), target: nil, action: nil)
	private let customNameButton=NSButton(radioButtonWithTitle: NSLocalizedString("UseCustomDeviceName", value: "Use a custom name", comment: ""), target: nil, action: nil)
	private let systemNameLabel=WindowUI.label("", size: 12, secondary: true)
	private let nameMessage=WindowUI.label("", size: 11, secondary: true)
	private let saveNameButton=NSButton(title: NSLocalizedString("SaveDeviceNameChanges", value: "Save changes", comment: ""), target: nil, action: nil)
	private let cancelNameButton=NSButton(title: NSLocalizedString("Cancel", value: "Cancel", comment: ""), target: nil, action: nil)
	private var savedCustomName:String?
	private var systemDeviceName=LocalDeviceIdentity.shared.systemDeviceName
	private var usesCustomName=false
	private var showNameValidation=false
	private var nameSaveError:String?
	private var nameConfirmation:DispatchWorkItem?
	private var savingName=false
	private let startReceivingButton=NSButton(checkboxWithTitle: NSLocalizedString("StartReceivingOnLaunch", value: "Start receiving when app opens", comment: ""), target: nil, action: nil)
	private let loginButton=NSButton(checkboxWithTitle: NSLocalizedString("LaunchAtLogin", value: "Launch at login", comment: ""), target: nil, action: nil)
	private let loginHelpButton=NSButton(title: NSLocalizedString("SetUpLoginItem", value: "Set up login item in System Settings…", comment: ""), target: nil, action: nil)
	private let rememberedCountLabel=WindowUI.label("", secondary: true)
	private let forgetButton=NSButton(title: NSLocalizedString("ForgetDevices", value: "Forget all", comment: ""), target: nil, action: nil)

	override func loadView(){
		view=WindowBackgroundView(frame: NSRect(origin: .zero, size: Self.defaultSize))
		view.wantsLayer=true
		sections.identifier=NSUserInterfaceItemIdentifier("SettingsSections")
		sections.setAccessibilityLabel(NSLocalizedString("SettingsSections", value: "Settings sections", comment: ""))
		sections.selectedSegment=selectedSection.rawValue
		sections.target=self
		sections.action=#selector(sectionChanged(_:))
		sections.translatesAutoresizingMaskIntoConstraints=false
		view.addSubview(sections)
		pages.tabViewType = .noTabsNoBorder
		pages.drawsBackground=false
		pages.translatesAutoresizingMaskIntoConstraints=false
		view.addSubview(pages)
		NSLayoutConstraint.activate([
			sections.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
			sections.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			pages.topAnchor.constraint(equalTo: sections.bottomAnchor, constant: 12),
			pages.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			pages.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			pages.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
		let general=page(.general)
		let device=card(NSLocalizedString("DeviceNameSetting", value: "Device name", comment: ""), in: general)
		WindowUI.fill(WindowUI.label(NSLocalizedString("DeviceNameExplanation", value: "Shown to nearby devices. Your Mac’s system name is unchanged.", comment: ""), size: 12, secondary: true), in: device)
		for button in [systemNameButton,customNameButton]{
			button.target=self
			button.action=#selector(nameModeChanged(_:))
		}
		device.addArrangedSubview(systemNameButton)
		systemNameLabel.identifier=NSUserInterfaceItemIdentifier("SystemDeviceName")
		WindowUI.fill(systemNameLabel, in: device)
		device.addArrangedSubview(customNameButton)
		nameField.identifier=NSUserInterfaceItemIdentifier("CustomDeviceName")
		nameField.setAccessibilityLabel(NSLocalizedString("CustomDeviceNameLabel", value: "Custom device name", comment: ""))
		nameField.placeholderString=NSLocalizedString("EnterDeviceName", value: "Enter a device name", comment: "")
		nameField.delegate=self
		WindowUI.fill(nameField, in: device)
		nameMessage.identifier=NSUserInterfaceItemIdentifier("DeviceNameMessage")
		WindowUI.fill(nameMessage, in: device)
		let nameActions=WindowUI.stack(.horizontal)
		cancelNameButton.target=self
		cancelNameButton.action=#selector(cancelNameChanges(_:))
		saveNameButton.target=self
		saveNameButton.action=#selector(saveName(_:))
		for button in [cancelNameButton,saveNameButton]{
			button.bezelStyle = .rounded
			nameActions.addArrangedSubview(button)
		}
		device.addArrangedSubview(nameActions)
		resetNameDraft()
		let startup=card(NSLocalizedString("StartupSettings", value: "Startup", comment: ""), in: general)
		startReceivingButton.target=self
		startReceivingButton.action=#selector(startReceivingChanged(_:))
		startup.addArrangedSubview(startReceivingButton)
		loginButton.target=self
		loginButton.action=#selector(launchAtLoginChanged(_:))
		startup.addArrangedSubview(loginButton)
		loginHelpButton.target=self
		loginHelpButton.action=#selector(openLoginItems(_:))
		loginHelpButton.bezelStyle = .inline
		startup.addArrangedSubview(loginHelpButton)
		if #available(macOS 13.0, *){loginHelpButton.isHidden=true}else{loginButton.isHidden=true}
		let remembered=card(NSLocalizedString("RememberedNames", value: "Remembered device names", comment: ""), in: general)
		WindowUI.fill(WindowUI.label(NSLocalizedString("RememberNameExplanation", value: "Remembering a name does not verify identity or skip approval. Always check the PIN.", comment: ""), size: 12, secondary: true), in: remembered)
		let rememberedRow=WindowUI.stack(.horizontal)
		rememberedRow.addArrangedSubview(rememberedCountLabel)
		rememberedRow.addArrangedSubview(WindowUI.spacer())
		forgetButton.bezelStyle = .inline
		forgetButton.target=self
		forgetButton.action=#selector(forgetDevices(_:))
		rememberedRow.addArrangedSubview(forgetButton)
		WindowUI.fill(rememberedRow, in: remembered)

		let updatePage=page(.updates)
		let updates=card(NSLocalizedString("UpdatesSettings", value: "Updates", comment: ""), in: updatePage)
		WindowUI.fill(updateVersionLabel, in: updates)
		let frequencyRow=WindowUI.stack(.horizontal)
		frequencyRow.addArrangedSubview(WindowUI.label(NSLocalizedString("UpdateCheckFrequencyLabel", value: "Check for updates:", comment: ""), size: 12))
		updateFrequency.identifier=NSUserInterfaceItemIdentifier("UpdateCheckFrequency")
		updateFrequency.setAccessibilityLabel(NSLocalizedString("UpdateCheckFrequencyLabel", value: "Check for updates:", comment: ""))
		for frequency in UpdateCheckFrequency.allCases{
			updateFrequency.addItem(withTitle: frequency.title)
			updateFrequency.lastItem?.representedObject=frequency.rawValue
		}
		updateFrequency.selectItem(withTitle: UpdateCheckFrequency.never.title)
		updateFrequency.target=self
		updateFrequency.action=#selector(updateFrequencyChanged(_:))
		frequencyRow.addArrangedSubview(updateFrequency)
		updates.addArrangedSubview(frequencyRow)
		WindowUI.fill(WindowUI.label(NSLocalizedString("UpdateChecksExplanation", value: "Checks GitHub for stable releases. Updates are downloaded and installed manually; nothing is installed automatically.", comment: ""), size: 11, secondary: true), in: updates)
		let updateActions=WindowUI.stack(.horizontal)
		checkUpdatesButton.target=self
		checkUpdatesButton.action=#selector(checkForUpdates(_:))
		checkUpdatesButton.bezelStyle = .rounded
		updateActions.addArrangedSubview(checkUpdatesButton)
		viewReleaseButton.target=self
		viewReleaseButton.action=#selector(viewRelease(_:))
		viewReleaseButton.bezelStyle = .rounded
		viewReleaseButton.isHidden=true
		updateActions.addArrangedSubview(viewReleaseButton)
		updates.addArrangedSubview(updateActions)
		updateStatusLabel.isHidden=true
		WindowUI.fill(updateStatusLabel, in: updates)

		let developerCredit=WindowUI.label(NSLocalizedString("DeveloperCredit", value: "Developed by Mark Andrey · github.com/markandreydc", comment: ""), size: 11, secondary: true)
		developerCredit.identifier=NSUserInterfaceItemIdentifier("DeveloperCreditFooter")
		let about=page(.about, footer: developerCredit)
		let identity=WindowUI.stack(spacing: 8)
		identity.alignment = .centerX
		let icon=NSImageView(image: NSImage(named: "QuickShareMacBrandIcon") ?? NSApp.applicationIconImage)
		icon.imageScaling = .scaleProportionallyUpOrDown
		NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 64),icon.heightAnchor.constraint(equalToConstant: 64)])
		identity.addArrangedSubview(icon)
		identity.addArrangedSubview(WindowUI.label("QuickShareMac", size: 22, weight: .semibold))
		identity.addArrangedSubview(aboutVersionLabel)
		let description=WindowUI.label(NSLocalizedString("AboutDescription", value: "Share files between your Mac and Android devices over your local network.", comment: ""), size: 12, secondary: true)
		description.alignment = .center
		WindowUI.fill(description, in: identity)
		WindowUI.fill(identity, in: about)
		let credits=card(NSLocalizedString("CreditsSettings", value: "Credits", comment: ""), in: about)
		WindowUI.fill(WindowUI.label(NSLocalizedString("UpstreamCredit", value: "Based on NearDrop by grishka · github.com/grishka/NearDrop", comment: ""), size: 11, secondary: true), in: credits)
		pages.selectTabViewItem(at: selectedSection.rawValue)
	}

	private func page(_ section:Section, footer:NSTextField?=nil)->NSStackView{
		let scroll=NSScrollView()
		scroll.drawsBackground=false
		scroll.hasVerticalScroller=true
		scroll.autohidesScrollers=true
		let document=FlippedDocumentView()
		document.translatesAutoresizingMaskIntoConstraints=false
		scroll.documentView=document
		document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive=true
		let content=WindowUI.stack(spacing: 14)
		WindowUI.pin(content, to: document, inset: 20)
		let item=NSTabViewItem(identifier: section.rawValue)
		if let footer=footer{
			let container=NSView()
			scroll.translatesAutoresizingMaskIntoConstraints=false
			footer.translatesAutoresizingMaskIntoConstraints=false
			footer.alignment = .center
			footer.setContentHuggingPriority(.required, for: .vertical)
			footer.setContentCompressionResistancePriority(.required, for: .vertical)
			container.addSubview(scroll)
			container.addSubview(footer)
			NSLayoutConstraint.activate([
				scroll.topAnchor.constraint(equalTo: container.topAnchor),
				scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
				scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
				scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
				footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
				footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
				footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
			])
			item.view=container
		}else{item.view=scroll}
		pages.addTabViewItem(item)
		return content
	}
	private func card(_ title:String, in parent:NSStackView)->NSStackView{
		let card=CardView()
		card.wantsLayer=true
		let content=WindowUI.stack(spacing: 10)
		WindowUI.pin(content, to: card, inset: 16)
		WindowUI.fill(WindowUI.label(title, size: 13, weight: .semibold), in: content)
		WindowUI.fill(card, in: parent)
		return content
	}
	func show(_ section:Section){
		_ = view
		selectedSection=section
		sections.selectedSegment=section.rawValue
		pages.selectTabViewItem(at: section.rawValue)
	}
	@objc private func sectionChanged(_ sender:NSSegmentedControl){
		if let section=Section(rawValue: sender.selectedSegment){show(section)}
	}

	func update(startReceivingOnLaunch:Bool, launchAtLogin:Bool, requiresLoginApproval:Bool, rememberedDeviceCount:Int, customDeviceName:String?=nil, systemDeviceName:String = LocalDeviceIdentity.shared.systemDeviceName){
		_ = view
		let hadNameDraft=hasNameDraftChanges
		let savedNameChanged=savedCustomName != customDeviceName
		savedCustomName=customDeviceName
		self.systemDeviceName=systemDeviceName
		systemNameLabel.stringValue=systemDeviceName
		if savedNameChanged && !hadNameDraft && !savingName{resetNameDraft()}
		else{
			if !usesCustomName && !hadNameDraft{nameField.stringValue=systemDeviceName}
			updateNameControls()
		}
		startReceivingButton.state=startReceivingOnLaunch ? .on : .off
		loginButton.state=launchAtLogin ? .on : .off
		if #available(macOS 13.0, *){loginHelpButton.isHidden = !requiresLoginApproval}
		rememberedCountLabel.stringValue=String.localizedStringWithFormat(NSLocalizedString("RememberedDevicesCount", value: "%d remembered device names", comment: ""), rememberedDeviceCount)
		forgetButton.isEnabled=rememberedDeviceCount>0
	}

	@objc private func startReceivingChanged(_ sender:NSButton){onStartReceivingOnLaunchChange?(sender.state == .on)}
	func updateUpdates(frequency:UpdateCheckFrequency, checking:Bool, currentVersion:String, availableRelease:UpdateRelease?, status:String){
		_ = view
		updateFrequency.selectItem(withTitle: frequency.title)
		checkUpdatesButton.isEnabled = !checking
		checkUpdatesButton.title=checking ? NSLocalizedString("CheckingForUpdates", value: "Checking for updates…", comment: "") : NSLocalizedString("CheckForUpdates", value: "Check for Updates…", comment: "")
		updateVersionLabel.stringValue=String(format: NSLocalizedString("InstalledVersion", value: "Version %@", comment: ""), currentVersion)
		aboutVersionLabel.stringValue=updateVersionLabel.stringValue
		viewReleaseButton.isHidden=availableRelease==nil
		updateStatusLabel.stringValue=status
		updateStatusLabel.isHidden=status.isEmpty
	}
	@objc private func updateFrequencyChanged(_ sender:NSPopUpButton){
		if let value=sender.selectedItem?.representedObject as? String, let frequency=UpdateCheckFrequency(rawValue: value){onUpdateCheckFrequencyChange?(frequency)}
	}
	@objc private func checkForUpdates(_ sender:NSButton){onCheckForUpdates?()}
	@objc private func viewRelease(_ sender:NSButton){onViewRelease?()}
	@objc private func launchAtLoginChanged(_ sender:NSButton){onLaunchAtLoginChange?(sender.state == .on)}
	@objc private func openLoginItems(_ sender:NSButton){onOpenLoginItems?()}
	@objc private func forgetDevices(_ sender:NSButton){onForgetRememberedDevices?()}
	private var hasNameDraftChanges:Bool{
		usesCustomName != (savedCustomName != nil) || (usesCustomName && nameField.stringValue != savedCustomName)
	}
	private func clearNameFeedback(){
		nameConfirmation?.cancel()
		nameConfirmation=nil
		nameSaveError=nil
	}
	private func resetNameDraft(){
		clearNameFeedback()
		usesCustomName=savedCustomName != nil
		nameField.stringValue=savedCustomName ?? systemDeviceName
		systemNameLabel.stringValue=systemDeviceName
		showNameValidation=false
		updateNameControls()
	}
	private func updateNameControls(){
		systemNameButton.state=usesCustomName ? .off : .on
		customNameButton.state=usesCustomName ? .on : .off
		nameField.isHidden = !usesCustomName
		let validated=try? LocalDeviceIdentity.validate(nameField.stringValue)
		let valid = !usesCustomName || validated != nil
		let candidate=usesCustomName ? validated : nil
		saveNameButton.isEnabled=valid && candidate != savedCustomName
		cancelNameButton.isEnabled=hasNameDraftChanges
		nameMessage.textColor = .secondaryLabelColor
		nameMessage.isHidden=false
		if let error=nameSaveError{
			nameMessage.stringValue=error
			nameMessage.textColor = .systemRed
		}else if nameConfirmation != nil{
			nameMessage.stringValue=NSLocalizedString("DeviceNameUpdated", value: "Device name updated.", comment: "")
		}else if usesCustomName && nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty{
			nameMessage.stringValue=NSLocalizedString("CustomDeviceNameGuidance", value: "Enter a name or select Use Mac’s name.", comment: "")
		}else if usesCustomName && !valid && showNameValidation{
			do{_ = try LocalDeviceIdentity.validate(nameField.stringValue)}
			catch{nameMessage.stringValue=error.localizedDescription; nameMessage.textColor = .systemRed}
		}else{nameMessage.isHidden=true}
	}
	@objc private func nameModeChanged(_ sender:NSButton){
		let selectedCustom=sender === customNameButton
		guard selectedCustom != usesCustomName else {return}
		view.window?.makeFirstResponder(nil)
		clearNameFeedback()
		usesCustomName=selectedCustom
		if usesCustomName && nameField.stringValue.isEmpty{nameField.stringValue=savedCustomName ?? systemDeviceName}
		showNameValidation=false
		updateNameControls()
		if usesCustomName{view.window?.makeFirstResponder(nameField)}
	}
	func controlTextDidChange(_ notification:Notification){
		guard notification.object as? NSTextField === nameField, !savingName else {return}
		clearNameFeedback()
		updateNameControls()
	}
	func controlTextDidEndEditing(_ notification:Notification){
		guard notification.object as? NSTextField === nameField, !savingName else {return}
		showNameValidation=true
		updateNameControls()
	}
	@objc private func cancelNameChanges(_ sender:Any?){
		savingName=true
		defer{savingName=false}
		view.window?.makeFirstResponder(nil)
		resetNameDraft()
	}
	@objc private func saveName(_ sender:Any?){
		guard !savingName else {return}
		savingName=true
		defer{savingName=false}
		clearNameFeedback()
		do{
			let name=usesCustomName ? try LocalDeviceIdentity.validate(nameField.stringValue) : nil
			guard name != savedCustomName else {return}
			try onDeviceNameChange?(name)
			savedCustomName=name
			view.window?.makeFirstResponder(nil)
			resetNameDraft()
			let confirmation=DispatchWorkItem { [weak self] in
				self?.nameConfirmation=nil
				self?.updateNameControls()
			}
			nameConfirmation=confirmation
			DispatchQueue.main.asyncAfter(deadline: .now()+3, execute: confirmation)
		}catch{nameSaveError=error.localizedDescription}
		updateNameControls()
	}
	deinit{nameConfirmation?.cancel()}
}
