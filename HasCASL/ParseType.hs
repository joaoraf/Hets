module ParseType where

import Id (Token(Token), Id(Id)) 
import Lexer ((<++>), (<<))
import Parsec
import Token (skipChar, makeToken, parseId)
import Type

oParen = skipChar '('
cParen = skipChar ')'

separatedBy :: (Token -> Parser a) -> Parser Token 
	    -> Token -> Parser [(Token, a)]
separatedBy p s t = do { r <- p t
		       ; l <- option [] (s >>= separatedBy p s)
		       ; return ((t, r) : l) 
		       }
sortId = parseId

primType :: Parser Type
primType = fmap (\i -> Type i []) sortId 
	   <|> (oParen >>= funType) << cParen

star = makeToken(string productSign <|> string altProductSign)

toId :: Token -> Id
toId i = Id [i] []

productType :: Token -> Parser Type
productType c = fmap makeProduct (separatedBy (const primType) star c)
    where makeProduct [(c, x)] = x
	  makeProduct [(_, x), (c, y)] = Type (toId c) [x, y]
	  makeProduct ((_, x) : l@(_ : _)) =  
	      let Type c m = makeProduct l in Type c (x:m) 

arrow = makeToken (string totalFunArrow <++> option "" (string partialSuffix))

funType :: Token -> Parser Type
funType c = fmap makeFuns (separatedBy productType arrow c)
    where makeFuns [(_, x)] = x
	  makeFuns ((_, x) : s@((c, _):_)) = 
	      let t = makeFuns s in Type (toId c) [x, t]

