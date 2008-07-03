{- |
Module      :  $Header$
Description :  embedding from CspCASL to Isabelle-HOL
Copyright   :  (c) Andy Gimblett, Liam O'Reilly and Markus Roggenbach, Swansea Uni 2008
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  csliam@swan.ac.uk
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

The embedding comorphism from CspCASL to Isabelle-HOL.
-}

module Comorphisms.CspCASL2IsabelleHOL where

import qualified Data.Set as Set

import CASL.AS_Basic_CASL
import Common.AS_Annotation
import Common.Result
import CspCASL.Logic_CspCASL
import CspCASL.AS_CspCASL
import CspCASL.SignCSP
import Isabelle.IsaSign as IsaSign
import Isabelle.Logic_Isabelle
import Logic.Logic
import Logic.Comorphism

isSingleton :: Set.Set a -> Bool
isSingleton s = Set.size s == 1

-- | The identity of the comorphism
data CspCASL2IsabelleHOL = CspCASL2IsabelleHOL deriving (Show)

-- Isabelle theories
type IsaTheory = (IsaSign.Sign, [Named IsaSign.Sentence])

instance Language CspCASL2IsabelleHOL -- default definition is okay

instance Comorphism CspCASL2IsabelleHOL
               CspCASL ()
               CspBasicSpec CspCASLSentence SYMB_ITEMS SYMB_MAP_ITEMS
               CspCASLSign
               CspMorphism
               () () ()
               Isabelle () () IsaSign.Sentence () ()
               IsaSign.Sign
               IsabelleMorphism () () ()  where
    sourceLogic CspCASL2IsabelleHOL = CspCASL
    sourceSublogic CspCASL2IsabelleHOL = ()
    targetLogic CspCASL2IsabelleHOL = Isabelle
    mapSublogic _cid _sl = Just ()
    map_theory CspCASL2IsabelleHOL = transCCTheory
    map_morphism = mapDefaultMorphism
    map_sentence CspCASL2IsabelleHOL sign = transCCSentence sign
    has_model_expansion CspCASL2IsabelleHOL = False
    is_weakly_amalgamable CspCASL2IsabelleHOL = False
    isInclusionComorphism CspCASL2IsabelleHOL = True

transCCTheory :: (CspCASLSign, [Named CspCASLSentence]) -> Result IsaTheory
transCCTheory _ = do return (IsaSign.emptySign, [makeNamed "empty_Isa_sentence" (mkSen (Const (mkVName "helloWorld") (Hide (Type "byeWorld" [] []) TFun Nothing)))])

transCCSentence :: CspCASLSign -> CspCASLSentence -> Result IsaSign.Sentence
transCCSentence _ _ = do return (mkSen (Const (mkVName "helloWorld") (Disp (Type "byeWorld" [] []) TFun Nothing)))

