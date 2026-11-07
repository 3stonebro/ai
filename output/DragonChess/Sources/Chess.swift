import Foundation

enum Side: String, Sendable { case red, black
    var opponent: Side { self == .red ? .black : .red }
    var title: String { self == .red ? "Red" : "Black" }
}
enum Kind: Int, Sendable { case general, advisor, elephant, horse, rook, cannon, soldier
    var value: Int { [100000, 120, 120, 300, 600, 350, 70][rawValue] }
}
struct Piece: Identifiable, Equatable, Sendable {
    let id: Int
    let side: Side
    let kind: Kind
    var x: Int
    var y: Int
    var glyph: String { (side == .red ? ["帥","仕","相","傌","俥","炮","兵"] : ["將","士","象","馬","車","砲","卒"])[kind.rawValue] }
}
struct Move: Equatable, Sendable { let id: Int; let x: Int; let y: Int }
struct Position: Sendable {
    var pieces: [Piece] = []
    var turn: Side = .red
    init() {
        let back: [Kind] = [.rook,.horse,.elephant,.advisor,.general,.advisor,.elephant,.horse,.rook]
        for side in [Side.black, .red] {
            let y = side == .black ? 0 : 9
            for x in 0...8 { pieces.append(Piece(id: pieces.count, side: side, kind: back[x], x: x, y: y)) }
            for x in [1,7] { pieces.append(Piece(id: pieces.count, side: side, kind: .cannon, x: x, y: side == .black ? 2 : 7)) }
            for x in [0,2,4,6,8] { pieces.append(Piece(id: pieces.count, side: side, kind: .soldier, x: x, y: side == .black ? 3 : 6)) }
        }
    }
    func at(_ x: Int, _ y: Int) -> Piece? { pieces.first { $0.x == x && $0.y == y } }
    func palace(_ x: Int, _ y: Int, _ side: Side) -> Bool { (3...5).contains(x) && (side == .black ? 0...2 : 7...9).contains(y) }
    func pseudo(_ p: Piece, _ x: Int, _ y: Int) -> Bool {
        guard (0...8).contains(x), (0...9).contains(y), x != p.x || y != p.y, at(x,y)?.side != p.side else { return false }
        let dx = x-p.x, dy = y-p.y, ax = abs(dx), ay = abs(dy)
        var screens = 0
        if dx == 0 { for r in (min(y,p.y)+1)..<max(y,p.y) { if at(x,r) != nil { screens += 1 } } }
        else if dy == 0 { for c in (min(x,p.x)+1)..<max(x,p.x) { if at(c,y) != nil { screens += 1 } } }
        switch p.kind {
        case .general:
            if at(x,y)?.kind == .general && dx == 0 && screens == 0 { return true }
            return ax+ay == 1 && palace(x,y,p.side)
        case .advisor: return ax == 1 && ay == 1 && palace(x,y,p.side)
        case .elephant: return ax == 2 && ay == 2 && (p.side == .red ? y >= 5 : y <= 4) && at(p.x+dx/2,p.y+dy/2) == nil
        case .horse:
            return (ax == 2 && ay == 1 && at(p.x+dx/2,p.y) == nil) || (ax == 1 && ay == 2 && at(p.x,p.y+dy/2) == nil)
        case .rook: return (dx == 0 || dy == 0) && screens == 0
        case .cannon: return (dx == 0 || dy == 0) && screens == (at(x,y) == nil ? 0 : 1)
        case .soldier:
            let crossed = p.side == .red ? p.y <= 4 : p.y >= 5
            return (dx == 0 && dy == (p.side == .red ? -1 : 1)) || (crossed && ax == 1 && dy == 0)
        }
    }
    func check(_ side: Side) -> Bool {
        guard let king = pieces.first(where: { $0.side == side && $0.kind == .general }) else { return true }
        return pieces.contains { $0.side != side && pseudo($0,king.x,king.y) }
    }
    func applying(_ m: Move) -> Position {
        var next = self
        next.pieces.removeAll { $0.x == m.x && $0.y == m.y && $0.id != m.id }
        if let i = next.pieces.firstIndex(where: { $0.id == m.id }) { next.pieces[i].x = m.x; next.pieces[i].y = m.y }
        next.turn = turn.opponent
        return next
    }
    func moves() -> [Move] {
        var result: [Move] = []
        for p in pieces where p.side == turn {
            for y in 0...9 { for x in 0...8 where pseudo(p,x,y) {
                let m = Move(id:p.id,x:x,y:y)
                if !applying(m).check(turn) { result.append(m) }
            } }
        }
        return result
    }
    func score() -> Int { pieces.reduce(0) { $0 + ($1.side == turn ? 1 : -1) * ($1.kind.value + ($1.kind == .soldier ? ( $1.side == .red ? 9-$1.y : $1.y ) * 8 : 0)) } }
    func search(_ depth: Int, _ alpha: Int, _ beta: Int) -> Int {
        if depth == 0 { return score() }
        let legal = moves()
        if legal.isEmpty { return -1_000_000-depth }
        var best = alpha
        for m in legal.sorted(by: { (at($0.x,$0.y)?.kind.value ?? 0) > (at($1.x,$1.y)?.kind.value ?? 0) }) {
            best = max(best, -applying(m).search(depth-1,-beta,-best))
            if best >= beta { break }
        }
        return best
    }
    func computerMove(level: Int) -> Move? {
        let legal = moves()
        if level == 0 { return legal.randomElement() }
        let depth = level == 1 ? 1 : 2
        return legal.shuffled().map { ($0, -applying($0).search(depth,-2_000_000,2_000_000)) }.max { $0.1 < $1.1 }?.0
    }
}
