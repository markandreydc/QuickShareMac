import Foundation

/// Reset only user-facing preferences, never the whole app domain (which also
/// contains remembered devices, caches, and other data).
enum AppSettingsDefaults{
	static func restore(in defaults:UserDefaults = .standard){
		defaults.set(true, forKey: "StartReceivingOnLaunch")
		defaults.set(false, forKey: "AlwaysOnTop")
		defaults.set(false, forKey: "CompressFoldersBeforeSending")
		defaults.set(0, forKey: "ReceivingDuration")
		defaults.set("never", forKey: "UpdateCheckFrequency")
		defaults.removeObject(forKey: "AutomaticallyCheckForUpdates")
		defaults.removeObject(forKey: ReceivedFilesFolder.bookmarkDefaultsKey)
	}
}

/// The folder where incoming files are saved. Defaults to Downloads; Settings can point it anywhere.
enum ReceivedFilesFolder{
	static let bookmarkDefaultsKey="ReceivedFilesFolderBookmark"
	static var defaults:UserDefaults = .standard
	private static var resolvedCustom:URL?
	private static var didResolve=false

	static var defaultURL:URL{
		(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser).resolvingSymlinksInPath()
	}

	static var currentURL:URL{customURL ?? defaultURL}

	static var customURL:URL?{
		if !didResolve{resolve()}
		if let custom=resolvedCustom, !FileManager.default.fileExists(atPath: custom.path, isDirectory: nil){
			defaults.removeObject(forKey: bookmarkDefaultsKey)
			resolvedCustom=nil
		}
		return resolvedCustom
	}

	static var isCustom:Bool{customURL != nil}

	static var displayName:String{FileManager.default.displayName(atPath: currentURL.path)}

	static func set(_ url:URL?) throws{
		guard let url=url else{
			defaults.removeObject(forKey: bookmarkDefaultsKey)
			resolvedCustom=nil
			didResolve=true
			return
		}
		let standardized=url.standardizedFileURL
		if standardized.resolvingSymlinksInPath().path==defaultURL.path{
			try set(nil)
			return
		}
		var isDirectory:ObjCBool=false
		guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue else{
			throw NSError(domain: "QuickShareMac.ReceivedFiles", code: 1, userInfo: [NSLocalizedDescriptionKey:NSLocalizedString("ReceivedFilesFolderMissing", value: "That folder no longer exists.", comment: "")])
		}
		let bookmark=try standardized.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
		defaults.set(bookmark, forKey: bookmarkDefaultsKey)
		resolvedCustom=standardized
		didResolve=true
		_ = standardized.startAccessingSecurityScopedResource()
	}

	static func resetCache(){
		didResolve=false
		resolvedCustom=nil
	}

	private static func resolve(){
		didResolve=true
		guard let data=defaults.data(forKey: bookmarkDefaultsKey) else{
			resolvedCustom=nil
			return
		}
		var stale=false
		guard let url=try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else{
			resolvedCustom=nil
			return
		}
		var isDirectory:ObjCBool=false
		guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else{
			defaults.removeObject(forKey: bookmarkDefaultsKey)
			resolvedCustom=nil
			return
		}
		_ = url.startAccessingSecurityScopedResource()
		if stale, let fresh=try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil){
			defaults.set(fresh, forKey: bookmarkDefaultsKey)
		}
		resolvedCustom=url
	}
}
