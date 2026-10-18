import Cocoa

enum FileDropFeedback:Equatable{
	case ready([URL]), folder([URL]), busy, unsupported, unreadable
	var canDrop:Bool{if case .ready=self{return true}; if case .folder=self{return true}; return false}
}

private final class DropOutlineView:NSView{
	var color:NSColor = .controlAccentColor{didSet{needsDisplay=true}}
	override func draw(_ dirtyRect:NSRect){
		color.withAlphaComponent(0.7).setStroke()
		let outline=NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
		outline.lineWidth=2
		outline.setLineDash([8,6], count: 2, phase: 0)
		outline.stroke()
	}
}

private final class FileDropOverlay:NSVisualEffectView{
	private let tint=NSView()
	private let outline=DropOutlineView()
	private let icon=NSImageView()
	private let title=WindowUI.label("", size: 24, weight: .semibold)
	private let subtitle=WindowUI.label("", size: 14, secondary: true)
	private let details=WindowUI.label("", size: 12, secondary: true)
	private var acceptsDrop=true
	override init(frame:NSRect){
		super.init(frame: frame)
		identifier=NSUserInterfaceItemIdentifier("FileDropOverlay")
		material = .contentBackground
		blendingMode = .withinWindow
		state = .active
		wantsLayer=true
		layer?.cornerRadius=18
		layer?.masksToBounds=true
		tint.wantsLayer=true
		WindowUI.pin(tint, to: self, inset: 0)
		WindowUI.pin(outline, to: self, inset: 12)
		let content=WindowUI.stack(spacing: 12)
		content.alignment = .centerX
		content.translatesAutoresizingMaskIntoConstraints=false
		addSubview(content)
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36),
			content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
			content.centerYAnchor.constraint(equalTo: centerYAnchor),
			icon.widthAnchor.constraint(equalToConstant: 64),
			icon.heightAnchor.constraint(equalToConstant: 64)
		])
		icon.imageScaling = .scaleProportionallyUpOrDown
		content.addArrangedSubview(icon)
		for label in [title,subtitle,details]{
			label.alignment = .center
			WindowUI.fill(label, in: content)
		}
		details.maximumNumberOfLines=2
		details.lineBreakMode = .byTruncatingMiddle
	}
	required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
	// Never become a second drag destination or intercept the normal window UI.
	override func hitTest(_ point:NSPoint)->NSView?{nil}
	func show(_ feedback:FileDropFeedback, compressFolders:Bool){
		acceptsDrop=feedback.canDrop
		let symbol:String
		details.stringValue=""
		switch feedback{
		case .ready(let urls):
			symbol="arrow.up.doc"
			title.stringValue=NSLocalizedString("DropToSend", value: "Drop to send", comment: "")
			subtitle.stringValue=NSLocalizedString("DropChooseDeviceNext", value: "Choose a nearby device next", comment: "")
			details.stringValue=urls.count==1 ? urls[0].lastPathComponent : String.localizedStringWithFormat(NSLocalizedString("DropFileCount", value: "%d files", comment: ""), urls.count)
		case .folder(let urls):
			symbol=compressFolders ? "doc.zipper" : "folder"
			title.stringValue=compressFolders ? NSLocalizedString("DropFolderTitle", value: "Compress & send", comment: "") : NSLocalizedString("DropSendFolderTitle", value: "Send folder", comment: "")
			subtitle.stringValue=compressFolders ? NSLocalizedString("DropFolderHelp", value: "Folders are compressed into ZIP files before sending.", comment: "") : NSLocalizedString("DropSendFolderHelp", value: "Files are sent directly, with folder paths. No ZIP is created.", comment: "")
			let folders=urls.filter {url in (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true}
			if urls.count==1{
				details.stringValue=urls[0].lastPathComponent
			}else if folders.count==urls.count{
				details.stringValue=String.localizedStringWithFormat(NSLocalizedString("DropFolderCount", value: "%d folders", comment: ""), folders.count)
			}else{
				details.stringValue=String.localizedStringWithFormat(NSLocalizedString("DropItemsCount", value: "%d items", comment: ""), urls.count)
			}
		case .busy:
			symbol="clock"
			title.stringValue=NSLocalizedString("DropBusyTitle", value: "Transfer in progress", comment: "")
			subtitle.stringValue=NSLocalizedString("DropBusyHelp", value: "Finish or cancel the current transfer first.", comment: "")
		case .unsupported:
			symbol="doc"
			title.stringValue=NSLocalizedString("DropFilesOnlyTitle", value: "Files only", comment: "")
			subtitle.stringValue=NSLocalizedString("DropFilesToSend", value: "Drop files here to send", comment: "")
		case .unreadable:
			symbol="exclamationmark.triangle"
			title.stringValue=NSLocalizedString("DropUnreadableTitle", value: "Can’t read these files", comment: "")
			subtitle.stringValue=NSLocalizedString("DropUnreadableHelp", value: "Choose files you can open, then try again.", comment: "")
		}
		icon.image=NSImage(systemSymbolName: symbol, accessibilityDescription: title.stringValue)
		details.isHidden=details.stringValue.isEmpty
		setAccessibilityLabel([title.stringValue,subtitle.stringValue,details.stringValue].filter {!$0.isEmpty}.joined(separator: ". "))
		updateColors()
	}
	private func updateColors(){
		let color:NSColor=acceptsDrop ? .controlAccentColor : .systemOrange
		icon.contentTintColor=color
		outline.color=color
		effectiveAppearance.performAsCurrentDrawingAppearance{tint.layer?.backgroundColor=color.withAlphaComponent(0.06).cgColor}
	}
	override func viewDidChangeEffectiveAppearance(){super.viewDidChangeEffectiveAppearance(); updateColors()}
}

