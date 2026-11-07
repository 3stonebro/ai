import Foundation
func require(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
var board = Position()
require(board.pieces.count == 32, "Initial army")
require(board.moves().count == 44, "Initial legal moves")
require(!board.check(.red) && !board.check(.black), "Initial generals safe")
let soldier = board.at(0,6)!
require(board.pseudo(soldier,0,5), "Soldier advances")
require(!board.pseudo(soldier,1,6), "Soldier cannot move sideways before river")
require(!board.pseudo(soldier,0,7), "Soldier cannot retreat")
let horse = board.at(1,9)!
require(board.pseudo(horse,2,7), "Horse legal move")
board.pieces.append(Piece(id:100,side:.red,kind:.soldier,x:1,y:8))
require(!board.pseudo(horse,2,7), "Horse leg blocked")
board = Position()
let elephant = board.at(2,9)!
require(board.pseudo(elephant,4,7), "Elephant diagonal")
board.pieces.append(Piece(id:101,side:.red,kind:.soldier,x:3,y:8))
require(!board.pseudo(elephant,4,7), "Elephant eye blocked")
board.pieces = [Piece(id:0,side:.red,kind:.general,x:4,y:9),Piece(id:1,side:.black,kind:.general,x:4,y:0),Piece(id:2,side:.red,kind:.rook,x:4,y:5)]
require(!board.moves().contains(Move(id:2,x:3,y:5)), "Cannot expose facing generals")
board.pieces.removeLast()
require(board.check(.red) && board.check(.black), "Flying generals")
board = Position()
let cannon = board.at(1,7)!
require(board.pseudo(cannon,1,0), "Cannon captures over one screen")
require(!board.pseudo(cannon,1,2), "Cannon cannot capture without screen")
for level in 0...2 {
    let position = Position()
    let move = position.computerMove(level:level)
    require(move != nil && position.moves().contains(move!), "AI supplies legal move")
}
print("Passed: initial setup, 44 opening moves, soldiers, horse legs, elephant eyes, cannon screens, flying generals, self-check, all AI levels")
