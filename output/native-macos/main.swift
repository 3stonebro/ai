import Cocoa

struct Star { var x: CGFloat; var y: CGFloat; var speed: CGFloat }
struct Bullet { var x: CGFloat; var y: CGFloat }

final class GameView: NSView {
    var stars: [Star] = []
    var bullets: [Bullet] = []
    var tankX: CGFloat = 360
    var destroyed = 0
    var missed = 0
    var playing = false
    var hasPlayed = false
    var keys = Set<UInt16>()
    var spawn: Double = 0
    var cooldown: Double = 0
    var previous = ProcessInfo.processInfo.systemUptime
    var timer: Timer?
    let tankY: CGFloat = 60
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        NotificationCenter.default.addObserver(self, selector: #selector(clearKeys), name: NSWindow.didResignKeyNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc func clearKeys() { keys.removeAll() }
    func start() {
        stars = []; bullets = []; destroyed = 0; missed = 0
        tankX = bounds.midX; spawn = 0.5; cooldown = 0
        keys.removeAll(); playing = true; hasPlayed = true
        previous = ProcessInfo.processInfo.systemUptime
    }
    override func keyDown(with event: NSEvent) {
        if !playing && (event.keyCode == 36 || event.keyCode == 49) { start(); return }
        if [UInt16(123), 124, 49].contains(event.keyCode) { keys.insert(event.keyCode) }
    }
    override func keyUp(with event: NSEvent) { keys.remove(event.keyCode) }
    override func mouseDown(with event: NSEvent) { if !playing { start() } }
    func finish() { playing = false; keys.removeAll() }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - previous, 0.04)
        previous = now
        guard playing, window?.isKeyWindow == true else { needsDisplay = true; return }
        let direction: CGFloat = (keys.contains(124) ? 1 : 0) - (keys.contains(123) ? 1 : 0)
        tankX = min(bounds.width - 48, max(48, tankX + direction * 430 * dt))
        cooldown = max(0, cooldown - dt)
        if keys.contains(49) && cooldown == 0 {
            bullets.append(Bullet(x: tankX, y: tankY + 36)); cooldown = 0.2
        }
        spawn -= dt
        if spawn <= 0 {
            stars.append(Star(x: CGFloat.random(in: 24...(bounds.width - 24)), y: bounds.height - 90, speed: CGFloat(135 + destroyed * 6)))
            spawn = 1.1
        }
        for i in bullets.indices { bullets[i].y += 560 * dt }
        for i in stars.indices.reversed() {
            stars[i].y -= stars[i].speed * dt
            let star = stars[i]
            if let b = bullets.firstIndex(where: { abs($0.x - star.x) <= 18 && abs($0.y - star.y) <= 24 }) {
                bullets.remove(at: b); stars.remove(at: i); destroyed += 1
                if destroyed == 10 { finish(); break }
            } else if star.y < -16 {
                stars.remove(at: i); missed += 1
                if missed == 3 { finish(); break }
            }
        }
        bullets.removeAll { $0.y > bounds.height }
        needsDisplay = true
    }
    func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = .white, centered: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: color]
        let string = value as NSString
        let width = string.size(withAttributes: attributes).width
        string.draw(at: NSPoint(x: centered ? x - width / 2 : x, y: y), withAttributes: attributes)
    }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, radius: CGFloat = 0) {
        color.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
    }
    func star(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        for i in 0..<10 {
            let angle = CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / 5
            let r = i % 2 == 0 ? radius : radius * 0.44
            let point = NSPoint(x: x + cos(angle) * r, y: y + sin(angle) * r)
            if i == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close(); color.setFill(); path.fill()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.16, blue: 0.28, alpha: 1), ending: NSColor(srgbRed: 0.035, green: 0.06, blue: 0.14, alpha: 1))!.draw(in: bounds, angle: 90)
        for i in 0..<65 {
            let x = CGFloat((i * 137) % 720), y = CGFloat((i * 83) % 440) + 70
            rect(x, y, 2, 2, NSColor.white.withAlphaComponent(0.25), radius: 1)
        }
        rect(0, bounds.height - 78, bounds.width, 78, NSColor.black.withAlphaComponent(0.25))
        text("STAR DEFENDER", x: 24, y: bounds.height - 47, size: 24)
        text("Destroyed \(destroyed) / 10     Missed \(missed) / 3", x: 390, y: bounds.height - 43, size: 17, color: .systemYellow)
        for s in stars { star(s.x, s.y, radius: 16, color: .systemYellow) }
        for b in bullets { rect(b.x - 3, b.y - 8, 6, 16, .systemMint, radius: 3) }
        rect(tankX - 46, tankY - 22, 92, 25, NSColor(white: 0.1, alpha: 1), radius: 10)
        for offset in stride(from: -32, through: 32, by: 16) { rect(tankX + CGFloat(offset) - 6, tankY - 18, 12, 16, .systemGray, radius: 6) }
        rect(tankX - 39, tankY - 4, 78, 22, .systemTeal, radius: 8)
        rect(tankX - 21, tankY + 12, 42, 19, .systemMint, radius: 7)
        rect(tankX - 5, tankY + 25, 10, 24, .systemMint, radius: 2)
        star(tankX, tankY + 6, radius: 7, color: .white)
        text("← →  Move     •     Hold Space to fire", x: bounds.midX, y: 12, size: 14, color: .lightGray, centered: true)
        if !playing {
            rect(0, 0, bounds.width, bounds.height - 78, NSColor.black.withAlphaComponent(0.72))
            let heading = !hasPlayed ? "Ready, aim, starlight!" : destroyed == 10 ? "Mission complete!" : "The stars slipped away"
            text(heading, x: bounds.midX, y: 315, size: 34, centered: true)
            text("Destroy 10 stars to win. Miss 3 and the game ends.", x: bounds.midX, y: 274, size: 18, color: .lightGray, centered: true)
            text("← → to move   •   Hold Space to shoot", x: bounds.midX, y: 238, size: 18, color: .lightGray, centered: true)
            rect(bounds.midX - 170, 155, 340, 52, .systemYellow, radius: 12)
            text(hasPlayed ? "Press Return to play again" : "Press Return to start", x: bounds.midX, y: 171, size: 19, color: .black, centered: true)
            text("You can also click to start", x: bounds.midX, y: 120, size: 14, color: .lightGray, centered: true)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let appMenu = NSMenu(); appMenu.addItem(withTitle: "Quit Star Defender", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = appMenu
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 580), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Star Defender"
        let view = GameView(frame: NSRect(x: 0, y: 0, width: 720, height: 580))
        window.contentView = view; window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
