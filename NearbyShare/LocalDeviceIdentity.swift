import Foundation

public final class LocalDeviceIdentity{
	// The Bonjour TXT item is limited to 255 bytes, including "n=". With
	// 18 bytes of endpoint metadata, 171 name bytes encode to 252 Base64 bytes.
	public static let maximumNameBytes=171
	// A narrowly shared preferences domain holds only the advertised name. The
	// containing app can write it; the sandboxed Share extension can only read it.
	public static let preferencesDomain="me.grishka.QuickShareMac.Identity"
	public static let shared=LocalDeviceIdentity(preferences: UserDefaults(suiteName: preferencesDomain)!)
	private let preferences:UserDefaults
	private let systemName:()->String
	private let key="CustomDeviceName"

	public init(preferences:UserDefaults, systemName:@escaping ()->String = {Host.current().localizedName ?? ProcessInfo.processInfo.hostName}){
		self.preferences=preferences
		self.systemName=systemName
	}
	public var customName:String?{
		guard let value=preferences.string(forKey: key) else {return nil}
		return try? Self.validate(value)
	}
	public var deviceName:String{
		if let customName=customName{return customName}
		let name=systemName().components(separatedBy: .controlCharacters).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
		var result=""
		for character in name{
			guard result.utf8.count+String(character).utf8.count<=Self.maximumNameBytes else {break}
			result.append(character)
		}
		return result.isEmpty ? "Mac" : result
	}
	public func setCustomName(_ value:String?) throws{
		if let value=value{preferences.set(try Self.validate(value), forKey: key)}
		else{preferences.removeObject(forKey: key)}
		// Flush this infrequent setting before another sandboxed process reads it.
		preferences.synchronize()
	}
	public static func validate(_ value:String) throws -> String{
		let name=value.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty, name.rangeOfCharacter(from: .controlCharacters)==nil, name.utf8.count<=maximumNameBytes else {
			throw NSError(domain: "QuickShareMac.DeviceName", code: 1, userInfo: [NSLocalizedDescriptionKey:NSLocalizedString("InvalidDeviceName", value: "Enter a device name without control characters, up to 171 UTF-8 bytes.", comment: "")])
		}
		return name
	}
}
