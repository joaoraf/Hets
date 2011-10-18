{- |
Module      :  $Header$
Description :  auxiliary datastructures for development graphs
Copyright   :  (c) DFKI GmbH 2011
License     :  GPLv2 or higher, see LICENSE.txt
Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

-}

module Static.DgUtils where

import qualified Common.Lib.Rel as Rel
import Common.Id
import Common.Utils (numberSuffix, splitByList, splitOn, readMaybe)
import Common.LibName
import Common.Consistency

import Data.Graph.Inductive.Graph (Node)
import Data.List
import Data.Maybe

import qualified Data.Map as Map
import qualified Data.Set as Set

-- ** node label types

data XPathPart = ElemName String | ChildIndex Int deriving (Show, Eq, Ord)

{- | name of a node in a DG; auxiliary nodes may have extension string
     and non-zero number (for these, names are usually hidden). -}
data NodeName = NodeName
  { getName :: SIMPLE_ID
  , extString :: String
  , extIndex :: Int
  , xpath :: [XPathPart]
  } deriving (Show, Eq, Ord)

readXPath :: Monad m => String -> m [XPathPart]
readXPath = mapM readXPathComp . splitOn '/'

readXPathComp :: Monad m => String -> m XPathPart
readXPathComp s = case splitAt 5 s of
  ("Spec[", s') -> case readMaybe $ takeWhile (/= ']') s' of
        Just i -> return $ ChildIndex i
        Nothing -> fail "cannot read nodes ChildIndex"
  _ -> return $ ElemName s

isInternal :: NodeName -> Bool
isInternal n = extIndex n /= 0 || not (null $ extString n)

-- | test if a conservativity is open, return input for None
hasOpenConsStatus :: Bool -> ConsStatus -> Bool
hasOpenConsStatus b (ConsStatus cons _ thm) = case cons of
    None -> b
    _ -> not $ isProvenThmLinkStatus thm

data DGNodeType = DGNodeType
  { isRefType :: Bool
  , isProvenNode :: Bool
  , isProvenCons :: Bool
  , isInternalSpec :: Bool }
  deriving (Eq, Ord, Show)

listDGNodeTypes :: [DGNodeType]
listDGNodeTypes = let bs = [False, True] in
  [ DGNodeType
    { isRefType = ref
    , isProvenNode = isEmpty'
    , isProvenCons = proven
    , isInternalSpec = spec }
  | ref <- bs
  , isEmpty' <- bs
  , proven <- bs
  , spec <- bs ]

-- | node modifications
data NodeMod = NodeMod
  { delAx :: Bool
  , delTh :: Bool
  , addSen :: Bool
  , delSym :: Bool
  , addSym :: Bool }
  deriving (Show, Eq)

-- | an unmodified node
unMod :: NodeMod
unMod = NodeMod False False False False False

delAxMod :: NodeMod
delAxMod = unMod { delAx = True }

delThMod :: NodeMod
delThMod = unMod { delTh = True }

delSenMod :: NodeMod
delSenMod = delAxMod { delTh = True }

addSenMod :: NodeMod
addSenMod = unMod { addSen = True }

senMod :: NodeMod
senMod = delSenMod { addSen = True }

delSymMod :: NodeMod
delSymMod = unMod { delSym = True }

addSymMod :: NodeMod
addSymMod = unMod { addSym = True }

symMod :: NodeMod
symMod = delSymMod { addSym = True }

-- ** edge types

-- | unique number for edges
newtype EdgeId = EdgeId Int deriving (Show, Eq, Ord)

-- | next edge id
incEdgeId :: EdgeId -> EdgeId
incEdgeId (EdgeId i) = EdgeId $ i + 1

-- | the first edge in a graph
startEdgeId :: EdgeId
startEdgeId = EdgeId 0

showEdgeId :: EdgeId -> String
showEdgeId (EdgeId i) = show i

-- | a set of used edges
newtype ProofBasis = ProofBasis { proofBasis :: Set.Set EdgeId }
    deriving (Show, Eq, Ord)

{- | Rules in the development graph calculus,
   Sect. IV:4.4 of the CASL Reference Manual explains them in depth
-}
data DGRule =
    DGRule String
  | DGRuleWithEdge String EdgeId
  | DGRuleLocalInference [(String, String)] -- renamed theorems
  | Composition [EdgeId]
    deriving (Show, Eq)

-- | proof status of a link
data ThmLinkStatus = LeftOpen | Proven DGRule ProofBasis deriving (Show, Eq)

isProvenThmLinkStatus :: ThmLinkStatus -> Bool
isProvenThmLinkStatus tls = case tls of
  LeftOpen -> False
  _ -> True

proofBasisOfThmLinkStatus :: ThmLinkStatus -> ProofBasis
proofBasisOfThmLinkStatus tls = case tls of
  LeftOpen -> emptyProofBasis
  Proven _ pB -> pB

