
{- HetCATS/HasCASL/TypeDecl.hs
   $Id$
   Authors: Christian Maeder
   Year:    2003
   
   analyse type decls
-}

module HasCASL.TypeDecl where

import HasCASL.As
import HasCASL.AsUtils
import Common.AS_Annotation(item)
import HasCASL.ClassAna
import FiniteMap
import Common.Id
import HasCASL.Le
import Data.Maybe
import Control.Monad.State

import CASL.MixfixParser(getTokenList, expandPos)
import Common.Lib.Parsec
import Common.Lib.Parsec.Error

import HasCASL.PrintAs(showPretty)
import Common.Result
import HasCASL.TypeAna

compatibleTypeDefn :: TypeDefn -> TypeDefn -> Id -> [Diagnosis]
compatibleTypeDefn d1 d2 i = 
    if case (d1, d2) of 
	    (TypeVarDefn, TypeVarDefn) -> True
	    (TypeVarDefn, _) -> False
	    (_, TypeVarDefn) -> False
	    _ -> True
    then [] else [mkDiag Error "incompatible redeclaration of type" i]

addTypeKind :: TypeDefn -> Id -> Kind -> State Env ()
addTypeKind d i k = 
    do tk <- getTypeMap
       case lookupFM tk i of
	      Nothing -> putTypeMap $ addToFM tk i 
			 $ TypeInfo k [] [] d
	      Just (TypeInfo ok ks sups defn) -> 
		  let ds = eqKindDiag k ok in
			  if null ds then 
			     if any (eqKind SameSyntax k) (ok:ks)
				then addDiag $ mkDiag Warning 
				     "redeclared type" i
				else putTypeMap $ addToFM tk i 
					 $ TypeInfo ok
					       (k:ks) sups defn
			     else appendDiags ds

addSuperType :: Type -> Id -> State Env ()
addSuperType t i =
    do tk <- getTypeMap
       case lookupFM tk i of
	      Nothing -> error "addSuperType"
	      Just (TypeInfo ok ks sups defn) -> 
				putTypeMap $ addToFM tk i 
					      $ TypeInfo ok ks (t:sups) defn

anaTypeItem :: GenKind -> Instance -> TypeItem -> State Env ()
anaTypeItem _ inst (TypeDecl pats kind _) = 
    do k <- anaKind kind
       let Result ds (Just is) = convertTypePatterns pats
       appendDiags ds
       mapM_ (anaTypeId NoTypeDefn inst kind) is   
anaTypeItem _ inst (SubtypeDecl pats t _) = 
    do sup <- anaType t
       let Result ds (Just is) = convertTypePatterns pats
       appendDiags ds
       mapM_ (anaTypeId NoTypeDefn inst star) is   
       mapM_ (addSuperType t) is

anaTypeItem _ inst (IsoDecl pats _) = 
    do let Result ds (Just is) = convertTypePatterns pats
       appendDiags ds
       mapM_ (anaTypeId NoTypeDefn inst star) is
       mapM_ ( \ i -> mapM_ (addSuperType (TypeName i 0)) is) is 

anaTypeItem _ inst (SubtypeDefn pat v t f ps) = 
    do (mk, newT) <- anaType t
       k <- case mk of 
	      Nothing -> return star
	      Just k -> do appendDiags $ eqKindDiag k star 
			   return k
       addDiag $ Diag Warning ("unchecked formula '" ++ showPretty f "'")
		   $ firstPos [v] ps
       let Result ds m = convertTypePattern pat
       appendDiags ds
       case m of 
	      Nothing -> return ()
	      Just i -> do anaTypeId (Supertype v newT $ item f) 
				     inst k i
			   addSuperType newT i
	   
anaTypeItem _ inst (AliasType pat mk sc _) = 
    do (ik, newPty) <- anaTypeScheme mk sc
       let Result ds m = convertTypePattern pat
       appendDiags ds
       case (m, ik) of 
	      (Just i, Just ki) -> anaTypeId (AliasTypeDefn newPty) inst ki i 
	      _ -> return ()

anaTypeItem gk inst (Datatype d) = anaDatatype gk inst d 

anaDatatype :: GenKind -> Instance -> DatatypeDecl -> State Env ()
anaDatatype genKind inst (DatatypeDecl pat kind _alts derivs _) =
    do k <- anaKind kind
       case derivs of 
		   Just c -> anaClass c
		   Nothing -> return $ Intersection [] [] -- ignore
       let Result ds m = convertTypePattern pat
       appendDiags ds
       case m of 
	      Nothing -> return ()
	      Just i -> 
		  do -- newAlts <- anaAlts i alts 
		     anaTypeId (DatatypeDefn genKind) inst k i 

-- TO DO analyse alternatives and add them to Datatype Defn
-- anaAlts :: Id -> 

anaTypeScheme :: Maybe Kind -> TypeScheme -> State Env (Maybe Kind, TypeScheme)
anaTypeScheme mk (TypeScheme tArgs (q :=> ty) p) =
    do k <- case mk of 
	    Nothing -> return Nothing
	    Just j -> fmap Just $ anaKind j
       tm <- getTypeMap    -- save global variables  
       mapM_ anaTypeArgs tArgs
       (ik, newTy) <- anaType ty
       let newPty = TypeScheme tArgs (q :=> newTy) p
       sik <- case ik of
	      Nothing -> return k
	      Just sk -> do let newK = typeArgsListToKind tArgs sk
			    case k of 
			        Nothing -> return ()
			        Just ki -> appendDiags $ eqKindDiag ki newK
			    return $ Just newK
       putTypeMap tm       -- forget local variables 
       return (sik, newPty)

