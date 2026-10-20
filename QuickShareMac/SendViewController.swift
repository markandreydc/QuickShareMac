import Cocoa

enum FileDropFeedback:Equatable{
	case ready([URL]), folder([URL]), busy, unsupported, unreadable
	var canDrop:Bool{if case .ready=self{return true}; if case .folder=self{return true}; return false}
}

private final class DropOutlineView:NSView{
	var color:NSColor = .controlAccentColor{didSet{needsDisplay=true}}
	override func hitTest(_ point:NSPoint)->NSView?{nil}
	override func draw(_ dirtyRect:NSRect){
		color.withAlphaComponent(0.7).setStroke()
		let outline=NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
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
		layer?.cornerRadius=8
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
	var compressFolders=false{didSet{if let feedback=dropFeedback{overlay.show(feedback, compressFolders: compressFolders)}}}
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

final class SelectedItemsTableView:NSTableView{
	var onContextMenu:((Int)->NSMenu?)?
	func contextMenu(forRow row:Int)->NSMenu?{
		guard row>=0, row<numberOfRows else{return nil}
		selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		window?.makeFirstResponder(self)
		return onContextMenu?(row)
	}
	override func menu(for event:NSEvent)->NSMenu?{
		contextMenu(forRow: row(at: convert(event.locationInWindow, from: nil)))
	}
}

private final class SelectedItemCellView:NSTableCellView{
	let removeButton=NSButton()
	var onRemove:(()->Void)?
	init(){
		super.init(frame: .zero)
		let row=WindowUI.stack(.horizontal, spacing: 8)
		WindowUI.pin(row, to: self, inset: 4)
		let icon=NSImageView()
		icon.imageScaling = .scaleProportionallyUpOrDown
		NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 20),icon.heightAnchor.constraint(equalToConstant: 20)])
		row.addArrangedSubview(icon)
		imageView=icon
		let name=NSTextField(labelWithString: "")
		name.identifier=NSUserInterfaceItemIdentifier("SendSelectionItem")
		name.lineBreakMode = .byTruncatingMiddle
		name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		row.addArrangedSubview(name)
		textField=name
		row.addArrangedSubview(WindowUI.spacer())
		removeButton.identifier=NSUserInterfaceItemIdentifier("SendSelectionRemove")
		removeButton.image=NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
		removeButton.imagePosition = .imageOnly
		removeButton.isBordered=false
		removeButton.contentTintColor = .secondaryLabelColor
		removeButton.target=self
		removeButton.action=#selector(removeItem(_:))
		NSLayoutConstraint.activate([removeButton.widthAnchor.constraint(equalToConstant: 20),removeButton.heightAnchor.constraint(equalToConstant: 20)])
		row.addArrangedSubview(removeButton)
	}
	required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
	@objc private func removeItem(_ sender:Any?){onRemove?()}
}

/// Shared presentation keeps incoming and outgoing session history consistent.
struct TransferHistoryItem:Equatable{
	let id:String
	let incoming:Bool
	let title:String
	let subtitle:String
	let finishedAt:Date
	let items:[URL]
	let status:String
	let statusDetail:String
	let completed:Bool
	let actionTitle:String?
	let actionSymbol:String
	let inlineAction:Bool
	let symbol:String
	var prefix:String{incoming ? "IncomingHistory" : "OutgoingHistory"}

	private static func subtitle(device:String, bytes:Int64?, date:Date)->String{
		var parts=[device]
		if let bytes=bytes{parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))}
		parts.append(DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))
		return parts.joined(separator: " · ")
	}
	init(_ result:OutgoingTransferResult){
		id=result.id.uuidString
		incoming=false
		title=result.itemDescription
		finishedAt=result.finishedAt
		items=result.displayItems
		subtitle=Self.subtitle(device: String(format: NSLocalizedString("SentToDevice", value: "To %@", comment: ""), result.deviceName), bytes: items.first?.isFileURL==true ? result.totalBytes : nil, date: finishedAt)
		completed=result.state == .completed
		status=completed ? NSLocalizedString("OutgoingHistorySent", value: "Sent", comment: "") : result.status
		statusDetail=result.status
		actionTitle=completed ? NSLocalizedString("SendAgain", value: "Send again…", comment: "") : NSLocalizedString("RetryTransfer", value: "Retry…", comment: "")
		actionSymbol="arrow.clockwise"
		inlineAction = !completed
		symbol=items.count>1 ? "doc.on.doc" : items.first?.isFileURL==false ? "link" : "doc"
	}
	init(_ transfer:IncomingTransferDisplay){
		id=transfer.id
		incoming=true
		title=transfer.description
		finishedAt=transfer.finishedAt
		items=transfer.savedFileURLs
		subtitle=Self.subtitle(device: String(format: NSLocalizedString("ReceivedFromDevice", value: "From %@", comment: ""), transfer.deviceName), bytes: transfer.totalBytes>0 || !items.isEmpty ? transfer.totalBytes : nil, date: finishedAt)
		completed=transfer.state == .completed
		switch transfer.state{
		case .completed: status=NSLocalizedString("IncomingHistoryReceived", value: "Received", comment: "")
		case .failed: status=NSLocalizedString("IncomingHistoryFailed", value: "Failed", comment: "")
		case .canceled: status=NSLocalizedString("TransferCanceled", value: "Canceled", comment: "")
		case .awaitingApproval, .receiving: status=transfer.status
		}
		statusDetail=transfer.status
		actionTitle=completed && !items.isEmpty ? NSLocalizedString("ShowInFinder", value: "Show in Finder", comment: "") : nil
		actionSymbol="folder"
		inlineAction=actionTitle != nil
		symbol=items.count>1 ? "doc.on.doc" : items.isEmpty ? "arrow.down.doc" : "doc"
	}
}

