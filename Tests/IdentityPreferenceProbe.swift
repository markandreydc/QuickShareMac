import Foundation

// Invoked only by run-shared-identity-tests.sh in disposable signed app bundles.
@main
struct IdentityPreferenceProbe{
	static func main() throws{
		let args=CommandLine.arguments
		let preferences=UserDefaults(suiteName: args[1])!
		let identity=LocalDeviceIdentity(preferences: preferences, systemName: {"System Mac"})
		switch args[2]{
		case "set": try identity.setCustomName(args[3])
		case "clear": preferences.removePersistentDomain(forName: args[1]); preferences.synchronize()
		default: break
		}
		print(identity.deviceName)
	}
}
