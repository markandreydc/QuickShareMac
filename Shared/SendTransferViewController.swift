import Cocoa
import NearbyShare
import QRCode
import Network

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

protocol SendingService:AnyObject{
	func startDeviceDiscovery()
	func stopDeviceDiscovery()
	func addShareExtensionDelegate(_ delegate:ShareExtensionDelegate)
	func removeShareExtensionDelegate(_ delegate:ShareExtensionDelegate)
	func startOutgoingTransfer(deviceID:String, delegate:ShareExtensionDelegate, urls:[URL]) -> Bool
	func cancelOutgoingTransfer(id:String)
	func generateQrCodeKey() -> String
	func clearQrCodeKey()
}

extension NearbyConnectionManager:SendingService{}

/// Compresses a folder into a ZIP file before it is sent. The main app injects
/// a real implementation; contexts that cannot run one (the Share extension)
/// leave it nil, which keeps folders rejected there with an explanation.
protocol FolderCompressing:AnyObject{
	func compress(folder:URL, into directory:URL, completion:@escaping (Result<URL,Error>)->Void)
	func cancel()
}

enum OutgoingState{case idle, choosingDevice, compressing, connecting, awaitingApproval, sending, completed, failed, canceled}

struct FolderCompressionStatus:Equatable{
	let name:String
	let index:Int
	let total:Int
}

struct OutgoingTransferResult{
	let id:UUID
	let deviceName:String
	let itemDescription:String
	let urls:[URL]
	let state:OutgoingState
	let status:String
}

class SendTransferViewController:NSViewController, ShareExtensionDelegate{
	var service:SendingService=NearbyConnectionManager.shared
	var folderCompressor:FolderCompressing?
	var continuesInBackground=false
	var embeddedInMainWindow=false
	private var discoveryVisible=true
	var onResult:((OutgoingTransferResult)->Void)?
	var onStateChange:((OutgoingState)->Void)?
	var onStateUpdate:(()->Void)?
	var onProgress:((Double)->Void)?
	var onDone:((Error?)->Void)?
	var onPreparationError:((Error)->Void)?
	var onOpenNetworkSettings:(()->Void)?
	private(set) var state:OutgoingState = .idle
	private(set) var progressFraction:Double?
	var recipientName:String?{chosenDevice?.name}
	/// The items actually being sent; folders are replaced by their ZIP files
	/// once compression finishes.
	var preparedItems:[URL]{urls}
	/// The progress of the folder currently being compressed, if any.
	private(set) var compressionProgress:FolderCompressionStatus?
	var isTransferring:Bool{state == .connecting || state == .awaitingApproval || state == .sending}
	var hasItems:Bool{!urls.isEmpty}
	private var urls:[URL]=[]
	private var sourceSelection:[URL]=[]
	private var scopedURLs:[URL]=[]
	private var foundDevices:[RemoteDeviceInfo]=[]
	private var chosenDevice:RemoteDeviceInfo?
	private var lastError:Error?
	private var sheetWindow:NSWindow?
	private var discovering=false
	private var registered=false
	private var terminal=false
	private var requestEnded=false
	private var totalBytes:Int64=0
	private var attemptID=UUID()
	private var transferID=UUID()
	private var attempt:SendingAttemptDelegate?
	private var timeout:DispatchWorkItem?
	private var compressionGeneration=UUID()
	private var compressionFiles:[URL]=[]
	private var compressionFileBytes:Int64=0
	private var compressedDirectory:URL?
	private let rateEstimator=TransferRateEstimator()
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
	private let retryButton=NSButton(title: NSLocalizedString("RetryTransfer", value: "Retry…", comment: ""), target: nil, action: nil)
	private let networkSettingsButton=NSButton(title: NSLocalizedString("OpenNetworkSettings", value: "Open Network Settings…", comment: ""), target: nil, action: nil)

