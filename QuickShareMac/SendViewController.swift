import Cocoa

final class SendDropView:WindowBackgroundView{
	var acceptsItems=true
	var onURLs:(([URL])->Bool)?
	override init(frame:NSRect){
		super.init(frame: frame)
		registerForDraggedTypes([.fileURL,.URL,.string])
	}
	required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
	static func urls(from pasteboard:NSPasteboard) -> [URL]{
		let urls=pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
		if !urls.isEmpty{return urls}
		if let text=pasteboard.string(forType: .string), let url=URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), SendTransferViewController.isSupportedLink(url){return [url]}
		return []
	}
	override func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation{
		let accepts=acceptsItems && !Self.urls(from: sender.draggingPasteboard).isEmpty
		layer?.borderColor=NSColor.controlAccentColor.cgColor
		layer?.borderWidth=accepts ? 2 : 0
		return accepts ? .copy : []
	}
	override func draggingUpdated(_ sender:NSDraggingInfo) -> NSDragOperation{draggingEntered(sender)}
	override func draggingExited(_ sender:NSDraggingInfo?){layer?.borderWidth=0}
	override func performDragOperation(_ sender:NSDraggingInfo) -> Bool{
		layer?.borderWidth=0
		guard acceptsItems else {return false}
		let urls=Self.urls(from: sender.draggingPasteboard)
		return !urls.isEmpty && (onURLs?(urls) ?? false)
	}
}

final class SendViewController:NSViewController{
	let sender=SendTransferViewController()
	var onTransferActivityChange:((Bool)->Void)?
	private(set) var recentTransfers:[OutgoingTransferResult]=[]
	private let content=WindowUI.stack(spacing: 16)
	private let senderCard=CardView()
	private let errorLabel=WindowUI.label("", size: 12, secondary: true)
	private let chooseButton=NSButton(title: NSLocalizedString("SendFiles", value: "Send files…", comment: ""), target: nil, action: nil)
	private let linkButton=NSButton(title: NSLocalizedString("ShareLink", value: "Share link…", comment: ""), target: nil, action: nil)
	private let linkRow=WindowUI.stack(.horizontal)
	private let linkField=NSTextField(string: "")
	private let history=WindowUI.stack(spacing: 10)
	private let historyHeading=WindowUI.stack(.horizontal)
	private var historyButtons:[NSButton]=[]

