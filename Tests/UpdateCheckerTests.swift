import Foundation

// URLProtocol fixtures intercept every request. These tests never contact GitHub
// or change the app's real preferences, and never open a browser or install code.
final class MockGitHubProtocol:URLProtocol{
	static var handler:((URLRequest,MockGitHubProtocol)->Void)?
	private var stopped=false
	override class func canInit(with request:URLRequest)->Bool{true}
	override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
	override func startLoading(){DispatchQueue.main.async{if !self.stopped{Self.handler?(self.request,self)}}}
	override func stopLoading(){DispatchQueue.main.async{self.stopped=true}}
	func reply(_ status:Int, data:Data = Data(), headers:[String:String] = [:]){
		guard !stopped else {return}
		client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: data)
		client?.urlProtocolDidFinishLoading(self)
	}
	func fail(){client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))}
}

@main
struct UpdateCheckerTests{
	static var checks=0
	static func expect(_ condition:@autoclosure ()->Bool, _ message:String){checks+=1; precondition(condition(),message)}
	static func wait(_ condition:()->Bool){
		let deadline=Date().addingTimeInterval(3)
		while !condition() && Date()<deadline{RunLoop.main.run(until: Date().addingTimeInterval(0.01))}
		expect(condition(), "The mocked update request must complete")
	}
	static func json(_ tag:String = "v1.1.0", url:String?=nil, draft:Bool=false, prerelease:Bool=false)->Data{
		try! JSONSerialization.data(withJSONObject: ["tag_name":tag,"html_url":url ?? "https://github.com/markandreydc/QuickShareMac/releases/tag/"+tag,"draft":draft,"prerelease":prerelease])
	}
	static func main(){
		for (older,newer) in [("1.9.0","v1.10.0"),("1.0.9","1.1.0"),("1.99.99","2.0.0"),("1.0.0-beta.2","1.0.0-beta.11"),("1.0.0-rc.1","1.0.0"),("1.0.0-1","1.0.0-alpha"),("1.0.0-beta","1.0.0-beta.1")]{
			expect(ReleaseVersion(older)!<ReleaseVersion(newer)!, "Semantic version precedence must order \(older) before \(newer)")
		}
		expect(ReleaseVersion("v1")==ReleaseVersion("1.0.0+build.13"), "Short v1 tags and build metadata must not change precedence")
		expect(ReleaseVersion("1.1")==ReleaseVersion("1.1.0"), "Short minor tags must be supported")
		for invalid in ["","v","1..0","01.0.0","1.0.0.1","1.0.0-","1.0.0-beta.01","1.0.0+","1.0.0++x","1.0.0 beta","1.0.0-💥","1.0.0/other","999999999999999999999999999999.0.0"]{
			expect(ReleaseVersion(invalid)==nil, "Malformed version must be rejected: \(invalid)")
		}
		var domains:[String]=[]
		var instances:[UpdateChecker]=[]
		defer{
			instances.forEach {$0.shutdown()}
			domains.forEach {UserDefaults.standard.removePersistentDomain(forName: $0)}
		}
		var now=Date(timeIntervalSince1970: 100000)
		var calendar=Calendar(identifier: .gregorian)
		calendar.timeZone=TimeZone(secondsFromGMT: 0)!
		func create(_ version:String = "1.0.0", legacyAutomatic:Bool?=nil, savedFrequency:String?=nil)->(UpdateChecker,UserDefaults,URLSession){
			let domain="QuickShareMac.UpdateTests."+UUID().uuidString
			domains.append(domain)
			let preferences=UserDefaults(suiteName: domain)!
			if let legacyAutomatic=legacyAutomatic{preferences.set(legacyAutomatic, forKey: "AutomaticallyCheckForUpdates")}
			if let savedFrequency=savedFrequency{preferences.set(savedFrequency, forKey: "UpdateCheckFrequency")}
			let configuration=URLSessionConfiguration.ephemeral
			configuration.protocolClasses=[MockGitHubProtocol.self]
			let session=URLSession(configuration: configuration)
			let checker=UpdateChecker(preferences: preferences, currentVersion: version, session: session, now: {now}, calendar: calendar)
			instances.append(checker)
			return (checker,preferences,session)
		}
		let (checker,preferences,session)=create()
		var results:[(Result<UpdateChecker.Outcome,UpdateCheckError>,Bool)]=[]
		checker.onResult={result,manual in
			expect(Thread.isMainThread, "Update results must be delivered on the main thread")
			results.append((result,manual))
		}
		var requests=0
		MockGitHubProtocol.handler={request,stub in
			requests+=1
			expect(request.url==UpdateChecker.latestURL, "Only the configured repository's latest-release endpoint may be requested")
			expect(request.value(forHTTPHeaderField: "Authorization")==nil, "The update checker must not embed a GitHub token")
			expect(request.value(forHTTPHeaderField: "Accept")=="application/vnd.github+json", "GitHub's JSON API must be requested")
			expect(request.value(forHTTPHeaderField: "User-Agent")=="QuickShareMac/1.0.0", "Requests must identify the app")
			stub.reply(200,data: json())
		}
		expect(!checker.automaticChecks, "Automatic update checks must be disabled by default")
		checker.start()
		expect(!checker.isChecking && requests==0, "Launching with automatic checks disabled must not send a request")
		checker.check()
		expect(checker.isChecking, "Manual checks must expose a pending state")
		wait{results.count==1}
		if case .success(.available(let release))=results[0].0{expect(release.tagName=="v1.1.0", "A newer release must be offered")}
		else{expect(false, "Expected an available update")}
		expect(results[0].1 && !checker.isChecking, "Manual completion must clear the pending state")
		expect(checker.availableRelease != nil && preferences.data(forKey: "CachedUpdateRelease") != nil, "A valid update must be cached for the next launch")
		let restored=UpdateChecker(preferences: preferences, currentVersion: "1.0.0", session: session)
		expect(restored.availableRelease==checker.availableRelease, "Known updates must remain visible across launches")
		let upgraded=UpdateChecker(preferences: preferences, currentVersion: "1.1.0", session: session)
		expect(upgraded.availableRelease==nil, "An installed update must not be offered again from cache")
		preferences.set(Data("broken cache".utf8), forKey: "CachedUpdateRelease")
		expect(UpdateChecker(preferences: preferences, currentVersion: "1.0.0", session: session).availableRelease==nil, "Corrupt cached releases must be ignored")
		let unsafeCache=UpdateRelease(tagName: "v99.0.0", pageURL: URL(string: "https://evil.example/update")!)
		preferences.set(try! JSONEncoder().encode(unsafeCache), forKey: "CachedUpdateRelease")
		expect(UpdateChecker(preferences: preferences, currentVersion: "1.0.0", session: session).availableRelease==nil, "Cached release links must pass the same origin validation as fresh responses")
		checker.setFrequency(.daily)
		expect(!checker.isChecking && requests==1, "Enabling daily checks after a manual check must respect the daily limit")
		expect(restored.automaticChecks, "The automatic-check preference must persist")
		now=now.addingTimeInterval(86400)
		checker.checkAutomaticallyIfDue()
		wait{results.count==2}
		expect(requests==2 && !results[1].1, "An opted-in daily check must run after 24 hours without a manual dialog")
		checker.checkAutomaticallyIfDue()
		expect(!checker.isChecking, "Repeated timer or wake events must not repeat a daily check")
		func check(_ status:Int, data:Data = Data(), headers:[String:String] = [:])->Result<UpdateChecker.Outcome,UpdateCheckError>{
			MockGitHubProtocol.handler={_,stub in requests+=1; stub.reply(status,data: data,headers: headers)}
			let count=results.count
			checker.check()
			wait{results.count==count+1}
			return results.last!.0
		}
		if case .success(.upToDate)=check(200,data: json("v1.0.0")){expect(true,"Equal versions are current")}
		else{expect(false,"Equal versions must not offer an update")}
		expect(checker.availableRelease==nil, "An up-to-date response must clear an old update")
		if case .success(.upToDate)=check(200,data: json("v0.9.0")){expect(true,"Older versions are not downgrades")}
		else{expect(false,"Older releases must not prompt a downgrade")}
		if case .success(.noRelease)=check(404){expect(true,"No release is a normal result")}
		else{expect(false,"An unpublished initial release must not be reported as up to date")}
		for invalid in [Data("not json".utf8),Data("{}".utf8),json(draft: true),json(prerelease: true),json("v1.2.0-beta.1"),json("release-next"),json(url: "https://evil.example/update"),json(url: "https://github.com/other/repo/releases/tag/v1.1.0"),json(url: "http://github.com/markandreydc/QuickShareMac/releases/tag/v1.1.0"),json(url: "https://github.com/markandreydc/QuickShareMac/releases/tag/v1.1.0?redirect=elsewhere")]{
			if case .failure(.invalidResponse)=check(200,data: invalid){expect(true,"Unsafe or unsupported releases are rejected")}
			else{expect(false,"Invalid releases must never yield an update link")}
		}
		if case .failure(.server)=check(503){expect(true,"Server errors are readable")}
		else{expect(false,"Unexpected HTTP status must be an error")}
		MockGitHubProtocol.handler={_,stub in stub.fail()}
		let count=results.count
		checker.check()
		wait{results.count==count+1}
		if case .failure(.offline)=results.last!.0{expect(true,"Offline errors are readable")}
		else{expect(false,"Network failure must not be reported as up to date")}
		if case .failure(.rateLimited)=check(429,headers: ["Retry-After":"120"]){expect(true,"Rate limiting is handled")}
		else{expect(false,"HTTP 429 must report rate limiting")}
		let previousRequests=requests
		checker.check()
		expect(requests==previousRequests && !checker.isChecking, "Rate-limited manual retries must not repeatedly contact GitHub")
		now=now.addingTimeInterval(121)
		if case .success(.upToDate)=check(200,data: json("v1.0.0")){expect(true,"Retry after backoff succeeds")}
		else{expect(false,"Checking must resume after Retry-After")}
		if case .failure(.rateLimited)=check(403,headers: ["X-RateLimit-Reset":String(Int(now.timeIntervalSince1970+7200))]){expect(true,"GitHub reset header is respected")}
		else{expect(false,"HTTP 403 must avoid repeated API requests")}
		expect((preferences.object(forKey: "UpdateCheckRetryAfter") as? Date)==now.addingTimeInterval(7200), "Rate-limit reset must persist across launches")

		let (joined,_,_)=create()
		var pending:MockGitHubProtocol?
		var joinedRequests=0
		MockGitHubProtocol.handler={_,stub in joinedRequests+=1; pending=stub}
		var joinedResults=0
		var wasManual=false
		joined.onResult={_,manual in joinedResults+=1; wasManual=manual}
		joined.setFrequency(.daily)
		wait{pending != nil}
		joined.check()
		joined.check()
		pending!.reply(200,data: json())
		wait{joinedResults==1}
		expect(joinedRequests==1 && wasManual, "A manual request must join an existing background check without duplicate networking")
		now=now.addingTimeInterval(86400)
		pending=nil
		joined.checkAutomaticallyIfDue()
		wait{pending != nil}
		joined.setFrequency(.never)
		pending!.reply(200,data: json())
		wait{!joined.isChecking}
		expect(joinedResults==1, "Disabling background checks must suppress a pending background callback")
		pending=nil
		joined.check()
		wait{pending != nil}
		joined.shutdown()
		RunLoop.main.run(until: Date().addingTimeInterval(0.05))
		expect(!joined.isChecking && joinedResults==1, "Shutdown must cancel requests without delivering late results")
		let (invalidVersion,_,_)=create("not-a-version")
		var rejected=false
		invalidVersion.onResult={result,_ in if case .failure(.invalidVersion)=result{rejected=true}}
		invalidVersion.check()
		expect(rejected && !invalidVersion.isChecking, "Unreadable installed versions must fail without networking")

		expect(checker.frequency == .daily, "The previous opt-in must now be represented by Daily")
		expect(create(legacyAutomatic: true).0.frequency == .daily, "An existing enabled checkbox must migrate to Daily")
		expect(create(legacyAutomatic: false).0.frequency == .never, "An existing disabled checkbox must migrate to Never")
		expect(create().0.frequency == .never, "Fresh installations must default to Never")
		expect(create(legacyAutomatic: true, savedFrequency: "monthly").0.frequency == .monthly, "An explicit frequency must not be overwritten by the old checkbox preference")
		expect(create(savedFrequency: "invalid").0.frequency == .never, "An invalid frequency must safely disable automatic checks")

		var scheduleRequests=0
		MockGitHubProtocol.handler={_,stub in scheduleRequests+=1; stub.reply(200,data: json("v1.0.0"))}
		let januaryEnd=calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12))!
		now=januaryEnd
		let (weekly,weeklyPreferences,weeklySession)=create()
		weekly.setFrequency(.weekly)
		wait{!weekly.isChecking && scheduleRequests==1}
		expect(UpdateChecker(preferences: weeklyPreferences, currentVersion: "1.0.0", session: weeklySession).frequency == .weekly, "Frequency choices must persist across launches")
		now=januaryEnd.addingTimeInterval(7*86400-1)
		weekly.checkAutomaticallyIfDue()
		expect(scheduleRequests==1 && !weekly.isChecking, "Weekly checks must wait seven days")
		now=now.addingTimeInterval(1)
		weekly.checkAutomaticallyIfDue()
		wait{!weekly.isChecking && scheduleRequests==2}
		weekly.checkAutomaticallyIfDue()
		expect(!weekly.isChecking && scheduleRequests==2, "Repeated wake/timer events must not duplicate a weekly check")
		weekly.setFrequency(.monthly)
		expect(!weekly.isChecking && scheduleRequests==2, "Switching to a longer schedule must respect the last check")
		now=now.addingTimeInterval(86400)
		weekly.setFrequency(.daily)
		wait{!weekly.isChecking && scheduleRequests==3}
		expect(weekly.frequency == .daily, "Switching to a shorter overdue schedule must run a check")
		weekly.setFrequency(.never)
		now=now.addingTimeInterval(400*86400)
		weekly.checkAutomaticallyIfDue()
		expect(!weekly.isChecking && scheduleRequests==3, "Never must disable all scheduled checks")
		weekly.check()
		wait{!weekly.isChecking && scheduleRequests==4}
		expect(weekly.frequency == .never, "Manual checks must work without changing the Never preference")

		now=januaryEnd
		let (monthly,_,_)=create()
		monthly.setFrequency(.monthly)
		wait{!monthly.isChecking && scheduleRequests==5}
		let februaryEnd=calendar.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 12))!
		now=februaryEnd.addingTimeInterval(-1)
		monthly.checkAutomaticallyIfDue()
		expect(!monthly.isChecking && scheduleRequests==5, "Monthly checks must wait until the next calendar month")
		now=februaryEnd
		monthly.checkAutomaticallyIfDue()
		wait{!monthly.isChecking && scheduleRequests==6}
		expect(UpdateCheckFrequency.monthly.nextCheck(after: januaryEnd, calendar: calendar)==februaryEnd, "Monthly must handle short months rather than assume 30 days")
		expect(UpdateCheckFrequency.never.nextCheck(after: januaryEnd, calendar: calendar)==nil, "Never must not have a next automatic-check date")
		print("Passed \(checks) update checker checks")
	}
}