	override func loadView(){
		view=ShareBackgroundView(frame: NSRect(x: 0, y: 0, width: 480, height: 500))
		view.wantsLayer=true
		if !embeddedInMainWindow{preferredContentSize=NSSize(width: 480, height: 500)}
		let content=ShareUI.stack(spacing: 16)
		ShareUI.pin(content, to: view, inset: embeddedInMainWindow ? 0 : 20)
		if !embeddedInMainWindow{ShareUI.fill(ShareUI.label(NSLocalizedString("SendWithQuickShareMac", value: "Send with QuickShareMac", comment: ""), size: 18, weight: .semibold), in: content)}
		let files=ShareUI.stack(.horizontal)
		filesIcon.imageScaling = .scaleProportionallyUpOrDown
		NSLayoutConstraint.activate([filesIcon.widthAnchor.constraint(equalToConstant: 28), filesIcon.heightAnchor.constraint(equalToConstant: 28)])
		files.addArrangedSubview(filesIcon)
		filesLabel.maximumNumberOfLines=2
		filesLabel.lineBreakMode = .byTruncatingMiddle
		files.addArrangedSubview(filesLabel)
		ShareUI.fill(files, in: content)
		ShareUI.fill(contentWrap, in: content)
		contentWrap.heightAnchor.constraint(greaterThanOrEqualToConstant: embeddedInMainWindow ? 160 : 230).isActive=true
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
		deviceName.maximumNumberOfLines=2
		ShareUI.fill(deviceName, in: progressView)
		pinLabel.font=NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
		pinLabel.alignment = .center
		pinLabel.isHidden=true
		pinLabel.setAccessibilityLabel(NSLocalizedString("VerificationPIN", value: "Verification PIN", comment: ""))
		ShareUI.fill(pinLabel, in: progressView)
		progressBar.style = .bar
		progressBar.isIndeterminate=false
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
		retryButton.bezelStyle = .rounded
		retryButton.target=self
		retryButton.action=#selector(retry(_:))
		retryButton.isHidden=true
		actions.addArrangedSubview(retryButton)
		networkSettingsButton.bezelStyle = .rounded
		networkSettingsButton.target=self
		networkSettingsButton.action=#selector(openNetworkSettings(_:))
		networkSettingsButton.isHidden=true
		actions.addArrangedSubview(networkSettingsButton)
		actions.addArrangedSubview(ShareUI.spacer())
		closeButton.bezelStyle = .rounded
		closeButton.keyEquivalent="\u{1b}"
		closeButton.target=self
		closeButton.action=#selector(cancel(_:))
		actions.addArrangedSubview(closeButton)
		ShareUI.fill(actions, in: content)
	}

	override func viewDidAppear(){
		super.viewDidAppear()
		if discoveryVisible && state == .choosingDevice && !discovering{beginDiscovery()}
	}

	override func viewWillDisappear(){
		super.viewWillDisappear()
		spinner.stopAnimation(nil)
		stopDiscovery()
		closeQrSheet()
		if !continuesInBackground{shutdown()}
	}

	func configureItems(_ items:[URL]) throws{
		guard !isTransferring else {throw selectionError(NSLocalizedString("FinishCurrentTransfer", value: "Finish or cancel the current transfer before choosing other items.", comment: ""))}
		guard !items.isEmpty else {throw selectionError(NSLocalizedString("NoAttachments", value: "No supported files or links were provided.", comment: ""))}
		let allFiles=items.allSatisfy(\.isFileURL)
		guard allFiles || (items.count==1 && Self.isSupportedLink(items[0])) else {
			throw selectionError(NSLocalizedString("UnsupportedSelection", value: "Choose files, or one HTTP or HTTPS link. Files and links cannot be sent together.", comment: ""))
		}
		// A text field may also submit when hiding its row ends editing. Preserve
		// the current discovery session if the same selection arrives twice.
		if sourceSelection==items && (state == .choosingDevice || state == .compressing){return}
		var scopes:[URL]=[]
		var files:[URL]=[]
		var folders:[URL]=[]
		var bytes:Int64=0
		do{
			for url in items where url.isFileURL{
				if url.startAccessingSecurityScopedResource(){scopes.append(url)}
				let values=try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
				if values.isDirectory==true{
					guard folderCompressor != nil else {throw selectionError(NSLocalizedString("FolderNotSupported", value: "Folders cannot be sent. Compress the folder in Finder, then share the ZIP file.", comment: ""))}
					guard FileManager.default.isReadableFile(atPath: url.path) else {throw selectionError(NSLocalizedString("UnreadableSelection", value: "One of the selected files is not readable. Choose it again in Finder.", comment: ""))}
					folders.append(url)
				}else{
					guard values.isRegularFile==true, FileManager.default.isReadableFile(atPath: url.path) else {throw selectionError(NSLocalizedString("UnreadableSelection", value: "One of the selected files is not readable. Choose it again in Finder.", comment: ""))}
					let (sum, overflow)=bytes.addingReportingOverflow(Int64(values.fileSize ?? 0))
					guard !overflow else {throw selectionError(NSLocalizedString("SelectionTooLarge", value: "The selected files are too large to send together.", comment: ""))}
					bytes=sum
					files.append(url)
				}
			}
		}catch{
			for url in scopes{url.stopAccessingSecurityScopedResource()}
			throw error
		}
		_ = view
		stopDiscovery()
		closeQrSheet()
		releaseScopes()
		releaseCompressedItems()
		scopedURLs=scopes
		sourceSelection=items
		if folders.isEmpty{
			applySelection(items: items, totalBytes: bytes)
		}else{
			beginCompression(folders: folders, files: files, fileBytes: bytes)
		}
	}

