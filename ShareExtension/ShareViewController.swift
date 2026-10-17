import Cocoa
import NearbyShare
import QRCode

private enum ShareUI{
	static func stack(_ orientation:NSUserInterfaceLayoutOrientation = .vertical, spacing:CGFloat = 10) -> NSStackView{
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
		child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive=true
	}
	static func pin(_ child:NSView, to parent:NSView, inset:CGFloat = 0){
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
		let view=NSView()
		view.setContentHuggingPriority(.defaultLow, for: .horizontal)
		return view
	}
}

private final class ShareBackgroundView:NSView{
	override var wantsUpdateLayer:Bool {true}
	override func updateLayer(){layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor}
	override func viewDidChangeEffectiveAppearance(){
		super.viewDidChangeEffectiveAppearance()
		needsDisplay=true
	}
}

class ShareViewController:NSViewController, ShareExtensionDelegate{
	private var urls:[URL]=[]
	private var foundDevices:[RemoteDeviceInfo]=[]
	private var chosenDevice:RemoteDeviceInfo?
	private var lastError:Error?
	private var sheetWindow:NSWindow?
	private var discovering=false
	private var registered=false
	private var terminal=false
	private var requestEnded=false
	private var totalBytes:Int64=0
	private let filesIcon=NSImageView()
	private let filesLabel=ShareUI.label(NSLocalizedString("PreparingFiles", value: "Preparing files…", comment: ""))
	private let contentWrap=NSView()
	private let discoveryView=ShareUI.stack(spacing: 12)
	private let loading=ShareUI.stack(spacing: 12)
	private let spinner=NSProgressIndicator()
	private let listView=NSCollectionView()
	private let scrollView=NSScrollView()
	private let progressView=ShareUI.stack(spacing: 12)
	private let deviceIcon=NSImageView()
	private let deviceName=ShareUI.label("", size: 15, weight: .semibold)
	private let pinLabel=ShareUI.label("", size: 28, weight: .semibold)
	private let progressBar=NSProgressIndicator()
	private let progressState=ShareUI.label("", secondary: true)
	private let progressHelp=ShareUI.label("", size: 12, secondary: true)
	private let guidance=ShareUI.label(NSLocalizedString("QuickShareDiscoveryHint", value: "Open Quick Share on your Android device and choose Receive, or connect with a QR code. Keep both devices on the same Wi-Fi network.", comment: ""), size: 12, secondary: true)
	private let qrCodeButton=NSButton(title: NSLocalizedString("ConnectWithQRCode", value: "Connect with QR code…", comment: ""), target: nil, action: nil)
	private let closeButton=NSButton(title: NSLocalizedString("Cancel", value: "Cancel", comment: ""), target: nil, action: nil)

