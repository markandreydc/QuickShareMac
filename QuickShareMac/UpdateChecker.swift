import Foundation

enum UpdateCheckFrequency:String, CaseIterable{
	case daily, weekly, monthly, never
	var title:String{
		switch self{
		case .daily: return NSLocalizedString("UpdateCheckDaily", value: "Daily", comment: "")
		case .weekly: return NSLocalizedString("UpdateCheckWeekly", value: "Weekly", comment: "")
		case .monthly: return NSLocalizedString("UpdateCheckMonthly", value: "Monthly", comment: "")
		case .never: return NSLocalizedString("UpdateCheckNever", value: "Never", comment: "")
		}
	}
	func nextCheck(after date:Date, calendar:Calendar)->Date?{
		switch self{
		case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
		case .weekly: return calendar.date(byAdding: .day, value: 7, to: date)
		case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
		case .never: return nil
		}
	}
}

// Numeric versions, with SemVer prerelease precedence. Short stable tags such
// as v1 and v1.1 are also accepted; build metadata does not affect precedence.
struct ReleaseVersion:Comparable{
	private let numbers:[UInt]
	private let prerelease:[String]
	init?(_ value:String){
		var text=value
		if text.hasPrefix("v"){text.removeFirst()}
		let metadata=text.split(separator: "+", omittingEmptySubsequences: false)
		guard metadata.count<=2 else {return nil}
		func identifiers(_ value:Substring)->[String]?{
			let parts=value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
			guard parts.allSatisfy({!$0.isEmpty && $0.utf8.allSatisfy {($0>=48 && $0<=57) || ($0>=65 && $0<=90) || ($0>=97 && $0<=122) || $0==45}}) else {return nil}
			return parts
		}
		if metadata.count==2, identifiers(metadata[1])==nil{return nil}
		let components=metadata[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
		let core=components[0].split(separator: ".", omittingEmptySubsequences: false)
		guard (1...3).contains(core.count) else {return nil}
		var numbers:[UInt]=[]
		for component in core{
			guard !component.isEmpty, component.utf8.allSatisfy({$0>=48 && $0<=57}), component.count==1 || component.first != "0", let number=UInt(component) else {return nil}
			numbers.append(number)
		}
		while numbers.count<3{numbers.append(0)}
		var prerelease:[String]=[]
		if components.count==2{
			guard core.count==3, let parts=identifiers(components[1]) else {return nil}
			for part in parts where part.utf8.allSatisfy({$0>=48 && $0<=57}){
				guard part.count==1 || part.first != "0" else {return nil}
			}
			prerelease=parts
		}
		self.numbers=numbers
		self.prerelease=prerelease
	}
	var isStable:Bool{prerelease.isEmpty}
	static func <(lhs:Self, rhs:Self)->Bool{
		if lhs.numbers != rhs.numbers{return lhs.numbers.lexicographicallyPrecedes(rhs.numbers)}
		if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty{return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty}
		for (left,right) in zip(lhs.prerelease,rhs.prerelease) where left != right{
			let leftNumeric=left.utf8.allSatisfy {$0>=48 && $0<=57}
			let rightNumeric=right.utf8.allSatisfy {$0>=48 && $0<=57}
			if leftNumeric != rightNumeric{return leftNumeric}
			if leftNumeric && left.count != right.count{return left.count<right.count}
			return left<right
		}
		return lhs.prerelease.count<rhs.prerelease.count
	}
}

struct UpdateRelease:Codable, Equatable{
	let tagName:String
	let pageURL:URL
	var isValid:Bool{
		guard let version=ReleaseVersion(tagName), version.isStable,
			let url=URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {return false}
		return url.scheme=="https" && url.host=="github.com" && url.port==nil && url.user==nil && url.password==nil && url.query==nil && url.fragment==nil
			&& url.path=="/markandreydc/QuickShareMac/releases/tag/"+tagName
	}
}

enum UpdateCheckError:LocalizedError{
	case invalidVersion, invalidResponse, rateLimited, server, offline
	var errorDescription:String?{
		switch self{
		case .invalidVersion: return NSLocalizedString("UpdateInvalidVersion", value: "This app's version could not be read. Download a current release from GitHub.", comment: "")
		case .invalidResponse: return NSLocalizedString("UpdateInvalidResponse", value: "GitHub returned an unsupported release or an invalid response. Please visit the releases page.", comment: "")
		case .rateLimited: return NSLocalizedString("UpdateRateLimited", value: "GitHub temporarily limited update requests. Please try again later or visit the releases page.", comment: "")
		case .server: return NSLocalizedString("UpdateServerError", value: "GitHub could not complete the update check. Please try again later.", comment: "")
		case .offline: return NSLocalizedString("UpdateNetworkError", value: "Could not connect to GitHub. Check your internet connection and try again.", comment: "")
		}
	}
}

// All state and callbacks live on the main thread. Networking uses an ephemeral
// session: no GitHub token, cookies, analytics, downloads or installation.
final class UpdateChecker{
	enum Outcome:Equatable{case available(UpdateRelease), upToDate, noRelease}
	static let latestURL=URL(string: "https://api.github.com/repos/markandreydc/QuickShareMac/releases/latest")!
	static let releasesURL=URL(string: "https://github.com/markandreydc/QuickShareMac/releases")!
	private let preferences:UserDefaults
	private let session:URLSession
	private let now:()->Date
	private let calendar:Calendar
	let currentVersion:String
	private(set) var isChecking=false
	private(set) var availableRelease:UpdateRelease?
	private(set) var statusText=""
	var onChange:(()->Void)?
	var onResult:((Result<Outcome,UpdateCheckError>, Bool)->Void)?
	private var task:URLSessionDataTask?
	private var timer:Timer?
	private var requestID:UUID?
	private var manualRequest=false
	private let frequencyKey="UpdateCheckFrequency"
	private let lastAttemptKey="LastUpdateCheckAttempt"
	private let cacheKey="CachedUpdateRelease"
	private let retryKey="UpdateCheckRetryAfter"
	var frequency:UpdateCheckFrequency{UpdateCheckFrequency(rawValue: preferences.string(forKey: frequencyKey) ?? "") ?? .never}
	var automaticChecks:Bool{frequency != .never}

