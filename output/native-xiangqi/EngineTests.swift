import Foundation

@main struct EngineTests {
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        print("PASS: \(name)")
    }
    static func main() {
        let opening = Position()
        check(opening.board.compactMap { $0 }.count == 32, "32 opening pieces")
        check(opening.moves().count == 44, "44 legal opening moves")
        check(!opening.inCheck(.red) && !opening.inCheck(.black), "neither side starts in check")
        check(opening.legal(Move(from:54,to:45)), "pawn advances")
        check(!opening.legal(Move(from:54,to:55)), "pawn cannot move sideways before river")
        check(!opening.legal(Move(from:54,to:63)), "pawn cannot retreat")
        var p = Position(empty:true)
        p.board[85] = Piece(side:.red,kind:.general); p.board[4] = Piece(side:.black,kind:.general)
        check(p.inCheck(.red) && p.inCheck(.black), "facing generals are in check")
        p.board[49] = Piece(side:.red,kind:.rook)
        check(!p.legal(Move(from:49,to:48)), "cannot expose facing generals")
        p.board[49] = Piece(side:.red,kind:.pawn)
        check(p.pseudo(49,40) && !p.pseudo(49,48), "uncrossed pawn")
        p.board[49] = nil; p.board[40] = Piece(side:.red,kind:.pawn)
        check(p.pseudo(40,39) && p.pseudo(40,31) && !p.pseudo(40,49), "crossed pawn movement")
        p = Position(empty:true); p.board[64] = Piece(side:.red,kind:.cannon); p.board[1] = Piece(side:.black,kind:.rook)
        check(!p.pseudo(64,1), "cannon cannot capture without screen")
        p.board[37] = Piece(side:.red,kind:.pawn)
        check(p.pseudo(64,1), "cannon captures across one screen")
        check(!p.pseudo(64,28), "cannon cannot jump to empty destination")
        p.board[19] = Piece(side:.black,kind:.pawn)
        check(!p.pseudo(64,1), "cannon cannot capture across two screens")
        p = Position(empty:true); p.board[82] = Piece(side:.red,kind:.horse)
        check(p.pseudo(82,63), "horse moves in L shape")
        p.board[73] = Piece(side:.red,kind:.pawn)
        check(!p.pseudo(82,63), "horse leg blocking")
        p = Position(empty:true); p.board[83] = Piece(side:.red,kind:.elephant)
        check(p.pseudo(83,63), "elephant diagonal")
        p.board[73] = Piece(side:.red,kind:.pawn)
        check(!p.pseudo(83,63), "elephant eye blocking")
        p.board[47] = Piece(side:.red,kind:.elephant)
        check(!p.pseudo(47,27), "elephant cannot cross river")
        p = Position(empty:true); p.board[84] = Piece(side:.red,kind:.advisor)
        check(p.pseudo(84,76) && !p.pseudo(84,74), "advisor stays in palace")
        p.board[85] = Piece(side:.red,kind:.general)
        check(!p.pseudo(85,67), "general cannot move two squares")
        p = opening.applying(Move(from:54,to:45))
        check(p.turn == .black && p.board[54] == nil && p.board[45]?.kind == .pawn, "move updates board and turn")
        if let reply = p.computerMove() { check(p.legal(reply), "computer returns legal move") }
        else { fatalError("Computer failed to move") }
        var game = opening
        for _ in 0..<12 {
            guard let move = game.computerMove() else { break }
            check(game.legal(move), "computer self-play legal move")
            let side = game.turn; game = game.applying(move)
            check(!game.inCheck(side), "self-play does not leave own general in check")
        }
    }
}