/// A transfer is always one row, even when it contains hundreds of files.
final class TransferHistoryRowView:NSTableCellView{
	private let actionButton=NSButton()
	private let moreButton=NSPopUpButton(frame: .zero, pullsDown: true)
	private let disclosure=NSButton()
	private let icon=NSImageView()
	private let title=WindowUI.label("", size: 12, weight: .medium)
	private let subtitle=WindowUI.label("", size: 11, secondary: true)
	private let status=WindowUI.label("", size: 11, secondary: true)
	private var actionItem:NSMenuItem?
	var onAction:(()->Void)?
	var onDismiss:(()->Void)?
	var onExpand:(()->Void)?

	override init(frame:NSRect){
		super.init(frame: frame)
		identifier=NSUserInterfaceItemIdentifier("OutgoingHistoryRow")
		let row=WindowUI.stack(.horizontal, spacing: 8)
		WindowUI.pin(row, to: self, inset: 10)
		disclosure.isBordered=false
		disclosure.target=self
		disclosure.action=#selector(expand(_:))
		disclosure.identifier=NSUserInterfaceItemIdentifier("OutgoingHistoryExpand")
		row.addArrangedSubview(disclosure)
		icon.imageScaling = .scaleProportionallyUpOrDown
		icon.contentTintColor = .secondaryLabelColor
		row.addArrangedSubview(icon)
		let labels=WindowUI.stack(spacing: 3)
		for label in [title,subtitle]{
			label.maximumNumberOfLines=1
			label.lineBreakMode = .byTruncatingMiddle
			WindowUI.fill(label, in: labels)
		}
		labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
		row.addArrangedSubview(labels)
		row.addArrangedSubview(WindowUI.spacer())
		status.maximumNumberOfLines=1
		status.lineBreakMode = .byTruncatingTail
		status.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
		row.addArrangedSubview(status)
		actionButton.isBordered=false
		actionButton.target=self
		actionButton.action=#selector(performAction(_:))
		row.addArrangedSubview(actionButton)
		moreButton.isBordered=false
		moreButton.imagePosition = .imageOnly
		(moreButton.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
		moreButton.identifier=NSUserInterfaceItemIdentifier("OutgoingHistoryMore")
		moreButton.setAccessibilityLabel(NSLocalizedString("TransferActions", value: "Transfer actions", comment: ""))
		row.addArrangedSubview(moreButton)
		NSLayoutConstraint.activate([
			disclosure.widthAnchor.constraint(equalToConstant: 14),
			disclosure.heightAnchor.constraint(equalToConstant: 24),
			icon.widthAnchor.constraint(equalToConstant: 22),
			icon.heightAnchor.constraint(equalToConstant: 22),
			status.widthAnchor.constraint(lessThanOrEqualToConstant: 100),
			actionButton.widthAnchor.constraint(equalToConstant: 24),
			actionButton.heightAnchor.constraint(equalToConstant: 24),
			moreButton.widthAnchor.constraint(equalToConstant: 24),
			moreButton.heightAnchor.constraint(equalToConstant: 24)
		])
	}
	required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
	func configure(_ result:TransferHistoryItem, expanded:Bool=false, actionEnabled:Bool=true){
		identifier=NSUserInterfaceItemIdentifier(result.prefix+"Row")
		let items=result.items
		let batch=items.count>1
		title.stringValue=result.title
		title.toolTip=result.title
		subtitle.stringValue=result.subtitle
		subtitle.toolTip=subtitle.stringValue+" · "+DateFormatter.localizedString(from: result.finishedAt, dateStyle: .medium, timeStyle: .short)
		icon.image=NSImage(systemSymbolName: result.symbol, accessibilityDescription: nil)
		disclosure.identifier=NSUserInterfaceItemIdentifier(result.prefix+"Expand")
		disclosure.isHidden = !batch
		disclosure.image=NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
		disclosure.setAccessibilityLabel(expanded ? NSLocalizedString("HideTransferFiles", value: "Hide files", comment: "") : NSLocalizedString("ShowTransferFiles", value: "Show files", comment: ""))
		disclosure.setAccessibilityValue(expanded ? 1 : 0)
		status.stringValue=result.status
		status.toolTip=result.statusDetail
		status.textColor=result.completed ? .systemGreen : .secondaryLabelColor
		actionButton.identifier=NSUserInterfaceItemIdentifier(result.prefix+(result.incoming ? "Reveal" : "Retry"))
		actionButton.image=NSImage(systemSymbolName: result.actionSymbol, accessibilityDescription: nil)
		actionButton.toolTip=result.actionTitle
		actionButton.setAccessibilityLabel(result.actionTitle)
		actionButton.isHidden = !result.inlineAction
		moreButton.identifier=NSUserInterfaceItemIdentifier(result.prefix+"More")
		let menu=NSMenu()
		menu.autoenablesItems=false
		let placeholder=NSMenuItem(title: "", action: nil, keyEquivalent: "")
		placeholder.image=NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
		menu.addItem(placeholder)
		actionItem=nil
		if let actionTitle=result.actionTitle{
			let action=NSMenuItem(title: actionTitle, action: #selector(performAction(_:)), keyEquivalent: "")
			action.target=self
			menu.addItem(action)
			actionItem=action
		}
		let dismiss=NSMenuItem(title: NSLocalizedString("Dismiss", value: "Dismiss", comment: ""), action: #selector(dismissResult(_:)), keyEquivalent: "")
		dismiss.target=self
		menu.addItem(dismiss)
		moreButton.menu=menu
		setActionEnabled(actionEnabled)
	}
	func setActionEnabled(_ enabled:Bool){actionButton.isEnabled=enabled; actionItem?.isEnabled=enabled}
	@objc private func performAction(_ sender:Any?){guard actionButton.isEnabled else{return}; onAction?()}
	@objc private func dismissResult(_ sender:Any?){onDismiss?()}
	@objc private func expand(_ sender:Any?){onExpand?()}
}

/// The full session history is virtualized; expanding a batch adds file rows,
/// not a tall card or another nested scrolling area.
final class TransferHistoryViewController:NSViewController, NSTableViewDataSource, NSTableViewDelegate{
	private struct Entry{let result:TransferHistoryItem; var file:URL?=nil}
	private let incoming:Bool
	private var prefix:String{incoming ? "IncomingHistory" : "OutgoingHistory"}
	private let table=NSTableView()
	private let scroll=NSScrollView()
	private let empty=WindowUI.label(NSLocalizedString("NoOutgoingHistory", value: "No outgoing transfers this session", comment: ""), size: 13, secondary: true)
	private let heading=WindowUI.label("", size: 16, weight: .semibold)
	private let clear=NSButton(title: NSLocalizedString("ClearRecent", value: "Clear", comment: ""), target: nil, action: nil)
	private var results:[TransferHistoryItem]=[]
	private var entries:[Entry]=[]
	private var expanded=Set<String>()
	private var actionEnabled=true
	var onAction:((String)->Void)?
	var onDismiss:((String)->Void)?
	var onClear:(()->Void)?
	var onClose:(()->Void)?

	override func loadView(){
		view=WindowBackgroundView(frame: NSRect(x: 0, y: 0, width: 580, height: 440))
		let content=WindowUI.stack(spacing: 12)
		WindowUI.pin(content, to: view, inset: 20)
		let header=WindowUI.stack(.horizontal)
		header.addArrangedSubview(heading)
		header.addArrangedSubview(WindowUI.spacer())
		clear.bezelStyle = .inline
		clear.target=self
		clear.action=#selector(clearHistory(_:))
		header.addArrangedSubview(clear)
		WindowUI.fill(header, in: content)
		let session=incoming ? NSLocalizedString("IncomingHistorySession", value: "Incoming transfers from this session", comment: "") : NSLocalizedString("OutgoingHistorySession", value: "Outgoing transfers from this session", comment: "")
		WindowUI.fill(WindowUI.label(session, size: 12, secondary: true), in: content)
		table.identifier=NSUserInterfaceItemIdentifier(prefix+"Table")
		table.headerView=nil
		table.style = .plain
		table.intercellSpacing = .zero
		table.allowsColumnReordering=false
		table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		table.selectionHighlightStyle = .none
		let column=NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Transfer"))
		column.resizingMask = .autoresizingMask
		table.addTableColumn(column)
		table.delegate=self
		table.dataSource=self
		table.setAccessibilityLabel(session)
		scroll.hasVerticalScroller=true
		scroll.autohidesScrollers=false
		scroll.scrollerStyle = .legacy
		scroll.borderType = .noBorder
		scroll.drawsBackground=false
		table.frame=NSRect(x: 0, y: 0, width: 540, height: 0)
		table.autoresizingMask = .width
		scroll.documentView=table
		empty.translatesAutoresizingMaskIntoConstraints=false
		if incoming{empty.stringValue=NSLocalizedString("NoIncomingHistory", value: "No incoming transfers this session", comment: "")}
		empty.alignment = .center
		scroll.addSubview(empty)
		NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),empty.widthAnchor.constraint(lessThanOrEqualTo: scroll.widthAnchor)])
		WindowUI.fill(scroll, in: content)
		scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
		scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive=true
		let footer=WindowUI.stack(.horizontal)
		footer.addArrangedSubview(WindowUI.spacer())
		let done=NSButton(title: NSLocalizedString("Done", value: "Done", comment: ""), target: self, action: #selector(closeHistory(_:)))
		done.bezelStyle = .rounded
		done.keyEquivalent="\r"
		footer.addArrangedSubview(done)
		WindowUI.fill(footer, in: content)
	}
	required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
	init(incoming:Bool=false){self.incoming=incoming; super.init(nibName: nil, bundle: nil)}
	func update(_ results:[TransferHistoryItem], actionEnabled:Bool=true, expanding id:String?=nil){
		_ = view
		self.results=results
		self.actionEnabled=actionEnabled
		expanded.formIntersection(Set(results.map(\.id)))
		if let id=id{expanded.insert(id)}
		heading.stringValue=String.localizedStringWithFormat(NSLocalizedString("OutgoingHistoryCount", value: "Transfer history · %d", comment: ""), results.count)
		clear.isEnabled = !results.isEmpty
		empty.isHidden = !results.isEmpty
		reloadEntries()
		if let id=id, let row=entries.firstIndex(where: {$0.result.id==id}){table.scrollRowToVisible(row)}
	}
	func setActionEnabled(_ enabled:Bool){
		actionEnabled=enabled
		let visibleRows=table.rows(in: table.visibleRect)
		guard visibleRows.location != NSNotFound else{return}
		for row in visibleRows.location..<NSMaxRange(visibleRows){(table.view(atColumn: 0, row: row, makeIfNecessary: false) as? TransferHistoryRowView)?.setActionEnabled(enabled)}
	}
	private func reloadEntries(){
		let origin=scroll.contentView.bounds.origin
		entries=results.flatMap {result -> [Entry] in
			[Entry(result: result)]+(expanded.contains(result.id) ? result.items.map {Entry(result: result, file: $0)} : [])
		}
		table.reloadData()
		scroll.contentView.scroll(to: origin)
		scroll.reflectScrolledClipView(scroll.contentView)
	}
	func numberOfRows(in tableView:NSTableView)->Int{entries.count}
	func tableView(_ tableView:NSTableView, heightOfRow row:Int)->CGFloat{entries[row].file==nil ? 58 : 28}
	func tableView(_ tableView:NSTableView, shouldSelectRow row:Int)->Bool{false}
	func tableView(_ tableView:NSTableView, viewFor tableColumn:NSTableColumn?, row:Int)->NSView?{
		let entry=entries[row]
		if let file=entry.file{
			let identifier=NSUserInterfaceItemIdentifier(prefix+"File")
			let cell=tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
			if cell.textField==nil{
				cell.identifier=identifier
				let name=WindowUI.label("", size: 11, secondary: true)
				name.maximumNumberOfLines=1
				name.lineBreakMode = .byTruncatingMiddle
				name.translatesAutoresizingMaskIntoConstraints=false
				cell.addSubview(name)
				NSLayoutConstraint.activate([name.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 64),name.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),name.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
				cell.textField=name
			}
			cell.textField?.stringValue=file.isFileURL ? file.lastPathComponent : file.absoluteString
			cell.textField?.toolTip=file.isFileURL ? file.path : file.absoluteString
			return cell
		}
		let cell=tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(prefix+"Row"), owner: self) as? TransferHistoryRowView ?? TransferHistoryRowView(frame: .zero)
		let id=entry.result.id
		cell.configure(entry.result, expanded: expanded.contains(id), actionEnabled: actionEnabled)
		cell.onAction={ [weak self] in self?.onAction?(id) }
		cell.onDismiss={ [weak self] in self?.onDismiss?(id) }
		cell.onExpand={ [weak self] in
			guard let self=self else{return}
			if !self.expanded.insert(id).inserted{self.expanded.remove(id)}
			self.reloadEntries()
		}
		return cell
	}
	@objc private func clearHistory(_ sender:Any?){onClear?()}
	@objc private func closeHistory(_ sender:Any?){onClose?()}
	override func cancelOperation(_ sender:Any?){onClose?()}
}