	override func loadView(){
		view=ShareBackgroundView(frame: NSRect(x: 0, y: 0, width: 480, height: 500))
		view.wantsLayer=true
		preferredContentSize=NSSize(width: 480, height: 500)
		let content=ShareUI.stack(spacing: 16)
		ShareUI.pin(content, to: view, inset: 20)
		ShareUI.fill(ShareUI.label(NSLocalizedString("SendWithQuickShareMac", value: "Send with QuickShareMac", comment: ""), size: 18, weight: .semibold), in: content)
		let files=ShareUI.stack(.horizontal)
		filesIcon.imageScaling = .scaleProportionallyUpOrDown
		NSLayoutConstraint.activate([filesIcon.widthAnchor.constraint(equalToConstant: 28), filesIcon.heightAnchor.constraint(equalToConstant: 28)])
		files.addArrangedSubview(filesIcon)
		filesLabel.maximumNumberOfLines=2
		filesLabel.lineBreakMode = .byTruncatingMiddle
		files.addArrangedSubview(filesLabel)
		ShareUI.fill(files, in: content)
		ShareUI.fill(contentWrap, in: content)
		contentWrap.heightAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive=true
		contentWrap.setContentHuggingPriority(.defaultLow, for: .vertical)
		ShareUI.pin(discoveryView, to: contentWrap)
		ShareUI.fill(ShareUI.label(NSLocalizedString("ChooseNearbyDevice", value: "Choose a nearby device", comment: ""), size: 13, weight: .semibold), in: discoveryView)
		let discoveryBody=NSView()
		ShareUI.fill(discoveryBody, in: discoveryView)
		discoveryBody.setContentHuggingPriority(.defaultLow, for: .vertical)
		scrollView.borderType = .noBorder
		scrollView.drawsBackground=false
		scrollView.hasVerticalScroller=true
		scrollView.autohidesScrollers=true
		ShareUI.pin(scrollView, to: discoveryBody)
		let layout=NSCollectionViewFlowLayout()
		layout.itemSize=NSSize(width: 128, height: 110)
		layout.minimumInteritemSpacing=12
		layout.minimumLineSpacing=12
		layout.sectionInset=NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
		listView.collectionViewLayout=layout
		listView.register(DeviceCollectionItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("Device"))
		listView.isSelectable=true
		listView.backgroundColors=[.clear]
		listView.dataSource=self
		listView.delegate=self
		listView.setAccessibilityLabel(NSLocalizedString("NearbyDevices", value: "Nearby devices", comment: ""))
		scrollView.documentView=listView
		listView.frame=NSRect(x: 0, y: 0, width: 440, height: 200)
		listView.autoresizingMask=[.width]
		loading.alignment = .centerX
		loading.translatesAutoresizingMaskIntoConstraints=false
		discoveryBody.addSubview(loading)
		NSLayoutConstraint.activate([
			loading.centerXAnchor.constraint(equalTo: discoveryBody.centerXAnchor),
			loading.centerYAnchor.constraint(equalTo: discoveryBody.centerYAnchor),
			loading.widthAnchor.constraint(equalTo: discoveryBody.widthAnchor)
		])
		spinner.style = .spinning
		spinner.isIndeterminate=true
		spinner.startAnimation(nil)
		loading.addArrangedSubview(spinner)
		loading.addArrangedSubview(ShareUI.label(NSLocalizedString("LookingForDevices", value: "Looking for devices…", comment: ""), weight: .medium))
		ShareUI.pin(progressView, to: contentWrap)
		progressView.isHidden=true
		progressView.setContentHuggingPriority(.defaultLow, for: .vertical)
		progressView.alignment = .centerX
		deviceIcon.imageScaling = .scaleProportionallyUpOrDown
		NSLayoutConstraint.activate([deviceIcon.widthAnchor.constraint(equalToConstant: 40), deviceIcon.heightAnchor.constraint(equalToConstant: 40)])
		progressView.addArrangedSubview(deviceIcon)
		deviceName.alignment = .center
		ShareUI.fill(deviceName, in: progressView)
		pinLabel.font=NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
		pinLabel.alignment = .center
		pinLabel.isHidden=true
		pinLabel.setAccessibilityLabel(NSLocalizedString("VerificationPIN", value: "Verification PIN", comment: ""))
		ShareUI.fill(pinLabel, in: progressView)
		progressBar.style = .bar
		progressBar.minValue=0
		progressBar.maxValue=100
		ShareUI.fill(progressBar, in: progressView)
		progressState.alignment = .center
		ShareUI.fill(progressState, in: progressView)
		progressHelp.alignment = .center
		ShareUI.fill(progressHelp, in: progressView)
		ShareUI.fill(guidance, in: content)
		let actions=ShareUI.stack(.horizontal)
		qrCodeButton.bezelStyle = .rounded
		qrCodeButton.target=self
		qrCodeButton.action=#selector(useQrCode(_:))
		actions.addArrangedSubview(qrCodeButton)
		actions.addArrangedSubview(ShareUI.spacer())
		closeButton.bezelStyle = .rounded
		closeButton.keyEquivalent="\u{1b}"
		closeButton.target=self
		closeButton.action=#selector(cancel(_:))
		actions.addArrangedSubview(closeButton)
		ShareUI.fill(actions, in: content)
	}

	override func viewDidLoad(){
		super.viewDidLoad()
		prepareAttachments()
	}

	override func viewWillDisappear(){
		super.viewWillDisappear()
		requestEnded=true
		spinner.stopAnimation(nil)
		progressBar.stopAnimation(nil)
		stopDiscovery()
		if registered{NearbyConnectionManager.shared.removeShareExtensionDelegate(self); registered=false}
		if let id=chosenDevice?.id, !terminal{NearbyConnectionManager.shared.cancelOutgoingTransfer(id: id)}
		closeQrSheet()
	}