{-

---------------------------- Signature -----------------------------
baseSign :: BaseSig
baseSign = Main_thy

typeToks :: CASL.Sign.Sign f e -> Set.Set String
typeToks = Set.map (\ s -> showIsaTypeT s baseSign) . sortSet

transTheory :: Pretty f => SignTranslator f e ->
               FormulaTranslator f e ->
               (CASL.Sign.Sign f e, [Named (FORMULA f)])
                   -> Result IsaTheory
transTheory trSig trForm (sign, sens) = do
  gens <-
      mapM (\ (Sort_gen_ax constr False) -> inductionScheme constr) genTypes
  fmap (trSig sign (extendedInfo sign)) $ return (IsaSign.emptySign {
    baseSig = baseSign,
    tsig = emptyTypeSig {arities =
               Set.fold (\s -> let s1 = showIsaTypeT s baseSign in
                                 Map.insert s1 [(isaTerm, [])])
                               Map.empty (sortSet sign)},
    constTab = Map.foldWithKey insertPreds
                (Map.foldWithKey insertOps Map.empty
                $ opMap sign) $ predMap sign,
    domainTab = dtDefs},
         zipWith (\ n -> makeNamed ("ga_induction_" ++ show n) . myMapSen)
             [1 :: Int ..] gens ++
         map (mapNamed myMapSen) real_sens)
     -- for now, no new sentences
  where
    tyToks = typeToks sign
    myMapSen = mkSen . transFORMULA sign tyToks trForm (getAssumpsToks sign)
    (real_sens, sort_gen_axs) = List.partition
        (\ s -> case sentence s of
                Sort_gen_ax _ _ -> False
                _ -> True) sens
    unique_sort_gen_axs = List.nubBy
            ( \ (Sort_gen_ax cs1 _) (Sort_gen_ax cs2 _) ->
                  any (flip elem $ map newSort cs1) $ map newSort cs2
            ) $ map sentence sort_gen_axs
    (freeTypes, genTypes) = List.partition (\ (Sort_gen_ax _ b) -> b)
                            $ unique_sort_gen_axs
    dtDefs = makeDtDefs sign tyToks freeTypes
    ga = globAnnos sign
    insertOps op ts m = if isSingleton ts then
      let t = Set.findMin ts in Map.insert
              (mkIsaConstT False ga (length $ opArgs t) op baseSign tyToks)
              (transOpType t) m
      else foldl (\ m1 (t, i) -> Map.insert
             (mkIsaConstIT False ga (length $ opArgs t) op i baseSign tyToks)
             (transOpType t) m1) m $ zip (Set.toList ts) [1..]
    insertPreds pre ts m = if isSingleton ts then
      let t = Set.findMin ts in Map.insert
              (mkIsaConstT True ga (length $ predArgs t) pre baseSign tyToks)
              (transPredType t) m
      else foldl (\ m1 (t, i) -> Map.insert
             (mkIsaConstIT True ga (length $ predArgs t) pre i baseSign tyToks)
             (transPredType t) m1) m $ zip (Set.toList ts) [1..]

makeDtDefs :: CASL.Sign.Sign f e -> Set.Set String -> [FORMULA f]
           -> [[(Typ,[(VName,[Typ])])]]
makeDtDefs sign = map . makeDtDef sign

makeDtDef :: CASL.Sign.Sign f e -> Set.Set String -> FORMULA f
          -> [(Typ,[(VName,[Typ])])]
makeDtDef sign tyToks nf = case nf of
  Sort_gen_ax constrs True -> map makeDt srts where
    (srts,ops,_maps) = recover_Sort_gen_ax constrs
    makeDt s = (transSort s, map makeOp (filter (hasTheSort s) ops))
    makeOp opSym = (transOP_SYMB sign tyToks opSym, transArgs opSym)
    hasTheSort s (Qual_op_name _ ot _) = s == res_OP_TYPE ot
    hasTheSort _ _ = error "CspCASL2IsabelleHOL.hasTheSort"
    transArgs (Qual_op_name _ ot _) = map transSort $ args_OP_TYPE ot
    transArgs _ = error "CspCASL2IsabelleHOL.transArgs"
  _ -> error "CspCASL2IsabelleHOL.makeDtDef"

transSort :: SORT -> Typ
transSort s = Type (showIsaTypeT s baseSign) [] []

transOpType :: OpType -> Typ
transOpType ot = mkCurryFunType (map transSort $ opArgs ot)
                 $ transSort (opRes ot)

transPredType :: PredType -> Typ
transPredType pt = mkCurryFunType (map transSort $ predArgs pt) boolType

------------------------------ Formulas ------------------------------

getAssumpsToks :: CASL.Sign.Sign f e -> Set.Set String
getAssumpsToks sign = Map.foldWithKey ( \ i ops s ->
    Set.union s $ Set.unions
        $ zipWith ( \ o _ -> getConstIsaToks i o baseSign) [1..]
                     $ Set.toList ops)
    (Map.foldWithKey ( \ i prds s ->
    Set.union s $ Set.unions
        $ zipWith ( \ o _ -> getConstIsaToks i o baseSign) [1..]
                     $ Set.toList prds) Set.empty $ predMap sign) $ opMap sign

var :: String -> Term
var v = IsaSign.Free (mkVName v)

transVar :: Set.Set String -> VAR -> String
transVar toks v = let
    s = showIsaConstT (simpleIdToId v) baseSign
    renVar t = if Set.member t toks then renVar $ "X_" ++ t else t
    in renVar s

quantifyIsa :: String -> (String, Typ) -> Term -> Term
quantifyIsa q (v, _) phi =
  App (conDouble q) (Abs (var v) phi NotCont) NotCont

quantify :: Set.Set String -> QUANTIFIER -> (VAR, SORT) -> Term -> Term
quantify toks q (v,t) phi  =
  quantifyIsa (qname q) (transVar toks v, transSort t) phi
  where
  qname Universal = allS
  qname Existential = exS
  qname Unique_existential = ex1S

transOP_SYMB :: CASL.Sign.Sign f e -> Set.Set String -> OP_SYMB -> VName
transOP_SYMB sign tyToks (Qual_op_name op ot _) = let
  ga = globAnnos sign
  l = length $ args_OP_TYPE ot in
  case (do ots <- Map.lookup op (opMap sign)
           if isSingleton ots
             then return $ mkIsaConstT False ga l op baseSign tyToks
             else do
               i <- List.elemIndex (toOpType ot) (Set.toList ots)
               return $ mkIsaConstIT False ga l op (i+1) baseSign tyToks) of
    Just vn -> vn
    Nothing -> error ("CASL2Isabelle unknown op: " ++ show op)
transOP_SYMB _ _ (Op_name _) = error "CASL2Isabelle: unqualified operation"

transPRED_SYMB :: CASL.Sign.Sign f e -> Set.Set String -> PRED_SYMB -> VName
transPRED_SYMB sign tyToks (Qual_pred_name p pt@(Pred_type args _) _) = let
  ga = globAnnos sign
  l = length args in
  case (do pts <- Map.lookup p (predMap sign)
           if isSingleton pts
             then return $ mkIsaConstT True ga l p baseSign tyToks
             else do
                   i <- List.elemIndex (toPredType pt) (Set.toList pts)
                   return $ mkIsaConstIT True ga l p (i+1) baseSign tyToks) of
    Just vn -> vn
    Nothing -> mkIsaConstT True ga (-1) p baseSign tyToks
    -- for predicate names in induction schemes
transPRED_SYMB _ _ (Pred_name _) = error "CASL2Isabelle: unqualified predicate"

mapSen :: FormulaTranslator f e -> CASL.Sign.Sign f e -> Set.Set String
       -> FORMULA f -> Sentence
mapSen trForm sign tyToks phi =
    mkSen $ transFORMULA sign tyToks trForm (getAssumpsToks sign) phi

transRecord :: CASL.Sign.Sign f e -> Set.Set String -> FormulaTranslator f e
            -> Set.Set String -> Record f Term Term
transRecord sign tyToks tr toks = Record
    { foldQuantification = \ _ qu vdecl phi _ ->
          foldr (quantify toks qu) phi (flatVAR_DECLs vdecl)
    , foldConjunction = \ _ phis _ ->
          if null phis then true else foldr1 binConj phis
    , foldDisjunction = \ _ phis _ ->
          if null phis then false else foldr1 binDisj phis
    , foldImplication = \ _ phi1 phi2 _ _ -> binImpl phi1 phi2
    , foldEquivalence = \ _ phi1 phi2 _ -> binEqv phi1 phi2
    , foldNegation = \ _ phi _ -> termAppl notOp phi
    , foldTrue_atom = \ _ _ -> true
    , foldFalse_atom = \ _ _ -> false
    , foldPredication = \ _ psymb args _ ->
          foldl termAppl (con $ transPRED_SYMB sign tyToks psymb) args
    , foldDefinedness = \ _ _ _ -> true -- totality assumed
    , foldExistl_equation = \ _ t1 t2 _ -> binEq t1 t2 -- equal types assumed
    , foldStrong_equation = \ _ t1 t2 _ -> binEq t1 t2 -- equal types assumed
    , foldMembership = \ _ _ _ _ -> true -- no subsorting assumed
    , foldMixfix_formula = error "transRecord: Mixfix_formula"
    , foldSort_gen_ax = error "transRecord: Sort_gen_ax"
    , foldExtFORMULA = \ _ phi -> tr sign tyToks phi
    , foldSimpleId = error "transRecord: Simple_id"
    , foldQual_var = \ _ v _ _ -> var $ transVar toks v
    , foldApplication = \ _ opsymb args _ ->
          foldl termAppl (con $ transOP_SYMB sign tyToks opsymb) args
    , foldSorted_term = \ _ t _ _ -> t -- no subsorting assumed
    , foldCast = \ _ t _ _ -> t -- no subsorting assumed
    , foldConditional = \ _  t1 phi t2 _ -> -- equal types assumed
          foldl termAppl (conDouble "If") [phi, t1, t2]
    , foldMixfix_qual_pred = error "transRecord: Mixfix_qual_pred"
    , foldMixfix_term = error "transRecord: Mixfix_term"
    , foldMixfix_token = error "transRecord: Mixfix_token"
    , foldMixfix_sorted_term = error "transRecord: Mixfix_sorted_term"
    , foldMixfix_cast = error "transRecord: Mixfix_cast"
    , foldMixfix_parenthesized = error "transRecord: Mixfix_parenthesized"
    , foldMixfix_bracketed = error "transRecord: Mixfix_bracketed"
    , foldMixfix_braced = error "transRecord: Mixfix_braced"
    }

transFORMULA :: CASL.Sign.Sign f e -> Set.Set String -> FormulaTranslator f e
             -> Set.Set String -> FORMULA f -> Term
transFORMULA sign tyToks tr = foldFormula . transRecord sign tyToks tr

-}