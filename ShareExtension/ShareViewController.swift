import Cocoa

// Only the extension adapter knows about NSExtensionContext. The transfer UI is
// compiled into both targets, so the main app and Share menu use the same flow.
class ShareViewController:SendTransferViewController{
	private var dismissed=false
	override func viewDidLoad(){
		super.viewDidLoad()
		onDone={ [weak self] error in
			guard let self=self else {return}
			self.dismissed=true
			self.shutdown()
			if let error=error{self.extensionContext?.cancelRequest(withError: error)}
			else{self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)}
		}
		prepareAttachments()
	}
	override func viewWillDisappear(){
		dismissed=true
		super.viewWillDisappear()
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
			guard let self=self, !self.dismissed else {return}
			do{
				if let error=loadingError{throw error}
				try self.configureItems(attachments.indices.compactMap {loaded[$0]})
			}catch{self.showFailure(error)}
		}
	}
}
