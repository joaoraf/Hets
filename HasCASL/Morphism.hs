{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2003
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable
    
Morphism on 'Env' (as for CASL)
-}

module HasCASL.Morphism where

import HasCASL.Le
import HasCASL.As
import HasCASL.AsToLe
import HasCASL.Unify
import HasCASL.Symbol
import HasCASL.MapTerm
import HasCASL.TypeDecl
import HasCASL.DataAna
import Common.Id
import Common.Keywords
import Common.Result
import Common.PrettyPrint
import Common.Lib.Pretty
import qualified Common.Lib.Map as Map

type IdMap = Map.Map Id Id

type FunMap = Map.Map (Id, TySc) (Id, TySc)

data Morphism = Morphism { msource :: Env
			 , mtarget :: Env
			 , classIdMap :: IdMap  -- ignore
			 , typeIdMap :: IdMap 
                         , funMap :: FunMap } 
                         deriving (Eq, Show)

instance PrettyPrint Morphism where
  printText0 ga m = 
      let tm = typeIdMap m 
	  fm = funMap m
	  ds = Map.foldWithKey ( \ (i, TySc s) (j, TySc t) l -> 
		(printText0 ga i <+> colon <+> printText0 ga s
		<+> text mapsTo	<+>	 
		printText0 ga j <+> colon <+> printText0 ga t) : l)
	       [] fm 
      in (if Map.isEmpty tm then empty
	 else text (typeS ++ sS) <+> printText0 ga tm)
         $$ (if Map.isEmpty fm then empty 
	     else text (opS ++ sS) <+> fsep (punctuate comma ds))
	 $$ nest 1 colon <+> braces (printText0 ga (msource m)) 
		    $$ nest 1 (text mapsTo)
		    <+> braces (printText0 ga (mtarget m))
      

mapType :: IdMap -> Type -> Type
-- include classIdMap later
mapType m ty = if Map.isEmpty m then ty else 
	      rename ( \ i k n ->
	       let t = TypeName i k n in
	       if n == 0 then 
		  case Map.lookup i m of
		  Just j -> TypeName j k 0
		  _ -> t
	       else t) ty

mapTypeScheme :: IdMap -> TypeScheme -> TypeScheme
-- rename clashing type arguments later
mapTypeScheme = mapTypeOfScheme . mapType

mapTySc :: IdMap -> TySc -> TySc
mapTySc m (TySc s1) = TySc $ mapTypeScheme m s1

mapSen :: Morphism -> Term -> Term
mapSen m = let tm = typeIdMap m in 
       mapTerm (mapFunSym tm (funMap m), mapType tm)

mapDatatypeDefn :: Morphism -> IdMap -> DatatypeDefn -> DatatypeDefn
mapDatatypeDefn m tm (DatatypeConstr i j k args alts) = 
    let tim = typeIdMap m
	rtm = Map.difference tim tm
	-- do not rename the types in the data type mapping
    in DatatypeConstr i (Map.findWithDefault j j tim)
		   k args $ map (mapAlt m tm rtm args $ TypeName j
				 (typeArgsListToKind args star) 0) alts

mapAlt :: Morphism -> IdMap -> IdMap -> [TypeArg] -> Type -> AltDefn -> AltDefn
mapAlt m tm rtm args dt (Construct i ts p sels) = 
    let sc = TypeScheme args 
	     ([] :=> getConstrType dt p (map (mapType tm) ts)) []
	(j, _) = mapFunSym (typeIdMap m) (funMap m) (i, sc)
    in Construct j (map (mapType rtm) ts) p sels
       -- not change (unused) selectors and (alas) partiality 

getDTMap :: [DatatypeDefn] -> IdMap 
getDTMap = foldr ( \ (DatatypeConstr i j _ _ _) m -> 
		   if i == j then m else
		   Map.insert i j m) Map.empty 

mapSentence :: Morphism -> Sentence -> Result Sentence
mapSentence m s = return $ case s of 
   Formula t -> Formula $ mapSen m t 
   DatatypeSen td -> DatatypeSen $ map (mapDatatypeDefn m $ getDTMap td) td
   ProgEqSen i sc pe ->
       let tm = typeIdMap m 
	   fm = funMap m 
	   f = mapFunSym tm fm
	   (ni, nsc) = f (i, sc) 
	   in ProgEqSen ni nsc $ mapEq (f,  mapType tm) pe

mapFunSym :: IdMap -> FunMap -> (Id, TypeScheme) -> (Id, TypeScheme)
mapFunSym tm fm (i, sc) = 
    let (j, TySc s) = mapFunEntry tm fm (i, TySc sc) in (j, s)

mapFunEntry :: IdMap -> FunMap -> (Id, TySc) -> (Id, TySc)
mapFunEntry tm fm p@(i, sc) = if Map.isEmpty tm && Map.isEmpty fm then p else 
    Map.findWithDefault (i, mapTySc tm sc) (i, sc) fm

mkMorphism :: Env -> Env -> Morphism
mkMorphism e1 e2 = Morphism e1 e2 Map.empty Map.empty Map.empty

embedMorphism :: Env -> Env -> Morphism
embedMorphism = mkMorphism

ideMor :: Env -> Morphism
ideMor e = embedMorphism e e

