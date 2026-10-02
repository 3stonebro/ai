import Foundation

enum Side: Int { case red, black; var other: Side { self == .red ? .black : .red } }
enum Kind { case general, advisor, elephant, horse, rook, cannon, pawn }
struct Piece {
    let side: Side
    let kind: Kind
    var label: String {
        switch kind {
        case .general: return side == .red ? "帥" : "將"
        case .advisor: return side == .red ? "仕" : "士"
        case .elephant: return side == .red ? "相" : "象"
        case .horse: return "馬"
        case .rook: return "車"
        case .cannon: return side == .red ? "炮" : "砲"
        case .pawn: return side == .red ? "兵" : "卒"
        }
    }
    var value: Int {
        switch kind { case .general: return 100000; case .rook: return 900; case .cannon: return 450; case .horse: return 400; case .elephant, .advisor: return 200; case .pawn: return 100 }
    }
}
struct Move: Equatable { let from: Int; let to: Int }
struct Position {
    var board = [Piece?](repeating: nil, count: 90)
    var turn: Side = .red
    init(empty: Bool = false) {
        guard !empty else { return }
        let row: [Kind] = [.rook, .horse, .elephant, .advisor, .general, .advisor, .elephant, .horse, .rook]
        for x in 0..<9 { board[x] = Piece(side: .black, kind: row[x]); board[81+x] = Piece(side: .red, kind: row[x]) }
        for x in [1,7] { board[18+x] = Piece(side: .black, kind: .cannon); board[63+x] = Piece(side: .red, kind: .cannon) }
        for x in [0,2,4,6,8] { board[27+x] = Piece(side: .black, kind: .pawn); board[54+x] = Piece(side: .red, kind: .pawn) }
    }
    func palace(_ x: Int, _ y: Int, _ side: Side) -> Bool { (3...5).contains(x) && (side == .red ? (7...9).contains(y) : (0...2).contains(y)) }
    func pseudo(_ from: Int, _ to: Int) -> Bool {
        guard from != to, (0..<90).contains(from), (0..<90).contains(to), let p = board[from], board[to]?.side != p.side else { return false }
        let x = from % 9, y = from / 9, tx = to % 9, ty = to / 9, dx = tx-x, dy = ty-y
        let ax = abs(dx), ay = abs(dy)
        func screens() -> Int {
            guard dx == 0 || dy == 0 else { return -1 }
            let step = dx == 0 ? (dy > 0 ? 9 : -9) : (dx > 0 ? 1 : -1)
            var at = from + step, count = 0
            while at != to { if board[at] != nil { count += 1 }; at += step }
            return count
        }
        switch p.kind {
        case .general:
            if board[to]?.kind == .general && dx == 0 && screens() == 0 { return true }
            return ax + ay == 1 && palace(tx,ty,p.side)
        case .advisor: return ax == 1 && ay == 1 && palace(tx,ty,p.side)
        case .elephant:
            return ax == 2 && ay == 2 && (p.side == .red ? ty >= 5 : ty <= 4) && board[(y+dy/2)*9+x+dx/2] == nil
        case .horse:
            if ax == 2 && ay == 1 { return board[y*9+x+dx/2] == nil }
            if ax == 1 && ay == 2 { return board[(y+dy/2)*9+x] == nil }
            return false
        case .rook: return screens() == 0
        case .cannon: return screens() == (board[to] == nil ? 0 : 1)
        case .pawn:
            if dx == 0 && dy == (p.side == .red ? -1 : 1) { return true }
            return (p.side == .red ? y <= 4 : y >= 5) && ay == 0 && ax == 1
        }
    }
    func inCheck(_ side: Side) -> Bool {
        guard let king = board.indices.first(where: { board[$0]?.side == side && board[$0]?.kind == .general }) else { return true }
        return board.indices.contains { board[$0]?.side == side.other && pseudo($0,king) }
    }
    func applying(_ move: Move) -> Position {
        var next = self; next.board[move.to] = next.board[move.from]; next.board[move.from] = nil; next.turn = turn.other; return next
    }
    func legal(_ move: Move) -> Bool {
        board[move.from]?.side == turn && pseudo(move.from,move.to) && !applying(move).inCheck(turn)
    }
    func moves() -> [Move] {
        var result: [Move] = []
        for from in board.indices where board[from]?.side == turn {
            for to in board.indices { let m = Move(from: from, to: to); if legal(m) { result.append(m) } }
        }
        return result
    }
    var key: String {
        board.map { p in guard let p = p else { return "." }; return "\(p.side.rawValue)\(p.label)" }.joined(separator: ",") + "\(turn.rawValue)"
    }
    func score(for side: Side) -> Int {
        board.enumerated().reduce(0) { total, entry in
            guard let p = entry.element else { return total }
            let advance = p.side == .red ? 9-entry.offset/9 : entry.offset/9
            let bonus = p.kind == .pawn ? advance * 12 : 0
            return total + (p.side == side ? 1 : -1) * (p.value + bonus)
        }
    }
    func computerMove() -> Move? {
        let options = moves().shuffled().sorted { (board[$0.to]?.value ?? 0) > (board[$1.to]?.value ?? 0) }
        var best: Move?, bestScore = Int.min
        for move in options {
            let next = applying(move), responses = next.moves()
            if responses.isEmpty { return move }
            var worst = Int.max
            for response in responses {
                worst = min(worst, next.applying(response).score(for: turn))
                if worst <= bestScore { break }
            }
            if worst > bestScore { bestScore = worst; best = move }
        }
        return best
    }
}
