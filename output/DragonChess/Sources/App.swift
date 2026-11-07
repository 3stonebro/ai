import SwiftUI
import SceneKit

@MainActor final class Game: ObservableObject {
    @Published var position = Position()
    @Published var selected: Int?
    @Published var busy = false
    @Published var mode = 0
    @Published var level = 1
    @Published var history: [Position] = []
    var generation = 0
    var legal: [Move] { position.moves() }
    var status: String {
        if legal.isEmpty { return "\(position.turn.opponent.title) wins" }
        if busy { return position.turn == .black && mode == 0 ? "Computer is thinking…" : "Moving…" }
        return "\(position.turn.title) to move" + (position.check(position.turn) ? " · Check" : "")
    }
    func reset() { generation += 1; position = Position(); history = []; selected = nil; busy = false }
    func undo() {
        guard !busy, !history.isEmpty else { return }
        position = history.removeLast()
        if mode == 0 && position.turn == .black && !history.isEmpty { position = history.removeLast() }
        selected = nil; generation += 1
    }
    func tap(_ x: Int, _ y: Int) {
        guard !busy, !legal.isEmpty, mode == 1 || position.turn == .red else { return }
        if let id = selected, let m = legal.first(where: { $0.id == id && $0.x == x && $0.y == y }) { play(m); return }
        selected = position.at(x,y).flatMap { $0.side == position.turn ? $0.id : nil }
    }
    func play(_ m: Move) {
        history.append(position); selected = nil; busy = true; position = position.applying(m)
        let token = generation
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            guard token == generation else { return }
            if mode == 0 && position.turn == .black && !legal.isEmpty {
                let snapshot = position, difficulty = level
                let reply = await Task.detached { snapshot.computerMove(level: difficulty) }.value
                guard token == generation else { return }
                if let reply { history.append(position); position = position.applying(reply); try? await Task.sleep(for: .milliseconds(850)) }
            }
            guard token == generation else { return }
            busy = false
        }
    }
}