	init(preferences:UserDefaults = .standard, currentVersion:String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", session:URLSession?=nil, now:@escaping ()->Date = Date.init, calendar:Calendar = .current){
		self.preferences=preferences
		self.currentVersion=currentVersion
		self.now=now
		self.calendar=calendar
		if preferences.object(forKey: frequencyKey)==nil{
			let migrated:UpdateCheckFrequency=preferences.bool(forKey: "AutomaticallyCheckForUpdates") ? .daily : .never
			preferences.set(migrated.rawValue, forKey: frequencyKey)
		}
		if let session=session{self.session=session}
		else{
			let configuration=URLSessionConfiguration.ephemeral
			configuration.httpShouldSetCookies=false
			configuration.timeoutIntervalForRequest=20
			configuration.timeoutIntervalForResource=30
			self.session=URLSession(configuration: configuration)
		}
		if let data=preferences.data(forKey: cacheKey), let cached=try? JSONDecoder().decode(UpdateRelease.self, from: data), cached.isValid,
			let installed=ReleaseVersion(currentVersion), let remote=ReleaseVersion(cached.tagName), remote>installed{availableRelease=cached}
		if let release=availableRelease{statusText=Self.availableText(release)}
	}
	static func availableText(_ release:UpdateRelease)->String{
		String(format: NSLocalizedString("UpdateAvailableStatus", value: "Update available: %@", comment: ""), release.tagName)
	}
	func start(){
		timer?.invalidate()
		let timer=Timer(timeInterval: 3600, repeats: true){ [weak self] _ in self?.checkAutomaticallyIfDue() }
		self.timer=timer
		RunLoop.main.add(timer, forMode: .common)
		checkAutomaticallyIfDue()
	}
	func setFrequency(_ frequency:UpdateCheckFrequency){
		preferences.set(frequency.rawValue, forKey: frequencyKey)
		onChange?()
		if frequency != .never{checkAutomaticallyIfDue()}
	}
	func checkAutomaticallyIfDue(){
		guard automaticChecks, !isChecking else {return}
		if let last=preferences.object(forKey: lastAttemptKey) as? Date,
			let next=frequency.nextCheck(after: last, calendar: calendar), now()<next{return}
		check(manual: false)
	}
	func check(manual:Bool = true){
		if isChecking{manualRequest = manualRequest || manual; return}
		guard ReleaseVersion(currentVersion) != nil else {finish(.failure(.invalidVersion), manual: manual); return}
		if let retry=preferences.object(forKey: retryKey) as? Date, now()<retry{finish(.failure(.rateLimited), manual: manual); return}
		preferences.set(now(), forKey: lastAttemptKey)
		manualRequest=manual
		isChecking=true
		statusText=NSLocalizedString("CheckingForUpdates", value: "Checking for updates…", comment: "")
		let id=UUID()
		requestID=id
		var request=URLRequest(url: Self.latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
		request.setValue("QuickShareMac/"+currentVersion, forHTTPHeaderField: "User-Agent")
		task=session.dataTask(with: request){ [weak self] data, response, error in
			DispatchQueue.main.async{
				guard let self=self, self.requestID==id else {return}
				let result=self.parse(data: data, response: response, error: error)
				self.finish(result, manual: self.manualRequest)
			}
		}
		onChange?()
		task?.resume()
	}
	private func parse(data:Data?, response:URLResponse?, error:Error?)->Result<Outcome,UpdateCheckError>{
		guard error==nil else {return .failure(.offline)}
		guard let response=response as? HTTPURLResponse else {return .failure(.invalidResponse)}
		if response.statusCode==403 || response.statusCode==429{
			var retry=now().addingTimeInterval(3600)
			if let value=response.value(forHTTPHeaderField: "Retry-After"), let seconds=Double(value), seconds.isFinite, seconds>=0{retry=now().addingTimeInterval(min(seconds,86400))}
			if let value=response.value(forHTTPHeaderField: "X-RateLimit-Reset"), let seconds=Double(value), seconds.isFinite{retry=max(retry, min(Date(timeIntervalSince1970: seconds),now().addingTimeInterval(86400)))}
			preferences.set(retry, forKey: retryKey)
			return .failure(.rateLimited)
		}
		if response.statusCode==404{return .success(.noRelease)}
		guard response.statusCode==200 else {return .failure(.server)}
		struct GitHubRelease:Decodable{
			let tag_name:String
			let html_url:URL
			let draft:Bool
			let prerelease:Bool
		}
		guard let data=data, data.count<=2_000_000, let release=try? JSONDecoder().decode(GitHubRelease.self, from: data), !release.draft, !release.prerelease else {return .failure(.invalidResponse)}
		let update=UpdateRelease(tagName: release.tag_name, pageURL: release.html_url)
		guard update.isValid, let remote=ReleaseVersion(update.tagName), let installed=ReleaseVersion(currentVersion) else {return .failure(.invalidResponse)}
		return .success(remote>installed ? .available(update) : .upToDate)
	}
	private func finish(_ result:Result<Outcome,UpdateCheckError>, manual:Bool){
		isChecking=false
		requestID=nil
		task=nil
		switch result{
		case .success(.available(let release)):
			availableRelease=release
			preferences.set(try? JSONEncoder().encode(release), forKey: cacheKey)
			statusText=Self.availableText(release)
		case .success:
			availableRelease=nil
			preferences.removeObject(forKey: cacheKey)
			statusText=NSLocalizedString("UpdateUpToDate", value: "You're up to date.", comment: "")
			if case .success(.noRelease)=result{statusText=NSLocalizedString("UpdateNoRelease", value: "No published stable release is available yet.", comment: "")}
		case .failure(let error): statusText=error.localizedDescription
		}
		onChange?()
		// Background checks never show dialogs; disabling them also suppresses a
		// pending background result. A manual check can join an in-flight request.
		if manual || automaticChecks{onResult?(result,manual)}
	}
	func shutdown(){
		timer?.invalidate()
		timer=nil
		requestID=nil
		task?.cancel()
		task=nil
		isChecking=false
	}
	deinit{timer?.invalidate(); task?.cancel()}
}
