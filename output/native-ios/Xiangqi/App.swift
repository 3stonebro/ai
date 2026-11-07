import UIKit
import SceneKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = GameController()
        self.window = window
        window.makeKeyAndVisible()
    }
}

final class GameController: UIViewController {
    let board = BoardView()
    let status = UILabel()
    let difficulty = UISegmentedControl(items: ["Easy", "Medium", "Hard"])
    let mode = UISegmentedControl(items: ["vs Computer", "Two players"])
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red:0.97,green:0.95,blue:0.9,alpha:1)
        let title = UILabel()
        title.text = "象棋  Xiangqi"; title.font = .boldSystemFont(ofSize:28); title.textColor = .systemRed
        mode.selectedSegmentIndex = 0
        mode.addTarget(self, action:#selector(changeMode), for:.valueChanged)
        difficulty.selectedSegmentIndex = 1
        difficulty.addTarget(self,action:#selector(changeDifficulty),for:.valueChanged)
        difficulty.accessibilityLabel = "Computer skill level"
        status.font = .systemFont(ofSize:16,weight:.medium); status.numberOfLines = 2; status.textAlignment = .center
        status.accessibilityTraits = .updatesFrequently
        let restart = UIButton(type:.system), undo = UIButton(type:.system)
        restart.setTitle("New game",for:.normal); undo.setTitle("Undo",for:.normal)
        restart.addTarget(self,action:#selector(newGame),for:.touchUpInside)
        undo.addTarget(board,action:#selector(BoardView.undo),for:.touchUpInside)
        let buttons = UIStackView(arrangedSubviews:[restart,undo]); buttons.distribution = .fillEqually
        let help = UILabel(); help.text = "Tap a piece, then a green destination. Red moves first."
        help.font = .systemFont(ofSize:13); help.numberOfLines = 2; help.textAlignment = .center; help.textColor = .darkGray
        let stack = UIStackView(arrangedSubviews:[title,mode,difficulty,status,board,buttons,help])
        stack.axis = .vertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo:safe.topAnchor,constant:12),
            stack.bottomAnchor.constraint(equalTo:safe.bottomAnchor,constant:-10),
            stack.centerXAnchor.constraint(equalTo:safe.centerXAnchor),
            stack.widthAnchor.constraint(equalTo:safe.widthAnchor,constant:-24),
            buttons.heightAnchor.constraint(equalToConstant:44),
            mode.heightAnchor.constraint(equalToConstant:34),
            difficulty.heightAnchor.constraint(equalToConstant:34)
        ])
        board.setContentHuggingPriority(.defaultLow,for:.vertical)
        board.onStatus = { [weak self] value in self?.status.text = value }
        board.refresh()
    }
    @objc func changeMode() { board.computer = mode.selectedSegmentIndex == 0; difficulty.isHidden = !board.computer; board.reset() }
    @objc func changeDifficulty() { board.level = difficulty.selectedSegmentIndex; board.reset() }
    @objc func newGame() { board.reset() }
}

