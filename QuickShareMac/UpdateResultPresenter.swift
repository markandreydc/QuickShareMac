import Cocoa

// Update checks are app-wide actions, not Settings navigation. Keep their
// presentation independent of both Settings and the main transfer window.
final class UpdateResultPresenter{
	private(set) var alert:NSAlert?
	var openURL:(URL)->Void = {NSWorkspace.shared.open($0)}
	@discardableResult func activateExistingAlert()->Bool{
		guard let alert=alert else {return false}
		NSApp.activate(ignoringOtherApps: true)
		alert.window.makeKeyAndOrderFront(nil)
		return true
	}
	func show(_ result:Result<UpdateChecker.Outcome,UpdateCheckError>, currentVersion:String){
		guard !activateExistingAlert() else {return}
		let alert=NSAlert()
		var destination:URL?
		switch result{
		case .success(.available(let release)):
			alert.messageText=NSLocalizedString("UpdateAvailableTitle", value: "A QuickShareMac update is available", comment: "")
			alert.informativeText=String(format: NSLocalizedString("UpdateAvailableMessage", value: "QuickShareMac %@ is available. You have %@.\n\nOpen the release page to download the update. Quit QuickShareMac after your transfers finish before replacing the app.", comment: ""), release.tagName, currentVersion)
			if release.isValid{destination=release.pageURL}
		case .success(.upToDate):
			alert.messageText=NSLocalizedString("UpdateUpToDate", value: "You're up to date.", comment: "")
			alert.informativeText=String(format: NSLocalizedString("UpdateCurrentMessage", value: "You're using QuickShareMac %@. No newer stable release is available.", comment: ""), currentVersion)
		case .success(.noRelease):
			alert.messageText=NSLocalizedString("UpdateNoRelease", value: "No published stable release is available yet.", comment: "")
			alert.informativeText=NSLocalizedString("UpdateNoReleaseMessage", value: "Check again after a stable GitHub release has been published. A tag alone is not a release.", comment: "")
		case .failure(let error):
			alert.alertStyle = .warning
			alert.messageText=NSLocalizedString("UpdateCheckFailed", value: "Couldn't check for updates", comment: "")
			alert.informativeText=error.localizedDescription
			destination=UpdateChecker.releasesURL
		}
		if destination != nil{
			alert.addButton(withTitle: NSLocalizedString("ViewRelease", value: "View Release", comment: ""))
			alert.addButton(withTitle: NSLocalizedString("UpdateLater", value: "Later", comment: ""))
		}else{alert.addButton(withTitle: NSLocalizedString("UpdateOK", value: "OK", comment: ""))}
		self.alert=alert
		defer{self.alert=nil}
		NSApp.activate(ignoringOtherApps: true)
		let response=alert.runModal()
		if response == .alertFirstButtonReturn, let destination=destination{openURL(destination)}
	}
}
