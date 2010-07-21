{-# LANGUAGE MultiParamTypeClasses, TypeSynonymInstances #-}
{- |
Module      :  $Header$
Description :  Comorphism from OWL 1.1 to CASL_Dl
Copyright   :  (c) Uni Bremen 2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt

Maintainer  :  luecke@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable (via Logic.Logic)

a not yet implemented comorphism
-}

module Comorphisms.OWL2CASL (OWL2CASL (..)) where

import Logic.Logic as Logic
import Logic.Comorphism
import Common.AS_Annotation
import Common.Result
import Common.Id
import Control.Monad
import Data.Char
import qualified Data.Set as Set
import qualified Data.Map as Map

-- OWL = domain
import OWL.Logic_OWL
import OWL.AS
import OWL.Sublogic
import OWL.Morphism
import qualified OWL.Sign as OS
-- CASL_DL = codomain
import CASL.Logic_CASL
import CASL.AS_Basic_CASL
import CASL.Sign
import CASL.Morphism
import CASL.Sublogic

import Common.ProofTree

data OWL2CASL = OWL2CASL deriving Show

instance Language OWL2CASL

instance Comorphism
    OWL2CASL        -- comorphism
    OWL             -- lid domain
    OWLSub          -- sublogics domain
    OntologyFile    -- Basic spec domain
    Axiom           -- sentence domain
    SymbItems       -- symbol items domain
    SymbMapItems    -- symbol map items domain
    OS.Sign         -- signature domain
    OWLMorphism     -- morphism domain
    Entity          -- symbol domain
    RawSymb         -- rawsymbol domain
    ProofTree       -- proof tree codomain
    CASL            -- lid codomain
    CASL_Sublogics  -- sublogics codomain
    CASLBasicSpec   -- Basic spec codomain
    CASLFORMULA     -- sentence codomain
    SYMB_ITEMS      -- symbol items codomain
    SYMB_MAP_ITEMS  -- symbol map items codomain
    CASLSign        -- signature codomain
    CASLMor         -- morphism codomain
    Symbol          -- symbol codomain
    RawSymbol       -- rawsymbol codomain
    ProofTree       -- proof tree domain
    where
      sourceLogic OWL2CASL = OWL
      sourceSublogic OWL2CASL = sl_top
      targetLogic OWL2CASL = CASL
      mapSublogic OWL2CASL _ = Just $ cFol
        { cons_features = emptyMapConsFeature }
      map_theory OWL2CASL = mapTheory
      map_morphism OWL2CASL = mapMorphism
      isInclusionComorphism OWL2CASL = True
      has_model_expansion OWL2CASL = True

-- | Mapping of OWL morphisms to CASL morphisms
mapMorphism :: OWLMorphism -> Result CASLMor
mapMorphism oMor =
    do
      cdm <- mapSign $ osource oMor
      ccd <- mapSign $ otarget oMor
      let emap = mmaps oMor
          preds = Map.foldWithKey (\ (Entity ty u1) u2 -> let
              i1 = uriToId u1
              i2 = uriToId u2
              in case ty of
                Class -> Map.insert (i1, conceptPred) i2
                ObjectProperty -> Map.insert (i1, objectPropPred) i2
                DataProperty -> Map.insert (i1, dataPropPred) i2
                _ -> id) Map.empty emap
          ops = Map.foldWithKey (\ (Entity ty u1) u2 -> case ty of
                NamedIndividual ->
                    Map.insert (uriToId u1, indiConst) (uriToId u2, Total)
                _ -> id) Map.empty emap
      return (embedMorphism () cdm ccd)
                 { op_map = ops
                 , pred_map = preds }

-- | OWL topsort Thing
thing :: Id
thing = stringToId "Thing"

noThing :: Id
noThing = stringToId "Nothing"

-- | OWL bottom
mkThingPred :: Id -> PRED_SYMB
mkThingPred i =
  Qual_pred_name i (toPRED_TYPE conceptPred) nullRange

-- | OWL Data topSort DATA
dataS :: SORT
dataS = stringToId $ drop 3 $ show OWLDATA

data VarOrIndi = OVar Int | OIndi URI

predefSorts :: Set.Set SORT
predefSorts = Set.singleton thing

hetsPrefix :: String
hetsPrefix = ""

conceptPred :: PredType
conceptPred = PredType [thing]

objectPropPred :: PredType
objectPropPred = PredType [thing, thing]

dataPropPred :: PredType
dataPropPred = PredType [thing, dataS]

indiConst :: OpType
indiConst = OpType Total [] thing

mapSign :: OS.Sign                 -- ^ OWL signature
        -> Result CASLSign         -- ^ CASL signature
mapSign sig =
      let conc = Set.union (OS.concepts sig) (OS.primaryConcepts sig)
          cvrt = map uriToId . Set.toList
          tMp k = Map.fromList . map (\ u -> (u, Set.singleton k))
          cPreds = thing : noThing : cvrt conc
          oPreds = cvrt $ OS.indValuedRoles sig
          dPreds = cvrt $ OS.dataValuedRoles sig
          aPreds = Map.unions
            [ tMp conceptPred cPreds
            , tMp objectPropPred oPreds
            , tMp dataPropPred dPreds ]
      in return (emptySign ())
             { sortSet = predefSorts
             , predMap = aPreds
             , opMap = tMp indiConst . cvrt $ OS.individuals sig
             }


loadDataInformation :: OWLSub -> Sign f ()
loadDataInformation sl =
    let
        dts = Set.map (stringToId . printXSDName) $ datatype sl
    in
     (emptySign ()) { sortSet = dts }


predefinedSentences :: [Named CASLFORMULA]
predefinedSentences =
    [
     makeNamed "nothing in Nothing" $
     Quantification Universal
     [Var_decl [mkNName 1] thing nullRange]
     (
      Negation
      (
       Predication
       (mkThingPred noThing)
       [Qual_var (mkNName 1) thing nullRange]
       nullRange
      )
      nullRange
     )
     nullRange
    ,
     makeNamed "thing in Thing" $
     Quantification Universal
     [Var_decl [mkNName 1] thing nullRange]
     (
       Predication
       (mkThingPred thing)
       [Qual_var (mkNName 1) thing nullRange]
       nullRange
     )
     nullRange
    ]

mapTheory :: (OS.Sign, [Named Axiom])
             -> Result (CASLSign, [Named CASLFORMULA])
mapTheory (owlSig, owlSens) =
        let
            sublogic =
                sl_max (sl_sig owlSig) $
                foldl sl_max sl_bottom $ map (sl_ax . sentence) owlSens
        in
    do
      cSig <- mapSign owlSig
      let pSig = loadDataInformation sublogic
      (cSensI, nSig) <- foldM (\ (x, y) z ->
                           do
                             (sen, sig) <- mapSentence y z
                             return (sen : x, uniteCASLSign sig y)
                             ) ([], cSig) owlSens
      let cSens = concatMap (\ x ->
                             case x of
                               Nothing -> []
                               Just a -> [a]
                        ) cSensI
      return (uniteCASLSign nSig pSig, predefinedSentences ++ cSens)

-- | mapping of OWL to CASL_DL formulae
mapSentence :: CASLSign                           -- ^ CASL Signature
  -> Named Axiom                                  -- ^ OWL Sentence
  -> Result (Maybe (Named CASLFORMULA), CASLSign) -- ^ CASL Sentence
mapSentence cSig inSen = do
    (outAx, outSig) <- mapAxiom cSig $ sentence inSen
    return (fmap (flip mapNamed inSen . const) outAx, outSig)

-- | Mapping of Axioms
mapAxiom :: CASLSign                             -- ^ CASL Signature
         -> Axiom                                -- ^ OWL Axiom
         -> Result (Maybe CASLFORMULA, CASLSign) -- ^ CASL Formula
mapAxiom cSig ax =
    let
        a = 1
        b = 2
        c = 3
    in
      case ax of
        PlainAxiom _ pAx ->
            case pAx of
              SubClassOf sub super ->
                  do
                    domT <- mapDescription cSig sub a
                    codT <- mapDescription cSig super a
                    return (Just $ Quantification Universal
                               [Var_decl [mkNName a] thing nullRange]
                               (Implication
                                domT
                                codT
                                True
                                nullRange) nullRange, cSig)
              EquivOrDisjointClasses eD dS ->
                  do
                    decrsS <- mapDescriptionListP cSig a $ comPairs dS dS
                    let decrsP =
                            case eD of
                              Equivalent ->
                                  map (\ (x, y) -> Equivalence x y nullRange)
                                      decrsS
                              Disjoint ->
                                  map (\ (x, y) -> Negation
                                       (Conjunction [x, y] nullRange) nullRange)
                                  decrsS
                    return (Just $ Quantification Universal
                              [Var_decl [mkNName a] thing nullRange]
                               (
                                Conjunction decrsP nullRange
                               ) nullRange, cSig)
              DisjointUnion cls sD ->
                  do
                    decrs <- mapDescriptionList cSig a sD
                    decrsS <- mapDescriptionListP cSig a $ comPairs sD sD
                    let decrsP = map (\ (x, y) -> Conjunction [x, y] nullRange)
                                 decrsS
                    mcls <- mapClassURI cSig cls (mkNName a)
                    return (Just $ Quantification Universal
                              [Var_decl [mkNName a] thing nullRange]
                               (
                                Equivalence
                                  mcls                 -- The class
                                (                      -- The rest
                                  Conjunction
                                  [
                                   Disjunction decrs nullRange
                                  , Negation
                                   (
                                    Conjunction decrsP nullRange
                                   )
                                   nullRange
                                  ]
                                  nullRange
                                )
                                nullRange
                               ) nullRange, cSig)
              SubObjectPropertyOf ch op ->
                  do
                    os <- mapSubObjProp cSig ch op c
                    return (Just os, cSig)
              EquivOrDisjointObjectProperties disOrEq oExLst ->
                  do
                    pairs <- mapComObjectPropsList cSig oExLst a b
                    return (Just $ Quantification Universal
                              [ Var_decl [mkNName a] thing nullRange
                              , Var_decl [mkNName b] thing nullRange]
                               (
                                Conjunction
                                (
                                 case disOrEq of
                                   Equivalent ->
                                       map (\ (x, y) ->
                                                Equivalence x y nullRange) pairs
                                   Disjoint ->
                                       map (\ (x, y) ->
                                                (Negation
                                                 (Conjunction [x, y] nullRange)
                                                 nullRange
                                                )
                                           ) pairs
                                )
                                nullRange
                               )
                               nullRange, cSig)
              ObjectPropertyDomainOrRange domOrRn objP descr ->
                        do
                          tobjP <- mapObjProp cSig objP a b
                          tdsc <- mapDescription cSig descr $
                                   case domOrRn of
                                     ObjDomain -> a
                                     ObjRange -> b
                          let vars = case domOrRn of
                                       ObjDomain -> (mkNName a, mkNName b)
                                       ObjRange -> (mkNName b, mkNName a)
                          return (Just $ Quantification Universal
                                     [Var_decl [fst vars] thing nullRange]
                                     (
                                      Quantification Existential
                                         [Var_decl [snd vars] thing nullRange]
                                         (
                                          Implication
                                           tobjP
                                           tdsc
                                          True
                                          nullRange
                                         )
                                      nullRange
                                     )
                                     nullRange, cSig)
              InverseObjectProperties o1 o2 ->
                  do
                    so1 <- mapObjProp cSig o1 a b
                    so2 <- mapObjProp cSig o2 b a
                    return (Just $ Quantification Universal
                             [Var_decl [mkNName a] thing nullRange
                             , Var_decl [mkNName b] thing nullRange]
                             (
                              Equivalence
                              so1
                              so2
                              nullRange
                             )
                             nullRange, cSig)
              ObjectPropertyCharacter cha o ->
                  case cha of
                    Functional ->
                        do
                          so1 <- mapObjProp cSig o a b
                          so2 <- mapObjProp cSig o a c
                          return (Just $ Quantification Universal
                                     [Var_decl [mkNName a] thing nullRange
                                     , Var_decl [mkNName b] thing nullRange
                                     , Var_decl [mkNName c] thing nullRange
                                     ]
                                     (
                                      Implication
                                      (
                                       Conjunction [so1, so2] nullRange
                                      )
                                      (
                                       Strong_equation
                                       (
                                        Qual_var (mkNName b) thing nullRange
                                       )
                                       (
                                        Qual_var (mkNName c) thing nullRange
                                       )
                                       nullRange
                                      )
                                      True
                                      nullRange
                                     )
                                     nullRange, cSig)
                    InverseFunctional ->
                        do
                          so1 <- mapObjProp cSig o a c
                          so2 <- mapObjProp cSig o b c
                          return (Just $ Quantification Universal
                                     [Var_decl [mkNName a] thing nullRange
                                     , Var_decl [mkNName b] thing nullRange
                                     , Var_decl [mkNName c] thing nullRange
                                     ]
                                     (
                                      Implication
                                      (
                                       Conjunction [so1, so2] nullRange
                                      )
                                      (
                                       Strong_equation
                                       (
                                        Qual_var (mkNName a) thing nullRange
                                       )
                                       (
                                        Qual_var (mkNName b) thing nullRange
                                       )
                                       nullRange
                                      )
                                      True
                                      nullRange
                                     )
                                     nullRange, cSig)
                    Reflexive ->
                        do
                          so <- mapObjProp cSig o a a
                          return (Just $ Quantification Universal
                                   [Var_decl [mkNName a] thing nullRange]
                                   (
                                    Implication
                                     (
                                      Membership
                                      (Qual_var (mkNName a) thing nullRange)
                                      thing
                                      nullRange
                                     )
                                     so
                                     True
                                     nullRange
                                   )
                                   nullRange, cSig)
                    Irreflexive ->
                        do
                          so <- mapObjProp cSig o a a
                          return
                                 (Just $ Quantification Universal
                                   [Var_decl [mkNName a] thing nullRange]
                                   (
                                    Implication
                                    (
                                     Membership
                                     (Qual_var (mkNName a) thing nullRange)
                                     thing
                                     nullRange
                                    )
                                    (
                                     Negation
                                     so
                                    nullRange
                                    )
                                    True
                                    nullRange
                                   )
                                   nullRange, cSig)
                    Symmetric ->
                        do
                          so1 <- mapObjProp cSig o a b
                          so2 <- mapObjProp cSig o b a
                          return
                           (Just $ Quantification Universal
                               [Var_decl [mkNName a] thing nullRange
                               , Var_decl [mkNName b] thing nullRange]
                               (
                                Implication
                                so1
                                so2
                                True
                                nullRange
                               )
                               nullRange, cSig)
                    Asymmetric ->
                        do
                          so1 <- mapObjProp cSig o a b
                          so2 <- mapObjProp cSig o b a
                          return
                           (Just $ Quantification Universal
                               [Var_decl [mkNName a] thing nullRange
                               , Var_decl [mkNName b] thing nullRange]
                               (
                                Implication
                                so1
                                (Negation so2 nullRange)
                                True
                                nullRange
                               )
                               nullRange, cSig)
                    Antisymmetric ->
                        do
                          so1 <- mapObjProp cSig o a b
                          so2 <- mapObjProp cSig o b a
                          return
                           (Just $ Quantification Universal
                               [Var_decl [mkNName a] thing nullRange
                               , Var_decl [mkNName b] thing nullRange]
                               (
                                Implication
                                 (Conjunction [so1, so2] nullRange)
                                 (
                                  Strong_equation
                                  (
                                   Qual_var (mkNName a) thing nullRange
                                  )
                                  (
                                   Qual_var (mkNName b) thing nullRange
                                  )
                                  nullRange
                                 )
                                True
                                nullRange
                               )
                               nullRange, cSig)
                    Transitive ->
                        do
                          so1 <- mapObjProp cSig o a b
                          so2 <- mapObjProp cSig o b c
                          so3 <- mapObjProp cSig o a c
                          return
                           (Just $ Quantification Universal
                               [Var_decl [mkNName a] thing nullRange
                               , Var_decl [mkNName b] thing nullRange
                               , Var_decl [mkNName c] thing nullRange]
                               (
                                Implication
                                (
                                 Conjunction [so1, so2] nullRange
                                )
                                 so3
                                True
                                nullRange
                               )
                               nullRange, cSig)
              SubDataPropertyOf dP1 dP2 ->
                  do
                    l <- mapDataProp cSig dP1 a b
                    r <- mapDataProp cSig dP2 a b
                    return (Just $ Quantification Universal
                               [ Var_decl [mkNName a] thing nullRange
                               , Var_decl [mkNName b] dataS nullRange]
                               (
                                Implication
                                l
                                r
                                True
                                nullRange
                               )
                               nullRange, cSig)
              EquivOrDisjointDataProperties disOrEq dlst ->
                  do
                    pairs <- mapComDataPropsList cSig dlst a b
                    return (Just $ Quantification Universal
                              [ Var_decl [mkNName a] thing nullRange
                              , Var_decl [mkNName b] dataS nullRange]
                               (
                                Conjunction
                                (
                                 case disOrEq of
                                   Equivalent ->
                                       map (\ (x, y) ->
                                                Equivalence x y nullRange) pairs
                                   Disjoint ->
                                       map (\ (x, y) ->
                                                (Negation
                                                 (Conjunction [x, y] nullRange)
                                                 nullRange
                                                )
                                           ) pairs
                                )
                                nullRange
                               )
                               nullRange, cSig)
              DataPropertyDomainOrRange domRn dpex ->
                        do
                          oEx <- mapDataProp cSig dpex a b
                          case domRn of
                            DataDomain mdom ->
                                do
                                  odes <- mapDescription cSig mdom a
                                  let vars = (mkNName a, mkNName b)
                                  return (Just $ Quantification Universal
                                         [Var_decl [fst vars] thing nullRange]
                                         (Quantification Existential
                                         [Var_decl [snd vars] dataS nullRange]
                                         (Implication oEx odes True nullRange)
                                         nullRange) nullRange, cSig)
                            DataRange rn ->
                                do
                                  odes <- mapDataRange cSig rn b
                                  let vars = (mkNName a, mkNName b)
                                  return (Just $ Quantification Universal
                                         [Var_decl [fst vars] thing nullRange]
                                         (Quantification Existential
                                         [Var_decl [snd vars] dataS nullRange]
                                         (Implication oEx odes True nullRange)
                                         nullRange) nullRange, cSig)
              FunctionalDataProperty o ->
                        do
                          so1 <- mapDataProp cSig o a b
                          so2 <- mapDataProp cSig o a c
                          return (Just $ Quantification Universal
                                     [Var_decl [mkNName a] thing nullRange
                                     , Var_decl [mkNName b] dataS nullRange
                                     , Var_decl [mkNName c] dataS nullRange
                                     ]
                                     (
                                      Implication
                                      (
                                       Conjunction [so1, so2] nullRange
                                      )
                                      (
                                       Strong_equation
                                       (
                                        Qual_var (mkNName b) dataS nullRange
                                       )
                                       (
                                        Qual_var (mkNName c) dataS nullRange
                                       )
                                       nullRange
                                      )
                                      True
                                      nullRange
                                     )
                                    nullRange, cSig
                                   )
              SameOrDifferentIndividual sameOrDiff indis ->
                  do
                    inD <- mapM (mapIndivURI cSig) indis
                    let inDL = comPairs inD inD
                    return (Just $ Conjunction
                             (map (\ (x, y) -> case sameOrDiff of
                                   Same -> Strong_equation x y nullRange
                                   Different -> Negation
                                     (Strong_equation x y nullRange) nullRange
                                 ) inDL)
                             nullRange, cSig)
              ClassAssertion indi cls ->
                  do
                    inD <- mapIndivURI cSig indi
                    ocls <- mapDescription cSig cls a
                    return (Just $ Quantification Universal
                             [Var_decl [mkNName a] thing nullRange]
                             (
                              Implication
                              (Strong_equation
                               (Qual_var (mkNName a) thing nullRange)
                               inD
                               nullRange
                              )
                               ocls
                              True
                              nullRange
                             )
                             nullRange, cSig)
              ObjectPropertyAssertion ass ->
                  case ass of
                    Assertion objProp posNeg sourceInd targetInd ->
                              do
                                inS <- mapIndivURI cSig sourceInd
                                inT <- mapIndivURI cSig targetInd
                                oPropH <- mapObjProp cSig objProp a b
                                let oProp = case posNeg of
                                              Positive -> oPropH
                                              Negative -> Negation
                                                           oPropH
                                                           nullRange
                                return (Just $ Quantification Universal
                                           [Var_decl [mkNName a]
                                                     thing nullRange
                                           , Var_decl [mkNName b]
                                                     thing nullRange]
                                         (
                                          Implication
                                          (
                                           Conjunction
                                           [
                                            Strong_equation
                                            (Qual_var (mkNName a) thing
                                             nullRange)
                                            inS
                                            nullRange
                                           , Strong_equation
                                            (Qual_var (mkNName b) thing
                                             nullRange)
                                            inT
                                            nullRange
                                           ]
                                           nullRange
                                          )
                                           oProp
                                          True
                                          nullRange
                                         )
                                         nullRange, cSig)
              DataPropertyAssertion ass ->
                  case ass of
                    Assertion dPropExp posNeg sourceInd targetInd ->
                        do
                          inS <- mapIndivURI cSig sourceInd
                          inT <- mapConstant cSig targetInd
                          dPropH <- mapDataProp cSig dPropExp a b
                          let dProp = case posNeg of
                                        Positive -> dPropH
                                        Negative -> Negation
                                                    dPropH
                                                    nullRange
                          return (Just $ Quantification Universal
                                             [Var_decl [mkNName a]
                                                       thing nullRange
                                             , Var_decl [mkNName b]
                                                       dataS nullRange]
                                    (
                                     Implication
                                     (
                                      Conjunction
                                      [
                                       Strong_equation
                                       (Qual_var (mkNName a) thing nullRange)
                                       inS
                                       nullRange
                                      , Strong_equation
                                       (Qual_var (mkNName b) dataS nullRange)
                                       inT
                                       nullRange
                                      ]
                                      nullRange
                                     )
                                      dProp
                                     True
                                     nullRange
                                    )
                                    nullRange, cSig)
              Declaration _ ->
                  return (Nothing, cSig)
        EntityAnno _ ->
              return (Nothing, cSig)

{- | Mapping along ObjectPropsList for creation of pairs for commutative
operations. -}
mapComObjectPropsList :: CASLSign                    -- ^ CASLSignature
                      -> [ObjectPropertyExpression]
                      -> Int                         -- ^ First variable
                      -> Int                         -- ^ Last  variable
                      -> Result [(CASLFORMULA, CASLFORMULA)]
mapComObjectPropsList cSig props num1 num2 =
      mapM (\ (x, z) -> do
                              l <- mapObjProp cSig x num1 num2
                              r <- mapObjProp cSig z num1 num2
                              return (l, r)
                       ) $ comPairs props props

-- | mapping of data constants
mapConstant :: CASLSign
            -> Constant
            -> Result (TERM ())
mapConstant _ c =
    do
      let cl = case c of
                 Constant l _ -> l
      return $ Application
               (
                Qual_op_name
                (stringToId cl)
                (Op_type Total [] dataS nullRange)
                nullRange
               )
               []
               nullRange

-- | Mapping of subobj properties
mapSubObjProp :: CASLSign
              -> SubObjectPropertyExpression
              -> ObjectPropertyExpression
              -> Int
              -> Result CASLFORMULA
mapSubObjProp cSig prop oP num1 =
    let
        num2 = num1 + 1
    in
      case prop of
        OPExpression oPL ->
            do
              l <- mapObjProp cSig oPL num1 num2
              r <- mapObjProp cSig oP num1 num2
              return $ Quantification Universal
                     [ Var_decl [mkNName num1] thing nullRange
                     , Var_decl [mkNName num2] thing nullRange]
                     (
                      Implication
                      r
                      l
                      True
                      nullRange
                     )
                     nullRange
        SubObjectPropertyChain props ->
            do
              let zprops = zip (tail props) [(num2 + 1) ..]
                  (_, vars) = unzip zprops
              oProps <- mapM (\ (z, x, y) -> mapObjProp cSig z x y) $
                                zip3 props ((num1 : vars) ++ [num2]) $
                                     tail ((num1 : vars) ++ [num2])
              ooP <- mapObjProp cSig oP num1 num2
              return $ Quantification Universal
                     [ Var_decl [mkNName num1] thing nullRange
                     , Var_decl [mkNName num2] thing nullRange]
                     (
                      Quantification Universal
                         (
                          map (\ x -> Var_decl [mkNName x] thing nullRange) vars
                         )
                         (
                          Implication
                          (Conjunction oProps nullRange)
                          ooP
                          True
                          nullRange
                         )
                       nullRange
                     )
                    nullRange

{- | Mapping along DataPropsList for creation of pairs for commutative
operations. -}
mapComDataPropsList :: CASLSign
                      -> [DataPropertyExpression]
                      -> Int                         -- ^ First variable
                      -> Int                         -- ^ Last  variable
                      -> Result [(CASLFORMULA, CASLFORMULA)]
mapComDataPropsList cSig props num1 num2 =
      mapM (\ (x, z) -> do
                              l <- mapDataProp cSig x num1 num2
                              r <- mapDataProp cSig z num1 num2
                              return (l, r)
                       ) $ comPairs props props

-- | Mapping of data properties
mapDataProp :: CASLSign
            -> DataPropertyExpression
            -> Int
            -> Int
            -> Result CASLFORMULA
mapDataProp _ dP nO nD =
    do
      let
          l = mkNName nO
          r = mkNName nD
      ur <- uriToIdM dP
      return $ Predication
                 (Qual_pred_name ur (toPRED_TYPE dataPropPred) nullRange)
                 [Qual_var l thing nullRange, Qual_var r dataS nullRange]
                 nullRange

-- | Mapping of obj props
mapObjProp :: CASLSign
              -> ObjectPropertyExpression
              -> Int
              -> Int
              -> Result CASLFORMULA
mapObjProp cSig ob num1 num2 =
    case ob of
      OpURI u ->
          do
            let l = mkNName num1
                r = mkNName num2
            ur <- uriToIdM u
            return $ Predication
              (Qual_pred_name ur (toPRED_TYPE objectPropPred) nullRange)
              [Qual_var l thing nullRange, Qual_var r thing nullRange]
              nullRange
      InverseOp u ->
          mapObjProp cSig u num2 num1

-- | Mapping of obj props with Individuals
mapObjPropI :: CASLSign
              -> ObjectPropertyExpression
              -> VarOrIndi
              -> VarOrIndi
              -> Result CASLFORMULA
mapObjPropI cSig ob lP rP =
      case ob of
        OpURI u ->
          do
            lT <- case lP of
                    OVar num1 -> return $ Qual_var (mkNName num1)
                                     thing nullRange
                    OIndi indivID -> mapIndivURI cSig indivID
            rT <- case rP of
                    OVar num1 -> return $ Qual_var (mkNName num1)
                                     thing nullRange
                    OIndi indivID -> mapIndivURI cSig indivID
            ur <- uriToIdM u
            return $ Predication
                       (Qual_pred_name ur
                        (toPRED_TYPE objectPropPred) nullRange)
                       [lT,
                        rT
                       ]
                       nullRange
        InverseOp u -> mapObjPropI cSig u rP lP

-- | Mapping of Class URIs
mapClassURI :: CASLSign
            -> OwlClassURI
            -> Token
            -> Result CASLFORMULA
mapClassURI _ uril uid =
    do
      ur <- uriToIdM uril
      return $ Predication
                  (Qual_pred_name ur (toPRED_TYPE conceptPred) nullRange)
                  [Qual_var uid thing nullRange]
                  nullRange

-- | Mapping of Individual URIs
mapIndivURI :: CASLSign
            -> IndividualURI
            -> Result (TERM ())
mapIndivURI _ uriI =
    do
      ur <- uriToIdM uriI
      return $ Application
                 (
                  Qual_op_name
                  ur
                  (Op_type Total [] thing nullRange)
                  nullRange
                 )
                 []
                 nullRange

uriToIdM :: URI -> Result Id
uriToIdM = return . uriToId

-- | Extracts Id from URI
uriToId :: URI -> Id
uriToId urI =
    let
        ur = case urI of
               QN _ "Thing" _ _ -> mkQName "Thing"
               QN _ "Nothing" _ _ -> mkQName "Nothing"
               _ -> urI
        repl a = if isAlphaNum a
                  then
                      a
                  else
                      '_'
        nP = map repl $ namePrefix ur
        lP = map repl $ localPart ur
        nU = map repl $ namespaceUri ur
    in stringToId $ nU ++ "" ++ nP ++ "" ++ lP

-- | Mapping of a list of descriptions
mapDescriptionList :: CASLSign
                      -> Int
                      -> [Description]
                      -> Result [CASLFORMULA]
mapDescriptionList cSig n lst =
      mapM (uncurry $ mapDescription cSig)
                                $ zip lst $ replicate (length lst) n

-- | Mapping of a list of pairs of descriptions
mapDescriptionListP :: CASLSign
                    -> Int
                    -> [(Description, Description)]
                    -> Result [(CASLFORMULA, CASLFORMULA)]
mapDescriptionListP cSig n lst =
    do
      let (l, r) = unzip lst
      llst <- mapDescriptionList cSig n l
      rlst <- mapDescriptionList cSig n r
      let olst = zip llst rlst
      return olst

-- | Build a name
mkNName :: Int -> Token
mkNName i = mkSimpleId $ hetsPrefix ++ mkNName_H i
    where
      mkNName_H k =
          case k of
            0 -> ""
            j -> mkNName_H (j `div` 26) ++ [chr (j `mod` 26 + 96)]

-- | Get all distinct pairs for commutative operations
comPairs :: [t] -> [t1] -> [(t, t1)]
comPairs [] [] = []
comPairs _ [] = []
comPairs [] _ = []
comPairs (a : as) (_ : bs) = zip (replicate (length bs) a) bs ++ comPairs as bs

-- | mapping of Data Range
mapDataRange :: CASLSign
             -> DataRange                -- ^ OWL DataRange
             -> Int                      -- ^ Current Variablename
             -> Result CASLFORMULA       -- ^ CASL_DL Formula
mapDataRange cSig rn inId =
    do
      let uid = mkNName inId
      case rn of
        DRDatatype uril ->
          do
            ur <- uriToIdM uril
            return $ Membership
                      (Qual_var uid thing nullRange)
                      ur
                      nullRange
        DataComplementOf dr ->
            do
              dc <- mapDataRange cSig dr inId
              return $ Negation dc nullRange
        DataOneOf _ -> error "nyi"
        DatatypeRestriction _ _ -> error "nyi"

-- | mapping of OWL Descriptions
mapDescription :: CASLSign
               -> Description              -- ^ OWL Description
               -> Int                      -- ^ Current Variablename
               -> Result CASLFORMULA       -- ^ CASL_DL Formula
mapDescription cSig des var =
    case des of
      OWLClassDescription cl -> mapClassURI cSig cl (mkNName var)
      ObjectJunction jt desL ->
          do
            desO <- mapM (flip (mapDescription cSig) var) desL
            return $ case jt of
              UnionOf -> Disjunction desO nullRange
              IntersectionOf -> Conjunction desO nullRange
      ObjectComplementOf descr ->
             do
               desO <- mapDescription cSig descr var
               return $ Negation desO nullRange
      ObjectOneOf indS ->
          do
            indO <- mapM (mapIndivURI cSig) indS
            let varO = Qual_var (mkNName var) thing nullRange
            let forms = map (mkStEq varO) indO
            return $ Disjunction forms nullRange
      ObjectValuesFrom qt oprop descr ->
        do
          opropO <- mapObjProp cSig oprop var (var + 1)
          descO <- mapDescription cSig descr (var + 1)
          case qt of
            SomeValuesFrom ->
                return $ Quantification Existential [Var_decl [mkNName
                                                               (var + 1)]
                                                       thing nullRange]
                       (
                        Conjunction
                        [opropO, descO]
                        nullRange
                       )
                       nullRange
            AllValuesFrom ->
                return $ Quantification Universal [Var_decl [mkNName
                                                               (var + 1)]
                                                       thing nullRange]
                       (
                        Implication
                        opropO descO
                        True
                        nullRange
                       )
                       nullRange
      ObjectExistsSelf oprop -> mapObjProp cSig oprop var var
      ObjectHasValue oprop indiv ->
            mapObjPropI cSig oprop (OVar var) (OIndi indiv)
      ObjectCardinality c ->
          case c of
            Cardinality ct n oprop d
                 ->
                   do
                     let vlst = [(var + 1) .. (n + var)]
                         vlstM = [(var + 1) .. (n + var + 1)]
                     dOut <- (\ x -> case x of
                                      Nothing -> return []
                                      Just y ->
                                            mapM (mapDescription cSig y) vlst
                                 ) d
                     let dlst = map (\ (x, y) ->
                                     Negation
                                     (
                                        Strong_equation
                                         (Qual_var (mkNName x) thing nullRange)
                                         (Qual_var (mkNName y) thing nullRange)
                                         nullRange
                                     )
                                     nullRange
                                    ) $ comPairs vlst vlst
                         dlstM = map (\ (x, y) ->
                                        Strong_equation
                                         (Qual_var (mkNName x) thing nullRange)
                                         (Qual_var (mkNName y) thing nullRange)
                                         nullRange
                                    ) $ comPairs vlstM vlstM

                         qVars = map (\ x ->
                                          Var_decl [mkNName x]
                                                    thing nullRange
                                     ) vlst
                         qVarsM = map (\ x ->
                                          Var_decl [mkNName x]
                                                    thing nullRange
                                     ) vlstM
                     oProps <- mapM (mapObjProp cSig oprop var) vlst
                     oPropsM <- mapM (mapObjProp cSig oprop var) vlstM
                     let minLst = Quantification Existential
                                  qVars
                                  (
                                   Conjunction
                                   (dlst ++ dOut ++ oProps)
                                   nullRange
                                  )
                                  nullRange
                     let maxLst = Quantification Universal
                                  qVarsM
                                  (
                                   Implication
                                   (Conjunction (oPropsM ++ dOut) nullRange)
                                   (Disjunction dlstM nullRange)
                                   True
                                   nullRange
                                  )
                                  nullRange
                     case ct of
                       MinCardinality -> return minLst
                       MaxCardinality -> return maxLst
                       ExactCardinality -> return $
                                           Conjunction
                                           [minLst, maxLst]
                                           nullRange

      DataValuesFrom _ _ _ _ -> fail "data handling nyi"
      DataHasValue _ _ -> fail "data handling nyi"
      DataCardinality _ -> fail "data handling nyi"