	/// Starts the regular discovery flow for a fully prepared selection.
	private func applySelection(items:[URL], totalBytes:Int64){
		urls=items
		self.totalBytes=totalBytes
		resetForDiscovery()
		if items.count==1, let url=items.first{
			filesLabel.stringValue=url.isFileURL ? url.lastPathComponent : url.absoluteString
			filesIcon.image=url.isFileURL ? NSWorkspace.shared.icon(forFile: url.path) : NSImage(named: NSImage.networkName)
		}else{
			filesLabel.stringValue=String.localizedStringWithFormat(NSLocalizedString("NFiles", value: "%d files", comment: ""), items.count)
			filesIcon.image=NSImage(named: NSImage.multipleDocumentsName)
		}
		filesLabel.toolTip=items.map {$0.isFileURL ? $0.lastPathComponent : $0.absoluteString}.joined(separator: "\n")
		if discoveryVisible{beginDiscovery()}
	}

	/// Compresses every chosen folder into its own ZIP file before discovery
	/// begins. Files chosen alongside folders are sent as-is.
	private func beginCompression(folders:[URL], files:[URL], fileBytes:Int64){
		guard let _=folderCompressor else {return}
		// The previous selection is gone, and its device list must not accept
		// clicks while the new ZIPs are being prepared.
		urls.removeAll()
		discoveryView.isHidden=true
		progressView.isHidden=true
		let generation=UUID()
		compressionGeneration=generation
		compressionFiles=files
		compressionFileBytes=fileBytes
		let directory=FileManager.default.temporaryDirectory.appendingPathComponent("QuickShareMac-Send-\(generation.uuidString)", isDirectory: true)
		compressedDirectory=directory
		compressionProgress=FolderCompressionStatus(name: folders[0].lastPathComponent, index: 1, total: folders.count)
		setState(.compressing)
		compressNext(folders: folders, index: 0, zips: [], directory: directory, generation: generation)
	}

