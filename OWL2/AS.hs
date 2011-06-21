{- |
Module      :  $Header$
Copyright   :  (c) Heng Jiang, Uni Bremen 2004-2007
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  non-portable(deriving Typeable)

Common datatypes for Functional and Manchester Syntax of OWl 2

It is modeled after the W3C document:
<http://www.w3.org/TR/2009/REC-owl2-syntax-20091027/#Functional-Style_Syntax>
-}

module OWL2.AS where

import Common.Keywords
import Common.Id (GetRange)

import OWL.Keywords
import OWL.ColonKeywords
import qualified Data.Map as Map

{- | full or abbreviated IRIs with a possible uri for the prefix
     or a local part following a hash sign -}
data QName = QN
  { namePrefix :: String
  -- ^ the name prefix part of a qualified name \"namePrefix:localPart\"
  , localPart :: String
  -- ^ the local part of a qualified name \"namePrefix:localPart\"
  , isFullIri :: Bool
  , namespaceUri :: String
  -- ^ the associated namespace uri (not printed)
  } deriving Show

showQN :: QName -> String
showQN q = (if isFullIri q then showQI else showQU) q

-- | show QName as abbreviated iri
showQU :: QName -> String
showQU (QN pre local _ _) =
    if null pre then local else pre ++ ":" ++ local

-- | show QName in ankle brackets as full iris
showQI :: QName -> String
showQI = ('<' :) . (++ ">") . showQU

nullQName :: QName
nullQName = QN "" "" False ""

dummyQName :: QName
dummyQName = QN "http" "//www.dfki.de/sks/hets/ontology/unamed" True ""

mkQName :: String -> QName
mkQName s = nullQName { localPart = s }

instance Eq QName where
    p == q = compare p q == EQ

instance Ord QName where
  compare (QN p1 l1 b1 n1) (QN p2 l2 b2 n2) =
    if null n1 then
      if null n2 then compare (b1, p1, l1) (b2, p2, l2) else LT
    else if null n2 then GT else compare (b1, l1, n1) (b2, l2, n2)

type IRIreference = QName
type IRI = QName

-- | prefix -> localname
type PrefixMap = Map.Map String String

type NodeID = IRI
type LexicalForm = String
type LanguageTag = String
type PrefixName = String
type ImportIRI = IRI
type OntologyIRI = IRI
type Class = IRI
type Datatype = IRI
type ObjectProperty = IRI
type DataProperty = IRI
type AnnotationProperty = IRI
type NamedIndividual = IRI
type Individual = IRI

-------------------------
-- LITERALS
-------------------------

data TypedOrUntyped = Typed Datatype | Untyped (Maybe LanguageTag)
    deriving (Show, Eq, Ord)

data Literal = Literal LexicalForm TypedOrUntyped
    deriving (Show, Eq, Ord)

cTypeS :: String
cTypeS = "^^"

-- | a lexical representation either with an "^^" URI (typed) or
-- an optional language tag starting with "\@" (untyped)

--------------------------
-- PROPERTY EXPRESSIONS
--------------------------

type InverseObjectProperty = ObjectPropertyExpression

data ObjectPropertyExpression = ObjectProp ObjectProperty
  | ObjectInverseOf InverseObjectProperty
	deriving (Show, Eq, Ord)

type DataPropertyExpression = DataProperty

-- | data type strings (some are not listed in the grammar)
datatypeKeys :: [String]
datatypeKeys =
  [ booleanS
  , dATAS
  , decimalS
  , floatS
  , integerS
  , negativeIntegerS
  , nonNegativeIntegerS
  , nonPositiveIntegerS
  , positiveIntegerS
  , stringS
  , universalS
  ]

--------------------------
-- DATA RANGES
--------------------------

data DatatypeFacet =
    LENGTH
  | MINLENGTH
  | MAXLENGTH
  | PATTERN
  | MININCLUSIVE
  | MINEXCLUSIVE
  | MAXINCLUSIVE
  | MAXEXCLUSIVE
  | TOTALDIGITS
  | FRACTIONDIGITS
    deriving (Show, Eq, Ord)

showFacet :: DatatypeFacet -> String
showFacet df = case df of
    LENGTH -> lengthS
    MINLENGTH -> minLengthS
    MAXLENGTH -> maxLengthS
    PATTERN -> patternS
    MININCLUSIVE -> lessEq
    MINEXCLUSIVE -> lessS
    MAXINCLUSIVE -> greaterEq
    MAXEXCLUSIVE -> greaterS
    TOTALDIGITS -> digitsS
    FRACTIONDIGITS -> fractionS

data DataRange
	= DataType Datatype
	| DataJunction JunctionType [DataRange]
          -- at least two elements in the list
	| DataComplementOf DataRange
	| DataOneOf [Literal]	-- at least one element in the list
	| DatatypeRestriction Datatype [(ConstrainingFacet, RestrictionValue)]
	  -- at least one element in the list
	deriving (Show, Eq, Ord)

data JunctionType = UnionOf | IntersectionOf deriving (Show, Eq, Ord)

