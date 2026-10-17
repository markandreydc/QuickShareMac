import Cocoa

final class StatusBarMenu:NSObject, NSMenuDelegate{
	struct State{
		let receiving:Bool
		let canSendFiles:Bool
	}
	let menu=NSMenu()
	var stateProvider:()->State = {State(receiving: false, canSendFiles: true)}
	var onShow:(()->Void)?
	var onSendFiles:(()->Void)?
	var onToggleReceiving:(()->Void)?
	var onSettings:(()->Void)?
	var onQuit:(()->Void)?
	private(set) var toolTip="QuickShareMac"
	private let receivingItem=NSMenuItem()
	private let sendItem=NSMenuItem()

	override init(){
		super.init()
		menu.delegate=self
		menu.autoenablesItems=false
		// Leave appearance, font, colors and item views to AppKit. In particular,
		// do not inherit the status button's wallpaper-dependent appearance.
		addItem(NSLocalizedString("ShowApp", value: "Show QuickShareMac", comment: ""), action: #selector(showApp(_:)))
		sendItem.title=NSLocalizedString("SendFiles", value: "Send files…", comment: "")
		sendItem.target=self
		sendItem.action=#selector(sendFiles(_:))
		menu.addItem(sendItem)
		receivingItem.target=self
		receivingItem.action=#selector(toggleReceiving(_:))
		menu.addItem(receivingItem)
		menu.addItem(.separator())
		addItem(NSLocalizedString("Settings", value: "Settings…", comment: ""), action: #selector(settings(_:)), key: ",")
		menu.addItem(.separator())
		addItem(NSLocalizedString("Quit", value: "Quit QuickShareMac", comment: ""), action: #selector(quit(_:)), key: "q")
		refresh()
	}

	func attach(to statusItem:NSStatusItem){
		// NSStatusItem owns menu presentation, highlighting, dismissal and both
		// mouse buttons. No custom click handler or contextual popup is needed.
		statusItem.button?.target=nil
		statusItem.button?.action=nil
		statusItem.button?.image=Self.makeIcon()
		statusItem.menu=menu
	}

	static func makeIcon() -> NSImage{
		let image:NSImage
		if #available(macOS 11.0, *), let symbol=NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "QuickShareMac"){
			image=symbol
		}else{
			// A monochrome fallback, not a template of the full-color app icon.
			image=NSImage(size: NSSize(width: 18, height: 18), flipped: false){ _ in
				NSColor.black.setStroke()
				let arrows=NSBezierPath()
				arrows.lineWidth=1.5
				arrows.lineCapStyle = .round
				arrows.lineJoinStyle = .round
				arrows.move(to: NSPoint(x: 2, y: 12))
				arrows.line(to: NSPoint(x: 16, y: 12))
				arrows.move(to: NSPoint(x: 12, y: 16))
				arrows.line(to: NSPoint(x: 16, y: 12))
				arrows.line(to: NSPoint(x: 12, y: 8))
				arrows.move(to: NSPoint(x: 16, y: 6))
				arrows.line(to: NSPoint(x: 2, y: 6))
				arrows.move(to: NSPoint(x: 6, y: 10))
				arrows.line(to: NSPoint(x: 2, y: 6))
				arrows.line(to: NSPoint(x: 6, y: 2))
				arrows.stroke()
				return true
			}
		}
		image.size=NSSize(width: 18, height: 18)
		image.isTemplate=true
		return image
	}

	func menuNeedsUpdate(_ menu:NSMenu){refresh()}
	func refresh(){
		let state=stateProvider()
		sendItem.isEnabled=state.canSendFiles
		receivingItem.title=state.receiving ? NSLocalizedString("MenuReceivingOn", value: "Receiving: On", comment: "") : NSLocalizedString("MenuReceivingOff", value: "Receiving: Off", comment: "")
		receivingItem.state=state.receiving ? .on : .off
		toolTip=state.receiving ? NSLocalizedString("MenuReceivingOnTooltip", value: "QuickShareMac · Receiving on. Click for menu.", comment: "") : NSLocalizedString("MenuReceivingOffTooltip", value: "QuickShareMac · Receiving off. Click for menu.", comment: "")
	}

	private func addItem(_ title:String, action:Selector, key:String = ""){
		let item=menu.addItem(withTitle: title, action: action, keyEquivalent: key)
		item.target=self
	}
	@objc private func showApp(_ sender:NSMenuItem){onShow?()}
	@objc private func sendFiles(_ sender:NSMenuItem){if stateProvider().canSendFiles{onSendFiles?()}}
	@objc private func toggleReceiving(_ sender:NSMenuItem){onToggleReceiving?(); refresh()}
	@objc private func settings(_ sender:NSMenuItem){onSettings?()}
	@objc private func quit(_ sender:NSMenuItem){onQuit?()}
}