@main struct DragonChessApp: App { var body: some Scene { WindowGroup { ContentView() } } }
struct ContentView: View {
    @StateObject private var game = Game()
    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                Text("象棋 · XIANGQI").font(.system(size: 32, weight: .bold, design: .serif)).foregroundStyle(Color(red:0.96,green:0.82,blue:0.55))
                Text("The river divides. Strategy unites.").font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }.padding(.top, 14)
            Picker("Game mode", selection: $game.mode) { Text("Vs Computer").tag(0); Text("Two Players").tag(1) }.pickerStyle(.segmented).onChange(of: game.mode) { _,_ in game.reset() }
            if game.mode == 0 {
                Picker("Computer skill", selection: $game.level) { Text("Easy").tag(0); Text("Medium").tag(1); Text("Hard").tag(2) }.pickerStyle(.segmented).disabled(game.busy)
            }
            Text(game.status).font(.title3.bold()).foregroundStyle(.white).accessibilityAddTraits(.updatesFrequently)
            BoardView(game: game).frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 22))
            Text("Tap a piece, then a highlighted destination.").font(.callout).foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 16) {
                Button("Undo", systemImage: "arrow.uturn.backward") { game.undo() }.disabled(game.busy || game.history.isEmpty)
                Spacer()
                Button("New Game", systemImage: "arrow.clockwise") { game.reset() }
            }.font(.headline).buttonStyle(.bordered).tint(Color(red:0.96,green:0.82,blue:0.55))
        }.padding(.horizontal, 18).padding(.bottom, 12).background(Color(red:0.08,green:0.13,blue:0.14)).preferredColorScheme(.dark)
    }
}
struct BoardView: UIViewRepresentable {
    @ObservedObject var game: Game
    func makeCoordinator() -> Coordinator { Coordinator(game) }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(); view.backgroundColor = UIColor(red:0.10,green:0.17,blue:0.18,alpha:1)
        view.scene = context.coordinator.scene; view.autoenablesDefaultLighting = true; view.antialiasingMode = .multisampling4X
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        context.coordinator.setup(); return view
    }
    func updateUIView(_ view: SCNView, context: Context) { context.coordinator.refresh(game) }
    @MainActor final class Coordinator: NSObject {
        var game: Game
        let scene = SCNScene()
        var nodes: [Int:SCNNode] = [:]
        var renderedGeneration = -1
        let markers = SCNNode()
        init(_ game: Game) { self.game = game }
        func material(_ color: UIColor) -> SCNMaterial { let m = SCNMaterial(); m.diffuse.contents = color; m.roughness.contents = 0.65; return m }
        func point(_ x: Int, _ y: Int, height: Float = 0.24) -> SCNVector3 { SCNVector3(Float(x)-4,height,Float(y)-4.5) }
        func line(_ a: SCNVector3, _ b: SCNVector3) {
            let dx = b.x-a.x, dz = b.z-a.z
            let node = SCNNode(geometry: SCNBox(width:0.025,height:0.018,length:CGFloat(sqrt(dx*dx+dz*dz)),chamferRadius:0))
            node.geometry?.materials = [material(UIColor(red:0.30,green:0.18,blue:0.10,alpha:1))]
            node.position = SCNVector3((a.x+b.x)/2,0.025,(a.z+b.z)/2); node.eulerAngles.y = atan2(dx,dz); scene.rootNode.addChildNode(node)
        }
        func label(_ text: String, color: UIColor, size: CGFloat) -> SCNNode {
            let geometry = SCNText(string:text,extrusionDepth:0.005); geometry.font = .boldSystemFont(ofSize:size); geometry.flatness = 0.1; geometry.materials = [material(color)]
            let n = SCNNode(geometry:geometry); let (min,max) = n.boundingBox
            n.pivot = SCNMatrix4MakeTranslation((min.x+max.x)/2,(min.y+max.y)/2,0); n.eulerAngles.x = -.pi/2; return n
        }
        func setup() {
            let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 6.4
            camera.position = SCNVector3(0,17,8); camera.look(at:SCNVector3(0,0,0)); scene.rootNode.addChildNode(camera)
            let board = SCNNode(geometry:SCNBox(width:9.1,height:0.3,length:10.1,chamferRadius:0.16)); board.position.y = -0.15
            board.geometry?.materials = [material(UIColor(red:0.78,green:0.59,blue:0.35,alpha:1))]; scene.rootNode.addChildNode(board)
            for y in 0...9 { line(point(0,y),point(8,y)) }
            for x in 0...8 { if x == 0 || x == 8 { line(point(x,0),point(x,9)) } else { line(point(x,0),point(x,4)); line(point(x,5),point(x,9)) } }
            for y in [0,7] { line(point(3,y),point(5,y+2)); line(point(5,y),point(3,y+2)) }
            let river = label("楚 河       漢 界",color:.brown,size:0.45); river.position = SCNVector3(0,0.04,0); scene.rootNode.addChildNode(river)
            // Invisible square hit targets cover all intersections.
            for y in 0...9 { for x in 0...8 {
                let n = SCNNode(geometry:SCNPlane(width:0.96,height:0.96)); n.eulerAngles.x = -.pi/2; n.position = point(x,y,height:0.04); n.name = "cell:\(x):\(y)"
                let m = material(.clear); m.writesToDepthBuffer = false; n.geometry?.materials = [m]; scene.rootNode.addChildNode(n)
            } }
            scene.rootNode.addChildNode(markers)
        }
        func refresh(_ game: Game) {
            self.game = game
            if renderedGeneration != game.generation {
                nodes.values.forEach { $0.removeAllActions(); $0.removeFromParentNode() }; nodes = [:]
                renderedGeneration = game.generation
            }
            let ids = Set(game.position.pieces.map(\.id))
            for id in Array(nodes.keys) where !ids.contains(id) { nodes[id]?.removeFromParentNode(); nodes.removeValue(forKey:id) }
            for p in game.position.pieces {
                let n: SCNNode
                if let old = nodes[p.id] { n = old } else {
                    n = SCNNode(geometry: SCNCylinder(radius:0.40,height:0.23)); n.geometry?.materials = [material(UIColor(red:0.96,green:0.86,blue:0.63,alpha:1))]
                    let text = label(p.glyph,color:p.side == .red ? UIColor(red:0.68,green:0.08,blue:0.07,alpha:1) : UIColor(red:0.08,green:0.13,blue:0.15,alpha:1),size:0.53); text.position.y = 0.125; text.eulerAngles.y = p.side == .black ? .pi : 0; n.addChildNode(text)
                    n.position = point(p.x,p.y); scene.rootNode.addChildNode(n); nodes[p.id] = n
                }
                n.name = "cell:\(p.x):\(p.y)"
                let target = point(p.x,p.y)
                if n.position.x != target.x || n.position.z != target.z { n.runAction(.move(to:target,duration:0.8)) }
            }
            markers.childNodes.forEach { $0.removeFromParentNode() }
            if let id = game.selected {
                for m in game.legal where m.id == id {
                    let n = SCNNode(geometry:SCNCylinder(radius:0.14,height:0.025)); n.geometry?.materials = [material(.systemTeal)]; n.position = point(m.x,m.y,height:0.07); markers.addChildNode(n)
                }
                if let p = game.position.pieces.first(where:{$0.id == id}) {
                    let n = SCNNode(geometry:SCNTorus(ringRadius:0.43,pipeRadius:0.035)); n.geometry?.materials = [material(.systemYellow)]; n.position = point(p.x,p.y,height:0.14); markers.addChildNode(n)
                }
            }
        }
        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? SCNView else { return }
            for hit in view.hitTest(recognizer.location(in:view),options:[.searchMode:SCNHitTestSearchMode.all.rawValue]) {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, name.hasPrefix("cell:") {
                        let parts = name.split(separator:":"); if let x = Int(parts[1]), let y = Int(parts[2]) { game.tap(x,y); return }
                    }
                    node = current.parent
                }
            }
        }
    }
}
