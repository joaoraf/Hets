{- |
Module      :  $Header$
Copyright   :  (c) Klaus L�ttich, C. Maeder, Uni Bremen 2005-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  non-portable (SPECIALIZE pragma, overlapping Typeable instances)

This module provides instances of
Common.ATerm.Conversion.ShATermConvertible.  The purpose is separation
of the class and those instances that are specialized for better
performance.
-}

-- specialization does not seem to gain anything

module Common.ATerm.ConvInstances() where

import Common.ATerm.Conversion
import Common.ATerm.AbstractSyntax
import Data.Graph.Inductive.Graph
import qualified Data.Graph.Inductive.Tree as Tree
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Rel as Rel
import qualified Common.OrderedMap as OMap
import Common.Id
import Common.Result
import Common.DynamicUtils

grTc :: TyCon
grTc = mkTyCon "Data.Graph.Inductive.Tree.Gr"

instance (Typeable a, Typeable b) => Typeable (Tree.Gr a b) where
  typeOf s = mkTyConApp grTc
             [ typeOf ((undefined :: Tree.Gr a b -> a) s)
             , typeOf ((undefined :: Tree.Gr a b -> b) s)]

instance (ShATermConvertible a,
          ShATermConvertible b) => ShATermConvertible (Tree.Gr a b) where
    toShATermAux att0 graph = do
       (att1, aa') <- toShATerm' att0 (labNodes graph)
       (att2, bb') <- toShATerm' att1 (labEdges graph)
       return $ addATerm (ShAAppl "Graph"  [ aa' , bb' ] []) att2
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl "Graph" [a,b] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    case fromShATerm' b att1 of { (att2, b') ->
                    (att2, mkGraph a' b') }}
            u -> fromShATermError "Data.Graph.Inductive.Tree.Gr" u

