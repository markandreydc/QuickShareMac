import Cocoa

struct IncomingTransferDisplay{
	let deviceName:String
	let description:String
	let status:String
	let progress:Double?
	let pendingID:String?
	let pinCode:String?
}

private final class CardView:NSView{
	override var wantsUpdateLayer:Bool { true }

	override func updateLayer(){
		layer?.backgroundColor=NSColor.controlBackgroundColor.cgColor
		layer?.cornerRadius=14
		layer?.borderColor=NSColor.separatorColor.withAlphaComponent(0.35).cgColor
		layer?.borderWidth=1
	}

	override func viewDidChangeEffectiveAppearance(){
		super.viewDidChangeEffectiveAppearance()
		needsDisplay=true
	}
}

private final class FlippedDocumentView:NSView{
	override var isFlipped:Bool { true }
}

final class MainWindowViewController:NSViewController{
	var onReceivingChange:((Bool)->Void)?
	var onStartReceivingOnLaunchChange:((Bool)->Void)?
	var onLaunchAtLoginChange:((Bool)->Void)?
	var onOpenLoginItems:(()->Void)?
	var onQuit:(()->Void)?
	var onTransferDecision:((String,Bool)->Void)?

	private let receivingSwitch=NSSwitch()
	private let startReceivingButton=NSButton(checkboxWithTitle: NSLocalizedString("StartReceivingOnLaunch", value: "Start receiving when app opens", comment: ""), target: nil, action: nil)
	private let loginButton=NSButton(checkboxWithTitle: NSLocalizedString("LaunchAtLogin", value: "Launch at login", comment: ""), target: nil, action: nil)
	private let loginHelpButton=NSButton(title: NSLocalizedString("SetUpLoginItem", value: "Set up login item in System Settings…", comment: ""), target: nil, action: nil)
	private let transferScrollView=NSScrollView()
	private let statusDot=NSView()
	private let statusLabel=NSTextField(labelWithString: "")