compMor :: Morphism -> Morphism -> Maybe Morphism
compMor m1 m2 = 
  if isSubEnv (mtarget m1) (msource m2) then 
      let tm2 = typeIdMap m2 
	  fm2 = funMap m2 in Just 
      (mkMorphism (msource m1) (mtarget m2))
      { typeIdMap = Map.foldWithKey ( \ i j -> 
		       Map.insert i $ Map.findWithDefault j j tm2)
			     tm2 $ typeIdMap m1
      , funMap = Map.foldWithKey ( \ p1 p2 -> 
		       Map.insert p1
		       $ mapFunEntry tm2 fm2 p2) fm2 $ funMap m1
      }
   else Nothing

inclusionMor :: Env -> Env -> Result Morphism
inclusionMor e1 e2 =
  if isSubEnv e1 e2
     then return (embedMorphism e1 e2)
     else pplain_error (ideMor initialEnv)
          (ptext "Attempt to construct inclusion between non-subsignatures:"
           $$ ptext "Singature 1:" $$ printText e1
           $$ ptext "Singature 2:" $$ printText e2)
           nullPos

symbMapToMorphism :: Env -> Env -> SymbolMap -> Result Morphism
symbMapToMorphism sigma1 sigma2 smap = do
  type_map1 <- Map.foldWithKey myIdMap (return Map.empty) $ typeMap sigma1
  fun_map1 <- Map.foldWithKey myAsMap (return Map.empty) $ assumps sigma1
  return (mkMorphism sigma1 sigma2)
	 { typeIdMap = type_map1
	 , funMap = fun_map1}
  where
  myIdMap i k m = do
    m1 <- m 
    sym <- maybeToResult nullPos 
             ("symbMapToMorphism - Could not map sort "++showId i "")
             $ Map.lookup (Symbol { symName = i
				  , symType = TypeAsItemType 
				               $ typeKind k
				  , symEnv = sigma1 }) smap
    return (Map.insert i (symName sym) m1)
  myAsMap i (OpInfos ots) m = foldr (insFun i) m ots
  insFun i ot m = do
    let osc = opType ot
    m1 <- m
    sym <- maybeToResult nullPos 
             ("symbMapToMorphism - Could not map op "++showId i "")
             $ Map.lookup (Symbol { symName = i
				  , symType = OpAsItemType osc
				  , symEnv = sigma1 }) smap
    k <- case symType sym of
        OpAsItemType sc -> return $ TySc sc
        _ -> plain_error (TySc osc)
              ("symbMapToMorphism - Wrong result symbol type for op"
               ++showId i "") nullPos 
    return (Map.insert (i, TySc osc) (symName sym, k) m1)

legalEnv :: Env -> Bool
legalEnv _ = True -- maybe a closure test?
legalMor :: Morphism -> Bool
legalMor m = let s = msource m
		 t = mtarget m
		 ts = typeIdMap m
		 fs = funMap m
	     in  
	     all (`elem` (Map.keys $ typeMap s)) 
		  (Map.keys ts)
	     && all (`elem` (Map.keys $ typeMap t))
		(Map.elems ts)
	     && all ((`elem` (Map.keys $ assumps s)) . fst)
		(Map.keys fs)
	     && all ((`elem` (Map.keys $ assumps t)) . fst)
		(Map.elems fs)

morphismUnion :: Morphism -> Morphism -> Result Morphism
morphismUnion m1 m2 = 
    do s <- merge (msource m1) $ msource m2
       t <- merge (mtarget m1) $ mtarget m2
       tm <- foldr ( \ (i, j) rm -> 
		     do m <- rm
		        case Map.lookup i m of
		          Nothing -> return $ Map.insert i j m
		          Just k -> if j == k then return m
		            else do 
		            Result [Diag Error 
			      ("incompatible mapping of type id: " ++ 
			       showId i " to: " ++ showId j " and: " 
			       ++ showId k "") $ posOfId i] $ Just ()
		            return m) 
	     (return $ typeIdMap m1) $ Map.toList $ typeIdMap m2
       fm <- foldr ( \ (isc@(i, _), jsc@(j, TySc sc1)) rm -> do
		     m <- rm
		     case Map.lookup isc m of
		       Nothing -> return $ Map.insert isc jsc m
		       Just ksc@(k, TySc sc2) -> if j == k && 
		         asSchemes 0 (equalSubs $ typeMap t) sc1 sc2  
		         then return m
		            else do 
		            Result [Diag Error 
			      ("incompatible mapping of op: " ++ 
			       showFun isc " to: " ++ showFun jsc " and: " 
			       ++ showFun ksc "") $ posOfId i] $ Just ()
		            return m) 
	     (return $ funMap m1) $ Map.toList $ funMap m2
       return (mkMorphism s t) 
		  { typeIdMap = tm
		  , funMap = fm }

showFun :: (Id, TySc) -> ShowS
showFun (i, TySc ty) = showId i . (" : " ++) . showPretty ty

morphismToSymbMap :: Morphism -> SymbolMap
morphismToSymbMap mor = 
  let
    src = msource mor
    tar = mtarget mor
    tm = typeIdMap mor
    typeSymMap = Map.foldWithKey ( \ i ti -> 
       let j = Map.findWithDefault i i tm
	   k = typeKind ti
	   in Map.insert (idToTypeSymbol src i k)
               $ idToTypeSymbol tar j k) Map.empty $ typeMap src
   in Map.foldWithKey
         ( \ i (OpInfos l) m ->
	     foldr ( \ oi -> 
	     let ty = opType oi 
                 (j, TySc t2) = mapFunEntry tm (funMap mor) (i, TySc ty)
             in	Map.insert (idToOpSymbol src i ty) 
                        (idToOpSymbol tar j t2)) m l) 
         typeSymMap $ assumps src