typeArgsListToKind :: [TypeArgs] -> Kind -> Kind
typeArgsListToKind tArgs k = 
    if null tArgs then k
       else typeArgsListToKind (init tArgs) 
	    (KindAppl (typeArgsToKind $ last tArgs) k []) 

typeArgsToKind :: TypeArgs -> Kind
typeArgsToKind (TypeArgs l ps) = if length l == 1 then typeArgToKind $ head l 
				 else ProdClass (map typeArgToKind l) ps
typeArgToKind :: TypeArg -> Kind
typeArgToKind (TypeArg _ k _ _) = k

anaTypeVarDecl :: TypeArg -> State Env ()
anaTypeVarDecl(TypeArg t k _ _) = 
    do nk <- anaKind k
       addTypeKind TypeVarDefn t k

anaTypeArgs :: TypeArgs -> State Env ()
anaTypeArgs(TypeArgs l _) = mapM_ anaTypeVarDecl l


kindArity :: ApplMode -> Kind -> Int
kindArity m (KindAppl k1 k2 _) =
    case m of 
	       TopLevel -> kindArity OnlyArg k1 + 
			   kindArity TopLevel k2
	       OnlyArg -> 1
kindArity m (ProdClass ks _) = 
    case m of TopLevel -> 0
	      OnlyArg -> sum $ map (kindArity m) ks
kindArity m (ExtClass k _ _) = kindArity m k
kindArity m (PlainClass _) = case m of
			     TopLevel -> 0
			     OnlyArg -> 1

anaTypeId :: TypeDefn -> Instance -> Kind -> Id -> State Env ()
-- type args not yet considered for kind construction 
anaTypeId defn _ kind i@(Id ts _ _)  = 
    let n = length $ filter isPlace ts 
    in if n == 0 || n == kindArity TopLevel kind then
       addTypeKind defn i kind
       else addDiag $ mkDiag Error "wrong arity of" i

convertTypePatterns :: [TypePattern] -> Result [Id]
convertTypePatterns [] = Result [] $ Just []
convertTypePatterns (s:r) =
    let Result d m = convertTypePattern s
	Result ds (Just l) = convertTypePatterns r
	in case m of 
		  Nothing -> Result (d++ds) $ Just l
		  Just i -> Result (d++ds) $ Just (i:l)

convertTypePattern, makeMixTypeId :: TypePattern -> Result Id
convertTypePattern (TypePattern t _ _) = return t
convertTypePattern(TypePatternToken t) = 
    if isPlace t then fatal_error ("illegal type '__'") (tokPos t)
       else return $ (simpleIdToId t)

convertTypePattern t =
    if {- hasPlaces t && -} hasTypeArgs t then
       fatal_error ( "arguments in type patterns not yet supported")
		   -- "illegal mix of '__' and '(...)'"  
                   (posOfTypePattern t)
    else makeMixTypeId t

-- TODO trailing places are not necessary for curried kinds
-- and should be ignored to avoid different Ids "Pred" and "Pred__"

typePatternToTokens :: TypePattern -> [Token]
typePatternToTokens (TypePattern ti _ _) = getTokenList True ti
typePatternToTokens (TypePatternToken t) = [t]
typePatternToTokens (MixfixTypePattern ts) = concatMap typePatternToTokens ts
typePatternToTokens (BracketTypePattern pk ts ps) =
    let tts = map typePatternToTokens ts 
	expand = expandPos (:[]) in
	case pk of 
		Parens -> if length tts == 1 && 
			  length (head tts) == 1 then head tts
			  else concat $ expand "(" ")" tts ps
		Squares -> concat $ expand "[" "]" tts ps 
		Braces ->  concat $ expand "{" "}" tts ps
typePatternToTokens (TypePatternArgs as) =
    map ( \ (TypeArg v _ _ _) -> Token "__" (posOfId v)) as

-- compound Ids not supported yet
getToken :: GenParser Token st Token
getToken = token tokStr tokPos Just

parseTypePatternId :: GenParser Token st Id
parseTypePatternId =
    do ts <- many1 getToken 
       return $ Id ts [] []

makeMixTypeId t = 
    case parse parseTypePatternId "" (typePatternToTokens t) of
    Left err -> fatal_error (showErrorMessages "or" "unknown parse error" 
                             "expecting" "unexpected" "end of input"
			     (errorMessages err)) 
		(errorPos err)
    Right x -> return x

hasPlaces, hasTypeArgs :: TypePattern -> Bool
hasPlaces (TypePattern _ _ _) = False
hasPlaces (TypePatternToken t) = isPlace t
hasPlaces (MixfixTypePattern ts) = any hasPlaces ts
hasPlaces (BracketTypePattern Parens _ _) = False
hasPlaces (BracketTypePattern _ ts _) = any hasPlaces ts
hasPlaces (TypePatternArgs _) = False

hasTypeArgs (TypePattern _ _ _) = True
hasTypeArgs (TypePatternToken _) = False
hasTypeArgs (MixfixTypePattern ts) = any hasTypeArgs ts
hasTypeArgs (BracketTypePattern Parens _ _) = True
hasTypeArgs (BracketTypePattern _ ts _) = any hasTypeArgs ts
hasTypeArgs (TypePatternArgs _) = True
