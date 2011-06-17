{- |
Module      :  $Header$
Copyright   :  (c) Heng Jiang, Uni Bremen 2005-2006
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

Pretty printing for OWL 2 DL theories - Functional Syntax
-}

module OWL2.FunctionalPrint where

import Common.AS_Annotation
import Common.Doc
import Common.DocUtils
import Common.Id
import Common.Keywords

import OWL2.AS
import OWL2.FS
import OWL2.Print
import OWL.Keywords
import OWL.ColonKeywords

import qualified Data.Set as Set
import qualified Data.Map as Map

instance Pretty Axiom where
    pretty = printAxiom

printAssertion :: (Pretty a, Pretty b) => Assertion a b -> Doc
printAssertion (Assertion a p s b) = indStart <+> pretty s $+$
   let d = fsep [pretty a, pretty b] in
   keyword factsC <+> case p of
     Positive -> d
     Negative -> keyword notS <+> d

printAxiom :: Axiom -> Doc
printAxiom axiom = case axiom of
  EntityAnno _ -> empty -- EntityAnnotation
  PlainAxiom _ paxiom -> case paxiom of
   SubClassOf sub super -> case super of
     Expression curi
       | localPart curi == "Thing" && namePrefix curi == "owl" -> empty
     _ -> classStart <+> pretty sub $+$ keyword subClassOfC <+> pretty super
   EquivOrDisjointClasses ty (clazz : equiList) ->
       classStart <+> pretty clazz $+$ printEquivOrDisjoint ty <+>
                      setToDocV (Set.fromList equiList)
   DisjointUnion curi discList ->
       classStart <+> pretty curi $+$ keyword disjointUnionOfC <+>
                   setToDocV (Set.fromList discList)
   -- ObjectPropertyAxiom
   SubObjectPropertyOf sopExp opExp ->
       opStart <+> pretty opExp $+$ keyword (case sopExp of
                 SubObjectPropertyChain _ -> subPropertyChainC
                 _ -> subPropertyOfC)
                   <+> pretty sopExp
   EquivOrDisjointObjectProperties ty (opExp : opList) ->
       opStart <+> pretty opExp $+$ printEquivOrDisjoint ty <+>
                   setToDocV (Set.fromList opList)
   ObjectPropertyDomainOrRange ty opExp desc ->
       opStart <+> pretty opExp $+$ printObjDomainOrRange ty <+> pretty desc
   InverseObjectProperties opExp1 opExp2 ->
       opStart <+> pretty opExp1 $+$ keyword inverseOfC <+> pretty opExp2
   ObjectPropertyCharacter ch opExp ->
       opStart <+> pretty opExp $+$ printCharact (show ch)
   -- DataPropertyAxiom
   SubDataPropertyOf dpExp1 dpExp2 ->
       dpStart <+> pretty dpExp1 $+$ keyword subPropertyOfC <+> pretty dpExp2
   EquivOrDisjointDataProperties ty (dpExp : dpList) ->
       dpStart <+> pretty dpExp $+$ printEquivOrDisjoint ty <+>
               setToDocV (Set.fromList dpList)
   DataPropertyDomainOrRange ddr dpExp ->
       dpStart <+> pretty dpExp $+$ printDataDomainOrRange ddr
   FunctionalDataProperty dpExp ->
       dpStart <+> pretty dpExp $+$ printCharact functionalS
   -- Fact
   SameOrDifferentIndividual ty (ind : indList) ->
       indStart <+> pretty ind $+$ printSameOrDifferent ty <+>
                 setToDocV (Set.fromList indList)
   ClassAssertion desc ind ->
       indStart <+> pretty ind $+$ keyword typesC <+> pretty desc
   ObjectPropertyAssertion ass -> printAssertion ass
   DataPropertyAssertion ass -> printAssertion ass
   Declaration _ -> empty    -- [Annotation] Entity
   DatatypeDefinition dt dr ->
       keyword datatypeC <+> pretty dt $+$ keyword equivalentToC <+> pretty dr
   HasKey cexpr objlist datalist -> classStart <+> pretty cexpr $+$ keyword hasKeyC
     <+> vcat (punctuate comma $ map pretty objlist ++ map pretty datalist)
   u -> error $ "unknow axiom " ++ show u

instance Pretty OntologyFile where
    pretty = vsep . map pretty . axiomsList . ontology