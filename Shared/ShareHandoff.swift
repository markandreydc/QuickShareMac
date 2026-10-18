import Foundation

/// The contract between the macOS Share extension and the main app. The
/// extension never transfers anything itself: it loads the shared items, hands
/// them to the main app, and dismisses. Files travel through LaunchServices,
/// which both activates the app and grants it access to those exact files;
/// links travel through the `quicksharemac://` URL scheme.
enum ShareHandoff{
	static let scheme="quicksharemac"
	static let host="send"
	static let linkQueryName="url"

	enum Payload:Equatable{
		case files([URL])
		case link(URL)
	}

	/// A single HTTP or HTTPS link is the only non-file item the send flow accepts.
	static func isSupportedLink(_ url:URL) -> Bool{
		["http","https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty && url.user==nil && url.password==nil
	}

	/// Classifies loaded share attachments. Finder shares files and folders,
	/// Safari shares one link, and anything else is rejected before the main
	/// app is asked to handle it. Mixed shares are rejected rather than
	/// truncated, matching the Send tab's own validation.
	static func payload(for items:[URL]) -> Payload?{
		guard !items.isEmpty else{return nil}
		let files=items.filter {$0.isFileURL}
		if files.count==items.count{return .files(files)}
		if files.isEmpty, items.count==1, let item=items.first, isSupportedLink(item){return .link(item)}
		return nil
	}

	/// The URL that asks the main app to take over a shared link.
	static func handoffURL(for link:URL) -> URL?{
		guard isSupportedLink(link), var components=URLComponents(string: "\(scheme)://\(host)") else{return nil}
		components.queryItems=[URLQueryItem(name: linkQueryName, value: link.absoluteString)]
		return components.url
	}

	/// Extracts the shared link from a `quicksharemac://send?url=…` URL.
	static func link(fromHandoffURL url:URL) -> URL?{
		guard url.scheme?.lowercased()==scheme, url.host?.lowercased()==host, let components=URLComponents(url: url, resolvingAgainstBaseURL: false) else{return nil}
		guard let raw=components.queryItems?.first(where: {$0.name==linkQueryName})?.value, let link=URL(string: raw) else{return nil}
		return isSupportedLink(link) ? link : nil
	}

	/// LaunchServices can deliver one Share-menu handoff as several open
	/// events, sometimes grouped by file type and spread over a moment. Open
	/// events that arrive within `window` of the previous one extend that
	/// handoff instead of replacing it, so every shared item survives.
	static func mergedHandoffURLs(previous:[URL], previousEvent:Date, new:[URL], now:Date, window:TimeInterval) -> [URL]{
		guard now.timeIntervalSince(previousEvent) <= window else{return new}
		var merged=previous
		for url in new where !merged.contains(url){merged.append(url)}
		return merged
	}
}
