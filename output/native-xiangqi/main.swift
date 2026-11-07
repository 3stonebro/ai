import Cocoa

final class ChessView: NSView {
    var position = Position()
    var history: [Position] = []
    var moveHistory: [Move] = []
    var selected: Int?
    var targets: [Int] = []
    var computer = true
    var thinking = false
    var animationMove: Move?
    var animationBoard: Position?
    var animationProgress: CGFloat = 0
    var animationTimer: Timer?
    let moveDuration: TimeInterval = 0.95
    var generation = 0
    var ended = false
    var status = "Red to move — select a piece"
    let originX: CGFloat = 62, originY: CGFloat = 98, step: CGFloat = 60
    override var acceptsFirstResponder: Bool { true }
    let red = NSColor(srgbRed: 0.73, green: 0.16, blue: 0.15, alpha: 1)
    let ink = NSColor(srgbRed: 0.17, green: 0.20, blue: 0.23, alpha: 1)
    func point(_ square: Int) -> NSPoint { NSPoint(x: originX + CGFloat(square%9)*step, y: originY + CGFloat(9-square/9)*step) }
    func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor, center: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color]
        let s = value as NSString
        s.draw(at: NSPoint(x: center ? x-s.size(withAttributes: attrs).width/2 : x, y: y), withAttributes: attrs)
    }
    func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) { color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill() }
    func line(_ a: NSPoint, _ b: NSPoint) { let p = NSBezierPath(); p.move(to: a); p.line(to: b); p.lineWidth = 1.2; p.stroke() }
    func button(_ label: String, _ rect: NSRect, active: Bool = false) {
        fill(rect, active ? red : NSColor(white: 0.88, alpha: 1), radius: 8)
        text(label,rect.midX,rect.minY+11,14,active ? .white : ink,center:true)
    }
    override func draw(_ dirtyRect: NSRect) {
        fill(bounds, NSColor(srgbRed: 0.96, green: 0.94, blue: 0.89, alpha: 1))
        text("象棋", 34, 711, 36, red)
        text("XIANGQI", 122, 729, 20, ink)
        text("Chinese chess · Red moves first", 123, 706, 13, .secondaryLabelColor)
        button("vs Computer",NSRect(x: 358,y: 718,width: 115,height: 40),active: computer)
        button("Two players",NSRect(x: 482,y: 718,width: 115,height: 40),active: !computer)
        text(status, 34, 675, 16, ink)
        fill(NSRect(x: 32,y: 68,width: 540,height: 600),NSColor(srgbRed: 0.90, green: 0.76, blue: 0.53, alpha: 1),radius: 14)
        ink.withAlphaComponent(0.7).setStroke()
        for y in 0..<10 { line(point(y*9),point(y*9+8)) }
        for x in 0..<9 {
            line(point(x),point(36+x)); line(point(45+x),point(81+x))
        }
        line(point(36),point(45)); line(point(44),point(53))
        for base in [0,63] { line(point(base+3),point(base+23)); line(point(base+5),point(base+21)) }
        text("楚 河",182,357,26,ink,center:true); text("漢 界",422,357,26,ink,center:true)
        if let last = moveHistory.last {
            for square in [last.from,last.to] { let p = point(square); fill(NSRect(x:p.x-27,y:p.y-27,width:54,height:54),NSColor.systemYellow.withAlphaComponent(0.38),radius: 8) }
        }
        for square in targets {
            let p = point(square); NSColor.systemGreen.withAlphaComponent(0.65).setFill()
            NSBezierPath(ovalIn: NSRect(x:p.x-8,y:p.y-8,width:16,height:16)).fill()
        }
        let display = animationBoard ?? position
        for square in display.board.indices {
            guard square != animationMove?.from, let piece = display.board[square] else { continue }
            drawPiece(piece, at: point(square), square: square)
        }
        if let move = animationMove, let piece = animationBoard?.board[move.from] {
            let from = point(move.from), to = point(move.to)
            ink.withAlphaComponent(0.25).setStroke()
            line(from, to)
            let t = animationProgress * animationProgress * (3 - 2 * animationProgress)
            let location = NSPoint(x: from.x + (to.x-from.x)*t, y: from.y + (to.y-from.y)*t)
            drawPiece(piece, at: location, square: move.from)
        }
        button("New game",NSRect(x:32,y:16,width:105,height:38))
        button("Undo",NSRect(x:147,y:16,width:78,height:38))
        text(animationMove != nil ? "Moving…" : thinking ? "Computer is thinking…" : "Click a piece, then a highlighted destination.", 240, 29, 13, ink)
    }
    func drawPiece(_ piece: Piece, at p: NSPoint, square: Int) {
        let circle = NSRect(x:p.x-25,y:p.y-25,width:50,height:50)
            NSColor.black.withAlphaComponent(0.18).setFill(); NSBezierPath(ovalIn: circle.offsetBy(dx:0,dy:-3)).fill()
            NSColor(srgbRed: 1, green: 0.93, blue: 0.76, alpha: 1).setFill(); NSBezierPath(ovalIn:circle).fill()
            let color = piece.side == .red ? red : ink
            color.setStroke(); let ring = NSBezierPath(ovalIn:circle.insetBy(dx:3,dy:3)); ring.lineWidth = 1.3; ring.stroke()
            if selected == square || targets.contains(square) {
                NSColor.systemGreen.setStroke(); let ring = NSBezierPath(ovalIn: circle.insetBy(dx:-2,dy:-2)); ring.lineWidth = 3; ring.stroke()
            }
            if piece.kind == .general && animationMove == nil && position.inCheck(piece.side) {
                NSColor.systemOrange.setStroke(); let ring = NSBezierPath(ovalIn:circle); ring.lineWidth = 4; ring.stroke()
            }
            text(piece.label,p.x,p.y-19,32,color,center:true)
    }
    func cancelAnimation() {
        animationTimer?.invalidate(); animationTimer = nil
        animationMove = nil; animationBoard = nil; animationProgress = 0
    }
    func reset() {
        cancelAnimation()
        generation += 1; thinking = false; position = Position(); history = []; moveHistory = []
        selected = nil; targets = []; ended = false; status = "Red to move — select a piece"; needsDisplay = true
    }
    func undo() {
        guard !history.isEmpty else { return }
        cancelAnimation()
        generation += 1; thinking = false
        position = history.removeLast(); moveHistory.removeLast()
        if computer && position.turn == .black && !history.isEmpty { position = history.removeLast(); moveHistory.removeLast() }
        selected = nil; targets = []; ended = false; refreshStatus(); needsDisplay = true
    }
    func refreshStatus() {
        let name = position.turn == .red ? "Red" : "Black"
        if position.moves().isEmpty {
            ended = true
            status = "\(position.turn == .red ? "Black" : "Red") wins — \(position.inCheck(position.turn) ? "checkmate" : "no legal moves")"
        } else if history.filter({ $0.key == position.key }).count >= 2 {
            ended = true; status = "Draw — position repeated three times"
        } else { status = "\(name) to move\(position.inCheck(position.turn) ? " — CHECK!" : " — select a piece")" }
    }
    func play(_ move: Move) {
        guard animationMove == nil, !ended, position.legal(move) else { return }
        animationBoard = position; animationMove = move; animationProgress = 0
        let name = position.turn == .red ? "Red" : "Black"
        history.append(position); moveHistory.append(move); position = position.applying(move)
        selected = nil; targets = []; status = "\(name) is moving…"; needsDisplay = true
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.animationProgress = min(1, CGFloat((ProcessInfo.processInfo.systemUptime-started)/self.moveDuration))
            self.needsDisplay = true
            if self.animationProgress >= 1 {
                self.cancelAnimation(); self.refreshStatus(); self.scheduleComputer()
            }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func scheduleComputer() {
        guard computer, position.turn == .black, !ended, !thinking, animationMove == nil else { return }
        thinking = true; needsDisplay = true
        let snapshot = position, token = generation
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let move = snapshot.computerMove()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard let self = self, token == self.generation else { return }
                self.thinking = false
                if let move = move { self.play(move) }
                else { self.refreshStatus(); self.needsDisplay = true }
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow,from:nil)
        if NSRect(x:358,y:718,width:115,height:40).contains(p) { if !computer { computer = true; reset() }; return }
        if NSRect(x:482,y:718,width:115,height:40).contains(p) { if computer { computer = false; reset() }; return }
        if NSRect(x:32,y:16,width:105,height:38).contains(p) { reset(); return }
        if NSRect(x:147,y:16,width:78,height:38).contains(p) { undo(); return }
        guard !ended, !thinking, animationMove == nil else { return }
        let x = Int(((p.x-originX)/step).rounded()), y = 9-Int(((p.y-originY)/step).rounded())
        guard (0..<9).contains(x), (0..<10).contains(y) else { return }
        let square = y*9+x, center = point(square)
        guard hypot(p.x-center.x,p.y-center.y) <= 29 else { return }
        if let from = selected, targets.contains(square) { play(Move(from:from,to:square)); return }
        if position.board[square]?.side == position.turn {
            selected = square; targets = position.moves().filter { $0.from == square }.map { $0.to }
        } else { selected = nil; targets = [] }
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { selected = nil; targets = []; needsDisplay = true }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(), appItem = NSMenuItem(), submenu = NSMenu()
        submenu.addItem(withTitle:"Quit Xiangqi",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appItem.submenu = submenu; menu.addItem(appItem); NSApp.mainMenu = menu
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:780),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "Xiangqi · Chinese Chess"
        let view = ChessView(frame:NSRect(x:0,y:0,width:620,height:780))
        window.contentView = view; window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular); app.delegate = delegate; app.run()
