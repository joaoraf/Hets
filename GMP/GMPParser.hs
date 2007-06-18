---------------------------------------------------------------------------------
-- the Generic Model Parser Abstract Syntax
-- Copyright 2007, Lutz Schroeder and Georgel Calin
---------------------------------------------------------------------------------

module GMPParser where

import Text.ParserCombinators.Parsec
import qualified Text.ParserCombinators.Parsec.Token as P
import Text.ParserCombinators.Parsec.Expr
import Text.ParserCombinators.Parsec.Language

import qualified Data.Bits as Bits
import qualified Data.Set as Set

import GMPAS
---------------------------------------------------------------------------------
-- Modal Logic Class
---------------------------------------------------------------------------------
class ModalLogic a where
    parseIndex :: Parser a
--    matchRo :: ???     -- step 3
--    getClause :: ???   -- step 4

instance ModalLogic ModalK where        -- K modal logic index
    parseIndex = return (ModalK ())
instance ModalLogic ModalKD where       -- KD modal logic index
    parseIndex = return (ModalKD ())
--- integer parseIndex-----------------------------------------------------------
instance ModalLogic Integer where   
    parseIndex = natural
--- characters parseIndex--------------------------------------------------------
instance ModalLogic Kars where
    parseIndex =  do l <- letter 
                     ;Kars i <- parseIndex 
                     ;return (Kars (l:i))
              <|> do return (Kars [])
--- bit-string parseIndex -------------------------------------------------------
revbInt x size
    = let
        revaux (x,size,y,i)
            = if (i == (size+1))
                then 0
                else let y = revaux(x,size,y,i+1)
                        in if (Bits.testBit x i)
                            then Bits.setBit y (size-i)
                            else Bits.clearBit y (size-i)
      in revaux(x,size,0,0)

bitParse i =  do try(char('0'))
                 ;(BitString n, size) <- bitParse (i+1)
                 ;return((BitString(Bits.clearBit n i), size))
          <|> do try(char('1'))
                 ;(BitString n, size) <- bitParse (i+1)
                 ;return((BitString(Bits.setBit n i), size))
          <|> return ((BitString 0), i-1)
          <?> "GMPParse.bitParse"

instance ModalLogic BitString where
    parseIndex = do (BitString rres,size) <- bitParse 0 
                    ;let res = revbInt rres size
                    ;return (BitString res)