	override func loadView(){
		let container=NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 660))
		view=container
		let content=NSStackView()
		content.orientation = .vertical
		content.alignment = .leading
		content.spacing=16
		content.translatesAutoresizingMaskIntoConstraints=false
		container.addSubview(content)
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
			content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
			content.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
			content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24)
		])

		let header=NSStackView()
		header.orientation = .horizontal
		header.alignment = .centerY
		header.spacing=12
		let icon=NSImageView(image: NSImage(named: NSImage.applicationIconName) ?? NSImage())
		icon.imageScaling = .scaleProportionallyUpOrDown
		NSLayoutConstraint.activate([
			icon.widthAnchor.constraint(equalToConstant: 44),
			icon.heightAnchor.constraint(equalToConstant: 44)
		])
		header.addArrangedSubview(icon)
		let titles=NSStackView()
		titles.orientation = .vertical
		titles.alignment = .leading
		titles.spacing=2
		let title=NSTextField(labelWithString: "QuickShareMac")
		title.font=NSFont.systemFont(ofSize: 21, weight: .semibold)
		titles.addArrangedSubview(title)
		let deviceName=Host.current().localizedName ?? ProcessInfo.processInfo.hostName
		let subtitle=NSTextField(labelWithString: String(format: NSLocalizedString("DeviceName", value: "Device name: %@", comment: ""), deviceName))
		subtitle.font=NSFont.systemFont(ofSize: 12)
		subtitle.textColor = .secondaryLabelColor
		subtitle.lineBreakMode = .byTruncatingMiddle
		subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 290).isActive=true
		titles.addArrangedSubview(subtitle)
		header.addArrangedSubview(titles)
		let spacer=NSView()
		spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
		header.addArrangedSubview(spacer)
		let status=NSStackView()
		status.orientation = .horizontal
		status.alignment = .centerY
		status.spacing=6
		statusDot.wantsLayer=true
		statusDot.layer?.cornerRadius=4
		NSLayoutConstraint.activate([
			statusDot.widthAnchor.constraint(equalToConstant: 8),
			statusDot.heightAnchor.constraint(equalToConstant: 8)
		])
		status.addArrangedSubview(statusDot)
		statusLabel.font=NSFont.systemFont(ofSize: 12, weight: .medium)
		status.addArrangedSubview(statusLabel)
		header.addArrangedSubview(status)
		content.addArrangedSubview(header)
		header.widthAnchor.constraint(equalTo: content.widthAnchor).isActive=true

		let (receiveCard, receiveContent)=makeCard(spacing: 6)
		let receiveRow=NSStackView()
		receiveRow.orientation = .horizontal
		receiveRow.alignment = .centerY
		let receiveTitle=sectionTitle(NSLocalizedString("ReceivingEnabled", value: "Receiving enabled", comment: ""))
		receiveRow.addArrangedSubview(receiveTitle)
		let receiveSpacer=NSView()
		receiveSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
		receiveRow.addArrangedSubview(receiveSpacer)
		receivingSwitch.target=self
		receivingSwitch.action=#selector(receivingChanged(_:))
		receiveRow.addArrangedSubview(receivingSwitch)
		receiveContent.addArrangedSubview(receiveRow)
		receiveRow.widthAnchor.constraint(equalTo: receiveContent.widthAnchor).isActive=true
		let visibility=NSTextField(labelWithString: NSLocalizedString("ReceivingVisibility", value: "Visible to everyone on your network while receiving.", comment: ""))
		visibility.font=NSFont.systemFont(ofSize: 12)
		visibility.textColor = .secondaryLabelColor
		receiveContent.addArrangedSubview(visibility)
		content.addArrangedSubview(receiveCard)
		receiveCard.widthAnchor.constraint(equalTo: content.widthAnchor).isActive=true

		let (settingsCard, settingsContent)=makeCard(spacing: 10)
		settingsContent.addArrangedSubview(sectionTitle(NSLocalizedString("StartupSettings", value: "Startup", comment: "")))
		startReceivingButton.target=self
		startReceivingButton.action=#selector(startReceivingChanged(_:))
		settingsContent.addArrangedSubview(startReceivingButton)
		loginButton.target=self
		loginButton.action=#selector(launchAtLoginChanged(_:))
		settingsContent.addArrangedSubview(loginButton)
		loginHelpButton.target=self
		loginHelpButton.action=#selector(openLoginItems(_:))
		loginHelpButton.bezelStyle = .inline
		settingsContent.addArrangedSubview(loginHelpButton)
		settingsContent.detachesHiddenViews=true
		if #available(macOS 13.0, *){
			loginHelpButton.isHidden=true
		}else{
			loginButton.isHidden=true
		}
		content.addArrangedSubview(settingsCard)
		settingsCard.widthAnchor.constraint(equalTo: content.widthAnchor).isActive=true

		let (transfersCard, transfersContent)=makeCard(spacing: 12)
		transfersContent.addArrangedSubview(sectionTitle(NSLocalizedString("IncomingTransfers", value: "Incoming transfers", comment: "")))
		transferScrollView.hasVerticalScroller=true
		transferScrollView.borderType = .noBorder
		transferScrollView.drawsBackground=false
		transfersContent.addArrangedSubview(transferScrollView)
		NSLayoutConstraint.activate([
			transferScrollView.widthAnchor.constraint(equalTo: transfersContent.widthAnchor),
			transferScrollView.heightAnchor.constraint(equalToConstant: 180)
		])
		content.addArrangedSubview(transfersCard)
		transfersCard.widthAnchor.constraint(equalTo: content.widthAnchor).isActive=true

		let footer=NSStackView()
		footer.orientation = .horizontal
		footer.alignment = .centerY
		let downloadHint=NSTextField(labelWithString: NSLocalizedString("SavedToDownloads", value: "Received files are saved to Downloads", comment: ""))
		downloadHint.font=NSFont.systemFont(ofSize: 11)
		downloadHint.textColor = .secondaryLabelColor
		footer.addArrangedSubview(downloadHint)
		let footerSpacer=NSView()
		footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
		footer.addArrangedSubview(footerSpacer)
		let quitButton=NSButton(title: NSLocalizedString("Quit", value: "Quit QuickShareMac", comment: ""), target: self, action: #selector(quit(_:)))
		quitButton.bezelStyle = .inline
		footer.addArrangedSubview(quitButton)
		content.addArrangedSubview(footer)
		footer.widthAnchor.constraint(equalTo: content.widthAnchor).isActive=true
	}

	private func makeCard(spacing:CGFloat) -> (CardView, NSStackView){
		let card=CardView()
		card.wantsLayer=true
		let stack=NSStackView()
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing=spacing
		stack.translatesAutoresizingMaskIntoConstraints=false
		card.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
			stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
			stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
			stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
		])
		return (card, stack)
	}

	private func sectionTitle(_ text:String) -> NSTextField{
		let label=NSTextField(labelWithString: text)
		label.font=NSFont.systemFont(ofSize: 14, weight: .semibold)
		return label
	}

	func update(receiving:Bool, startReceivingOnLaunch:Bool, launchAtLogin:Bool, transfers:[IncomingTransferDisplay]){
		_ = view // Accessing the view loads it on macOS versions before 14.
		receivingSwitch.state=receiving ? .on : .off
		startReceivingButton.state=startReceivingOnLaunch ? .on : .off
		loginButton.state=launchAtLogin ? .on : .off
		statusLabel.stringValue=receiving ? NSLocalizedString("ReadyToReceive", value: "Ready to receive", comment: "") : NSLocalizedString("ReceivingOff", value: "Receiving off", comment: "")
		statusLabel.textColor = .secondaryLabelColor
		statusDot.layer?.backgroundColor=(receiving ? NSColor.systemGreen : NSColor.tertiaryLabelColor).cgColor

		let listHeight=transfers.reduce(CGFloat(0)) { $0 + ($1.pendingID == nil ? 82 : 150) }
		let document=FlippedDocumentView(frame: NSRect(x: 0, y: 0, width: 476, height: max(180, listHeight)))
		if transfers.isEmpty{
			let empty=NSStackView()
			empty.orientation = .vertical
			empty.alignment = .centerX
			empty.spacing=8
			empty.translatesAutoresizingMaskIntoConstraints=false
			let symbol=NSTextField(labelWithString: "↓")
			symbol.font=NSFont.systemFont(ofSize: 30, weight: .ultraLight)
			symbol.textColor = .tertiaryLabelColor
			empty.addArrangedSubview(symbol)
			let emptyTitle=NSTextField(labelWithString: NSLocalizedString("NoIncomingTransfers", value: "No incoming transfers", comment: ""))
			emptyTitle.font=NSFont.systemFont(ofSize: 13, weight: .medium)
			empty.addArrangedSubview(emptyTitle)
			let emptyDetail=NSTextField(labelWithString: NSLocalizedString("IncomingTransfersHint", value: "Accepted files will appear here.", comment: ""))
			emptyDetail.font=NSFont.systemFont(ofSize: 11)
			emptyDetail.textColor = .secondaryLabelColor
			empty.addArrangedSubview(emptyDetail)
			document.addSubview(empty)
			NSLayoutConstraint.activate([
				empty.centerXAnchor.constraint(equalTo: document.centerXAnchor),
				empty.centerYAnchor.constraint(equalTo: document.centerYAnchor)
			])
		}else{
			let rows=NSStackView()
			rows.orientation = .vertical
			rows.alignment = .leading
			rows.spacing=14
			rows.translatesAutoresizingMaskIntoConstraints=false
			document.addSubview(rows)
			NSLayoutConstraint.activate([
				rows.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 4),
				rows.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
				rows.topAnchor.constraint(equalTo: document.topAnchor, constant: 4)
			])
			for transfer in transfers{
				let row=NSStackView()
				row.orientation = .vertical
				row.alignment = .leading
				row.spacing=5
				let title=NSTextField(labelWithString: "\(transfer.deviceName) · \(transfer.description)")
				title.font=NSFont.systemFont(ofSize: 13, weight: .medium)
				title.lineBreakMode = .byTruncatingMiddle
				row.addArrangedSubview(title)
				let progress=NSProgressIndicator()
				progress.style = .bar
				progress.controlSize = .small
				progress.minValue=0
				progress.maxValue=100
				progress.isIndeterminate=transfer.progress==nil
				if let fraction=transfer.progress{
					progress.doubleValue=max(0, min(1, fraction))*100
				}else{
					progress.startAnimation(nil)
				}
				row.addArrangedSubview(progress)
				let status=NSTextField(labelWithString: transfer.status)
				status.font=NSFont.systemFont(ofSize: 11)
				status.textColor = .secondaryLabelColor
				status.lineBreakMode = .byTruncatingTail
				row.addArrangedSubview(status)
				if let id=transfer.pendingID{
					if let pin=transfer.pinCode{
						let pinLabel=NSTextField(labelWithString: String(format: NSLocalizedString("PinCode", value: "PIN: %@", comment: ""), pin))
						pinLabel.font=NSFont.systemFont(ofSize: 13, weight: .semibold)
						row.addArrangedSubview(pinLabel)
						let verify=NSTextField(labelWithString: NSLocalizedString("VerifyPin", value: "Check that the PIN matches on the sending device.", comment: ""))
						verify.font=NSFont.systemFont(ofSize: 11)
						verify.textColor = .secondaryLabelColor
						row.addArrangedSubview(verify)
					}
					let actions=NSStackView()
					actions.orientation = .horizontal
					actions.spacing=8
					let accept=NSButton(title: NSLocalizedString("Accept", value: "Accept", comment: ""), target: self, action: #selector(acceptTransfer(_:)))
					accept.identifier=NSUserInterfaceItemIdentifier(id)
					let decline=NSButton(title: NSLocalizedString("Decline", value: "Decline", comment: ""), target: self, action: #selector(declineTransfer(_:)))
					decline.identifier=NSUserInterfaceItemIdentifier(id)
					actions.addArrangedSubview(accept)
					actions.addArrangedSubview(decline)
					row.addArrangedSubview(actions)
				}
				rows.addArrangedSubview(row)
				NSLayoutConstraint.activate([
					row.widthAnchor.constraint(equalTo: rows.widthAnchor),
					title.widthAnchor.constraint(equalTo: row.widthAnchor),
					progress.widthAnchor.constraint(equalTo: row.widthAnchor),
					status.widthAnchor.constraint(equalTo: row.widthAnchor)
				])
			}
		}
		transferScrollView.documentView=document
	}

	@objc private func receivingChanged(_ sender:NSSwitch){onReceivingChange?(sender.state == .on)}
	@objc private func startReceivingChanged(_ sender:NSButton){onStartReceivingOnLaunchChange?(sender.state == .on)}
	@objc private func launchAtLoginChanged(_ sender:NSButton){onLaunchAtLoginChange?(sender.state == .on)}
	@objc private func openLoginItems(_ sender:NSButton){onOpenLoginItems?()}
	@objc private func quit(_ sender:NSButton){onQuit?()}
	@objc private func acceptTransfer(_ sender:NSButton){
		guard let id=sender.identifier?.rawValue else {return}
		onTransferDecision?(id, true)
	}
	@objc private func declineTransfer(_ sender:NSButton){
		guard let id=sender.identifier?.rawValue else {return}
		onTransferDecision?(id, false)
	}
}