	override func loadView(){
		let drop=SendDropView(frame: NSRect(x: 0, y: 0, width: 520, height: 500))
		drop.wantsLayer=true
		drop.onURLs={ [weak self] urls in self?.selectItems(urls) ?? false }
		view=drop
		let scroll=NSScrollView()
		scroll.hasVerticalScroller=true
		scroll.autohidesScrollers=true
		scroll.borderType = .noBorder
		scroll.drawsBackground=false
		WindowUI.pin(scroll, to: view, inset: 0)
		let document=FlippedDocumentView()
		document.translatesAutoresizingMaskIntoConstraints=false
		scroll.documentView=document
		WindowUI.pin(content, to: document, inset: 0)
		document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive=true
		let selection=CardView()
		selection.wantsLayer=true
		let selectionContent=WindowUI.stack(spacing: 10)
		WindowUI.pin(selectionContent, to: selection, inset: 16)
		WindowUI.fill(WindowUI.label(NSLocalizedString("DropFilesToSend", value: "Drop files here to send", comment: ""), size: 16, weight: .semibold), in: selectionContent)
		WindowUI.fill(WindowUI.label(NSLocalizedString("SendSelectionHint", value: "Choose files or one web link, then select a device. Nothing is sent until you choose a recipient.", comment: ""), size: 12, secondary: true), in: selectionContent)
		let buttons=WindowUI.stack(.horizontal)
		chooseButton.bezelStyle = .rounded
		chooseButton.target=self
		chooseButton.action=#selector(chooseFiles(_:))
		linkButton.bezelStyle = .rounded
		linkButton.target=self
		linkButton.action=#selector(showLinkEntry(_:))
		buttons.addArrangedSubview(chooseButton)
		buttons.addArrangedSubview(linkButton)
		selectionContent.addArrangedSubview(buttons)
		linkField.placeholderString="https://example.com"
		linkField.setAccessibilityLabel(NSLocalizedString("LinkAddress", value: "Link address", comment: ""))
		linkField.target=self
		linkField.action=#selector(shareLink(_:))
		linkRow.addArrangedSubview(linkField)
		let useLink=NSButton(title: NSLocalizedString("ChooseLink", value: "Choose link", comment: ""), target: self, action: #selector(shareLink(_:)))
		useLink.bezelStyle = .rounded
		linkRow.addArrangedSubview(useLink)
		WindowUI.fill(linkRow, in: selectionContent)
		linkRow.isHidden=true
		errorLabel.textColor = .systemRed
		WindowUI.fill(errorLabel, in: selectionContent)
		errorLabel.isHidden=true
		WindowUI.fill(selection, in: content)
		sender.continuesInBackground=true
		sender.embeddedInMainWindow=true
		sender.setDiscoveryVisible(false)
		sender.onResult={ [weak self] result in self?.record(result) }
		sender.onStateChange={ [weak self] _ in
			self?.errorLabel.isHidden=true
			self?.updateControls()
		}
		sender.onDone={ [weak self] _ in self?.clearSelection() }
		addChild(sender)
		senderCard.wantsLayer=true
		WindowUI.pin(sender.view, to: senderCard, inset: 16)
		sender.view.heightAnchor.constraint(equalToConstant: 320).isActive=true
		WindowUI.fill(senderCard, in: content)
		senderCard.isHidden=true
		historyHeading.addArrangedSubview(WindowUI.label(NSLocalizedString("RecentOutgoingTransfers", value: "Recent outgoing transfers · this session", comment: ""), size: 13, weight: .semibold))
		historyHeading.addArrangedSubview(WindowUI.spacer())
		let clear=NSButton(title: NSLocalizedString("ClearRecent", value: "Clear", comment: ""), target: self, action: #selector(clearHistory(_:)))
		clear.bezelStyle = .inline
		historyHeading.addArrangedSubview(clear)
		WindowUI.fill(historyHeading, in: content)
		WindowUI.fill(history, in: content)
		historyHeading.isHidden=true
		history.isHidden=true
	}

	func setActive(_ active:Bool){
		sender.setDiscoveryVisible(active)
	}

	@discardableResult func selectItems(_ urls:[URL]) -> Bool{
		_ = view
		do{
			try sender.configureItems(urls)
			errorLabel.isHidden=true
			linkRow.isHidden=true
			senderCard.isHidden=false
			updateControls()
			return true
		}catch{
			errorLabel.stringValue=error.localizedDescription
			errorLabel.isHidden=false
			return false
		}
	}

	@objc func chooseFiles(_ sender:Any?){
		guard !self.sender.isTransferring, let window=view.window else {return}
		let panel=NSOpenPanel()
		panel.canChooseFiles=true
		panel.canChooseDirectories=false
		panel.allowsMultipleSelection=true
		panel.treatsFilePackagesAsDirectories=true
		panel.prompt=NSLocalizedString("ChooseFiles", value: "Choose files", comment: "")
		panel.beginSheetModal(for: window){ [weak self] response in
			if response == .OK{self?.selectItems(panel.urls)}
		}
	}
	@objc func showLinkEntry(_ sender:Any?){
		guard !self.sender.isTransferring else {return}
		linkRow.isHidden=false
		view.window?.makeFirstResponder(linkField)
	}
	@objc private func shareLink(_ sender:Any?){
		guard let url=URL(string: linkField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), SendTransferViewController.isSupportedLink(url) else {
			errorLabel.stringValue=NSLocalizedString("ValidWebLinkRequired", value: "Enter a complete HTTP or HTTPS link, such as https://example.com.", comment: "")
			errorLabel.isHidden=false
			return
		}
		selectItems([url])
	}
	private func clearSelection(){
		sender.shutdown()
		senderCard.isHidden=true
		updateControls()
	}
	private func updateControls(){
		let enabled = !sender.isTransferring
		chooseButton.isEnabled=enabled
		linkButton.isEnabled=enabled
		linkField.isEnabled=enabled
		(view as? SendDropView)?.acceptsItems=enabled
		for button in historyButtons{button.isEnabled=enabled}
		onTransferActivityChange?(!enabled)
	}
	private func record(_ result:OutgoingTransferResult){
		recentTransfers.removeAll {$0.id==result.id}
		recentTransfers.insert(result, at: 0)
		if result.state == .completed{senderCard.isHidden=true}
		rebuildHistory()
	}
	private func rebuildHistory(){
		for child in history.arrangedSubviews{history.removeArrangedSubview(child); child.removeFromSuperview()}
		historyButtons.removeAll()
		history.isHidden=recentTransfers.isEmpty
		historyHeading.isHidden=recentTransfers.isEmpty
		for result in recentTransfers{
			let card=CardView()
			card.wantsLayer=true
			let body=WindowUI.stack(spacing: 6)
			WindowUI.pin(body, to: card, inset: 14)
			let title=WindowUI.label(String(format: NSLocalizedString("SentToDevice", value: "To %@", comment: ""), result.deviceName), weight: .semibold)
			title.maximumNumberOfLines=2
			WindowUI.fill(title, in: body)
			let details=WindowUI.label(result.itemDescription, size: 12, secondary: true)
			details.maximumNumberOfLines=2
			details.toolTip=result.itemDescription
			WindowUI.fill(details, in: body)
			let status=WindowUI.label(result.status, size: 12, secondary: true)
			status.textColor=result.state == .completed ? .systemGreen : .secondaryLabelColor
			WindowUI.fill(status, in: body)
			let actions=WindowUI.stack(.horizontal)
			let retry=NSButton(title: result.state == .completed ? NSLocalizedString("SendAgain", value: "Send again…", comment: "") : NSLocalizedString("RetryTransfer", value: "Retry…", comment: ""), target: self, action: #selector(retryRecent(_:)))
			retry.identifier=NSUserInterfaceItemIdentifier(result.id.uuidString)
			retry.bezelStyle = .inline
			actions.addArrangedSubview(retry)
			historyButtons.append(retry)
			actions.addArrangedSubview(WindowUI.spacer())
			let dismiss=NSButton(title: NSLocalizedString("Dismiss", value: "Dismiss", comment: ""), target: self, action: #selector(dismissRecent(_:)))
			dismiss.identifier=retry.identifier
			dismiss.bezelStyle = .inline
			actions.addArrangedSubview(dismiss)
			WindowUI.fill(actions, in: body)
			WindowUI.fill(card, in: history)
		}
		updateControls()
	}
	@objc private func retryRecent(_ button:NSButton){
		guard let result=recentTransfers.first(where: {$0.id.uuidString==button.identifier?.rawValue}) else {return}
		selectItems(result.urls)
	}
	@objc private func dismissRecent(_ button:NSButton){
		recentTransfers.removeAll {$0.id.uuidString==button.identifier?.rawValue}
		rebuildHistory()
	}
	@objc private func clearHistory(_ sender:Any?){recentTransfers.removeAll(); rebuildHistory()}
}
