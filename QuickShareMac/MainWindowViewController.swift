import Cocoa

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
	let sendController=SendViewController()
	private let tabs=NSSegmentedControl(labels: [NSLocalizedString("ReceiveTab", value: "Receive", comment: ""), NSLocalizedString("SendTab", value: "Send", comment: "")], trackingMode: .selectOne, target: nil, action: nil)
	private let receiveContent=WindowUI.stack(spacing: 16)
	var onReceivingChange:((Bool)->Void)?
	var onOpenSettings:(()->Void)?
	var onTransferDecision:((String,TransferDecision)->Void)?
	var onRevealTransfer:((String)->Void)?
	var onDismissTransfer:((String)->Void)?
	var onClearRecentTransfers:(()->Void)?
	private let receivingSwitch=NSSwitch()
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
	private let recentHeading=WindowUI.stack(.horizontal)
	private let activeHeading=WindowUI.label(NSLocalizedString("IncomingTransfers", value: "Incoming transfers", comment: ""), size: 13, weight: .semibold)
	private var receiving=false

	override func loadView(){
		let drop=SendDropView(frame: NSRect(x: 0, y: 0, width: 560, height: 640))
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
		let device=WindowUI.label(Host.current().localizedName ?? ProcessInfo.processInfo.hostName, size: 12, secondary: true)
		device.maximumNumberOfLines=1
		device.lineBreakMode = .byTruncatingMiddle
		WindowUI.fill(device, in: titles)
		header.addArrangedSubview(titles)
		header.addArrangedSubview(WindowUI.spacer())
		let settings=NSButton(title: NSLocalizedString("Settings", value: "Settings…", comment: ""), target: self, action: #selector(openSettings(_:)))
		settings.bezelStyle = .inline
		header.addArrangedSubview(settings)
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
		WindowUI.fill(receiveCard, in: receiveContent)
		WindowUI.fill(approvalTitle, in: approvalStack)
		WindowUI.fill(approvalRow, in: approvalStack)
		approvalRow.onDecision={ [weak self] id, decision in self?.onTransferDecision?(id, decision) }
		WindowUI.fill(approvalStack, in: receiveContent)

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

	override func viewDidAppear(){super.viewDidAppear(); sendController.setActive(tabs.selectedSegment==1)}
	override func viewWillDisappear(){super.viewWillDisappear(); sendController.setActive(false)}
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

	func update(receiving:Bool, transfers:[IncomingTransferDisplay]){
		_ = view
		self.receiving=receiving
		receivingSwitch.state=receiving ? .on : .off
		statusLabel.stringValue=receiving ? NSLocalizedString("ReadyToReceive", value: "Ready to receive", comment: "") : NSLocalizedString("ReceivingOff", value: "Receiving off", comment: "")
		visibilityLabel.stringValue=receiving ? NSLocalizedString("ReceivingVisibility", value: "Visible to everyone on your network while receiving.", comment: "") : NSLocalizedString("ReceivingOffDetail", value: "New requests are paused. Transfers in progress can finish.", comment: "")
		let pending=transfers.filter {$0.state == .awaitingApproval}
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
		emptyDetail.stringValue=receiving ? String(format: NSLocalizedString("ReceiveInstructions", value: "Open Quick Share on your Android device and choose “%@”.\nBoth devices must be on the same Wi-Fi network.", comment: ""), Host.current().localizedName ?? ProcessInfo.processInfo.hostName) : NSLocalizedString("EnableReceivingHint", value: "Enable receiving to let nearby devices send files to this Mac.", comment: "")
		enableButton.isHidden=receiving
		var desired:[(String,NSView)]=[]
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
	}

	@objc private func receivingChanged(_ sender:NSSwitch){onReceivingChange?(sender.state == .on)}
	@objc private func enableReceiving(_ sender:NSButton){onReceivingChange?(true)}
	@objc private func openSettings(_ sender:NSButton){onOpenSettings?()}
	@objc private func clearRecent(_ sender:NSButton){onClearRecentTransfers?()}
	@objc private func openDownloads(_ sender:NSButton){
		if let url=FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first{NSWorkspace.shared.open(url)}
	}
}

final class SettingsViewController:NSViewController{
	var onStartReceivingOnLaunchChange:((Bool)->Void)?
	var onLaunchAtLoginChange:((Bool)->Void)?
	var onOpenLoginItems:(()->Void)?
	var onForgetRememberedDevices:(()->Void)?
	private let startReceivingButton=NSButton(checkboxWithTitle: NSLocalizedString("StartReceivingOnLaunch", value: "Start receiving when app opens", comment: ""), target: nil, action: nil)
	private let loginButton=NSButton(checkboxWithTitle: NSLocalizedString("LaunchAtLogin", value: "Launch at login", comment: ""), target: nil, action: nil)
	private let loginHelpButton=NSButton(title: NSLocalizedString("SetUpLoginItem", value: "Set up login item in System Settings…", comment: ""), target: nil, action: nil)
	private let rememberedCountLabel=WindowUI.label("", secondary: true)
	private let forgetButton=NSButton(title: NSLocalizedString("ForgetDevices", value: "Forget all", comment: ""), target: nil, action: nil)

	override func loadView(){
		view=WindowBackgroundView(frame: NSRect(x: 0, y: 0, width: 460, height: 300))
		view.wantsLayer=true
		let content=WindowUI.stack(spacing: 14)
		WindowUI.pin(content, to: view, inset: 24)
		WindowUI.fill(WindowUI.label(NSLocalizedString("StartupSettings", value: "Startup", comment: ""), size: 14, weight: .semibold), in: content)
		startReceivingButton.target=self
		startReceivingButton.action=#selector(startReceivingChanged(_:))
		content.addArrangedSubview(startReceivingButton)
		loginButton.target=self
		loginButton.action=#selector(launchAtLoginChanged(_:))
		content.addArrangedSubview(loginButton)
		loginHelpButton.target=self
		loginHelpButton.action=#selector(openLoginItems(_:))
		loginHelpButton.bezelStyle = .inline
		content.addArrangedSubview(loginHelpButton)
		if #available(macOS 13.0, *){loginHelpButton.isHidden=true}else{loginButton.isHidden=true}
		WindowUI.fill(WindowUI.label(NSLocalizedString("RememberedNames", value: "Remembered device names", comment: ""), size: 14, weight: .semibold), in: content)
		WindowUI.fill(WindowUI.label(NSLocalizedString("RememberNameExplanation", value: "Remembering a name does not verify identity or skip approval. Always check the PIN.", comment: ""), size: 12, secondary: true), in: content)
		let rememberedRow=WindowUI.stack(.horizontal)
		rememberedRow.addArrangedSubview(rememberedCountLabel)
		rememberedRow.addArrangedSubview(WindowUI.spacer())
		forgetButton.bezelStyle = .inline
		forgetButton.target=self
		forgetButton.action=#selector(forgetDevices(_:))
		rememberedRow.addArrangedSubview(forgetButton)
		WindowUI.fill(rememberedRow, in: content)
	}

	func update(startReceivingOnLaunch:Bool, launchAtLogin:Bool, requiresLoginApproval:Bool, rememberedDeviceCount:Int){
		_ = view
		startReceivingButton.state=startReceivingOnLaunch ? .on : .off
		loginButton.state=launchAtLogin ? .on : .off
		if #available(macOS 13.0, *){loginHelpButton.isHidden = !requiresLoginApproval}
		rememberedCountLabel.stringValue=String.localizedStringWithFormat(NSLocalizedString("RememberedDevicesCount", value: "%d remembered device names", comment: ""), rememberedDeviceCount)
		forgetButton.isEnabled=rememberedDeviceCount>0
	}

	@objc private func startReceivingChanged(_ sender:NSButton){onStartReceivingOnLaunchChange?(sender.state == .on)}
	@objc private func launchAtLoginChanged(_ sender:NSButton){onLaunchAtLoginChange?(sender.state == .on)}
	@objc private func openLoginItems(_ sender:NSButton){onOpenLoginItems?()}
	@objc private func forgetDevices(_ sender:NSButton){onForgetRememberedDevices?()}
}