final class SendViewController:NSViewController, NSTableViewDataSource, NSTableViewDelegate{
	let sender=SendTransferViewController()
	var compressFolders=SendPreferences.compressFolders(){didSet{sender.folderHandling=compressFolders ? .compress : .sendContents}}
	var onTransferActivityChange:((Bool)->Void)?
	var onTransferCompleted:((OutgoingTransferResult)->Void)?
	var onContentSizeChange:(()->Void)?
	var onOpenItem:((URL)->Bool)?
	var onRevealItem:((URL)->Void)?
	var contentHeight:CGFloat{content.fittingSize.height}
	private(set) var recentTransfers:[OutgoingTransferResult]=[]
	private let content=WindowUI.stack(spacing: 16)
	private let senderCard=CardView()
	private let selectionContent=WindowUI.stack(spacing: 10)
	private let dropIcon=WindowUI.symbol("doc.on.doc", description: NSLocalizedString("DropFilesToSend", value: "Drop files here to send", comment: ""))
	private let dropOutline=DropOutlineView()
	private let selectionHeadingSpacer=WindowUI.spacer()
	private var emptyTitleWidth:NSLayoutConstraint!
	private let errorLabel=WindowUI.label("", size: 12, secondary: true)
	private let selectionTitle=WindowUI.label("", size: 16, weight: .semibold)
	private let removeAllButton=NSButton(title: NSLocalizedString("RemoveAllSelectedItems", value: "Remove All", comment: ""), target: nil, action: nil)
	private let selectionHelp=WindowUI.label("", size: 12, secondary: true)
	private let selectionList=SelectedItemsTableView()
	private let selectionScroll=NSScrollView()
	private var selectionListHeight:NSLayoutConstraint!
	private var listedFiles:[URL]=[]
	private var listedItemsEditable=true
	private let chooseButton=NSButton(title: NSLocalizedString("SendFiles", value: "Send files…", comment: ""), target: nil, action: nil)
	private let preparingSpinner=NSProgressIndicator()
	private let history=WindowUI.stack(spacing: 0)
	private let historyCard=CardView()
	private let historyHeading=WindowUI.stack(.horizontal)
	private let historyTitle=WindowUI.label("", size: 13, weight: .semibold)
	private let viewAllButton=NSButton(title: "", target: nil, action: nil)
	private var historyRows:[TransferHistoryRowView]=[]
	private var historySheet:TransferHistoryViewController?

