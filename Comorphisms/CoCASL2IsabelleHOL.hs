{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski and Uni Bremen 2003
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

   
   The embedding comorphism from CoCASL to Isabelle-HOL.

-}

{- todo: 
    encoding of cofreeness
    modal formulas
-}

module Comorphisms.CoCASL2IsabelleHOL where

import Logic.Logic
import Logic.Comorphism
import Data.List as List
import Data.Maybe
import Data.Char
import Debug.Trace
-- CoCASL
import CoCASL.Logic_CoCASL
import CoCASL.CoCASLSign
import CoCASL.AS_CoCASL
import CoCASL.StatAna
import CASL.AS_Basic_CASL
import CASL.Morphism
import Comorphisms.CASL2IsabelleHOL

-- Isabelle
import Isabelle.IsaSign as IsaSign
import Isabelle.IsaConsts
import Isabelle.Logic_Isabelle


-- | The identity of the comorphism
data CoCASL2IsabelleHOL = CoCASL2IsabelleHOL deriving (Show)

instance Language CoCASL2IsabelleHOL -- default definition is okay

instance Comorphism CoCASL2IsabelleHOL
               CoCASL ()
               C_BASIC_SPEC CoCASLFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               CSign 
               CoCASLMor
               CASL.Morphism.Symbol CASL.Morphism.RawSymbol ()
               Isabelle () () IsaSign.Sentence () ()
               IsaSign.Sign 
               () () () ()  where
    sourceLogic _ = CoCASL
    sourceSublogic _ = ()
    targetLogic _ = Isabelle
    targetSublogic _ = ()
    map_theory _ = transTheory sigTrCoCASL formTrCoCASL
    --map_morphism _ morphism1 -> Maybe morphism2
    map_sentence _ sign =
      return . mapSen formTrCoCASL sign
    --map_symbol :: cid -> symbol1 -> Set symbol2


-- | extended signature translation for CoCASL
sigTrCoCASL :: SignTranslator C_FORMULA CoCASLSign
sigTrCoCASL _ _ = id

conjs :: [Term] -> Term
conjs l = if null l then true else foldr1 binConj l

-- | extended formula translation for CoCASL
formTrCoCASL :: FormulaTranslator C_FORMULA CoCASLSign
formTrCoCASL sign (CoSort_gen_ax sorts ops _) = 
  foldr (quantifyIsa "All") phi (predDecls++[("u",ts),("v",ts)])
  where
  ts = transSort $ head sorts
  -- phi expresses: all bisimulations are the equality
  phi = prems `binImpl` concls
  -- indices and predicates for all involved sorts
  indices = [0..length sorts - 1]
  predDecls = zip [rvar i | i<-indices] (map binPred sorts)
  binPred s = let s' = transSort s in mkCurryFunType [s',s'] boolType
  -- premises: all relations are bisimulations
  prems = conjs (map prem (zip sorts indices))
  {- generate premise for s, where s is the i-th sort
     for all x,y of that sort, 
      if all sel_j(x) R_j sel_j(y), where sel_j ranges over the selectors for s
      then x R y
     here, R_i is the relation for the result type of sel_j, or the equality
  -}
  prem (s,i) = 
    let -- get all selectors with first argument sort s
        sels = List.filter isSelForS ops
        isSelForS (Qual_op_name _ t _) = case (args_OP_TYPE t) of
           (s1:_) -> s1 == s
           _ -> False 
        isSelForS _ = False
        premSel opsymb@(Qual_op_name n t _) =
         let -- get extra parameters of the selectors
             args = tail $ args_OP_TYPE t
             indicesArgs = [1..length args]
             res = res_OP_TYPE t
             -- variables for the extra parameters
             varDecls = zip [xvar i | i<-indicesArgs] (map transSort args)
             -- the selector ...
--(c)             top = Const (transOP_SYMB sign opsymb) noType isaTerm
             top = Const (transOP_SYMB sign opsymb) -- noType 
             -- applied to x and extra parameter vars
             appFold = foldl ( \ t1 t2 -> App t1 t2 IsCont)
             rhs = appFold (App top (var "x") IsCont) 
                       (map (var . xvar) indicesArgs)
             -- applied to y and extra parameter vars
             lhs = appFold (App top (var "y") IsCont) 
                             (map (var . xvar) indicesArgs)
             chi = -- is the result of selector non-observable? 
                   if res `elem` sorts
                     -- then apply corresponding relation
                     then App (App (var $ 
                                    rvar (fromJust (findIndex (==res) sorts)))
                               rhs NotCont) lhs NotCont
                     -- else use equality
                     else binEq rhs lhs
          in foldr (quantifyIsa "All") chi varDecls
        prem1 = conjs (map premSel sels)
        concl1 = App (App (var $ rvar i) (var "x") NotCont) (var "y") NotCont
        psi = concl1 `binImpl` prem1
        typS = transSort s
     in foldr (quantifyIsa "All") psi [("x",typS),("y",typS)]
  -- conclusion: all relations are the equality
  concls = conjs (map concl (zip sorts indices))
  concl (s,i) = binImpl (App (App (var $ rvar i) (var "u") NotCont) 
                     (var "v") NotCont) 
                             (binEq (var "u") (var "v"))
formTrCoCASL sign (Box mod phi _) = 
   trace "WARNING: ignoring modal forumla" 
          $ true
formTrCoCASL sign (Diamond mod phi _) = 
   trace "WARNING: ignoring modal forumla" 
          $ true