	private func prepareAttachments(){
		let attachments=(extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap {$0.attachments ?? []}
		guard !attachments.isEmpty else {
			showFailure(NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [NSLocalizedDescriptionKey:NSLocalizedString("NoAttachments", value: "No supported files or links were provided.", comment: "")]))
			return
		}
		let group=DispatchGroup()
		var loaded:[Int:URL]=[:]
		var loadingError:Error?
		for (index, provider) in attachments.enumerated(){
			group.enter()
			provider.loadObject(ofClass: NSURL.self){ item, error in
				DispatchQueue.main.async {
					if let url=item as? URL{loaded[index]=url}
					else{loadingError=error ?? NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnsupportedSchemeError)}
					group.leave()
				}
			}
		}
		group.notify(queue: .main){ [weak self] in
			guard let self=self, !self.requestEnded else {return}
			if let error=loadingError{self.showFailure(error); return}
			self.urls=attachments.indices.compactMap {loaded[$0]}
			for url in self.urls where url.isFileURL{
				var directory:ObjCBool=false
				if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue{
					self.showFailure(NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnsupportedSchemeError, userInfo: [NSLocalizedDescriptionKey:NSLocalizedString("FolderNotSupported", value: "Folders cannot be sent. Compress the folder in Finder, then share the ZIP file.", comment: "")]))
					return
				}
				let size=(try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
				let (sum, overflow)=self.totalBytes.addingReportingOverflow(size)
				self.totalBytes=overflow ? Int64.max : sum
			}
			if self.urls.count==1, let url=self.urls.first{
				self.filesLabel.stringValue=url.isFileURL ? url.lastPathComponent : url.absoluteString
				self.filesIcon.image=url.isFileURL ? NSWorkspace.shared.icon(forFile: url.path) : NSImage(named: NSImage.networkName)
			}else{
				self.filesLabel.stringValue=String.localizedStringWithFormat(NSLocalizedString("NFiles", value: "%d files", comment: ""), self.urls.count)
				self.filesIcon.image=NSImage(named: NSImage.multipleDocumentsName)
			}
			self.beginDiscovery()
			self.qrCodeButton.isEnabled=true
		}
		qrCodeButton.isEnabled=false
	}

	// Kept separate from attachment preparation so previews can render without networking.
	func beginDiscovery(){
		NearbyConnectionManager.shared.startDeviceDiscovery()
		discovering=true
		NearbyConnectionManager.shared.addShareExtensionDelegate(self)
		registered=true
	}

	private func stopDiscovery(){
		if discovering{NearbyConnectionManager.shared.stopDeviceDiscovery(); discovering=false}
	}

	@objc func cancel(_ sender:Any?){
		guard !requestEnded else {return}
		requestEnded=true
		if let id=chosenDevice?.id, !terminal{NearbyConnectionManager.shared.cancelOutgoingTransfer(id: id)}
		stopDiscovery()
		closeQrSheet()
		if terminal && lastError==nil{extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)}
		else{extensionContext?.cancelRequest(withError: lastError ?? NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))}
	}

	@objc func useQrCode(_ sender:Any?){
		guard sheetWindow==nil, chosenDevice==nil, !urls.isEmpty, let parent=view.window else {return}
		let sheet=NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 430), styleMask: [.titled], backing: .buffered, defer: false)
		sheet.contentView=ShareBackgroundView(frame: NSRect(x: 0, y: 0, width: 380, height: 430))
		sheet.contentView?.wantsLayer=true
		sheet.title=NSLocalizedString("ConnectWithQRCode", value: "Connect with QR code…", comment: "")
		let content=ShareUI.stack(spacing: 16)
		content.alignment = .centerX
		ShareUI.pin(content, to: sheet.contentView!, inset: 24)
		let instructions=ShareUI.label(NSLocalizedString("QRCodeInstructions", value: "Scan this code with your Android camera to connect. Verify the PIN before accepting the transfer.", comment: ""))
		instructions.alignment = .center
		ShareUI.fill(instructions, in: content)
		let qrKey=NearbyConnectionManager.shared.generateQrCodeKey()
		do{
			let image=try QRCode.build
				.text("https://quickshare.google/qrcode#key=\(qrKey)")
				.backgroundColor(CGColor(gray: 1, alpha: 1))
				.quietZonePixelCount(12)
				.errorCorrection(.medium)
				.generate.image(dimension: 480)
			let qr=NSImageView(image: NSImage(cgImage: image, size: NSSize(width: 240, height: 240)))
			qr.setAccessibilityLabel(NSLocalizedString("ConnectionQRCode", value: "Connection QR code. Scan with an Android camera.", comment: ""))
			NSLayoutConstraint.activate([qr.widthAnchor.constraint(equalToConstant: 240), qr.heightAnchor.constraint(equalToConstant: 240)])
			content.addArrangedSubview(qr)
		}catch{
			NearbyConnectionManager.shared.clearQrCodeKey()
			let alert=NSAlert(error: error)
			alert.beginSheetModal(for: parent)
			return
		}
		let help=ShareUI.label(NSLocalizedString("QRCodeNetworkHelp", value: "Both devices must be on the same Wi-Fi network. Some public networks block connections between devices.", comment: ""), size: 12, secondary: true)
		help.alignment = .center
		ShareUI.fill(help, in: content)
		let cancel=NSButton(title: NSLocalizedString("Cancel", value: "Cancel", comment: ""), target: self, action: #selector(dismissQrCodeSheet(_:)))
		cancel.bezelStyle = .rounded
		cancel.keyEquivalent="\u{1b}"
		content.addArrangedSubview(cancel)
		sheetWindow=sheet
		parent.beginSheet(sheet)
	}

	@objc func dismissQrCodeSheet(_ sender:Any?){closeQrSheet()}
	private func closeQrSheet(clearKey:Bool = true){
		if let sheet=sheetWindow{sheet.sheetParent?.endSheet(sheet); sheet.orderOut(nil); sheetWindow=nil}
		if clearKey{NearbyConnectionManager.shared.clearQrCodeKey()}
	}

	func addDevice(device:RemoteDeviceInfo){
		guard chosenDevice==nil, !terminal, !requestEnded else {return}
		if let index=foundDevices.firstIndex(where: {$0.id==device.id}){foundDevices[index]=device}
		else{foundDevices.append(device)}
		loading.isHidden = !foundDevices.isEmpty
		spinner.stopAnimation(nil)
		listView.reloadData()
	}
	func removeDevice(id:String){
		guard chosenDevice==nil else {return}
		foundDevices.removeAll {$0.id==id}
		listView.reloadData()
		loading.isHidden = !foundDevices.isEmpty
		if foundDevices.isEmpty{spinner.startAnimation(nil)}
	}
	func startTransferWithQrCode(device:RemoteDeviceInfo){
		guard sheetWindow != nil, chosenDevice==nil, !requestEnded else {return}
		closeQrSheet(clearKey: false)
		selectDevice(device)
		NearbyConnectionManager.shared.clearQrCodeKey()
	}
	func connectionWasEstablished(pinCode:String){
		guard !requestEnded, !terminal else {return}
		pinLabel.stringValue=pinCode
		pinLabel.isHidden=false
		progressBar.stopAnimation(nil)
		progressBar.isHidden=true
		progressState.stringValue=NSLocalizedString("WaitingForApproval", value: "Waiting for approval", comment: "")
		progressHelp.stringValue=NSLocalizedString("VerifySendingPIN", value: "Check that this PIN matches on the receiving device, then accept there.", comment: "")
	}
	func connectionFailed(with error:Error){
		guard !requestEnded, !terminal else {return}
		showFailure(error)
	}
	func transferAccepted(){
		guard !requestEnded, !terminal else {return}
		pinLabel.isHidden=true
		progressBar.isHidden=false
		progressBar.stopAnimation(nil)
		progressBar.isIndeterminate=false
		progressBar.doubleValue=0
		progressHelp.stringValue=NSLocalizedString("KeepDevicesConnected", value: "Keep both devices connected until the transfer finishes.", comment: "")
		progressState.stringValue=NSLocalizedString("Sending", value: "Sending…", comment: "")
	}
	func transferProgress(progress:Double){
		guard !requestEnded, !terminal else {return}
		let fraction=max(0, min(1, progress))
		progressBar.doubleValue=fraction*100
		let percent=String.localizedStringWithFormat(NSLocalizedString("SendingPercent", value: "Sending · %d%%", comment: ""), Int(fraction*100))
		if totalBytes>0{
			let bytes=ByteCountFormatter.string(fromByteCount: Int64(min(Double(Int64.max-1024), Double(totalBytes)*fraction)), countStyle: .file)
			progressState.stringValue="\(percent) · \(bytes) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
		}else{progressState.stringValue=percent}
	}
	func transferFinished(){
		guard !requestEnded, !terminal else {return}
		terminal=true
		progressBar.stopAnimation(nil)
		progressBar.isHidden=true
		pinLabel.isHidden=true
		deviceIcon.image=NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
		deviceIcon.contentTintColor = .systemGreen
		progressState.stringValue=NSLocalizedString("TransferFinished", value: "Transfer finished", comment: "")
		progressHelp.stringValue=NSLocalizedString("FilesSent", value: "Your items were sent successfully.", comment: "")
		closeButton.title=NSLocalizedString("Done", value: "Done", comment: "")
	}

	private func selectDevice(_ device:RemoteDeviceInfo){
		guard chosenDevice==nil, !terminal, !requestEnded, !urls.isEmpty, let id=device.id else {return}
		chosenDevice=device
		spinner.stopAnimation(nil)
		// Start before stopping discovery, which owns the service browser.
		NearbyConnectionManager.shared.startOutgoingTransfer(deviceID: id, delegate: self, urls: urls)
		stopDiscovery()
		discoveryView.isHidden=true
		progressView.isHidden=false
		qrCodeButton.isHidden=true
		guidance.isHidden=true
		deviceName.stringValue=device.name
		deviceIcon.image=imageForDeviceType(device.type)
		progressBar.isIndeterminate=true
		progressBar.startAnimation(nil)
		progressState.stringValue=NSLocalizedString("Connecting", value: "Connecting…", comment: "")
		progressHelp.stringValue=NSLocalizedString("WaitingForDevice", value: "Waiting for the receiving device to respond.", comment: "")
	}

	private func showFailure(_ error:Error){
		lastError=error
		terminal=true
		spinner.stopAnimation(nil)
		progressBar.stopAnimation(nil)
		stopDiscovery()
		closeQrSheet()
		discoveryView.isHidden=true
		progressView.isHidden=false
		qrCodeButton.isHidden=true
		guidance.isHidden=true
		progressBar.isHidden=true
		pinLabel.isHidden=true
		deviceIcon.image=NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
		deviceIcon.contentTintColor = .systemOrange
		var reason=error.localizedDescription
		if let nearby=error as? NearbyError, case let .canceled(cancellation)=nearby{
			switch cancellation{
			case .userRejected: reason=NSLocalizedString("TransferDeclined", value: "Declined", comment: "")
			case .userCanceled: reason=NSLocalizedString("TransferCanceled", value: "Canceled", comment: "")
			case .notEnoughSpace: reason=NSLocalizedString("NotEnoughSpace", value: "Not enough disk space", comment: "")
			case .unsupportedType: reason=NSLocalizedString("UnsupportedType", value: "Attachment type not supported", comment: "")
			case .timedOut: reason=NSLocalizedString("TransferTimedOut", value: "Timed out", comment: "")
			}
		}
		progressState.stringValue=reason
		progressHelp.stringValue=NSLocalizedString("SendFailureHelp", value: "Check Quick Share on the receiving device, available storage, and the Wi-Fi connection. Close this sheet and share again to retry.", comment: "")
		closeButton.title=NSLocalizedString("Close", value: "Close", comment: "")
	}
}