instance (Ord a, ShATermConvertible a, ShATermConvertible b)
    => ShATermConvertible (Map.Map a b) where
    {-# SPECIALIZE instance ShATermConvertible (Map.Map Id (Set.Set Id)) #-}
    {-# SPECIALIZE instance (ShATermConvertible a)
           => ShATermConvertible (Map.Map String (OMap.ElemWOrd a)) #-}
    {-# SPECIALIZE instance (ShATermConvertible b, Ord b)
      => ShATermConvertible (Map.Map Id (Set.Set b)) #-}
    toShATermAux att fm = do
      (att1, i) <- toShATerm' att $ Map.toAscList fm
      return $ addATerm (ShAAppl "Map" [i] []) att1
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl "Map" [a] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    (att1, Map.fromDistinctAscList a') }
            u -> fromShATermError "Map.Map" u

elemWOrdTc :: TyCon
elemWOrdTc = mkTyCon "Common.OrderedMap.ElemWOrd"

instance (Typeable a) => Typeable (OMap.ElemWOrd a) where
  typeOf s = mkTyConApp elemWOrdTc
             [typeOf ((undefined :: OMap.ElemWOrd a -> a) s)]

instance (ShATermConvertible a) => ShATermConvertible (OMap.ElemWOrd a) where
    toShATermAux att0 e = do
       (att1,aa') <- toShATerm' att0 (OMap.order e)
       (att2,bb') <- toShATerm' att1 (OMap.ele e)
       return $ addATerm (ShAAppl "EWOrd"  [ aa' , bb' ] []) att2
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl "EWOrd" [a,b] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    case fromShATerm' b att1 of { (att2, b') ->
                    (att2, OMap.EWOrd { OMap.order = a', OMap.ele = b'}) }}
            u -> fromShATermError "OMap.ElemWOrd" u

instance (Ord a,ShATermConvertible a) => ShATermConvertible (Set.Set a) where
    {-# SPECIALIZE instance ShATermConvertible (Set.Set Id) #-}
    toShATermAux att set = do
      (att1, i) <-  toShATerm' att $ Set.toAscList set
      return $ addATerm (ShAAppl "Set" [i] []) att1
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl "Set" [a] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    (att1, Set.fromDistinctAscList a') }
            u -> fromShATermError "Set.Set" u

relTc :: TyCon
relTc = mkTyCon "Rel.Rel"

instance (Typeable a) => Typeable (Rel.Rel a) where
  typeOf s = mkTyConApp relTc
             [typeOf ((undefined :: Rel.Rel a -> a) s)]

instance (Ord a,ShATermConvertible a) => ShATermConvertible (Rel.Rel a) where
    {-# SPECIALIZE instance ShATermConvertible (Rel.Rel Id) #-}
    toShATermAux att rel = do
      (att1, i) <-  toShATerm' att $ Rel.toMap rel
      return $ addATerm (ShAAppl "Rel" [i] []) att1
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl "Rel" [a] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    (att1, Rel.fromDistinctMap a') }
            u -> fromShATermError "Rel.Rel" u

instance (ShATermConvertible a) => ShATermConvertible (Maybe a) where
    {-# SPECIALIZE instance ShATermConvertible (Maybe Token) #-}
    toShATermAux att mb = case mb of
        Nothing -> return $ addATerm (ShAAppl "N" [] []) att
        Just x -> do
          (att1, x') <- toShATerm' att x
          return $ addATerm (ShAAppl "J" [x'] []) att1
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl "N" [] _ -> (att0, Nothing)
            ShAAppl "J" [a] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    (att1, Just a') }
            u -> fromShATermError "Prelude.Maybe" u

instance ShATermConvertible a => ShATermConvertible [a] where
    -- for compound Ids, Set.Set and Rel.Rel
    {-# SPECIALIZE instance ShATermConvertible [Id] #-}
    -- for Id
    {-# SPECIALIZE instance ShATermConvertible [Token] #-}
    -- for Token and all other Strings
    {-# SPECIALIZE instance ShATermConvertible [Char] #-}
    -- for all types in AST with [Pos]
    {-# SPECIALIZE instance ShATermConvertible [Pos] #-}
    toShATermAux att l = toShATermList' att l
    fromShATermAux ix att = fromShATermList' ix att

instance (ShATermConvertible a, ShATermConvertible b)
    => ShATermConvertible (a, b) where
    -- for Maps
    {-# SPECIALIZE instance ShATermConvertible (Id, Id) #-}
    {-# SPECIALIZE instance ShATermConvertible (Id, Set.Set Id) #-}
    {-# SPECIALIZE instance ShATermConvertible b
      => ShATermConvertible (Id, b) #-}
    {-# SPECIALIZE instance (Ord b, ShATermConvertible b)
      => ShATermConvertible (Id, Set.Set b) #-}
    -- for Graph nodes
    {-# SPECIALIZE instance ShATermConvertible b
      => ShATermConvertible (Int, b) #-}
    toShATermAux att0 (x,y) = do
      (att1, x') <- toShATerm' att0 x
      (att2, y') <- toShATerm' att1 y
      return $ addATerm (ShAAppl "" [x',y'] []) att2
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl "" [a,b] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    case fromShATerm' b att1 of { (att2, b') ->
                    (att2, (a', b'))}}
            u -> fromShATermError "(,)" u

instance (ShATermConvertible a, ShATermConvertible b, ShATermConvertible c)
    => ShATermConvertible (a, b, c) where
    -- for Graph labels
    {-# SPECIALIZE instance ShATermConvertible b
      => ShATermConvertible (Int,b,Int) #-}
    toShATermAux att0 (x,y,z) = do
      (att1, x') <- toShATerm' att0 x
      (att2, y') <- toShATerm' att1 y
      (att3, z') <- toShATerm' att2 z
      return $ addATerm (ShAAppl "" [x',y',z'] []) att3
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl "" [a,b,c] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    case fromShATerm' b att1 of { (att2, b') ->
                    case fromShATerm' c att2 of { (att3, c') ->
                    (att3, (a', b', c'))}}}
            u -> fromShATermError "(,,)" u

instance (ShATermConvertible a, ShATermConvertible b, ShATermConvertible c,
          ShATermConvertible d) => ShATermConvertible (a, b, c, d) where
    toShATermAux att0 (x,y,z,w) = do
      (att1, x') <- toShATerm' att0 x
      (att2, y') <- toShATerm' att1 y
      (att3, z') <- toShATerm' att2 z
      (att4, w') <- toShATerm' att3 w
      return $ addATerm (ShAAppl "" [x',y',z',w'] []) att4
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl "" [a,b,c,d] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    case fromShATerm' b att1 of { (att2, b') ->
                    case fromShATerm' c att2 of { (att3, c') ->
                    case fromShATerm' d att3 of { (att4, d') ->
                    (att4, (a', b', c', d'))}}}}
            u -> fromShATermError "(,,,)" u

_tc_PosTc :: TyCon
_tc_PosTc = mkTyCon "Pos"
instance Typeable Pos where
    typeOf _ = mkTyConApp _tc_PosTc []

_tc_RangeTc :: TyCon
_tc_RangeTc = mkTyCon "Range"
instance Typeable Range where
    typeOf _ = mkTyConApp _tc_RangeTc []

_tc_TokenTc :: TyCon
_tc_TokenTc = mkTyCon "Token"
instance Typeable Token where
    typeOf _ = mkTyConApp _tc_TokenTc []

_tc_IdTc :: TyCon
_tc_IdTc = mkTyCon "Id"
instance Typeable Id where
    typeOf _ = mkTyConApp _tc_IdTc []

instance ShATermConvertible Pos where
    toShATermAux att0 (SourcePos a b c) = do
        (att1, a') <- toShATerm' att0 a
        (att2, b') <- toShATerm' att1 b
        (att3, c') <- toShATerm' att2 c
        return $ addATerm (ShAAppl "P" [a',b',c'] []) att3
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl _ [a,b,c] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    case fromShATerm' b att1 of { (att2, b') ->
                    case fromShATerm' c att2 of { (att3, c') ->
                    (att3, SourcePos a' b' c') }}}
            u -> fromShATermError "Pos" u

instance ShATermConvertible Range where
    toShATermAux att0 (Range a) = do
        (att1, a') <- toShATerm' att0 a
        return $ addATerm (ShAAppl "R" [a'] []) att1
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl ('R' : _) [a] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    (att1, Range a') }
            u -> fromShATermError "Range" u

instance ShATermConvertible Token where
    toShATermAux att0 (Token a b) = do
        (att1, a') <- toShATerm' att0 a
        (att2, b') <- toShATerm' att1 b
        return $ addATerm (ShAAppl "T" [a',b'] []) att2
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl ('T' : _) [a,b] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    case fromShATerm' b att1 of { (att2, b') ->
                    (att2, Token a' b') }}
            u -> fromShATermError "Token" u

instance ShATermConvertible Id where
    toShATermAux att0 (Id a b c) = do
        (att1, a') <- toShATerm' att0 a
        (att2, b') <- toShATerm' att1 b
        (att3, c') <- toShATerm' att2 c
        return $ addATerm (ShAAppl "I" [a',b',c'] []) att3
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl ('I' : _) [a,b,c] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    case fromShATerm' b att1 of { (att2, b') ->
                    case fromShATerm' c att2 of { (att3, c') ->
                    (att3, Id a' b' c') }}}
            u -> fromShATermError "Id" u

_tc_DiagKindTc :: TyCon
_tc_DiagKindTc = mkTyCon "DiagKind"
instance Typeable DiagKind where
    typeOf _ = mkTyConApp _tc_DiagKindTc []

_tc_DiagnosisTc :: TyCon
_tc_DiagnosisTc = mkTyCon "Diagnosis"
instance Typeable Diagnosis where
    typeOf _ = mkTyConApp _tc_DiagnosisTc []

instance ShATermConvertible DiagKind where
    toShATermAux att0 Error = do
        return $ addATerm (ShAAppl "Error" [] []) att0
    toShATermAux att0 Warning = do
        return $ addATerm (ShAAppl "Warning" [] []) att0
    toShATermAux att0 Hint = do
        return $ addATerm (ShAAppl "Hint" [] []) att0
    toShATermAux att0 Debug = do
        return $ addATerm (ShAAppl "Debug" [] []) att0
    toShATermAux att0 MessageW = do
        return $ addATerm (ShAAppl "MessageW" [] []) att0
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl "Error" [] _ ->
                    (att0, Error)
            ShAAppl "Warning" [] _ ->
                    (att0, Warning)
            ShAAppl "Hint" [] _ ->
                    (att0, Hint)
            ShAAppl "Debug" [] _ ->
                    (att0, Debug)
            ShAAppl "MessageW" [] _ ->
                    (att0, MessageW)
            u -> fromShATermError "DiagKind" u

instance ShATermConvertible Diagnosis where
    toShATermAux att0 (Diag a b c) = do
        (att1, a') <- toShATerm' att0 a
        (att2, b') <- toShATerm' att1 b
        (att3, c') <- toShATerm' att2 c
        return $ addATerm (ShAAppl "Diag" [a',b',c'] []) att3
    fromShATermAux ix att0 =
        case getShATerm ix att0 of
            ShAAppl "Diag" [a,b,c] _ ->
                    case fromShATerm' a att0 of { (att1, a') ->
                    case fromShATerm' b att1 of { (att2, b') ->
                    case fromShATerm' c att2 of { (att3, c') ->
                    (att3, Diag a' b' c') }}}
            u -> fromShATermError "Diagnosis" u