	private func compressNext(folders:[URL], index:Int, zips:[URL], directory:URL, generation:UUID){
		guard generation==compressionGeneration, let compressor=folderCompressor else {return}
		if index>=folders.count{
			var bytes=compressionFileBytes
			for zip in zips{
				let size=(try? zip.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
				let (sum, overflow)=bytes.addingReportingOverflow(Int64(size))
				bytes=overflow ? Int64.max : sum
			}
			compressionProgress=nil
			applySelection(items: compressionFiles+zips, totalBytes: bytes)
			return
		}
		compressionProgress=FolderCompressionStatus(name: folders[index].lastPathComponent, index: index+1, total: folders.count)
		onStateChange?(state)
		compressor.compress(folder: folders[index], into: directory){ [weak self] result in
			guard let self=self, generation==self.compressionGeneration else{return}
			switch result{
			case .success(let zip): self.compressNext(folders: folders, index: index+1, zips: zips+[zip], directory: directory, generation: generation)
			case .failure(let error): self.failCompression(error, generation: generation)
			}
		}
	}

	private func failCompression(_ error:Error, generation:UUID){
		guard generation==compressionGeneration else{return}
		releaseCompressedItems()
		sourceSelection=[]
		urls.removeAll()
		setState(.idle)
		onPreparationError?(error)
	}

	/// Terminates any compression in progress and removes the temporary ZIPs of
	/// the previous selection. Temp files from a replaced or finished selection
	/// are never reused; retries recompress from the original folders.
	private func releaseCompressedItems(){
		compressionGeneration=UUID()
		compressionProgress=nil
		compressionFiles=[]
		compressionFileBytes=0
		folderCompressor?.cancel()
		if let directory=compressedDirectory{try? FileManager.default.removeItem(at: directory)}
		compressedDirectory=nil
	}

	func setDiscoveryVisible(_ visible:Bool){
		discoveryVisible=visible
		if visible && state == .choosingDevice{beginDiscovery()}
		else if !visible{stopDiscovery(); closeQrSheet()}
	}

	static func isSupportedLink(_ url:URL) -> Bool{
		ShareHandoff.isSupportedLink(url)
	}

	private func selectionError(_ message:String) -> Error{NSError(domain: "QuickShareMac.Send", code: 1, userInfo: [NSLocalizedDescriptionKey:message])}
	private func releaseScopes(){
		for url in scopedURLs{url.stopAccessingSecurityScopedResource()}
		scopedURLs.removeAll()
	}
	private func setState(_ state:OutgoingState){
		self.state=state
		if state != .sending{progressFraction=nil}
		onStateChange?(state)
		onStateUpdate?()
	}
	private func resetForDiscovery(){
		timeout?.cancel()
		attemptID=UUID()
		attempt=nil
		chosenDevice=nil
		rateEstimator.reset()
		lastError=nil
		terminal=false
		requestEnded=false
		foundDevices.removeAll()
		listView.reloadData()
		discoveryView.isHidden=false
		progressView.isHidden=true
		progressBar.stopAnimation(nil)
		pinLabel.isHidden=true
		qrCodeButton.isHidden=false
		qrCodeButton.isEnabled=true
		retryButton.isHidden=true
		networkSettingsButton.isHidden=true
		guidance.isHidden=false
		loading.isHidden=false
		closeButton.title=NSLocalizedString("Cancel", value: "Cancel", comment: "")
		setState(.choosingDevice)
	}

	@objc func retry(_ sender:Any?){
		guard terminal, !urls.isEmpty else {return}
		// Rediscover and explicitly choose a recipient again; never automatically resend.
		resetForDiscovery()
		if discoveryVisible{beginDiscovery()}
	}

	@objc private func openNetworkSettings(_ sender:Any?){
		if let onOpenNetworkSettings=onOpenNetworkSettings{onOpenNetworkSettings(); return}
		let address:String
		if #available(macOS 13.0, *){address="x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocalNetwork"}
		else{address="x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"}
		if let url=URL(string: address){NSWorkspace.shared.open(url)}
	}

	func shutdown(){
		if isTransferring{cancel(nil)}
		requestEnded=true
		timeout?.cancel()
		stopDiscovery()
		closeQrSheet()
		releaseScopes()
		releaseCompressedItems()
		sourceSelection.removeAll()
		urls.removeAll()
		chosenDevice=nil
		attempt=nil
		setState(.idle)
	}

	deinit{
		timeout?.cancel()
		for url in scopedURLs{url.stopAccessingSecurityScopedResource()}
		folderCompressor?.cancel()
	}

	// Kept separate from attachment preparation so previews can render without networking.
	func beginDiscovery(){
		guard !discovering else {return}
		foundDevices.removeAll()
		listView.reloadData()
		loading.isHidden=false
		spinner.startAnimation(nil)
		service.startDeviceDiscovery()
		discovering=true
		service.addShareExtensionDelegate(self)
		registered=true
	}

	private func stopDiscovery(){
		if registered{service.removeShareExtensionDelegate(self); registered=false}
		if discovering{service.stopDeviceDiscovery(); discovering=false}
	}

	@objc func cancel(_ sender:Any?){
		guard !requestEnded else {return}
		if let id=chosenDevice?.id, !terminal{
			attemptID=UUID()
			service.cancelOutgoingTransfer(id: id)
			timeout?.cancel()
			terminal=true
			progressBar.stopAnimation(nil)
			progressBar.isHidden=true
			pinLabel.isHidden=true
			lastError=NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
			progressState.stringValue=NSLocalizedString("TransferCanceled", value: "Canceled", comment: "")
			progressHelp.stringValue=NSLocalizedString("RetryChooseRecipient", value: "Retry to choose a recipient again, or select other items to send.", comment: "")
			retryButton.isHidden=false
			closeButton.title=NSLocalizedString("Done", value: "Done", comment: "")
			setState(.canceled)
			recordResult()
			return
		}
		requestEnded=true
		stopDiscovery()
		closeQrSheet()
		onDone?(terminal ? lastError : NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
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
		let qrKey=service.generateQrCodeKey()
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
			service.clearQrCodeKey()
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
		if let sheet=sheetWindow{
			sheet.sheetParent?.endSheet(sheet)
			sheet.orderOut(nil)
			sheetWindow=nil
			if clearKey{service.clearQrCodeKey()}
		}
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
		service.clearQrCodeKey()
	}
	func connectionWasEstablished(pinCode:String){
		guard !requestEnded, !terminal else {return}
		setState(.awaitingApproval)
		armTimeout(seconds: 120)
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
		progressFraction=0
		setState(.sending)
		armTimeout(seconds: 60)
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
		guard progress.isFinite else {return}
		armTimeout(seconds: 60)
		let fraction=max(0, min(1, progress))
		progressFraction=fraction
		onProgress?(fraction)
		progressBar.doubleValue=fraction*100
		let percent=String.localizedStringWithFormat(NSLocalizedString("SendingPercent", value: "Sending · %d%%", comment: ""), Int(fraction*100))
		if totalBytes>0{
			let sentBytes=min(Double(Int64.max-1024), Double(totalBytes)*fraction)
			let bytes=ByteCountFormatter.string(fromByteCount: Int64(sentBytes), countStyle: .file)
			progressState.stringValue="\(percent) · \(bytes) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"
			if let rate=rateEstimator.update(bytes: sentBytes), rate>0, let remaining=rateEstimator.estimatedRemaining(totalBytes: Double(totalBytes)){
				progressHelp.stringValue="\(TransferRateFormat.speed(rate)) · \(TransferRateFormat.remaining(remaining))"
			}
		}else{progressState.stringValue=percent}
	}
	func transferFinished(){
		guard !requestEnded, !terminal else {return}
		terminal=true
		timeout?.cancel()
		progressBar.stopAnimation(nil)
		progressBar.doubleValue=100
		progressBar.isHidden=false
		pinLabel.isHidden=true
		deviceIcon.image=NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
		deviceIcon.contentTintColor = .systemGreen
		progressState.stringValue=NSLocalizedString("TransferFinished", value: "Transfer finished", comment: "")
		progressHelp.stringValue=NSLocalizedString("FilesSent", value: "Your items were sent successfully.", comment: "")
		closeButton.title=NSLocalizedString("Done", value: "Done", comment: "")
		setState(.completed)
		recordResult()
	}

	func selectDevice(_ device:RemoteDeviceInfo){
		guard chosenDevice==nil, !terminal, !requestEnded, !urls.isEmpty, let id=device.id else {return}
		chosenDevice=device
		attemptID=UUID()
		transferID=UUID()
		let attempt=SendingAttemptDelegate(owner: self, id: attemptID)
		self.attempt=attempt
		spinner.stopAnimation(nil)
		discoveryView.isHidden=true
		progressView.isHidden=false
		qrCodeButton.isHidden=true
		guidance.isHidden=true
		deviceName.stringValue=device.name
		deviceIcon.image=imageForDeviceType(device.type)
		deviceIcon.contentTintColor = .labelColor
		progressBar.isHidden=false
		progressBar.doubleValue=0
		progressState.stringValue=NSLocalizedString("Connecting", value: "Connecting…", comment: "")
		progressHelp.stringValue=NSLocalizedString("ConnectingBeforeApproval", value: "Opening the network connection and verifying Quick Share. A transfer request has not reached the phone yet.", comment: "")
		setState(.connecting)
		armTimeout(seconds: 30)
		// Start before stopping discovery, which owns the service browser.
		let started=service.startOutgoingTransfer(deviceID: id, delegate: attempt, urls: urls)
		stopDiscovery()
		if !started{showFailure(selectionError(NSLocalizedString("RecipientUnavailable", value: "This device is no longer available, or already has a transfer in progress. Retry to find it again.", comment: "")))}
	}

	func showFailure(_ error:Error){
		_ = view
		lastError=error
		terminal=true
		timeout?.cancel()
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
		var permissionBlocked=false
		var recipientRefused=false
		if let nearby=error as? NearbyError{
			switch nearby{
			case .localNetworkDenied:
				permissionBlocked=true
				reason=NSLocalizedString("LocalNetworkBlocked", value: "macOS blocked local-network access.", comment: "")
			case .canceled(let cancellation):
				switch cancellation{
				case .userRejected: reason=NSLocalizedString("TransferDeclined", value: "Declined", comment: "")
				case .userCanceled: reason=NSLocalizedString("TransferCanceled", value: "Canceled", comment: "")
				case .notEnoughSpace: reason=NSLocalizedString("NotEnoughSpace", value: "Not enough disk space", comment: "")
				case .unsupportedType: reason=NSLocalizedString("UnsupportedType", value: "Attachment type not supported", comment: "")
				case .timedOut: reason=NSLocalizedString("TransferTimedOut", value: "Timed out", comment: "")
				}
			case .inputOutput: reason=NSLocalizedString("SendConnectionInterrupted", value: "The connection was interrupted, or a selected file could not be read.", comment: "")
			case .ukey2, .protocolError, .requiredFieldMissing: reason=NSLocalizedString("SendSecureConnectionFailed", value: "Could not establish a secure Quick Share connection.", comment: "")
			}
		}else if case .posix(.ECONNREFUSED)? = error as? NWError{
			recipientRefused=true
			reason=NSLocalizedString("RecipientRefusedConnection", value: "The receiving device refused the connection.", comment: "")
		}
		progressState.stringValue=reason
		if permissionBlocked{
			progressHelp.stringValue=NSLocalizedString("LocalNetworkBlockedHelp", value: "macOS denied this connection. Allow QuickShareMac in System Settings → Privacy & Security → Local Network. If already enabled, quit and reopen this signed build, then retry.", comment: "")
		}else if recipientRefused{
			progressHelp.stringValue=NSLocalizedString("RecipientRefusedHelp", value: "Open Quick Share on the unlocked phone and choose Receive, or retry using Connect with QR code. Keep both devices on the same Wi-Fi network.", comment: "")
		}else{
			progressHelp.stringValue=NSLocalizedString("SendRetryHelp", value: "Check Quick Share on the receiving device, available storage, and the Wi-Fi connection. Retry to choose the recipient again.", comment: "")
		}
		networkSettingsButton.isHidden = !permissionBlocked
		closeButton.title=NSLocalizedString("Close", value: "Close", comment: "")
		retryButton.isHidden=urls.isEmpty
		setState(.failed)
		recordResult()
	}

	private func recordResult(){
		guard let device=chosenDevice else {return}
		// History keeps the original selection so retrying recompresses folders
		// instead of pointing at temporary ZIPs that no longer exist.
		let recordedURLs=sourceSelection.isEmpty ? urls : sourceSelection
		onResult?(OutgoingTransferResult(id: transferID, deviceName: device.name, itemDescription: filesLabel.stringValue, urls: recordedURLs, state: state, status: progressState.stringValue))
	}

	private func armTimeout(seconds:Double){
		timeout?.cancel()
		let id=attemptID
		let work=DispatchWorkItem { [weak self] in
			guard let self=self, self.attemptID==id, self.isTransferring else {return}
			if let deviceID=self.chosenDevice?.id{self.service.cancelOutgoingTransfer(id: deviceID)}
			self.attemptID=UUID()
			self.showFailure(NearbyError.canceled(reason: .timedOut))
		}
		timeout=work
		DispatchQueue.main.asyncAfter(deadline: .now()+seconds, execute: work)
	}

	fileprivate func receiveAttempt(_ id:UUID, action:(SendTransferViewController)->Void){
		guard attemptID==id, !terminal, !requestEnded else {return}
		action(self)
	}
}

private final class SendingAttemptDelegate:ShareExtensionDelegate{
	weak var owner:SendTransferViewController?
	let id:UUID
	init(owner:SendTransferViewController, id:UUID){self.owner=owner; self.id=id}
	func addDevice(device:RemoteDeviceInfo){}
	func removeDevice(id:String){}
	func startTransferWithQrCode(device:RemoteDeviceInfo){}
	func connectionWasEstablished(pinCode:String){owner?.receiveAttempt(id){$0.connectionWasEstablished(pinCode: pinCode)}}
	func connectionFailed(with error:Error){owner?.receiveAttempt(id){$0.connectionFailed(with: error)}}
	func transferAccepted(){owner?.receiveAttempt(id){$0.transferAccepted()}}
	func transferProgress(progress:Double){owner?.receiveAttempt(id){$0.transferProgress(progress: progress)}}
	func transferFinished(){owner?.receiveAttempt(id){$0.transferFinished()}}
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

extension SendTransferViewController:NSCollectionViewDataSource, NSCollectionViewDelegate{
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