final class SendDropView:WindowBackgroundView{
	var compressFolders=true{didSet{if let feedback=dropFeedback{overlay.show(feedback, compressFolders: compressFolders)}}}
	var acceptsItems=true{didSet{if oldValue != acceptsItems, let pasteboard=dragPasteboard{_ = previewDrop(from: pasteboard, sourceOperationMask: sourceOperationMask)}}}
	var onURLs:(([URL])->Bool)?
	private(set) var dropFeedback:FileDropFeedback?
	private let overlay=FileDropOverlay(frame: .zero)
	private var dragPasteboard:NSPasteboard?
	private var sourceOperationMask:NSDragOperation = .copy
	private var cachedChangeCount:Int?
	private var cachedFeedback:FileDropFeedback?
	override init(frame:NSRect){
		super.init(frame: frame)
		registerForDraggedTypes([.fileURL,.URL,.string,.tiff,.png])
	}
	required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
	static func urls(from pasteboard:NSPasteboard) -> [URL]{
		let urls=pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
		return urls.allSatisfy(\.isFileURL) ? urls : []
	}
	private static func fileFeedback(from pasteboard:NSPasteboard)->FileDropFeedback{
		let urls=urls(from: pasteboard)
		guard !urls.isEmpty else {return .unsupported}
		var folderCount=0
		for url in urls{
			var scoped=false
			defer{if scoped{url.stopAccessingSecurityScopedResource()}}
			do{
				let keys:Set<URLResourceKey>=[.isDirectoryKey,.isRegularFileKey]
				let values:URLResourceValues
				do{values=try url.resourceValues(forKeys: keys)}
				catch{
					let failure=error as NSError
					guard failure.domain==NSCocoaErrorDomain, failure.code==NSFileReadNoPermissionError else {return .unreadable}
					scoped=url.startAccessingSecurityScopedResource()
					guard scoped else {return .unreadable}
					values=try url.resourceValues(forKeys: keys)
				}
				if values.isDirectory==true{
					folderCount+=1
				}else{
					guard values.isRegularFile==true else {return .unreadable}
				}
				if !FileManager.default.isReadableFile(atPath: url.path){
					if !scoped{scoped=url.startAccessingSecurityScopedResource()}
					guard FileManager.default.isReadableFile(atPath: url.path) else {return .unreadable}
				}
			}catch{return .unreadable}
		}
		return folderCount>0 ? .folder(urls) : .ready(urls)
	}
	@discardableResult func previewDrop(from pasteboard:NSPasteboard, sourceOperationMask:NSDragOperation = .copy)->NSDragOperation{
		if dragPasteboard !== pasteboard || cachedChangeCount != pasteboard.changeCount{
			cachedFeedback=nil
			cachedChangeCount=pasteboard.changeCount
		}
		if acceptsItems && sourceOperationMask.contains(.copy) && cachedFeedback==nil{cachedFeedback=Self.fileFeedback(from: pasteboard)}
		dragPasteboard=pasteboard
		self.sourceOperationMask=sourceOperationMask
		let feedback:FileDropFeedback = !acceptsItems ? .busy : !sourceOperationMask.contains(.copy) ? .unsupported : cachedFeedback ?? .unsupported
		dropFeedback=feedback
		if overlay.superview==nil{WindowUI.pin(overlay, to: self, inset: 12)}
		overlay.show(feedback, compressFolders: compressFolders)
		overlay.isHidden=false
		return feedback.canDrop ? .copy : []
	}
	func endDropPreview(){
		overlay.isHidden=true
		dropFeedback=nil
		dragPasteboard=nil
		cachedChangeCount=nil
		cachedFeedback=nil
	}
	@discardableResult func receiveDrop(from pasteboard:NSPasteboard, sourceOperationMask:NSDragOperation = .copy)->Bool{
		endDropPreview()
		guard acceptsItems, sourceOperationMask.contains(.copy) else {return false}
		switch Self.fileFeedback(from: pasteboard){
		case .ready(let urls), .folder(let urls): return onURLs?(urls) ?? false
		default: return false
		}
	}
	override func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation{
		previewDrop(from: sender.draggingPasteboard, sourceOperationMask: sender.draggingSourceOperationMask)
	}
	override func draggingUpdated(_ sender:NSDraggingInfo) -> NSDragOperation{draggingEntered(sender)}
	override func draggingExited(_ sender:NSDraggingInfo?){endDropPreview()}
	override func draggingEnded(_ sender:NSDraggingInfo){endDropPreview()}
	override func concludeDragOperation(_ sender:NSDraggingInfo?){endDropPreview()}
	override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool{
		acceptsItems && sender.draggingSourceOperationMask.contains(.copy) && Self.fileFeedback(from: sender.draggingPasteboard).canDrop
	}
	override func performDragOperation(_ sender:NSDraggingInfo) -> Bool{
		receiveDrop(from: sender.draggingPasteboard, sourceOperationMask: sender.draggingSourceOperationMask)
	}
	override func viewDidMoveToWindow(){super.viewDidMoveToWindow(); if window==nil{endDropPreview()}}
}

