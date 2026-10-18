import Cocoa
import Network
@testable import NearbyShare

// Exercises the real encryption/transfer protocol on 127.0.0.1 only. All received
// files go into a disposable test directory, never the user's Downloads folder.
@main
struct SendingIntegrationTests{
	static var checks=0
	static func expect(_ condition:@autoclosure () throws -> Bool, _ message:String){
		checks+=1
		precondition(try! condition(), message)
	}
	static func main() throws{
		_ = NSApplication.shared
		NSApp.setActivationPolicy(.prohibited)
		let maximumName=try LocalDeviceIdentity.validate(String(repeating: "a", count: LocalDeviceIdentity.maximumNameBytes))
		let endpoint=EndpointInfo(name: maximumName, deviceType: .computer).serialize()
		let encoded=endpoint.urlSafeBase64EncodedString().data(using: .utf8)!
		let txt=NetService.data(fromTXTRecord: ["n":encoded])
		expect(encoded.count+2<=255 && NetService.dictionary(fromTXTRecord: txt)["n"]==encoded, "The maximum device name must fit a Bonjour TXT record without losing discovery metadata")
		expect(EndpointInfo(data: endpoint)?.name==maximumName, "The maximum device name must round-trip through endpoint metadata")
		let directory=FileManager.default.temporaryDirectory.appendingPathComponent("quickshare-protocol-tests-"+UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer{try? FileManager.default.removeItem(at: directory)}
		let destination=directory.appendingPathComponent("received", isDirectory: true)
		try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
		let file=directory.appendingPathComponent("payload.bin")
		let empty=directory.appendingPathComponent("empty.txt")
		let anotherDirectory=directory.appendingPathComponent("another", isDirectory: true)
		try FileManager.default.createDirectory(at: anotherDirectory, withIntermediateDirectories: true)
		let sameNameFile=anotherDirectory.appendingPathComponent("payload.bin")
		let otherPayload=Data("Different file, same name".utf8)
		let payload=Data((0..<1200000).map {UInt8(truncatingIfNeeded: $0)})
		try payload.write(to: file)
		try Data().write(to: empty)
		try otherPayload.write(to: sameNameFile)
		let existing=destination.appendingPathComponent("payload.bin")
		try Data("Keep this existing file".utf8).write(to: existing)

		for path in ["/absolute","../escape","Album/../escape","Album//sub","Album/./sub","Album/","Album/\0"]{
			do{_ = try OutboundNearbyConnection.safeParentFolder(path); expect(false, "Unsafe folder paths must be rejected: \(path)")}
			catch{expect(true, "Unsafe folder path rejected")}
		}
		expect(try OutboundNearbyConnection.safeParentFolder("Al?bum/2023")=="Al_bum/2023", "Each folder-path component must be sanitized without flattening the hierarchy")
		let accepted=try LoopbackTransfer(urls: [file,empty,sameNameFile], directory: destination, decision: .accept, parentFolders: [file:"Al?bum/2023",empty:"Al?bum",sameNameFile:"Album (2)"])
		accepted.run()
		expect(accepted.clientSucceeded && accepted.clientError==nil, "Sender must complete a multi-file transfer")
		expect(accepted.receiverDone && accepted.receiverError==nil, "Receiver must complete a multi-file transfer")
		expect(accepted.clientPIN==accepted.metadata?.pinCode && accepted.clientPIN != nil, "Both endpoints must derive the same PIN")
		expect(accepted.receivedSenderName=="Protocol Test Mac", "Outgoing handshakes must advertise the configured local device name")
		expect(accepted.metadata?.savedFileURLs.count==3, "Receiver must report actual destination paths")
		let urls=accepted.metadata!.savedFileURLs
		expect(Set(urls).count==3, "Same-named files must get different destination paths")
		let receivedPayloads=try urls.filter {$0.pathExtension=="bin"}.map {try Data(contentsOf: $0)}
		expect(receivedPayloads.contains(payload), "Multi-chunk payload must arrive unchanged")
		expect(receivedPayloads.contains(otherPayload), "Same-named attachments must not overwrite each other")
		expect(try Data(contentsOf: urls.first(where: {$0.pathExtension=="txt"})!).isEmpty, "Zero-byte files must arrive successfully")
		expect(try String(contentsOf: existing, encoding: .utf8)=="Keep this existing file", "Existing destination files must not be overwritten")
		let wireFiles=accepted.receiver!.introducedFiles
		expect(wireFiles.map(\.parentFolder)==["Al_bum/2023","Al_bum","Album (2)"], "The encrypted introduction must carry relative folder paths for every attachment")
		let headers=accepted.receiver!.fileHeaders
		expect(!headers.isEmpty && headers.allSatisfy {header in wireFiles.contains {$0.payloadID==header.id && $0.name==header.fileName && $0.parentFolder==header.parentFolder}}, "File chunks and zero-byte EOF headers must carry the same folder and filename as their introduction")
		expect(Set(headers.map(\.id))==Set(wireFiles.map(\.payloadID)), "Even zero-byte files must transmit folder metadata in their payload header")
		accepted.stop()

		let rejected=try LoopbackTransfer(urls: [file], directory: destination, decision: .reject)
		rejected.run()
		if let error=rejected.clientError as? NearbyError, case .canceled(reason: .userRejected)=error{expect(true, "Rejected")}
		else{expect(false, "Rejection must reach the sender as a readable failure")}
		expect(!rejected.clientSucceeded, "Rejected transfers must not report success")
		rejected.stop()

		let canceled=try LoopbackTransfer(urls: [file], directory: destination, decision: .cancel)
		canceled.run()
		expect(!canceled.clientSucceeded && canceled.clientError != nil, "Cancel during approval must terminate the transfer")
		canceled.stop()

		let disconnected=try LoopbackTransfer(urls: [file], directory: destination, decision: .disconnect)
		disconnected.run()
		expect(!disconnected.clientSucceeded && disconnected.clientError != nil, "Unexpected peer closure must report failure instead of hanging")
		disconnected.stop()
		testBlockedConnections()
		print("Passed \(checks) loopback protocol checks")
	}

	static func testBlockedConnections(){
		let errors:[NWError]=[.dns(-65570), .posix(.EACCES), .posix(.EPERM)]
		for error in errors{
			let connection=NWConnection(host: "127.0.0.1", port: 9, using: .tcp)
			let sender=OutboundNearbyConnection(connection: connection, id: UUID().uuidString, urlsToSend: [])
			let observer=ConnectionFailureObserver()
			sender.delegate=observer
			connection.start(queue: NearbyConnection.dispatchQueue)
			NearbyConnection.dispatchQueue.sync{
				sender.handleConnectionState(.waiting(error))
				// Framework callbacks queued before cancellation must be harmless.
				sender.handleConnectionState(.ready)
				sender.handleConnectionState(.failed(error))
			}
			expect(waitForCancellation(connection), "A waiting connection must be physically canceled")
			expect(observer.failureCount==1, "Policy denial must report exactly one terminal failure")
			if case .localNetworkDenied? = observer.error as? NearbyError{expect(true, "Policy denied")}
			else{expect(false, "Network policy failures must map to a specific permission error")}
		}
		let mapped=NearbyConnection.connectionFailure(.posix(.ENETUNREACH), policyDenied: true)
		if case .localNetworkDenied? = mapped as? NearbyError{expect(true, "Path denied")}
		else{expect(false, "The path's local-network-denied reason must take precedence")}
		let refused=NearbyConnection.connectionFailure(.posix(.ECONNREFUSED))
		if case .posix(.ECONNREFUSED)? = refused as? NWError{expect(true, "Refused")}
		else{expect(false, "A phone refusing a connection must not be mislabeled as permission denial")}
		let connection=NWConnection(host: "127.0.0.1", port: 9, using: .tcp)
		let sender=OutboundNearbyConnection(connection: connection, id: UUID().uuidString, urlsToSend: [])
		let observer=ConnectionFailureObserver()
		sender.delegate=observer
		connection.start(queue: NearbyConnection.dispatchQueue)
		NearbyConnection.dispatchQueue.sync{sender.cancel()}
		expect(waitForCancellation(connection), "Cancel before TCP is ready must not wait for a send completion")
		expect(observer.failureCount==1, "Cancel before connecting must finish exactly once")
	}

	static func waitForCancellation(_ connection:NWConnection) -> Bool{
		let deadline=Date().addingTimeInterval(1)
		while connection.state != .cancelled && Date()<deadline{RunLoop.main.run(until: Date().addingTimeInterval(0.01))}
		return connection.state == .cancelled
	}
}

private final class ConnectionFailureObserver:OutboundNearbyConnectionDelegate{
	var failureCount=0
	var error:Error?
	func outboundConnectionWasEstablished(connection:OutboundNearbyConnection){}
	func outboundConnectionTransferAccepted(connection:OutboundNearbyConnection){}
	func outboundConnection(connection:OutboundNearbyConnection, transferProgress:Double){}
	func outboundConnection(connection:OutboundNearbyConnection, failedWithError error:Error){failureCount+=1; self.error=error}
	func outboundConnectionTransferFinished(connection:OutboundNearbyConnection){preconditionFailure("A blocked connection cannot succeed")}
}

private final class RecordingInboundConnection:InboundNearbyConnection{
	var introducedFiles:[Sharing_Nearby_FileMetadata]=[]
	var fileHeaders:[Location_Nearby_Connections_PayloadTransferFrame.PayloadHeader]=[]
	override func processTransferSetupFrame(_ frame:Sharing_Nearby_Frame) throws{
		if frame.v1.type == .introduction{introducedFiles=frame.v1.introduction.fileMetadata}
		try super.processTransferSetupFrame(frame)
	}
	override func processFileChunk(frame:Location_Nearby_Connections_PayloadTransferFrame) throws{
		fileHeaders.append(frame.payloadHeader)
		try super.processFileChunk(frame: frame)
	}
}

private final class LoopbackTransfer:InboundNearbyConnectionDelegate, OutboundNearbyConnectionDelegate{
	enum Decision{case accept, reject, cancel, disconnect}
	let listener:NWListener
	let urls:[URL]
	let directory:URL
	let decision:Decision
	var sender:OutboundNearbyConnection?
	var receiver:RecordingInboundConnection?
	var clientSucceeded=false
	var clientDone=false
	var receiverDone=false
	var clientError:Error?
	var receiverError:Error?
	var metadata:TransferMetadata?
	var clientPIN:String?
	var receivedSenderName:String?

