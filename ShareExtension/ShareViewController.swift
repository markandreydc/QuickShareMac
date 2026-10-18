import Cocoa

/// Finder's Share menu entry point. The extension never transfers anything
/// itself: it loads the shared items, hands them to the main app, and dismisses.
/// The main app owns the Send tab, device discovery, folder compression, and
/// transfer history, so the Share menu and the app window always agree.
class ShareViewController:NSViewController{
	private var dismissed=false
	private var handedOff=false
	private var lastPayload:ShareHandoff.Payload?
	private let iconView=NSImageView()
	private let titleLabel=NSTextField(labelWithString: "")
	private let itemsLabel=NSTextField(wrappingLabelWithString: "")
	private let helpLabel=NSTextField(wrappingLabelWithString: "")
	private let retryButton=NSButton(title: NSLocalizedString("Retry", value: "Retry", comment: ""), target: nil, action: nil)
	private let cancelButton=NSButton(title: NSLocalizedString("Cancel", value: "Cancel", comment: ""), target: nil, action: nil)

	override func loadView(){
		let root=NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 236))
		let content=NSStackView()
		content.orientation = .vertical
		content.alignment = .centerX
		content.spacing=10
		content.detachesHiddenViews=true
		content.translatesAutoresizingMaskIntoConstraints=false
		root.addSubview(content)
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
			content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
			content.centerYAnchor.constraint(equalTo: root.centerYAnchor),
			content.topAnchor.constraint(greaterThanOrEqualTo: root.topAnchor, constant: 20),
			content.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16)
		])
		iconView.image=NSImage(named: "QuickShareMacIcon")
		iconView.imageScaling = .scaleProportionallyUpOrDown
		iconView.translatesAutoresizingMaskIntoConstraints=false
		NSLayoutConstraint.activate([iconView.widthAnchor.constraint(equalToConstant: 64), iconView.heightAnchor.constraint(equalToConstant: 64)])
		content.addArrangedSubview(iconView)
		titleLabel.font=NSFont.systemFont(ofSize: 15, weight: .semibold)
		titleLabel.alignment = .center
		titleLabel.maximumNumberOfLines=2
		titleLabel.lineBreakMode = .byTruncatingMiddle
		for label in [titleLabel,itemsLabel,helpLabel]{
			label.translatesAutoresizingMaskIntoConstraints=false
			label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
			content.addArrangedSubview(label)
			label.widthAnchor.constraint(equalTo: content.widthAnchor).isActive=true
		}
		for label in [itemsLabel,helpLabel]{
			label.font=NSFont.systemFont(ofSize: 12)
			label.textColor = .secondaryLabelColor
			label.alignment = .center
			label.maximumNumberOfLines=2
			label.lineBreakMode = .byTruncatingMiddle
		}
		retryButton.bezelStyle = .rounded
		retryButton.target=self
		retryButton.action=#selector(retry(_:))
		retryButton.isHidden=true
		cancelButton.bezelStyle = .rounded
		cancelButton.target=self
		cancelButton.action=#selector(cancel(_:))
		cancelButton.keyEquivalent="\u{1b}"
		let buttons=NSStackView(views: [retryButton,cancelButton])
		buttons.orientation = .horizontal
		buttons.spacing=8
		buttons.translatesAutoresizingMaskIntoConstraints=false
		content.addArrangedSubview(buttons)
		view=root
	}

	override func viewDidLoad(){
		super.viewDidLoad()
		titleLabel.stringValue=NSLocalizedString("HandoffOpening", value: "Opening QuickShareMac…", comment: "")
		itemsLabel.isHidden=true
		helpLabel.isHidden=true
		updateAccessibility()
		prepareAttachments()
	}

	override func viewWillDisappear(){
		dismissed=true
		super.viewWillDisappear()
	}

	/// The handoff runs through LaunchServices. Tests override this to observe
	/// exactly what would be opened without launching another app.
	func handOff(_ payload:ShareHandoff.Payload, completion:@escaping (Error?) -> Void){
		Self.open(payload, completion: completion)
	}

	private func prepareAttachments(){
		let attachments=(extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap {$0.attachments ?? []}
		guard !attachments.isEmpty else {
			showFailure(title: Self.unsuitableTitle, detail: NSLocalizedString("NoAttachments", value: "No supported files or links were provided.", comment: ""))
			return
		}
		let group=DispatchGroup()
		var loaded:[Int:URL]=[:]
		for (index, provider) in attachments.enumerated(){
			group.enter()
			provider.loadObject(ofClass: NSURL.self){ item, _ in
				DispatchQueue.main.async {
					if let url=item as? URL{loaded[index]=url}
					group.leave()
				}
			}
		}
		group.notify(queue: .main){ [weak self] in
			guard let self=self, !self.dismissed else {return}
			let items=attachments.indices.compactMap {loaded[$0]}
			guard items.count==attachments.count else {
				self.showFailure(title: Self.unsuitableTitle, detail: NSLocalizedString("UnreadableSelection", value: "One of the selected files is not readable. Choose it again in Finder.", comment: ""))
				return
			}
			self.beginHandoff(items: items)
		}
	}

	private func beginHandoff(items:[URL]){
		guard !handedOff else{return}
		guard let payload=ShareHandoff.payload(for: items) else {
			showFailure(title: Self.unsuitableTitle, detail: NSLocalizedString("UnsupportedSelection", value: "Choose files, or one HTTP or HTTPS link. Files and links cannot be sent together.", comment: ""))
			return
		}
		lastPayload=payload
		showHandingOff(payload: payload)
		handOff(payload){ [weak self] error in
			DispatchQueue.main.async{
				guard let self=self, !self.dismissed else {return}
				if let error=error{
					self.showFailure(title: Self.failedTitle, detail: error.localizedDescription.isEmpty ? Self.failedHelp : error.localizedDescription)
				}else{
					self.handedOff=true
					self.dismissed=true
					self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
				}
			}
		}
	}

	private func showHandingOff(payload:ShareHandoff.Payload){
		titleLabel.stringValue=NSLocalizedString("HandoffOpening", value: "Opening QuickShareMac…", comment: "")
		switch payload{
		case .files(let files):
			itemsLabel.stringValue=files.count==1 ? files[0].lastPathComponent : String.localizedStringWithFormat(NSLocalizedString("HandoffItemsCount", value: "%d items", comment: ""), files.count)
		case .link(let link):
			itemsLabel.stringValue=link.absoluteString
		}
		itemsLabel.isHidden=itemsLabel.stringValue.isEmpty
		helpLabel.stringValue=NSLocalizedString("HandoffContinues", value: "The device list opens in the main window. Nothing is sent until you choose a recipient.", comment: "")
		helpLabel.isHidden=false
		retryButton.isHidden=true
		updateAccessibility()
	}

	private func showFailure(title:String, detail:String){
		titleLabel.stringValue=title
		itemsLabel.stringValue=detail
		itemsLabel.isHidden=detail.isEmpty
		helpLabel.stringValue=""
		helpLabel.isHidden=true
		retryButton.isHidden=lastPayload==nil
		updateAccessibility()
	}

	private func updateAccessibility(){
		view.setAccessibilityLabel([titleLabel.stringValue,itemsLabel.isHidden ? "" : itemsLabel.stringValue,helpLabel.isHidden ? "" : helpLabel.stringValue].filter {!$0.isEmpty}.joined(separator: ". "))
	}

	@objc private func retry(_ sender:Any?){
		guard let payload=lastPayload else {return}
		beginHandoff(items: payload.items)
	}

	@objc private func cancel(_ sender:Any?){
		dismissed=true
		extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
	}

	private static var unsuitableTitle:String{NSLocalizedString("HandoffUnsuitableTitle", value: "Can’t send these items", comment: "")}
	private static var failedTitle:String{NSLocalizedString("HandoffFailedTitle", value: "Couldn’t open QuickShareMac", comment: "")}
	private static var failedHelp:String{NSLocalizedString("HandoffFailedHelp", value: "Open QuickShareMac from Applications, then try again.", comment: "")}

	private static func open(_ payload:ShareHandoff.Payload, completion:@escaping (Error?) -> Void){
		switch payload{
		case .link(let link):
			guard let url=ShareHandoff.handoffURL(for: link) else{
				completion(handoffError)
				return
			}
			NSWorkspace.shared.open(url, configuration: openConfiguration()){ _, error in completion(error)}
		case .files(let files):
			guard let app=containingAppURL else{
				completion(handoffError)
				return
			}
			// LaunchServices can silently drop sibling documents when a
			// multi-item open contains a quarantined item whose security check
			// takes over the whole request (observed with a downloaded ZIP
			// shared next to a DOCX), so each item travels in its own open
			// request. The main app merges the resulting events back into one
			// selection.
			let group=DispatchGroup()
			var failure:Error?
			for file in files{
				group.enter()
				NSWorkspace.shared.open([file], withApplicationAt: app, configuration: openConfiguration()){ _, error in
					DispatchQueue.main.async{
						if failure==nil{failure=error}
						group.leave()
					}
				}
			}
			group.notify(queue: .main){completion(failure)}
		}
	}

	/// The app that contains this extension, or its registered location when the
	/// extension runs from a relocated bundle.
	private static var containingAppURL:URL?{
		let app=Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
		if app.pathExtension=="app"{return app}
		return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "me.grishka.QuickShareMac")
	}

	private static func openConfiguration() -> NSWorkspace.OpenConfiguration{
		let configuration=NSWorkspace.OpenConfiguration()
		configuration.activates=true
		configuration.addsToRecentItems=false
		configuration.promptsUserIfNeeded=false
		return configuration
	}

	private static var handoffError:Error{
		NSError(domain: "me.grishka.QuickShareMac.ShareExtension", code: 1, userInfo: [NSLocalizedDescriptionKey:failedHelp])
	}
}

private extension ShareHandoff.Payload{
	var items:[URL]{
		switch self{
		case .files(let files): return files
		case .link(let link): return [link]
		}
	}
}