final class SendViewController:NSViewController{
	let sender=SendTransferViewController()
	var compressFolders=SendPreferences.compressFolders(){didSet{sender.folderHandling=compressFolders ? .compress : .sendContents}}
	var onTransferActivityChange:((Bool)->Void)?
	private(set) var recentTransfers:[OutgoingTransferResult]=[]
	private let content=WindowUI.stack(spacing: 16)
	private let senderCard=CardView()
	private let errorLabel=WindowUI.label("", size: 12, secondary: true)
	private let selectionTitle=WindowUI.label("", size: 16, weight: .semibold)
	private let selectionHelp=WindowUI.label("", size: 12, secondary: true)
	private let selectionList=WindowUI.stack(spacing: 6)
	private let selectionScroll=NSScrollView()
	private var selectionListHeight:NSLayoutConstraint!
	private var listedFiles:[URL]=[]
	private var selectedFiles:[URL]=[]
	private let chooseButton=NSButton(title: NSLocalizedString("SendFiles", value: "Send files…", comment: ""), target: nil, action: nil)
	private let preparingSpinner=NSProgressIndicator()
	private let history=WindowUI.stack(spacing: 10)
	private let historyHeading=WindowUI.stack(.horizontal)
	private var historyButtons:[NSButton]=[]

	override func loadView(){
		view=WindowBackgroundView(frame: NSRect(x: 0, y: 0, width: 520, height: 500))
		view.wantsLayer=true
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
		selectionTitle.identifier=NSUserInterfaceItemIdentifier("SendSelectionTitle")
		selectionTitle.maximumNumberOfLines=2
		selectionTitle.lineBreakMode = .byTruncatingMiddle
		WindowUI.fill(selectionTitle, in: selectionContent)
		selectionList.identifier=NSUserInterfaceItemIdentifier("SendSelectionList")
		selectionScroll.identifier=NSUserInterfaceItemIdentifier("SendSelectionScroll")
		selectionScroll.setAccessibilityLabel(NSLocalizedString("SelectedFilesAndFolders", value: "Selected files and folders", comment: ""))
		selectionScroll.hasVerticalScroller=true
		selectionScroll.autohidesScrollers=true
		selectionScroll.borderType = .noBorder
		selectionScroll.drawsBackground=false
		let listDocument=FlippedDocumentView()
		listDocument.translatesAutoresizingMaskIntoConstraints=false
		selectionScroll.documentView=listDocument
		WindowUI.pin(selectionList, to: listDocument, inset: 0)
		listDocument.widthAnchor.constraint(equalTo: selectionScroll.contentView.widthAnchor).isActive=true
		selectionListHeight=selectionScroll.heightAnchor.constraint(equalToConstant: 0)
		selectionListHeight.isActive=true
		selectionScroll.isHidden=true
		WindowUI.fill(selectionScroll, in: selectionContent)
		WindowUI.fill(selectionHelp, in: selectionContent)
		chooseButton.bezelStyle = .rounded
		chooseButton.target=self
		chooseButton.action=#selector(chooseFiles(_:))
		chooseButton.toolTip=NSLocalizedString("ChooseFilesAndFolders", value: "Choose files or folders to send", comment: "")
		chooseButton.setAccessibilityLabel(chooseButton.toolTip)
		preparingSpinner.style = .spinning
		preparingSpinner.controlSize = .small
		preparingSpinner.isIndeterminate=true
		preparingSpinner.isHidden=true
		let chooseRow=WindowUI.stack(.horizontal)
		chooseRow.addArrangedSubview(preparingSpinner)
		chooseRow.addArrangedSubview(chooseButton)
		chooseRow.addArrangedSubview(WindowUI.spacer())
		selectionContent.addArrangedSubview(chooseRow)
		errorLabel.textColor = .systemRed
		WindowUI.fill(errorLabel, in: selectionContent)
		errorLabel.isHidden=true
		WindowUI.fill(selection, in: content)
		sender.continuesInBackground=true
		sender.embeddedInMainWindow=true
		sender.folderCompressor=DittoFolderCompressor()
		sender.folderHandling=compressFolders ? .compress : .sendContents
		sender.setDiscoveryVisible(false)
		sender.onResult={ [weak self] result in self?.record(result) }
		sender.onStateChange={ [weak self] _ in
			self?.errorLabel.isHidden=true
			self?.updateControls()
		}
		sender.onDone={ [weak self] _ in self?.clearSelection() }
		sender.onPreparationError={ [weak self] error in
			guard let self=self else{return}
			self.errorLabel.stringValue=error.localizedDescription
			self.errorLabel.isHidden=false
			self.selectedFiles=[]
			self.senderCard.isHidden=true
			self.updateControls()
		}
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
		updateControls()
	}