	init(urls:[URL], directory:URL, decision:Decision, parentFolders:[URL:String] = [:]) throws{
		self.urls=urls
		self.directory=directory
		self.decision=decision
		let parameters=NWParameters.tcp
		parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
		listener=try NWListener(using: parameters)
		listener.newConnectionHandler={ [weak self] connection in
			guard let self=self else {connection.cancel(); return}
			let receiver=RecordingInboundConnection(connection: connection, id: UUID().uuidString, downloadDirectory: directory)
			receiver.delegate=self
			self.receiver=receiver
			receiver.start()
		}
		listener.stateUpdateHandler={ [weak self] state in
			guard let self=self else {return}
			if case .ready=state, let port=self.listener.port{
				let connection=NWConnection(host: "127.0.0.1", port: port, using: .tcp)
				let sender=OutboundNearbyConnection(connection: connection, id: UUID().uuidString, urlsToSend: urls, localDeviceName: "Protocol Test Mac", parentFolders: parentFolders)
				sender.delegate=self
				self.sender=sender
				sender.start()
			}else if case .failed(let error)=state{self.clientError=error; self.clientDone=true; self.receiverDone=true}
		}
	}
	func run(){
		listener.start(queue: .main)
		let deadline=Date().addingTimeInterval(15)
		while Date()<deadline && !(clientDone && (decision != .accept || receiverDone)){
			RunLoop.main.run(until: Date().addingTimeInterval(0.01))
		}
		precondition(clientDone, "Protocol test timed out waiting for the sender")
	}
	func stop(){
		listener.cancel()
		if let sender=sender{NearbyConnection.dispatchQueue.async {sender.connection.cancel()}}
		if let receiver=receiver{NearbyConnection.dispatchQueue.async {receiver.connection.cancel()}}
		RunLoop.main.run(until: Date().addingTimeInterval(0.05))
		sender?.delegate=nil
		receiver?.delegate=nil
	}
	func obtainUserConsent(for transfer:TransferMetadata, from device:RemoteDeviceInfo, connection:InboundNearbyConnection){
		metadata=transfer
		receivedSenderName=device.name
		switch decision{
		case .accept: connection.submitUserConsent(accepted: true)
		case .reject: connection.submitUserConsent(accepted: false)
		case .cancel:
			if let sender=sender{NearbyConnection.dispatchQueue.async {sender.cancel()}}
		case .disconnect: NearbyConnection.dispatchQueue.async {connection.connection.cancel()}
		}
	}
	func incomingConnection(connection:InboundNearbyConnection, didReceiveBytes count:Int64){}
	func connectionWasTerminated(connection:InboundNearbyConnection, error:Error?){receiverError=error; receiverDone=true}
	func outboundConnectionWasEstablished(connection:OutboundNearbyConnection){DispatchQueue.main.async {self.clientPIN=connection.pinCode}}
	func outboundConnectionTransferAccepted(connection:OutboundNearbyConnection){}
	func outboundConnection(connection:OutboundNearbyConnection, transferProgress:Double){}
	func outboundConnection(connection:OutboundNearbyConnection, failedWithError error:Error){DispatchQueue.main.async {self.clientError=error; self.clientDone=true}}
	func outboundConnectionTransferFinished(connection:OutboundNearbyConnection){DispatchQueue.main.async {self.clientSucceeded=true; self.clientDone=true}}
}