	override func loadView(){
		view=WindowBackgroundView(frame: NSRect(x: 0, y: 0, width: 520, height: 500))
		view.wantsLayer=true
		(view as? WindowBackgroundView)?.backgroundStyle = .transparent
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
		selection.identifier=NSUserInterfaceItemIdentifier("SendSelectionCard")
		selection.wantsLayer=true
		selection.usesSoftAppearance=true
		selectionContent.alignment = .centerX
		WindowUI.pin(selectionContent, to: selection, inset: 16)
		dropOutline.color = .systemBlue
		WindowUI.pin(dropOutline, to: selection, inset: 8)
		dropIcon.identifier=NSUserInterfaceItemIdentifier("SendDropIcon")
		dropIcon.contentTintColor = .systemBlue
		NSLayoutConstraint.activate([dropIcon.widthAnchor.constraint(equalToConstant: 44),dropIcon.heightAnchor.constraint(equalToConstant: 44)])
		selectionContent.addArrangedSubview(dropIcon)
		selectionTitle.identifier=NSUserInterfaceItemIdentifier("SendSelectionTitle")
		selectionTitle.maximumNumberOfLines=2
		selectionTitle.lineBreakMode = .byTruncatingMiddle
		let selectionHeading=WindowUI.stack(.horizontal)
		selectionHeading.addArrangedSubview(selectionTitle)
		selectionHeading.addArrangedSubview(selectionHeadingSpacer)
		emptyTitleWidth=selectionTitle.widthAnchor.constraint(equalTo: selectionHeading.widthAnchor)
		removeAllButton.identifier=NSUserInterfaceItemIdentifier("SendSelectionRemoveAll")
		removeAllButton.bezelStyle = .regularSquare
		if #available(macOS 26.0, *){removeAllButton.borderShape = .roundedRectangle}
		removeAllButton.controlSize = .small
		removeAllButton.toolTip=NSLocalizedString("RemoveAllFromSendList", value: "Remove all items from the send list without deleting files", comment: "")
		removeAllButton.target=self
		removeAllButton.action=#selector(removeAllItems(_:))
		removeAllButton.isHidden=true
		selectionHeading.addArrangedSubview(removeAllButton)
		WindowUI.fill(selectionHeading, in: selectionContent)
		selectionList.identifier=NSUserInterfaceItemIdentifier("SendSelectionList")
		selectionList.headerView=nil
		selectionList.style = .plain
		selectionList.rowHeight=28
		selectionList.intercellSpacing = .zero
		selectionList.usesAutomaticRowHeights=false
		selectionList.usesAlternatingRowBackgroundColors=true
		selectionList.allowsMultipleSelection=false
		selectionList.allowsEmptySelection=true
		selectionList.allowsColumnReordering=false
		selectionList.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
		selectionList.setAccessibilityLabel(NSLocalizedString("SelectedFilesAndFolders", value: "Selected files and folders", comment: ""))
		let column=NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SelectedItem"))
		column.resizingMask = .autoresizingMask
		selectionList.addTableColumn(column)
		selectionList.dataSource=self
		selectionList.delegate=self
		selectionList.onContextMenu={ [weak self] row in self?.itemMenu(forRow: row) }
		selectionScroll.identifier=NSUserInterfaceItemIdentifier("SendSelectionScroll")
		selectionScroll.setAccessibilityLabel(NSLocalizedString("SelectedFilesAndFolders", value: "Selected files and folders", comment: ""))
		selectionScroll.hasVerticalScroller=true
		selectionScroll.autohidesScrollers=false
		selectionScroll.scrollerStyle = .legacy
		selectionScroll.hasHorizontalScroller=false
		selectionScroll.borderType = .noBorder
		selectionScroll.drawsBackground=false
		selectionList.frame=NSRect(x: 0, y: 0, width: 440, height: 0)
		selectionList.autoresizingMask = .width
		selectionScroll.documentView=selectionList
		selectionListHeight=selectionScroll.heightAnchor.constraint(equalToConstant: 0)
		selectionListHeight.isActive=true
		selectionScroll.isHidden=true
		WindowUI.fill(selectionScroll, in: selectionContent)
		WindowUI.fill(selectionHelp, in: selectionContent)
		chooseButton.bezelStyle = .regularSquare
		if #available(macOS 26.0, *){chooseButton.borderShape = .roundedRectangle}
		chooseButton.bezelColor = .systemBlue
		chooseButton.controlSize = .large
		chooseButton.target=self
		chooseButton.action=#selector(chooseFiles(_:))
		chooseButton.toolTip=NSLocalizedString("ChooseFilesAndFolders", value: "Choose files or folders to send", comment: "")
		chooseButton.setAccessibilityLabel(chooseButton.toolTip)
		preparingSpinner.style = .spinning
		preparingSpinner.controlSize = .small
		preparingSpinner.isIndeterminate=true
		preparingSpinner.isHidden=true
		let chooseRow=WindowUI.stack(.horizontal)
		let leading=WindowUI.spacer()
		let trailing=WindowUI.spacer()
		chooseRow.addArrangedSubview(leading)
		chooseRow.addArrangedSubview(preparingSpinner)
		chooseRow.addArrangedSubview(chooseButton)
		chooseRow.addArrangedSubview(trailing)
		leading.widthAnchor.constraint(equalTo: trailing.widthAnchor).isActive=true
		WindowUI.fill(chooseRow, in: selectionContent)
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
			self.senderCard.isHidden=true
			self.updateControls()
		}
		addChild(sender)
		senderCard.wantsLayer=true
		senderCard.usesSoftAppearance=true
		WindowUI.pin(sender.view, to: senderCard, inset: 16)
		sender.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive=true
		WindowUI.fill(senderCard, in: content)
		senderCard.isHidden=true
		historyTitle.maximumNumberOfLines=1
		historyTitle.lineBreakMode = .byTruncatingTail
		historyTitle.toolTip=NSLocalizedString("OutgoingHistorySession", value: "Outgoing transfers from this session", comment: "")
		historyHeading.addArrangedSubview(historyTitle)
		historyHeading.addArrangedSubview(WindowUI.spacer())
		let clear=NSButton(title: NSLocalizedString("ClearRecent", value: "Clear", comment: ""), target: self, action: #selector(clearHistory(_:)))
		clear.bezelStyle = .inline
		historyHeading.addArrangedSubview(clear)
		WindowUI.fill(historyHeading, in: content)
		historyCard.wantsLayer=true
		historyCard.usesSoftAppearance=true
		WindowUI.pin(history, to: historyCard, inset: 0)
		WindowUI.fill(historyCard, in: content)
		viewAllButton.identifier=NSUserInterfaceItemIdentifier("ViewAllOutgoingTransfers")
		viewAllButton.bezelStyle = .inline
		viewAllButton.target=self
		viewAllButton.action=#selector(viewAllHistory(_:))
		WindowUI.fill(viewAllButton, in: content)
		historyHeading.isHidden=true
		historyCard.isHidden=true
		viewAllButton.isHidden=true
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

	/// Window drops add original source items, never prepared ZIPs or folder contents.
	@discardableResult func appendItems(_ urls:[URL])->Bool{
		_ = view
		guard !sender.isTransferring else{
			showSelectionError(NSLocalizedString("FinishCurrentTransfer", value: "Finish or cancel the current transfer before choosing other items.", comment: ""))
			return false
		}
		guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else{
			showSelectionError(NSLocalizedString("SendFilesOnly", value: "The Send tab accepts files only. To share a link, use the macOS Share menu.", comment: ""))
			return false
		}
		let existing=sender.originalItems
		guard existing.allSatisfy(\.isFileURL) else{
			showSelectionError(NSLocalizedString("CannotAddFilesToLink", value: "Remove the shared link before adding files or folders.", comment: ""))
			return false
		}
		var seen=Set(existing.map { $0.standardizedFileURL })
		let additions=urls.filter { seen.insert($0.standardizedFileURL).inserted }
		guard !additions.isEmpty else{
			errorLabel.isHidden=true
			onContentSizeChange?()
			return true
		}
		return applySelection(existing+additions)
	}

	/// A single HTTP or HTTPS link handed over by the macOS Share menu.
	@discardableResult func selectLink(_ url:URL) -> Bool{
		_ = view
		return applySelection([url])
	}

	private func applySelection(_ items:[URL]) -> Bool{
		do{
			try sender.configureItems(items)
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
		onContentSizeChange?()
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
		senderCard.isHidden=true
		errorLabel.isHidden=true
		updateControls()
	}
	private func updateSelectionList(){
		let files=sender.originalItems
		let editable = !sender.isTransferring
		guard files != listedFiles || editable != listedItemsEditable else{return}
		let selectedRow=selectionList.selectedRow
		let selected=listedFiles.indices.contains(selectedRow) ? listedFiles[selectedRow] : nil
		let origin=selectionScroll.contentView.bounds.origin
		let preserveScroll=files == listedFiles || (files.count>listedFiles.count && files.starts(with: listedFiles))
		listedFiles=files
		listedItemsEditable=editable
		selectionScroll.isHidden=files.isEmpty
		selectionListHeight.constant=CGFloat(min(files.count,5))*selectionList.rowHeight
		selectionList.reloadData()
		if let selected=selected, let row=files.firstIndex(of: selected){
			selectionList.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		}else{
			selectionList.deselectAll(nil)
		}
		selectionScroll.contentView.scroll(to: preserveScroll ? origin : .zero)
		selectionScroll.reflectScrolledClipView(selectionScroll.contentView)
	}

	func numberOfRows(in tableView:NSTableView)->Int{listedFiles.count}
	func tableView(_ tableView:NSTableView, viewFor tableColumn:NSTableColumn?, row:Int)->NSView?{
		guard listedFiles.indices.contains(row) else{return nil}
		let identifier=NSUserInterfaceItemIdentifier("SelectedItemCell")
		let cell=tableView.makeView(withIdentifier: identifier, owner: self) as? SelectedItemCellView ?? SelectedItemCellView()
		cell.identifier=identifier
		let file=listedFiles[row]
		let name=file.isFileURL ? file.lastPathComponent : file.absoluteString
		cell.textField?.stringValue=name
		cell.textField?.toolTip=file.isFileURL ? file.path : file.absoluteString
		cell.setAccessibilityHelp(cell.textField?.toolTip)
		cell.imageView?.image=file.isFileURL ? NSWorkspace.shared.icon(forFile: file.path) : NSImage(named: NSImage.networkName)
		cell.removeButton.isEnabled = !sender.isTransferring
		cell.removeButton.toolTip=NSLocalizedString("RemoveFromSendList", value: "Remove from send list", comment: "")
		cell.removeButton.setAccessibilityLabel(String(format: NSLocalizedString("RemoveSelectedItem", value: "Remove %@ from send list", comment: ""), name))
		cell.onRemove={ [weak self] in self?.removeItem(file) }
		return cell
	}

	private func removeItem(_ url:URL){
		guard !sender.isTransferring, sender.originalItems.contains(url) else{return}
		let remaining=sender.originalItems.filter { $0 != url }
		if remaining.isEmpty{clearSelection()}
		else{_ = applySelection(remaining)}
	}
	@objc private func removeAllItems(_ sender:Any?){
		guard !self.sender.isTransferring else{return}
		clearSelection()
	}
	private func itemMenu(forRow row:Int)->NSMenu?{
		guard listedFiles.indices.contains(row) else{return nil}
		let url=listedFiles[row]
		let menu=NSMenu()
		menu.autoenablesItems=false
		let open=NSMenuItem(title: NSLocalizedString("OpenSelectedItem", value: "Open", comment: ""), action: #selector(openItem(_:)), keyEquivalent: "")
		open.target=self
		open.representedObject=url
		open.isEnabled = !url.isFileURL || FileManager.default.fileExists(atPath: url.path)
		menu.addItem(open)
		if url.isFileURL{
			let reveal=NSMenuItem(title: NSLocalizedString("RevealSelectedItem", value: "Reveal in Finder", comment: ""), action: #selector(revealItem(_:)), keyEquivalent: "")
			reveal.target=self
			reveal.representedObject=url
			reveal.isEnabled=open.isEnabled
			menu.addItem(reveal)
		}
		return menu
	}
	private func validItemURL(_ item:NSMenuItem)->URL?{
		guard let url=item.representedObject as? URL, sender.originalItems.contains(url) else{return nil}
		guard !url.isFileURL || FileManager.default.fileExists(atPath: url.path) else{
			showSelectionError(NSLocalizedString("SelectedItemMissing", value: "This item is no longer available at its original location.", comment: ""))
			return nil
		}
		return url
	}
	@objc private func openItem(_ item:NSMenuItem){
		guard let url=validItemURL(item) else{return}
		if !(onOpenItem?(url) ?? NSWorkspace.shared.open(url)){
			showSelectionError(NSLocalizedString("SelectedItemOpenFailed", value: "This item could not be opened with its default app.", comment: ""))
		}
	}
	@objc private func revealItem(_ item:NSMenuItem){
		guard let url=validItemURL(item), url.isFileURL else{return}
		if let reveal=onRevealItem{reveal(url)}
		else{NSWorkspace.shared.activateFileViewerSelecting([url])}
	}
	private func updateControls(){
		updateSelectionList()
		let enabled = !sender.isTransferring
		let preparing=sender.isPreparing
		let empty=sender.originalItems.isEmpty
		chooseButton.isEnabled=enabled && !preparing
		removeAllButton.isHidden=empty
		removeAllButton.isEnabled=enabled && !empty
		selectionHeadingSpacer.isHidden=empty
		emptyTitleWidth.isActive=empty
		selectionTitle.alignment=empty ? .center : .left
		selectionTitle.font=NSFont.systemFont(ofSize: empty ? 20 : 16, weight: .semibold)
		selectionHelp.alignment=empty ? .center : .left
		errorLabel.alignment=empty ? .center : .left
		dropIcon.isHidden = !empty
		dropOutline.isHidden = !empty
		selectionContent.edgeInsets=NSEdgeInsets(top: empty ? 16 : 0, left: 0, bottom: empty ? 16 : 0, right: 0)
		if preparing{
			preparingSpinner.startAnimation(nil)
		}else{
			preparingSpinner.stopAnimation(nil)
		}
		preparingSpinner.isHidden = !preparing
		let displayItems=sender.preparedItems.isEmpty ? sender.originalItems : sender.preparedItems
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
				selectionTitle.stringValue=displayItems[0].isFileURL
					? NSLocalizedString("OneFileReadyToSend", value: "1 file ready to send", comment: "")
					: NSLocalizedString("LinkReadyToSend", value: "Link ready to send", comment: "")
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
		for row in historyRows{row.setActionEnabled(enabled && !preparing)}
		historySheet?.setActionEnabled(enabled && !preparing)
		onTransferActivityChange?(!enabled)
		onContentSizeChange?()
	}
	private func record(_ result:OutgoingTransferResult){
		let alreadyCompleted=recentTransfers.contains {$0.id==result.id && $0.state == .completed}
		recentTransfers.removeAll {$0.id==result.id}
		recentTransfers.insert(result, at: 0)
		if result.state == .completed && !alreadyCompleted && sender.state == .completed{
			// The result already owns the history/retry snapshot. Clear only the
			// just-finished selection, never a new selection after a stale callback.
			clearSelection()
		}
		rebuildHistory()
		if result.state == .completed && !alreadyCompleted{onTransferCompleted?(result)}
	}
	private func rebuildHistory(){
		for child in history.arrangedSubviews{history.removeArrangedSubview(child); child.removeFromSuperview()}
		historyRows.removeAll()
		historyCard.isHidden=recentTransfers.isEmpty
		historyHeading.isHidden=recentTransfers.isEmpty
		historyTitle.stringValue=String.localizedStringWithFormat(NSLocalizedString("RecentOutgoingTransfersCount", value: "Recent outgoing transfers · %d", comment: ""), recentTransfers.count)
		viewAllButton.isHidden=recentTransfers.count<=3
		viewAllButton.title=String.localizedStringWithFormat(NSLocalizedString("ViewAllOutgoingTransfers", value: "View all %d transfers →", comment: ""), recentTransfers.count)
		for result in recentTransfers.prefix(3){
			if !historyRows.isEmpty{
				let separator=NSBox()
				separator.boxType = .separator
				WindowUI.fill(separator, in: history)
			}
			let row=TransferHistoryRowView(frame: .zero)
			row.configure(TransferHistoryItem(result), actionEnabled: !sender.isTransferring && !sender.isPreparing)
			row.heightAnchor.constraint(equalToConstant: 58).isActive=true
			row.onAction={ [weak self] in self?.retryRecent(result.id) }
			row.onDismiss={ [weak self] in self?.dismissRecent(result.id) }
			row.onExpand={ [weak self] in self?.showHistory(expanding: result.id) }
			historyRows.append(row)
			WindowUI.fill(row, in: history)
		}
		historySheet?.update(recentTransfers.map(TransferHistoryItem.init), actionEnabled: !sender.isTransferring && !sender.isPreparing)
		onContentSizeChange?()
		updateControls()
	}
	private func retryRecent(_ id:UUID){
		guard !sender.isTransferring, !sender.isPreparing, let result=recentTransfers.first(where: {$0.id==id}) else {return}
		closeHistory()
		if result.urls.count==1, let link=result.urls.first, !link.isFileURL{
			_ = selectLink(link)
		}else{
			_ = selectItems(result.urls)
		}
	}
	private func dismissRecent(_ id:UUID){
		recentTransfers.removeAll {$0.id==id}
		rebuildHistory()
	}
	@objc private func viewAllHistory(_ sender:Any?){showHistory()}
	private func showHistory(expanding id:UUID?=nil){
		guard view.window != nil else{return}
		if let sheet=historySheet{sheet.update(recentTransfers.map(TransferHistoryItem.init), actionEnabled: !sender.isTransferring && !sender.isPreparing, expanding: id?.uuidString); return}
		let sheet=TransferHistoryViewController()
		sheet.onAction={ [weak self] id in if let id=UUID(uuidString: id){self?.retryRecent(id)} }
		sheet.onDismiss={ [weak self] id in if let id=UUID(uuidString: id){self?.dismissRecent(id)} }
		sheet.onClear={ [weak self] in self?.clearHistory(nil) }
		sheet.onClose={ [weak self] in self?.closeHistory() }
		sheet.update(recentTransfers.map(TransferHistoryItem.init), actionEnabled: !sender.isTransferring && !sender.isPreparing, expanding: id?.uuidString)
		historySheet=sheet
		presentAsSheet(sheet)
	}
	private func closeHistory(){
		guard let sheet=historySheet else{return}
		dismiss(sheet)
		historySheet=nil
		onContentSizeChange?()
	}
	@objc private func clearHistory(_ sender:Any?){recentTransfers.removeAll(); rebuildHistory()}
}