type ConstrainingFacet = IRI
type RestrictionValue = Literal

---------------------------
-- CLASS EXPERSSIONS
---------------------------

data QuantifierType = AllValuesFrom | SomeValuesFrom deriving (Show, Eq, Ord)

showQuantifierType :: QuantifierType -> String
showQuantifierType ty = case ty of
    AllValuesFrom -> onlyS
    SomeValuesFrom -> someS

data CardinalityType = MinCardinality | MaxCardinality | ExactCardinality
    deriving (Show, Eq, Ord)

showCardinalityType :: CardinalityType -> String
showCardinalityType ty = case ty of
    MinCardinality -> minS
    MaxCardinality -> maxS
    ExactCardinality -> exactlyS

data Cardinality a b = Cardinality CardinalityType Int a (Maybe b)
    deriving (Show, Eq, Ord)

data ClassExpression =
    Expression Class
  | ObjectJunction JunctionType [ClassExpression]  -- min. 2 ClassExpressions
  | ObjectComplementOf ClassExpression
  | ObjectOneOf [Individual]  -- min. 1 Individual
  | ObjectValuesFrom QuantifierType ObjectPropertyExpression ClassExpression
  | ObjectHasValue ObjectPropertyExpression Individual
  | ObjectHasSelf ObjectPropertyExpression
  | ObjectCardinality (Cardinality ObjectPropertyExpression ClassExpression)
  | DataValuesFrom QuantifierType
       DataPropertyExpression [DataPropertyExpression] DataRange
  | DataHasValue DataPropertyExpression Literal
  | DataCardinality (Cardinality DataPropertyExpression DataRange)
    deriving (Show, Eq, Ord)

-------------------
-- ANNOTATIONS
-------------------

data Annotation = Annotation [Annotation] AnnotationProperty AnnotationValue
	  deriving (Show, Eq, Ord)

data AnnotationAxiom
	= AnnotationAssertion [Annotation] IRI
	| SubAnnotationPropertyOf [Annotation] AnnotationProperty AnnotationProperty
	| AnnotationPropertyDomainOrRange AnnotationDomainOrRange [Annotation] AnnotationProperty IRI
	deriving (Show, Eq, Ord)

data AnnotationDomainOrRange = AnnDomain | AnnRange deriving (Show, Eq, Ord)

showAnnDomainOrRange :: AnnotationDomainOrRange -> String
showAnnDomainOrRange dr = case dr of
    AnnDomain -> domainC
    AnnRange -> rangeC

data AnnotationValue
	= AnnValue IRI
	| AnnValLit Literal
	  deriving (Show, Eq, Ord)

type SourceIndividual = Individual
type TargetIndividual = Individual
type TargetValue = Literal

data EquivOrDisjoint =
    Equivalent
  | Disjoint
  | SubPropertyOf
  | InverseOf
  | SubClass
  | Domain
  | Range
  | Types
    deriving (Show, Eq, Ord)

showEquivOrDisjoint :: EquivOrDisjoint -> String
showEquivOrDisjoint ed = case ed of
    Equivalent -> equivalentToC
    Disjoint -> disjointWithC
    SubPropertyOf -> subPropertyOfC
    InverseOf -> inverseOfC
    SubClass -> subClassOfC
    Domain -> domainC
    Range -> rangeC
    Types -> typesC

data ObjDomainOrRange = ObjDomain | ObjRange deriving (Show, Eq, Ord)

showObjDomainOrRange :: ObjDomainOrRange -> String
showObjDomainOrRange dr = case dr of
    ObjDomain -> domainC
    ObjRange -> rangeC

data DataDomainOrRange = DataDomain ClassExpression | DataRange DataRange
    deriving (Show, Eq, Ord)

data Character =
    Functional
  | InverseFunctional
  | Reflexive
  | Irreflexive
  | Symmetric
  | Asymmetric
  | Antisymmetric
  | Transitive
    deriving (Enum, Bounded, Show, Eq, Ord)

data SameOrDifferent = Same | Different | Individuals deriving (Show, Eq, Ord)

showSameOrDifferent :: SameOrDifferent -> String
showSameOrDifferent sd = case sd of
    Same -> sameAsC
    Different -> differentFromC
    Individuals -> individualsC

data PositiveOrNegative = Positive | Negative deriving (Show, Eq, Ord)

data SubObjectPropertyExpression
  = OPExpression ObjectPropertyExpression
  | SubObjectPropertyChain [ObjectPropertyExpression] -- min. 2 ObjectPropertyExpression
    deriving (Show, Eq, Ord)

--Entities

-- | Syntax of Entities
data Entity = Entity EntityType IRI deriving (Show, Eq, Ord)

instance GetRange Entity

data EntityType =
    Datatype
  | Class
  | ObjectProperty
  | DataProperty
  | AnnotationProperty
  | NamedIndividual
    deriving (Enum, Bounded, Show, Read, Eq, Ord)

entityTypes :: [EntityType]
entityTypes = [minBound .. maxBound]