---------------------------------------------------------------------------------
-- SAT Decidability Algorithm
-- The folowing is a sketch of the algorithm and will need 
-- many other auxiliary things
---------------------------------------------------------------------------------
{-
checkSAT = do f <- par5er
           ; H <- guessPV f
           ; Ro = chooseCC H
           ; R = chooseRC Ro
           ; c = guessClause R
           ; res = checkSAT c R Ro
           ; return res
-}
---------------------------------------------------------------------------------
-- 1. Guess Pseudovaluation H for f
---------------------------------------------------------------------------------
{- first test the "genF" list and after the list given by "genTV"
until we get to "genF" if f is unsatisfiable -}
-- guessPV
-- modify the set truth values
--genTV :: Set (BoolTVandMA -> Set TVandMA
{- needs some adjustment 
genTV s =
    case s of
        (Set.empty) -> Set.empty
        _ -> if not(null s) then
              let ((t,x),y) = Set.deleteFindMin s in 
               if (t == False)
                then (insert (True,x) y)
                else (insert (False,x) genTV(y))
-}
-- Junctor evaluation
jmap :: Junctor -> Bool -> Bool -> Bool
jmap j x y =
    case j of
        And -> and([x,y])
        Or -> or([x,y])
        If -> or([not(x),y])
        Fi -> or([x,not(y)])
        Iff -> and([or([not(x),y]),or([x,not(y)])])
{-
eval s f = 
    case f of
        T -> True
        F -> False
        Neg f1 -> not(eval s f1)
        Junctor f1 j f2 -> (jmap j (eval s f1) (eval s f2))
        Mapp i f1 -> 
-}
setMA f =                                  -- make Modal Atoms set from Formula f
    case f of
        T -> Set.empty
        F -> Set.empty
        Neg f1 -> setMA f1
        Junctor f1 j f2 -> Set.union (setMA f1) (setMA f2)
        Mapp i f1 -> Set.insert (False,f1) Set.empty
---------------------------------------------------------------------------------
-- 2. Choose a contracted clause Ro /= F over MA(H) s.t. H "PL-entails" ~Ro
---------------------------------------------------------------------------------
-- chooseCC

-- 5. Recursively check that ~c(R,Ro) is satisfiable.
-- checkS
---------------------------------------------------------------------------------
-- Parser for polymorphic (Formula,a) Type
---------------------------------------------------------------------------------
par5er :: ModalLogic a => Parser (Formula a) -- main parser
par5er = do f <- prim; option (f) (inf f)
      <?> "GMPParser.par5er"

junc :: Parser Junctor -- junctor parser
junc =  do try(string "/\\"); whiteSpace; return And
    <|> do try(string "\\/"); whiteSpace; return Or
    <|> do try(string "->");  whiteSpace; return If
    <|> do try(string "<->"); whiteSpace; return Iff
    <|> do try(string "<-");  whiteSpace; return Fi
    <?> "GMPParser.junc"

inf :: ModalLogic a => (Formula a)-> Parser (Formula a)-- infix parser
inf f1 =
    do iot <- junc; f2 <-par5er; return $ Junctor f1 iot f2
    <?> "GMPParser.inf"

prim :: ModalLogic a => Parser (Formula a)  -- primitive parser
prim = 
        do try(string "F")
           ;whiteSpace
           ;return F
    <|> do try(string "T")
           ;whiteSpace
           ;return T
    <|> do try(string "~")
           ;whiteSpace
           ;f <- par5er
           ;return $ Neg f
    <|> do try(char '(')
           ;whiteSpace
           ;f <- par5er
           ;whiteSpace
           ;char ')'
           ;whiteSpace
           ;return f
    <|> do try(char '[')
           ;whiteSpace
           ;i <- parseIndex
           ;whiteSpace
           ;char ']'
           ;whiteSpace
           ;f <-par5er
           ;return $ Mapp (Mop i Square) f
    <|> do try(char '<')
           ;whiteSpace
           ;i <- parseIndex
           ;whiteSpace
           ;char '>'
           ;whiteSpace
           ;f <- par5er
           ;return $ Mapp (Mop i Angle) f
    <?> "GMPParser.prim"
---------------------------------------------------------------------------------
-- Funtion to run parser & print
---------------------------------------------------------------------------------
runLex :: Show b => Parser b -> String -> IO ()
runLex p input = run (do 
    whiteSpace
    ; x <- p
    ; eof
    ; return x
    ) input

run :: Show a => Parser a -> String -> IO ()
run p input
        = case (parse p "" input) of
                Left err -> do putStr "parse error at "
                               ;print err
                Right x -> print x

---------------------------------------------------------------------------------
-- The lexer
---------------------------------------------------------------------------------
lexer            = P.makeTokenParser gmpDef

lexeme          = P.lexeme lexer
parens          = P.parens lexer
braces          = P.braces lexer
semiSep         = P.semiSep lexer
semiSep1        = P.semiSep1 lexer
commaSep        = P.commaSep lexer
commaSep1       = P.commaSep1 lexer
whiteSpace      = P.whiteSpace lexer 
symbol          = P.symbol lexer
identifier      = P.identifier lexer
reserved        = P.reserved lexer
natural         = P.natural lexer


gmpDef
    = haskellStyle
    { identStart        = letter
    , identLetter       = alphaNum <|> oneOf "_'" -- ???
    , opStart           = opLetter gmpDef
    , opLetter          = oneOf "\\-</~[]"
    , reservedOpNames   = ["~","->","<-","<->","/\\","\\/","[]"]
    }
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------