data Scope = Local | Global deriving (Show, Eq, Ord)

data LinkKind = DefLink | ThmLink ThmLinkStatus deriving (Show, Eq)

data FreeOrCofree = Free | Cofree | NPFree
  deriving (Show, Eq, Ord, Enum, Bounded, Read)

fcList :: [FreeOrCofree]
fcList = [minBound .. maxBound]

-- | required and proven conservativity (with a proof)
data ConsStatus = ConsStatus Conservativity Conservativity ThmLinkStatus
  deriving (Show, Eq)

isProvenConsStatusLink :: ConsStatus -> Bool
isProvenConsStatusLink = not . hasOpenConsStatus False

mkConsStatus :: Conservativity -> ConsStatus
mkConsStatus c = ConsStatus c None LeftOpen

getConsOfStatus :: ConsStatus -> Conservativity
getConsOfStatus (ConsStatus c _ _) = c

-- | to be displayed as edge label
showConsStatus :: ConsStatus -> String
showConsStatus cs = case cs of
  ConsStatus None None _ -> ""
  ConsStatus None _ LeftOpen -> ""
  ConsStatus c _ LeftOpen -> show c ++ "?"
  ConsStatus _ cp _ -> show cp

-- | converts a DGEdgeType to a String
getDGEdgeTypeName :: DGEdgeType -> String
getDGEdgeTypeName e =
  (if isInc e then (++ "Inc") else id)
  $ getDGEdgeTypeModIncName $ edgeTypeModInc e

revertDGEdgeTypeName :: String -> DGEdgeType
revertDGEdgeTypeName tp = fromMaybe (error "DevGraph.revertDGEdgeTypeName")
  $ find ((== tp) . getDGEdgeTypeName) listDGEdgeTypes

getDGEdgeTypeModIncName :: DGEdgeTypeModInc -> String
getDGEdgeTypeModIncName et = case et of
  ThmType thm isPrvn _ _ ->
    let prvn = (if isPrvn then "P" else "Unp") ++ "roven" in
    case thm of
      HidingThm -> prvn ++ "HidingThm"
      FreeOrCofreeThm fc -> prvn ++ shows fc "Thm"
      GlobalOrLocalThm scope isHom ->
          let het = if isHom then id else ("Het" ++) in
          het (case scope of
                 Local -> "Local"
                 Global -> if isHom then "Global" else "") ++ prvn ++ "Thm"
  FreeOrCofreeDef fc -> shows fc "Def"
  _ -> show et

data DGEdgeType = DGEdgeType
  { edgeTypeModInc :: DGEdgeTypeModInc
  , isInc :: Bool }
  deriving (Eq, Ord, Show)

data DGEdgeTypeModInc =
    GlobalDef
  | HetDef
  | HidingDef
  | LocalDef
  | FreeOrCofreeDef FreeOrCofree
  | ThmType { thmEdgeType :: ThmTypes
            , isProvenEdge :: Bool
            , isConservativ :: Bool
            , isPending :: Bool }
  deriving (Eq, Ord, Show)

data ThmTypes =
    HidingThm
  | FreeOrCofreeThm FreeOrCofree
  | GlobalOrLocalThm { thmScope :: Scope
                     , isHomThm :: Bool }
  deriving (Eq, Ord, Show)