final class BoardView: UIView {
    var position = Position()
    var history: [Position] = []
    var moves: [Move] = []
    var selected: Int?
    var targets: [Int] = []
    var computer = true, thinking = false, ended = false
    var level = 1
    var generation = 0
    var onStatus: ((String)->Void)?
    var moving: Move?
    var before: Position?
    var progress: CGFloat = 0
    var started: CFTimeInterval = 0
    var displayLink: CADisplayLink?
    let sceneView = SCNView()
    let world = SCNScene()
    let piecesRoot = SCNNode()
    let cameraNode = SCNNode()
    var animatedNode: SCNNode?
    var renderedKey = ""
    var faceTextures: [String: UIImage] = [:]
    let ink = UIColor(red:0.18,green:0.19,blue:0.2,alpha:1)
    override init(frame: CGRect) {
        super.init(frame:frame)
        isOpaque = false
        setupScene()
        addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tap(_:))))
        accessibilityLabel = "Chinese chess board"
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func cancel() { displayLink?.invalidate(); displayLink = nil; moving = nil; before = nil; progress = 0 }
    func reset() {
        generation += 1; cancel(); thinking = false; ended = false
        position = Position(); history = []; moves = []; selected = nil; targets = []; refresh()
    }
    @objc func undo() {
        guard !history.isEmpty else { return }
        generation += 1; cancel(); thinking = false; ended = false
        position = history.removeLast(); moves.removeLast()
        if computer && position.turn == .black && !history.isEmpty { position = history.removeLast(); moves.removeLast() }
        selected = nil; targets = []; refresh()
    }
    func refresh() {
        let side = position.turn == .red ? "Red" : "Black"
        if position.moves().isEmpty {
            ended = true
            onStatus?("\(position.turn == .red ? "Black" : "Red") wins — \(position.inCheck(position.turn) ? "checkmate" : "no legal moves")")
        } else if history.filter({$0.key == position.key}).count >= 2 {
            ended = true; onStatus?("Draw — threefold repetition")
        } else { onStatus?("\(side) to move\(position.inCheck(position.turn) ? " — CHECK!" : "")") }
        renderBoard()
    }
    @objc func tap(_ recognizer:UITapGestureRecognizer) {
        guard !ended, !thinking, moving == nil else { return }
        let location = recognizer.location(in:sceneView)
        let hits = sceneView.hitTest(location, options: nil)
        guard let hit = hits.first else { return }
        var node: SCNNode? = hit.node
        var touched: Int?
        while let current = node {
            if let name = current.name, name.hasPrefix("square-"), let value = Int(name.dropFirst(7)) { touched = value; break }
            node = current.parent
        }
        let x = Int((hit.worldCoordinates.x + 4).rounded())
        let y = Int((hit.worldCoordinates.z + 4.5).rounded())
        if touched == nil && (!(0..<9).contains(x) || !(0..<10).contains(y)) { return }
        let square = touched ?? (y*9+x)
        if let from = selected, targets.contains(square) { play(Move(from:from,to:square)); return }
        if position.board[square]?.side == position.turn {
            selected = square; targets = position.moves().filter{$0.from == square}.map{$0.to}
        } else { selected = nil; targets = [] }
        renderBoard()
    }
    func play(_ move:Move) {
        guard moving == nil, !ended, position.legal(move) else { return }
        before = position; moving = move; progress = 0
        history.append(position); moves.append(move); position = position.applying(move)
        selected = nil; targets = []
        onStatus?("\(before!.turn == .red ? "Red" : "Black") is moving…")
        started = CACurrentMediaTime()
        let link = CADisplayLink(target:self,selector:#selector(animate))
        displayLink = link; link.add(to:.main,forMode:.common)
        renderBoard()
    }
    @objc func animate() {
        progress = min(1,CGFloat((CACurrentMediaTime()-started)/0.95))
        renderBoard()
        if progress >= 1 { cancel(); refresh(); reply() }
    }
    func reply() {
        guard computer, position.turn == .black, !ended, !thinking, moving == nil else { return }
        thinking = true; onStatus?("Black is thinking…")
        let snapshot = position, token = generation, skill = level
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let move = snapshot.computerMove(level: skill)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.4) {
                guard let self = self, self.generation == token else { return }
                self.thinking = false
                if let move = move { self.play(move) } else { self.refresh() }
            }
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        sceneView.frame = bounds
        // Orthographic scale is vertical; allow room for the board on narrow phones.
        let aspect = max(0.1, bounds.width / max(1,bounds.height))
        cameraNode.camera?.orthographicScale = Double(max(11.7, 10.4/aspect) / 2)
    }
    func material(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial(); m.diffuse.contents = color; m.roughness.contents = 0.65
        m.lightingModel = .physicallyBased
        return m
    }
    func setupScene() {
        sceneView.scene = world; sceneView.backgroundColor = .clear
        sceneView.antialiasingMode = .multisampling4X
        sceneView.autoenablesDefaultLighting = false
        addSubview(sceneView)
        cameraNode.camera = SCNCamera(); cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.position = SCNVector3(0,15,8.5)
        cameraNode.look(at:SCNVector3(0,0,0))
        world.rootNode.addChildNode(cameraNode); sceneView.pointOfView = cameraNode
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 650; world.rootNode.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional
        sun.light?.intensity = 1100; sun.light?.castsShadow = true
        sun.light?.shadowRadius = 4; sun.light?.shadowColor = UIColor.black.withAlphaComponent(0.3)
        sun.eulerAngles = SCNVector3(-Float.pi/3,-Float.pi/5,0); world.rootNode.addChildNode(sun)
        let base = SCNBox(width:9.5,height:0.35,length:10.5,chamferRadius:0.15)
        base.materials = [material(UIColor(red:0.36,green:0.18,blue:0.08,alpha:1))]
        let board = SCNNode(geometry:base); board.position.y = -0.2; world.rootNode.addChildNode(board)
        let surface = SCNPlane(width:9.2,height:10.2)
        let wood = material(.white); wood.diffuse.contents = boardTexture(); surface.materials = [wood]
        let top = SCNNode(geometry:surface); top.eulerAngles.x = -.pi/2; top.position.y = -0.015
        world.rootNode.addChildNode(top)
        world.rootNode.addChildNode(piecesRoot)
        renderBoard()
    }
    func boardTexture() -> UIImage {
        let size = CGSize(width:920,height:1020)
        return UIGraphicsImageRenderer(size:size).image { context in
            let cg = context.cgContext
            UIColor(red:0.86,green:0.68,blue:0.43,alpha:1).setFill(); cg.fill(CGRect(origin:.zero,size:size))
            for i in 0..<180 {
                cg.setStrokeColor(UIColor.brown.withAlphaComponent(0.035).cgColor)
                cg.move(to:CGPoint(x:0,y:CGFloat(i)*6)); cg.addLine(to:CGPoint(x:920,y:CGFloat(i)*6+8)); cg.strokePath()
            }
            func pt(_ x:Int,_ y:Int)->CGPoint { CGPoint(x:60+x*100,y:60+y*100) }
            func line(_ a:CGPoint,_ b:CGPoint) { cg.move(to:a); cg.addLine(to:b); cg.strokePath() }
            cg.setStrokeColor(ink.cgColor); cg.setLineWidth(2)
            for y in 0..<10 { line(pt(0,y),pt(8,y)) }
            for x in 0..<9 { line(pt(x,0),pt(x,4)); line(pt(x,5),pt(x,9)) }
            line(pt(0,4),pt(0,5)); line(pt(8,4),pt(8,5))
            for y in [0,7] { line(pt(3,y),pt(5,y+2)); line(pt(5,y),pt(3,y+2)) }
            let attrs: [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize:44),.foregroundColor:ink]
            ("楚 河" as NSString).draw(at:CGPoint(x:190,y:482),withAttributes:attrs)
            ("漢 界" as NSString).draw(at:CGPoint(x:590,y:482),withAttributes:attrs)
        }
    }
    func face(_ piece:Piece)->UIImage {
        let key = "\(piece.side.rawValue)\(piece.label)"
        if let cached = faceTextures[key] { return cached }
        let image = UIGraphicsImageRenderer(size:CGSize(width:256,height:256)).image { ctx in
            UIColor(red:1,green:0.91,blue:0.7,alpha:1).setFill(); ctx.fill(CGRect(x:0,y:0,width:256,height:256))
            let color: UIColor = piece.side == .red ? UIColor(red:0.7,green:0.06,blue:0.04,alpha:1) : ink
            color.setStroke(); let ring = UIBezierPath(ovalIn:CGRect(x:15,y:15,width:226,height:226)); ring.lineWidth = 5; ring.stroke()
            let attrs: [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize:156,weight:.semibold),.foregroundColor:color]
            let label = piece.label as NSString, size = label.size(withAttributes:attrs)
            label.draw(at:CGPoint(x:(256-size.width)/2,y:(256-size.height)/2),withAttributes:attrs)
        }
        faceTextures[key] = image; return image
    }
    func pieceNode(_ piece:Piece, square:Int)->SCNNode {
        let body = SCNCylinder(radius:0.4,height:0.22); body.radialSegmentCount = 48
        body.materials = [material(UIColor(red:0.68,green:0.43,blue:0.2,alpha:1))]
        let node = SCNNode(geometry:body); node.name = "square-\(square)"
        // A textured disk above the cylinder keeps the Chinese glyph facing the camera.
        let disk = SCNPlane(width:0.79,height:0.79)
        let top = material(.white)
        let texture = face(piece)
        // Clip the square texture to the round face.
        top.diffuse.contents = UIGraphicsImageRenderer(size:texture.size).image { _ in
            UIBezierPath(ovalIn:CGRect(origin:.zero,size:texture.size)).addClip()
            texture.draw(at:.zero)
        }
        top.isDoubleSided = true; disk.materials = [top]
        let lid = SCNNode(geometry:disk); lid.eulerAngles.x = -.pi/2; lid.position.y = 0.112
        node.addChildNode(lid)
        node.position = location(square); return node
    }
    func location(_ square:Int)->SCNVector3 { SCNVector3(Float(square%9)-4,0.12,Float(square/9)-4.5) }
    func marker(_ square:Int,color:UIColor,radius:CGFloat = 0.45) {
        let ring = SCNTorus(ringRadius:radius,pipeRadius:0.035)
        let m = material(color); m.emission.contents = color.withAlphaComponent(0.35); ring.materials = [m]
        let node = SCNNode(geometry:ring); node.name = "square-\(square)"
        node.position = location(square); node.position.y = 0.025; piecesRoot.addChildNode(node)
    }
    func renderBoard() {
        let shown = before ?? position
        let key = shown.key + "\(selected ?? -1)\(targets)\(moves.last?.from ?? -1),\(moves.last?.to ?? -1),\(moving?.from ?? -1)"
        if key != renderedKey {
            renderedKey = key
            piecesRoot.childNodes.forEach { $0.removeFromParentNode() }; animatedNode = nil
            if let last = moves.last { marker(last.from,color:.systemYellow); marker(last.to,color:.systemYellow) }
            for s in targets { marker(s,color:.systemGreen,radius:shown.board[s] == nil ? 0.14 : 0.45) }
            if let s = selected { marker(s,color:.systemGreen) }
            for s in shown.board.indices {
                guard let piece = shown.board[s] else { continue }
                let node = pieceNode(piece,square:s); piecesRoot.addChildNode(node)
                if s == moving?.from { animatedNode = node }
                if moving == nil && piece.kind == .general && position.inCheck(piece.side) { marker(s,color:.systemOrange) }
            }
        }
        if let move = moving, let node = animatedNode {
            let a = location(move.from), b = location(move.to), t = Float(progress*progress*(3-2*progress))
            node.position = SCNVector3(a.x+(b.x-a.x)*t,0.12+0.22*sin(t * .pi),a.z+(b.z-a.z)*t)
        }
    }
}