private func imageForDeviceType(_ type:RemoteDeviceInfo.DeviceType) -> NSImage?{
	let symbol:String
	switch type{
	case .tablet: symbol="rectangle.portrait"
	case .computer: symbol="laptopcomputer"
	default: symbol="smartphone"
	}
	return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
}

private final class DeviceCollectionItem:NSCollectionViewItem{
	override func loadView(){
		view=NSView()
		let content=ShareUI.stack(spacing: 8)
		content.alignment = .centerX
		ShareUI.pin(content, to: view, inset: 8)
		let icon=NSImageView()
		icon.imageScaling = .scaleProportionallyUpOrDown
		NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 36), icon.heightAnchor.constraint(equalToConstant: 36)])
		content.addArrangedSubview(icon)
		imageView=icon
		let name=ShareUI.label("", size: 12, weight: .medium)
		name.maximumNumberOfLines=2
		name.alignment = .center
		name.lineBreakMode = .byTruncatingMiddle
		ShareUI.fill(name, in: content)
		textField=name
	}
	override var isSelected:Bool{
		didSet{
			view.wantsLayer=true
			view.layer?.cornerRadius=10
			view.layer?.backgroundColor=(isSelected ? NSColor.selectedContentBackgroundColor : NSColor.clear).cgColor
			textField?.textColor=isSelected ? .alternateSelectedControlTextColor : .labelColor
		}
	}
}

extension ShareViewController:NSCollectionViewDataSource, NSCollectionViewDelegate{
	func collectionView(_ collectionView:NSCollectionView, numberOfItemsInSection section:Int) -> Int{foundDevices.count}
	func collectionView(_ collectionView:NSCollectionView, itemForRepresentedObjectAt indexPath:IndexPath) -> NSCollectionViewItem{
		let item=collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("Device"), for: indexPath)
		let device=foundDevices[indexPath.item]
		item.textField?.stringValue=device.name
		item.imageView?.image=imageForDeviceType(device.type)
		item.view.toolTip=device.name
		item.view.setAccessibilityLabel(device.name)
		return item
	}
	func collectionView(_ collectionView:NSCollectionView, didSelectItemsAt indexPaths:Set<IndexPath>){
		guard let index=indexPaths.first?.item, foundDevices.indices.contains(index) else {return}
		selectDevice(foundDevices[index])
	}
}