	func setActive(_ active:Bool){
		sender.setDiscoveryVisible(active)
	}

	@discardableResult func selectItems(_ urls:[URL]) -> Bool{
		_ = view
		guard urls.allSatisfy(\.isFileURL) else {
			showSelectionError(NSLocalizedString("SendFilesOnly", value: "The Send tab accepts files only. To share a link, use the macOS Share menu.", comment: ""))
			return false
		}
		return applySelection(urls)
	}

	/// A single HTTP or HTTPS link handed over by the macOS Share menu.
	@discardableResult func selectLink(_ url:URL) -> Bool{
		_ = view
		return applySelection([url])
	}

	private func applySelection(_ items:[URL]) -> Bool{
		do{
			try sender.configureItems(items)
			selectedFiles=items.filter(\.isFileURL)
			errorLabel.isHidden=true
			senderCard.isHidden=false
			updateControls()
			return true
		}catch{
			showSelectionError(error.localizedDescription)
			return false
		}
	}

	private func showSelectionError(_ message:String){
		errorLabel.stringValue=message
		errorLabel.isHidden=false
	}

	@objc func chooseFiles(_ sender:Any?){
		guard !self.sender.isTransferring, !self.sender.isPreparing, let window=view.window else {return}
		let panel=NSOpenPanel()
		panel.canChooseFiles=true
		panel.canChooseDirectories=true
		panel.allowsMultipleSelection=true
		panel.treatsFilePackagesAsDirectories=true
		panel.prompt=NSLocalizedString("ChooseFilesOrFolders", value: "Choose", comment: "")
		panel.beginSheetModal(for: window){ [weak self] response in
			if response == .OK{self?.selectItems(panel.urls)}
		}
	}
	private func clearSelection(){
		sender.shutdown()
		selectedFiles=[]
		senderCard.isHidden=true
		updateControls()
	}
	private func updateSelectionList(){
		// Keep original names in a list capped at five rows. Extra items scroll
		// independently instead of pushing the recipient controls down the tab.
		let files=(sender.hasItems || sender.isPreparing) && (selectedFiles.count>1 || !sender.parentFolders.isEmpty) ? selectedFiles : []
		guard files != listedFiles else {return}
		listedFiles=files
		for row in selectionList.arrangedSubviews{selectionList.removeArrangedSubview(row); row.removeFromSuperview()}
		selectionScroll.isHidden=files.isEmpty
		selectionListHeight.constant=CGFloat(max(0,min(files.count,5)*26-6))
		for file in files{
			let row=WindowUI.stack(.horizontal, spacing: 8)
			row.heightAnchor.constraint(equalToConstant: 20).isActive=true
			let icon=NSImageView()
			icon.image=NSWorkspace.shared.icon(forFile: file.path)
			icon.imageScaling = .scaleProportionallyUpOrDown
			NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20)])
			row.addArrangedSubview(icon)
			let name=WindowUI.label(file.lastPathComponent)
			name.identifier=NSUserInterfaceItemIdentifier("SendSelectionItem")
			name.maximumNumberOfLines=1
			name.lineBreakMode = .byTruncatingMiddle
			name.isSelectable=true
			name.toolTip=file.path
			name.setAccessibilityHelp(file.path)
			row.addArrangedSubview(name)
			WindowUI.fill(row, in: selectionList)
		}
		selectionScroll.contentView.scroll(to: .zero)
		selectionScroll.reflectScrolledClipView(selectionScroll.contentView)
	}
	private func updateControls(){
		updateSelectionList()
		let enabled = !sender.isTransferring
		let preparing=sender.isPreparing
		chooseButton.isEnabled=enabled && !preparing
		if preparing{
			preparingSpinner.startAnimation(nil)
		}else{
			preparingSpinner.stopAnimation(nil)
		}
		preparingSpinner.isHidden = !preparing
		let displayItems=sender.preparedItems.isEmpty ? selectedFiles : sender.preparedItems
		if sender.state == .preparing, let name=sender.gatheringFolderName{
			selectionTitle.stringValue=String(format: NSLocalizedString("GatheringFolderFiles", value: "Gathering files from “%@”…", comment: ""), name)
			selectionHelp.stringValue=NSLocalizedString("GatheringFolderHelp", value: "Files are sent directly, with folder paths. No ZIP is created. Large folders can take a moment.", comment: "")
		}else if sender.state == .compressing, let progress=sender.compressionProgress{
			selectionTitle.stringValue=String(format: NSLocalizedString("CompressingFolder", value: "Compressing “%@”…", comment: ""), progress.name)
			selectionHelp.stringValue=progress.total>1
				? String.localizedStringWithFormat(NSLocalizedString("CompressingFolderStep", value: "Folder %d of %d. Folders are compressed into ZIP files before sending.", comment: ""), progress.index, progress.total)
				: NSLocalizedString("CompressingFolderHelp", value: "Folders are compressed into ZIP files before sending. Large folders can take a moment.", comment: "")
		}else if sender.state == .choosingDevice && !displayItems.isEmpty{
			if displayItems.count==1{
				selectionTitle.stringValue=displayItems[0].isFileURL ? displayItems[0].lastPathComponent : displayItems[0].absoluteString
			}else{
				selectionTitle.stringValue=String.localizedStringWithFormat(NSLocalizedString("FilesReadyToSend", value: "%d files ready to send", comment: ""), displayItems.count)
			}
			selectionHelp.stringValue=sender.parentFolders.isEmpty
				? NSLocalizedString("DropReadyChooseDevice", value: "Choose a nearby device. Nothing is sent until you choose a recipient.", comment: "")
				: NSLocalizedString("FolderReadyChooseDevice", value: "Choose a nearby device. Files will be sent without a ZIP; folder layout depends on the receiver.", comment: "")
		}else if !enabled{
			selectionTitle.stringValue=NSLocalizedString("DropBusyTitle", value: "Transfer in progress", comment: "")
			selectionHelp.stringValue=NSLocalizedString("KeepDevicesConnected", value: "Keep both devices connected until the transfer finishes.", comment: "")
		}else{
			selectionTitle.stringValue=NSLocalizedString("DropFilesToSend", value: "Drop files here to send", comment: "")
			selectionHelp.stringValue=NSLocalizedString("SendFilesOrFoldersSelectionHint", value: "Choose files or folders, then select a device. Nothing is sent until you choose a recipient.", comment: "")
		}
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
		if result.urls.count==1, let link=result.urls.first, !link.isFileURL{
			_ = selectLink(link)
		}else{
			_ = selectItems(result.urls)
		}
	}
	@objc private func dismissRecent(_ button:NSButton){
		recentTransfers.removeAll {$0.id.uuidString==button.identifier?.rawValue}
		rebuildHistory()
	}
	@objc private func clearHistory(_ sender:Any?){recentTransfers.removeAll(); rebuildHistory()}
}