-- | Creates a list with all DGEdgeType types
listDGEdgeTypes :: [DGEdgeType]
listDGEdgeTypes =
  [ DGEdgeType { edgeTypeModInc = modinc
               , isInc = isInclusion' }
  | modinc <-
    [ GlobalDef
    , HetDef
    , HidingDef
    , LocalDef
    ] ++ [ FreeOrCofreeDef fc | fc <- fcList ] ++
      [ ThmType { thmEdgeType = thmType
                , isProvenEdge = proven
                , isConservativ = cons
                , isPending = pending }
      | thmType <- HidingThm
        : [ FreeOrCofreeThm fc | fc <- fcList ] ++
          [ GlobalOrLocalThm { thmScope = scope
                             , isHomThm = hom }
          | scope <- [Local, Global]
          , hom <- [True, False]
          ]
      , proven <- [True, False]
      , cons <- [True, False]
      , pending <- [True, False]
      ]
  , isInclusion' <- [True, False]
  ]


-- * datatypes for storing the nodes of the ref tree in the global env

data RTPointer =
   RTNone
 | NPUnit Node
 | NPBranch Node (Map.Map SIMPLE_ID RTPointer)
        -- here the leaves can be either NPUnit or NPComp
 | NPRef Node Node
 | NPComp (Map.Map SIMPLE_ID RTPointer)
         {- here the leaves can be NPUnit or NPComp
         and roots are needed for inserting edges -}
 deriving (Show, Eq)

-- map nodes

mapRTNodes :: Map.Map Node Node -> RTPointer -> RTPointer
mapRTNodes f rtp = let app = flip $ Map.findWithDefault (error "mapRTNodes")
  in case rtp of
  RTNone -> RTNone
  NPUnit x -> NPUnit (app f x)
  NPRef x y -> NPRef (app f x) (app f y)
  NPBranch x g -> NPBranch (app f x) (Map.map (mapRTNodes f) g)
  NPComp g -> NPComp (Map.map (mapRTNodes f) g)

-- compositions

compPointer :: RTPointer -> RTPointer -> RTPointer
compPointer (NPUnit n1) (NPUnit n2) = NPRef n1 n2
compPointer (NPUnit n1) (NPBranch _ f) = NPBranch n1 f
compPointer (NPUnit n1) (NPRef _ n2) = NPRef n1 n2
compPointer (NPRef n1 _) (NPRef _ n2) = NPRef n1 n2
compPointer (NPRef n1 _) (NPBranch _ f) = NPBranch n1 f
compPointer (NPBranch n1 f1) (NPComp f2) =
       NPBranch n1 (Map.unionWith (\ _ y -> y) f1 f2 )
compPointer (NPComp f1) (NPComp f2) =
       NPComp (Map.unionWith (\ _ y -> y) f1 f2)
compPointer x y = error $ "compPointer:" ++ show x ++ " " ++ show y

-- sources

refSource :: RTPointer -> Node
refSource (NPUnit n) = n
refSource (NPBranch n _) = n
refSource (NPRef n _) = n
refSource x = error ("refSource:" ++ show x)

data RTLeaves = RTLeaf Node | RTLeaves (Map.Map SIMPLE_ID RTLeaves)
 deriving Show

refTarget :: RTPointer -> RTLeaves
refTarget (NPUnit n) = RTLeaf n
refTarget (NPRef _ n) = RTLeaf n
refTarget (NPComp f) = RTLeaves $ Map.map refTarget f
refTarget (NPBranch _ f) = RTLeaves $ Map.map refTarget f
refTarget x = error ("refTarget:" ++ show x)

-- ** for node names

emptyNodeName :: NodeName
emptyNodeName = NodeName (mkSimpleId "") "" 0 []

showExt :: NodeName -> String
showExt n = let i = extIndex n in extString n ++ if i == 0 then "" else show i

showName :: NodeName -> String
showName n = let ext = showExt n in
    tokStr (getName n) ++ if null ext then ext else "__" ++ ext

makeName :: SIMPLE_ID -> NodeName
makeName n = NodeName n "" 0 [ElemName $ tokStr n]

parseNodeName :: String -> NodeName
parseNodeName s = case splitByList "__" s of
                    [i] ->
                        makeName $ mkSimpleId i
                    [i, e] ->
                        let n = makeName $ mkSimpleId i
                            mSf = numberSuffix e
                            (es, sf) = fromMaybe (e, 0) mSf
                        in n { extString = es
                             , extIndex = sf }
                    _ ->
                        error
                        $ "parseNodeName: malformed NodeName, too many __: "
                              ++ s

incBy :: Int -> NodeName -> NodeName
incBy i n = n
  { extIndex = extIndex n + i
  , xpath = case xpath n of
              ChildIndex j : r -> ChildIndex (j + i) : r
              l -> ChildIndex i : l }

inc :: NodeName -> NodeName
inc = incBy 1

extName :: String -> NodeName -> NodeName
extName s n = n
  { extString = showExt n ++ take 1 s
  , extIndex = 0
  , xpath = ElemName s : xpath n }

-- ** handle edge numbers and proof bases

-- | create a default ID which has to be changed when inserting a certain edge.
defaultEdgeId :: EdgeId
defaultEdgeId = EdgeId $ -1

emptyProofBasis :: ProofBasis
emptyProofBasis = ProofBasis Set.empty

nullProofBasis :: ProofBasis -> Bool
nullProofBasis = Set.null . proofBasis

addEdgeId :: ProofBasis -> EdgeId -> ProofBasis
addEdgeId (ProofBasis s) e = ProofBasis $ Set.insert e s

-- | checks if the given edge is contained in the given proof basis..
edgeInProofBasis :: EdgeId -> ProofBasis -> Bool
edgeInProofBasis e = Set.member e . proofBasis

-- * utilities

topsortedLibsWithImports :: Rel.Rel LibName -> [LibName]
topsortedLibsWithImports = concatMap Set.toList . Rel.topSort

getMapAndMaxIndex :: Ord k => k -> (b -> Map.Map k a) -> b -> (Map.Map k a, k)
getMapAndMaxIndex c f gctx =
    let m = f gctx in (m, if Map.null m then c else fst $ Map.findMax m)

-- | or two predicates
liftOr :: (a -> Bool) -> (a -> Bool) -> a -> Bool
liftOr f g x = f x || g x
