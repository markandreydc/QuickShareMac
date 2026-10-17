//
//  FolderCompressor.swift
//  QuickShareMac
//

import Foundation

enum FolderCompressionError:LocalizedError{
	case failed(folder:String)

	var errorDescription:String?{
		switch self{
		case .failed(let folder):
			return String(format: NSLocalizedString("FolderCompressionFailed", value: "The folder “%@” could not be compressed. Check that it can be read, then try again.", comment: ""), folder)
		}
	}
}

/// Compresses folders with the system `ditto` tool so the result matches
/// Finder's Compress menu: a ZIP that keeps resource forks and stores the
/// folder itself, not just its contents.
final class DittoFolderCompressor:FolderCompressing{
	private let queue=DispatchQueue(label: "QuickShareMac.folder-compressor", qos: .userInitiated)
	private var process:Process?

	func compress(folder:URL, into directory:URL, completion:@escaping (Result<URL,Error>)->Void){
		queue.async{ [weak self] in
			guard let self=self else{return}
			self.process?.terminate()
			self.process=nil
			let destination=directory.appendingPathComponent(folder.lastPathComponent+".zip")
			let process=Process()
			process.executableURL=URL(fileURLWithPath: "/usr/bin/ditto")
			process.arguments=["-c","-k","--sequesterRsrc","--keepParent",folder.path,destination.path]
			let errorPipe=Pipe()
			process.standardError=errorPipe
			process.standardOutput=Pipe()
			do{
				try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
				try? FileManager.default.removeItem(at: destination)
				try process.run()
			}catch{
				DispatchQueue.main.async{completion(.failure(error))}
				return
			}
			self.process=process
			process.terminationHandler={ [weak self] finished in
				let status=finished.terminationStatus
				let details=errorPipe.fileHandleForReading.readDataToEndOfFile()
				#if DEBUG
				if status != 0{print("ditto exited with status \(status): \(String(data: details.suffix(2000), encoding: .utf8) ?? "")")}
				#endif
				self?.queue.async{
					if self?.process === finished{self?.process=nil}
				}
				let succeeded=status == 0 && FileManager.default.fileExists(atPath: destination.path)
				DispatchQueue.main.async{
					completion(succeeded ? .success(destination) : .failure(FolderCompressionError.failed(folder: folder.lastPathComponent)))
				}
			}
		}
	}

	func cancel(){
		queue.async{ [weak self] in
			self?.process?.terminate()
			self?.process=nil
		}
	}
}
