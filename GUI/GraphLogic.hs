{- |
Module      :  $Header$
Description :  Logic for manipulating the graph in the  Central GUI
Copyright   :  (c) Jorina Freya Gerken, Till Mossakowski, Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  till@tzi.de
Stability   :  provisional
Portability :  non-portable (imports Logic)
-}

module GUI.GraphLogic
    ( undo
    , redo
    , reload
    , performProofAction
    , openProofStatus
    , saveProofStatus
    , nodeErr
    , proofMenu
    , openTranslateGraph
    , showReferencedLibrary
    , showSpec
    , getSignatureOfNode
    , getTheoryOfNode
    , getLocalAxOfNode
    , translateTheoryOfNode
    , displaySubsortGraph
    , displayConceptGraph
    , lookupTheoryOfNode
    , getSublogicOfNode
    , showOriginOfNode
    , showProofStatusOfNode
    , proveAtNode
    , showJustSubtree
    , showIDOfEdge
    , getNumberOfNode
    , showMorphismOfEdge
    , showOriginOfEdge
    , checkconservativityOfEdge
    , showProofStatusOfThm
    , convertNodes
    , convertEdges
    , hideNodes
    , getLibDeps
    , hideShowNames
    , showNodes
    , translateGraph
    , showLibGraph
    )
    where

import Logic.Logic(conservativityCheck)
import Logic.Coerce(coerceSign, coerceMorphism)
import Logic.Grothendieck
import Logic.Comorphism
import Logic.Prover

import Comorphisms.LogicGraph(logicGraph)

import Syntax.AS_Library(LIB_NAME, getModTime, getLIB_ID)

import Static.DevGraph
import Static.DGToSpec(dgToSpec, computeTheory)
import Static.AnalysisLibrary(anaLibExt, anaLib)
import Static.DGTranslation(libEnv_translation)

import Proofs.EdgeUtils
import Proofs.InferBasic(basicInferenceNode)
import Proofs.StatusUtils(lookupHistory, removeContraryChanges)

import GUI.Utils(listBox, createTextSaveDisplay)
import GUI.Taxonomy (displayConceptGraph,displaySubsortGraph)
import GUI.DGTranslation(getDGLogic)
import GUI.GraphTypes
import GUI.AbstractGraphView as AGV
import qualified GUI.HTkUtils (displayTheory,
                               displayTheoryWithWarning,
                               createInfoDisplayWithTwoButtons)

import GraphDisp(deleteArc, deleteNode)
import TextDisplay(createTextDisplay)
import InfoBus(encapsulateWaitTermAct)
import DialogWin (useHTk)
import Messages(errorMess)
import qualified HTk

import Common.Id(nullRange)
import Common.DocUtils(showDoc, pretty)
import Common.Doc(vcat)
import Common.ResultT(liftR, runResultT)
import Common.AS_Annotation(isAxiom)
import Common.Result as Res
import qualified Common.OrderedMap as OMap
import qualified Common.InjMap as InjMap
import qualified Common.Lib.Rel as Rel
import qualified Common.Lib.Graph as Tree

import Driver.Options
import Driver.WriteFn(writeShATermFile)
import Driver.ReadFn(libNameToFile, readVerbose)

import System.Directory(getModificationTime)

import Data.IORef
import Data.Maybe(fromJust)
import Data.List(nub,deleteBy,find)
import Data.Graph.Inductive.Graph as Graph(Node, LEdge, LNode, lab', labNode')
import qualified Data.IntMap as IntMap
import qualified Data.Map as Map

--import Control.Monad()
import Control.Monad.Trans(lift)
import Control.Concurrent.MVar(tryPutMVar, readMVar, tryTakeMVar)

-- | Undo one step of the History
undo :: GInfo -> LibEnv -> IO ()
undo (GInfo {libEnvIORef = ioRefProofStatus,
             conversionMapsIORef = convRef,
             graphId = gid,
             gi_LIB_NAME = ln,
             gi_GraphInfo = actGraphInfo
             }) initEnv = do
  oldEnv <- readIORef ioRefProofStatus
  let
    gctx = lookupGlobalContext ln oldEnv
    initgctx = lookupGlobalContext ln initEnv
    phist = proofHistory gctx
    rhist = redoHistory gctx
  if phist == [emptyHistory] then return ()
    else do
      let
        lastchange = head phist
        phist' = tail phist
        rhist' = lastchange:rhist
        gctx' = (applyProofHistory phist' initgctx ) {redoHistory = rhist'}
        newEnv = Map.insert ln gctx' initEnv
        dgraph = devGraph gctx'
      writeIORef ioRefProofStatus newEnv
      remakeGraph convRef gid actGraphInfo dgraph ln

-- | redo one step of the redoHistory
redo :: GInfo -> LibEnv -> IO ()
redo (GInfo {libEnvIORef = ioRefProofStatus,
             conversionMapsIORef = convRef,
             graphId = gid,
             gi_LIB_NAME = ln,
             gi_GraphInfo = actGraphInfo
             }) initEnv = do
  oldEnv <- readIORef ioRefProofStatus
  let
    gctx = lookupGlobalContext ln oldEnv
    initgctx = lookupGlobalContext ln initEnv
    phist = proofHistory gctx
    rhist = redoHistory gctx
  if rhist == [emptyHistory] then return ()
    else do
      let
        nextchange = head rhist
        rhist' = tail rhist
        phist' = nextchange:phist
        gctx' = (applyProofHistory phist' initgctx) {redoHistory = rhist'}
        newEnv = Map.insert ln gctx' initEnv
        dgraph = devGraph gctx'
      writeIORef ioRefProofStatus newEnv
      remakeGraph convRef gid actGraphInfo dgraph ln

-- | reloads the Library of the DevGraph
reload :: GInfo -> IO()
reload (GInfo {libEnvIORef = ioRefProofStatus,
             conversionMapsIORef = convRef,
             graphId = gid,
             gi_LIB_NAME = ln,
             gi_GraphInfo = actGraphInfo,
             gi_hetcatsOpts = opts
             }) = do
  oldle <- readIORef ioRefProofStatus
  let
    libdeps = Rel.toList $ Rel.intransKernel $ Rel.transClosure $ Rel.fromList
              $ getLibDeps oldle
  ioruplibs <- newIORef ([] :: [LIB_NAME])
  writeIORef ioruplibs []
  reloadLibs ioRefProofStatus opts libdeps ioruplibs ln
  le <- readIORef ioRefProofStatus
  let
    dgraph = devGraph $ lookupGlobalContext ln le
  writeIORef ioRefProofStatus le
  remakeGraph convRef gid actGraphInfo dgraph ln

-- | Creates a list of all LIB_NAME pairs, which have a dependency
getLibDeps :: LibEnv -> [(LIB_NAME, LIB_NAME)]
getLibDeps le =
  concat $ map (\ ln -> getDep ln le) $ Map.keys le

-- | Creates a list of LIB_NAME pairs for the fist argument 
getDep :: LIB_NAME -> LibEnv -> [(LIB_NAME, LIB_NAME)]
getDep ln le =
  map (\ x -> (ln, x)) $ map (\ (_,x,_) -> dgn_libname x) $ IntMap.elems $
    IntMap.filter (\ (_,x,_) -> isDGRef x) $ Tree.convertToMap $ 
    dgBody $ devGraph $ lookupGlobalContext ln le

-- | Reloads a library
reloadLib :: IORef LibEnv -> HetcatsOpts -> IORef [LIB_NAME] -> LIB_NAME
          -> IO ()
reloadLib iorle opts ioruplibs ln = do
  mfile <- existsAnSource opts {intype = GuessIn}
           $ rmSuffix $ libNameToFile opts ln
  case mfile of
    Nothing -> do
      return ()
    Just file -> do
      le <- readIORef iorle
      let
        le' = Map.delete ln le
      mres <- anaLibExt opts file le'
      case mres of
        Just (_, newle) -> do
          uplibs <- readIORef ioruplibs
          writeIORef ioruplibs $ ln:uplibs
          writeIORef iorle newle
          return ()
        Nothing -> do
          fail $ "Could not read original development graph from '"++ file
                 ++  "'"
          return ()

-- | Reloads libraries if nessesary
reloadLibs :: IORef LibEnv -> HetcatsOpts -> [(LIB_NAME, LIB_NAME)]
           -> IORef [LIB_NAME] -> LIB_NAME -> IO Bool
reloadLibs iorle opts deps ioruplibs ln = do
  uplibs <- readIORef ioruplibs
  case elem ln uplibs of
    True -> return True
    False -> do
      let
        deps' = map (snd) $ filter (\ (ln',_) -> ln == ln') deps
      res <- mapM (reloadLibs iorle opts deps ioruplibs) deps'
      let
        libupdate = foldl (\ u r -> if r then True else u) False res
      case libupdate of
        True -> do
          reloadLib iorle opts ioruplibs ln
          return True
        False -> do
          le <- readIORef iorle
          let
            newln:_ = filter (ln ==) $ Map.keys le
          mfile <- existsAnSource opts $ rmSuffix $ libNameToFile opts ln
          case mfile of
            Nothing -> do
              return False
            Just file -> do
              newmt <- getModificationTime file
              let
                libupdate' = (getModTime $ getLIB_ID newln) < newmt
              case libupdate' of
                False -> return False
                True -> do
                  reloadLib iorle opts ioruplibs ln
                  return True

-- | Deletes the old edges and nodes of the Graph and makes new ones
remakeGraph :: IORef ConversionMaps -> Descr -> GraphInfo -> DGraph -> LIB_NAME
            -> IO ()
remakeGraph convRef gid actginfo dgraph ln = do
  (gs,ev_cnt) <- readIORef actginfo
  let
    Just (_, g) = find (\ (gid', _) -> gid' == gid) gs
    gs' = deleteBy (\ (gid1,_) (gid2,_) -> gid1 == gid2) (gid,g) gs
    og = theGraph g
  -- reads and delets the old nodes and edges
  mapM_ (deleteArc og) $ map (\ (_,_,_,x) -> x) $ map snd $ AGV.edges g
  mapM_ (deleteNode og) $ map snd $ map snd $ AGV.nodes g
  -- stores the graph without nodes and edges in the GraphInfo
  let
    g' = g {theGraph = og, AGV.nodes = [], AGV.edges = []}
  writeIORef actginfo ((gid,g'):gs',ev_cnt)
  -- creates new nodes and edges
  convMaps <- readIORef convRef
  newConvMaps <- convertNodes convMaps gid actginfo dgraph ln
  finalConvMaps <- convertEdges newConvMaps gid actginfo dgraph ln
  -- writes the ConversionMap and redisplays the graph
  writeIORef convRef finalConvMaps
  redisplay gid actginfo
  return ()

hideShowNames :: GInfo -> IO ()
hideShowNames (GInfo {graphId = gid,
                      gi_GraphInfo = actGraphInfo,
                      internalNamesIORef = showInternalNames
                     }) = do
  (intrn::InternalNames) <- readIORef showInternalNames
  let showThem = not $ showNames intrn
      showItrn s = if showThem then s else ""
  mapM_ (\(s,upd) -> upd (\_ -> showItrn s)) $ updater intrn
  writeIORef showInternalNames $ intrn {showNames = showThem}
  redisplay gid actGraphInfo
  return ()

showNodes :: GInfo -> IO ()
showNodes (GInfo {descrIORef = event,
                  graphId = gid,
                  gi_GraphInfo = actGraphInfo
                 }) = do
  descr <- readIORef event
  showIt gid descr actGraphInfo
  redisplay gid actGraphInfo
  return ()

translateGraph :: GInfo -> ConvFunc -> LibFunc -> IO ()
translateGraph (GInfo {libEnvIORef = ioRefProofStatus,
                       gi_LIB_NAME = ln,
                       gi_hetcatsOpts = opts
                      }) convGraph showLib = do
  le <- readIORef ioRefProofStatus
  openTranslateGraph le ln opts (getDGLogic le) convGraph showLib

showLibGraph :: GInfo -> LibFunc -> IO ()
showLibGraph gInfo showLib = do
  showLib gInfo
  return ()

performProofAction :: GInfo -> IO () -> IO ()
performProofAction gInfo@(GInfo {descrIORef = event,
                                 graphId = gid,
                                 gi_GraphInfo = actGraphInfo
                                }) proofAction = do
  descr <- readIORef event
  AGV.Result _ errorMsg <- checkHasHiddenNodes gid descr actGraphInfo
  case errorMsg of
    Nothing -> do
      showNodes gInfo
      proofAction
      hideNodes gInfo
    Just _ -> proofAction

saveProofStatus :: GInfo -> FilePath -> IO ()
saveProofStatus (GInfo {libEnvIORef = ioRefProofStatus,
                        gi_LIB_NAME = ln,
                        gi_hetcatsOpts = opts
                       }) file = encapsulateWaitTermAct $ do
    proofStatus <- readIORef ioRefProofStatus
    writeShATermFile file (ln, lookupHistory ln proofStatus)
    putIfVerbose opts 2 $ "Wrote " ++ file

-- | implementation of open menu, read in a proof status
openProofStatus :: GInfo -> FilePath -> ConvFunc -> LibFunc
                -> IO (Descr, GraphInfo, ConversionMaps)
openProofStatus (GInfo {libEnvIORef = ioRefProofStatus,
                        conversionMapsIORef = convRef,
                        gi_LIB_NAME = ln,
                        gi_hetcatsOpts = opts
                       }) file convGraph showLib = do
    mh <- readVerbose opts ln file
    case mh of
      Nothing -> fail
                 $ "Could not read proof status from file '"
                       ++ file ++ "'"
      Just h -> do
          let libfile = libNameToFile opts ln
          m <- anaLib opts { outtypes = [] } libfile
          case m of
            Nothing -> fail
                 $ "Could not read original development graph from '"
                       ++ libfile ++  "'"
            Just (_, libEnv) -> case Map.lookup ln libEnv of
                Nothing -> fail
                 $ "Could not get original development graph for '"
                       ++ showDoc ln "'"
                Just gctx -> do
                    oldEnv <- readIORef ioRefProofStatus
                    let proofStatus = Map.insert ln
                                      (applyProofHistory h gctx) oldEnv
                    writeIORef ioRefProofStatus proofStatus
                    gInfo <- emptyGInfo
                    gInfo' <- setGInfo gInfo ln proofStatus opts          
                    (gid, actGraphInfo, convMaps) <-
                      convGraph gInfo' "Proof Status " showLib
                    writeIORef convRef convMaps
                    redisplay gid actGraphInfo
                    return (gid, actGraphInfo, convMaps)

-- | apply a rule of the development graph calculus
proofMenu :: GInfo
             -> (LibEnv -> IO (Res.Result LibEnv))
             -> IO ()
proofMenu (GInfo {libEnvIORef = ioRefProofStatus,
                  descrIORef = event,
                  conversionMapsIORef = convRef,
                  graphId = gid,
                  gi_LIB_NAME = ln,
                  gi_GraphInfo = actGraphInfo,
                  gi_hetcatsOpts = hOpts,
                  proofGUIMVar = guiMVar,
                  visibleNodesIORef = ioRefVisibleNodes}) proofFun = do
  filled <- tryPutMVar guiMVar Nothing
  if not filled
     then readMVar guiMVar >>=
                  (maybe (putIfVerbose hOpts 4 "proofMenu: ignored Nothing")
                         (\ w -> do
                             putIfVerbose hOpts 4 $
                                  "proofMenu: Ignored Proof command; " ++
                                  "maybe a proof window is still open?"
                             HTk.putWinOnTop w))
     else do
        proofStatus <- readIORef ioRefProofStatus
        putIfVerbose hOpts 4 "Proof started via \"Proofs\" menu"
        Res.Result ds res <- proofFun proofStatus
        putIfVerbose hOpts 4 "Analyzing result of proof"
        case res of
          Nothing -> mapM_ (putStrLn . show) ds
          Just newProofStatus -> do
             let newGlobContext = lookupGlobalContext ln newProofStatus
                 history = proofHistory newGlobContext
             writeIORef ioRefProofStatus newProofStatus
             descr <- readIORef event
             convMaps <- readIORef convRef
             (newDescr,convMapsAux)
                 <- applyChanges gid ln actGraphInfo descr ioRefVisibleNodes
                                 convMaps history
             writeIORef ioRefProofStatus $
               Map.insert ln newGlobContext newProofStatus
             writeIORef event newDescr
             writeIORef convRef convMapsAux
             redisplay gid actGraphInfo
             mGUIMVar <- tryTakeMVar guiMVar
             maybe (fail $ "should be filled with Nothing after "++
                        "proof attempt")
                   (const $ return ())
                   mGUIMVar

nodeErr :: Descr -> IO ()
nodeErr descr = error $ "node with descriptor " ++ show descr
                ++ " has no corresponding node in the development graph"

showSpec :: Descr -> DGraphAndAGraphNode -> DGraph -> IO ()
showSpec descr dgAndabstrNodeMap dgraph =
  case InjMap.lookupWithB descr dgAndabstrNodeMap of
   Nothing -> return ()
   Just (_, node) -> do
      let sp = dgToSpec dgraph node
      putStrLn $ case sp of
            Res.Result ds Nothing -> show $ vcat $ map pretty ds
            Res.Result _ m -> showDoc m ""

hideNodes :: GInfo -> IO ()
hideNodes (GInfo {descrIORef = event,
                    graphId = gid,
                    gi_GraphInfo = actGraphInfo
                   }) = do 
  AGV.Result descr msg <- hideSetOfNodeTypes gid
                            ["open_cons__internal",
                             "locallyEmpty__open_cons__internal",
                             "proven_cons__internal",
                             "locallyEmpty__proven_cons__internal"]
                            True actGraphInfo
  writeIORef event descr
  case msg of
    Nothing -> do redisplay gid actGraphInfo
                  return ()
    Just err -> putStrLn err
  return () 

{- | auxiliary method for debugging. shows the number of the given node
     in the abstraction graph -}
getNumberOfNode :: Descr -> IO()
getNumberOfNode descr =
  let title = "Number of node"
-- make the node number consistent
    in createTextDisplay title (showDoc (descr-1) "") [HTk.size(10,10)]

{- | outputs the signature of a node in a window;
used by the node menu defined in initializeGraph -}
getSignatureOfNode :: Descr -> DGraphAndAGraphNode -> DGraph -> IO()
getSignatureOfNode descr dgAndabstrNodeMap dgraph =
  case InjMap.lookupWithB descr dgAndabstrNodeMap of
    Just (_, node) ->
      let dgnode = lab' (contextDG dgraph node)
          title = "Signature of "++showName (dgn_name dgnode)
       in createTextDisplay title (showDoc (dgn_sign dgnode) "")
                            [HTk.size(80,50)]
    Nothing -> nodeErr descr

{- |
   fetches the theory from a node inside the IO Monad
   (added by KL based on code in getTheoryOfNode) -}
lookupTheoryOfNode :: IORef LibEnv -> Descr -> DGraphAndAGraphNode ->
                      DGraph -> IO (Res.Result (Node,G_theory))
lookupTheoryOfNode proofStatusRef descr dgAndabstrNodeMap _ = do
 libEnv <- readIORef proofStatusRef
 case (do
  (ln, node) <-
        maybeToResult nullRange ("Node "++show descr++" not found")
                       $ InjMap.lookupWithB descr dgAndabstrNodeMap
  gth <- computeTheory libEnv ln node
  return (node, gth)
    ) of
   r -> do
         return r

{- | outputs the local axioms of a node in a window;
used by the node menu defined in initializeGraph-}
getLocalAxOfNode :: GInfo -> Descr -> DGraphAndAGraphNode -> DGraph -> IO ()
getLocalAxOfNode _ descr dgAndabstrNodeMap dgraph = do
  case InjMap.lookupWithB descr dgAndabstrNodeMap of
    Just (_, node) ->
      do let dgnode = lab' (contextDG dgraph node)
         case dgnode of
           DGNode _ gth _ _ _ _ _ ->
              displayTheory "Local Axioms" node dgraph gth
           DGRef name _ _ _ _ _ ->
              createTextDisplay ("Local Axioms of "++ showName name)
                    "no local axioms (reference node to other library)"
                    [HTk.size(30,10)]
    Nothing -> nodeErr descr

{- | outputs the theory of a node in a window;
used by the node menu defined in initializeGraph-}
getTheoryOfNode :: GInfo -> Descr -> DGraphAndAGraphNode -> DGraph -> IO ()
getTheoryOfNode gInfo descr dgAndabstrNodeMap dgraph = do
 r <- lookupTheoryOfNode (libEnvIORef gInfo) descr dgAndabstrNodeMap dgraph
 case r of
  Res.Result ds res -> do
    showDiags (gi_hetcatsOpts gInfo) ds
    case res of
      (Just (n, gth)) ->
            GUI.HTkUtils.displayTheoryWithWarning
                "Theory"
                (showName $ dgn_name $ lab' (contextDG dgraph n))
                (addHasInHidingWarning dgraph n)
                gth
      _ -> return ()

displayTheory :: String -> Node -> DGraph -> G_theory -> IO ()
displayTheory ext node dgraph gth =
     GUI.HTkUtils.displayTheory ext
        (showName $ dgn_name $ lab' (contextDG dgraph node))
        gth

{- | translate the theory of a node in a window;
used by the node menu defined in initializeGraph-}
translateTheoryOfNode :: GInfo -> Descr -> DGraphAndAGraphNode -> DGraph
                      -> IO ()
translateTheoryOfNode gInfo@(GInfo {gi_hetcatsOpts = opts})
                      descr dgAndabstrNodeMap dgraph = do
 libEnv <- readIORef $ libEnvIORef gInfo
 case (do
   (ln, node) <-
        maybeToResult nullRange ("Node "++show descr++" not found")
                       $ InjMap.lookupWithB descr dgAndabstrNodeMap
   th <- computeTheory libEnv ln node
   return (node,th) ) of
  Res.Result [] (Just (node,th)) -> do
    Res.Result ds _ <-  runResultT(
      do G_theory lid sign _ sens _ <- return th
         -- find all comorphism paths starting from lid
         let paths = findComorphismPaths logicGraph (sublogicOfTh th)
         -- let the user choose one
         sel <- lift $ listBox "Choose a logic translation"
                   (map show paths)
         i <- case sel of
           Just j -> return j
           _ -> liftR $ fail "no logic translation chosen"
         Comorphism cid <- return (paths!!i)
         -- adjust lid's
         let lidS = sourceLogic cid
             lidT = targetLogic cid
         sign' <- coerceSign lid lidS "" sign
         sens' <- coerceThSens lid lidS "" sens
         -- translate theory along chosen comorphism
         (sign'',sens1) <-
             liftR $ wrapMapTheory cid (sign', toNamedList sens')
         lift $ GUI.HTkUtils.displayTheoryWithWarning
                "Translated Theory"
                (showName $ dgn_name $ lab' (contextDG dgraph node))
                (addHasInHidingWarning dgraph node)
                (G_theory lidT sign'' 0 (toThSens sens1) 0)
     )
    showDiags opts ds
    return ()
  Res.Result ds _ -> showDiags opts ds

{- | outputs the sublogic of a node in a window;
used by the node menu defined in initializeGraph -}
getSublogicOfNode :: IORef LibEnv -> Descr -> DGraphAndAGraphNode
                  -> DGraph -> IO()
getSublogicOfNode proofStatusRef descr dgAndabstrNodeMap dgraph = do
  libEnv <- readIORef proofStatusRef
  case InjMap.lookupWithB descr dgAndabstrNodeMap of
    Just (ln, node) ->
      let dgnode = lab' (contextDG dgraph node)
          name = case dgnode of
                       (DGNode nname _ _ _ _ _ _) -> nname
                       _ -> emptyNodeName
       in case computeTheory libEnv ln node of
        Res.Result _ (Just th) ->
                let logstr = show $ sublogicOfTh th
                    title =  "Sublogic of "++showName name
                 in createTextDisplay title logstr [HTk.size(30,10)]
        Res.Result ds _ ->
          error $ "Could not compute theory for sublogic computation: "
                ++ concatMap show ds
    Nothing -> nodeErr descr

-- | prints the origin of the node
showOriginOfNode :: Descr -> DGraphAndAGraphNode -> DGraph -> IO()
showOriginOfNode descr dgAndabstrNodeMap dgraph =
  case InjMap.lookupWithB descr dgAndabstrNodeMap of
    Just (_, node) ->
      do let dgnode = lab' (contextDG dgraph node)
         case dgnode of
           DGNode name _ _ _ orig _ _ ->
              let title =  "Origin of node "++showName name
               in createTextDisplay title
                    (showDoc orig "") [HTk.size(30,10)]
           DGRef _ _ _ _ _ _ -> error "showOriginOfNode: no DGNode"
    Nothing -> nodeErr descr

-- | Show proof status of a node
showProofStatusOfNode :: GInfo -> Descr -> DGraphAndAGraphNode -> DGraph
                      -> IO ()
showProofStatusOfNode _ descr dgAndabstrNodeMap dgraph =
  case InjMap.lookupWithB descr dgAndabstrNodeMap of
    Just (_, node) ->
      do let dgnode = lab' (contextDG dgraph node)
         let stat = showStatusAux dgnode
         let title =  "Proof status of node "++showName (dgn_name dgnode)
         createTextDisplay title stat [HTk.size(105,55)]
    Nothing -> nodeErr descr

showStatusAux :: DGNodeLab -> String
showStatusAux dgnode =
  case dgn_theory dgnode of
  G_theory _ _ _ sens _ ->
     let goals = OMap.filter (not . isAxiom) sens
         (proven,open) = OMap.partition isProvenSenStatus goals
      in "Proven proof goals:\n"
         ++ showDoc proven ""
         ++ if not $ hasOpenConsStatus True dgnode
             then showDoc (dgn_cons_status dgnode)
                      "is the conservativity status of this node"
             else ""
         ++ "\nOpen proof goals:\n"
         ++ showDoc open ""
         ++ if hasOpenConsStatus False dgnode
             then showDoc (dgn_cons_status dgnode)
                      "should be the conservativity status of this node"
             else ""

-- | start local theorem proving or consistency checking at a node
proveAtNode :: Bool -> GInfo -> Descr -> DGraphAndAGraphNode -> DGraph -> IO ()
proveAtNode checkCons
            gInfo@(GInfo {gi_LIB_NAME = ln, proofGUIMVar = guiMVar})
            descr
            dgAndabstrNodeMap
            dgraph =
  case InjMap.lookupWithB descr dgAndabstrNodeMap of
    Just libNode -> if (checkCons
                        || not (hasIncomingHidingEdge dgraph $ snd libNode))
                       then
                       proofMenu gInfo (basicInferenceNode checkCons
                                        logicGraph libNode ln guiMVar)
                       else
                       GUI.HTkUtils.createInfoDisplayWithTwoButtons
                           "Warning"
                           "This node has incoming hiding links!!!"
                           "Prove anyway"
                           (proofMenu gInfo (basicInferenceNode checkCons
                                            logicGraph libNode ln guiMVar))
    Nothing -> nodeErr descr

-- | print the id of the edge
showIDOfEdge :: Descr -> Maybe (LEdge DGLinkLab) -> IO ()
showIDOfEdge _ (Just (_, _, linklab)) =
      createTextDisplay "ID of Edge" (show $ dgl_id linklab) [HTk.size(30,10)]
showIDOfEdge descr Nothing =
      createTextDisplay "Error"
          ("edge " ++ show descr ++ " has no corresponding edge"
                ++ "in the development graph") [HTk.size(30,10)]

-- | print the morphism of the edge
showMorphismOfEdge :: Descr -> Maybe (LEdge DGLinkLab) -> IO ()
showMorphismOfEdge _ (Just (_,_,linklab)) =
      createTextDisplay "Signature morphism"
           (showDoc (dgl_morphism linklab) "" ++ hidingMorph)
           [HTk.size(100,40)]
  where
    hidingMorph = case dgl_type linklab of
                    HidingThm morph _ -> "\n ++++++ \n"
                                           ++ showDoc morph ""
                    _ -> ""
showMorphismOfEdge descr Nothing =
      createTextDisplay "Error"
          ("edge " ++ show descr ++ " has no corresponding edge"
                ++ "in the development graph") [HTk.size(30,10)]

-- | print the origin of the edge
showOriginOfEdge :: Descr -> Maybe (LEdge DGLinkLab) -> IO ()
showOriginOfEdge _ (Just (_,_,linklab)) =
      createTextDisplay "Origin of link"
        (showDoc (dgl_origin linklab) "")  [HTk.size(30,10)]
showOriginOfEdge descr Nothing =
      createTextDisplay "Error"
         ("edge " ++ show descr ++ " has no corresponding edge"
                ++ "in the development graph") [HTk.size(30,10)]

-- | print the proof base of the edge
showProofStatusOfThm :: Descr -> Maybe (LEdge DGLinkLab) -> IO ()
showProofStatusOfThm _ (Just ledge) =
    createTextSaveDisplay "Proof Status" "proofstatus.txt"
         (showDoc (getProofStatusOfThm ledge) "\n")
showProofStatusOfThm descr Nothing =
    -- why putStrLn here and no createTextDisplay elsewhere with this message
    putStrLn ("edge " ++ show descr ++ " has no corresponding edge"
                ++ "in the development graph")

-- | check conservativity of the edge
checkconservativityOfEdge :: Descr -> GInfo -> Maybe (LEdge DGLinkLab) -> IO()
checkconservativityOfEdge _ gInfo
                           (Just (source,target,linklab)) = do
  libEnv <- readIORef $ libEnvIORef gInfo
  let dgraph = lookupDGraph (gi_LIB_NAME gInfo) libEnv
      dgtar = lab' (contextDG dgraph target)
  case dgtar of
    DGNode _ (G_theory lid _ _ sens _) _ _ _ _ _ ->
     case dgl_morphism linklab of
     GMorphism cid _ _ morphism2 _ -> do
      morphism2' <- coerceMorphism (targetLogic cid) lid
                   "checkconservativityOfEdge" morphism2
      let th = case computeTheory libEnv (gi_LIB_NAME gInfo) source of
                Res.Result _ (Just th1) -> th1
                _ -> error "checkconservativityOfEdge: computeTheory"
      G_theory lid1 sign1 _ sens1 _ <- return th
      sign2 <- coerceSign lid1 lid "checkconservativityOfEdge.coerceSign" sign1
      sens2 <- coerceThSens lid1 lid "" sens1
      let Res.Result ds res =
                     conservativityCheck lid (sign2, toNamedList sens2)
                                         morphism2' $ toNamedList sens
          showRes = case res of
                   Just(Just True) -> "The link is conservative"
                   Just(Just False) -> "The link is not conservative"
                   _ -> "Could not determine whether link is conservative"
          myDiags = unlines (map show ds)
      createTextDisplay "Result of conservativity check"
                      (showRes ++ "\n" ++ myDiags) [HTk.size(50,50)]
    DGRef _ _ _ _ _ _ -> error "checkconservativityOfEdge: no DGNode"

checkconservativityOfEdge descr _ Nothing =
      createTextDisplay "Error"
          ("edge " ++ show descr ++ " has no corresponding edge "
                ++ "in the development graph") [HTk.size(30,10)]

getProofStatusOfThm :: (LEdge DGLinkLab) -> ThmLinkStatus
getProofStatusOfThm (_,_,label) =
  case (dgl_type label) of
    (LocalThm proofStatus _ _) -> proofStatus
    (GlobalThm proofStatus _ _) -> proofStatus
    (HidingThm _ proofStatus) -> proofStatus -- richtig?
    _ -> error "the given edge is not a theorem"

{- | converts the nodes of the development graph, if it has any,
and returns the resulting conversion maps
if the graph is empty the conversion maps are returned unchanged-}
convertNodes :: ConversionMaps -> Descr -> GraphInfo -> DGraph
                  -> LIB_NAME -> IO ConversionMaps
convertNodes convMaps descr grInfo dgraph libname
  | isEmptyDG dgraph = return convMaps
  | otherwise = convertNodesAux convMaps
                                descr
                                grInfo
                                (labNodesDG dgraph)
                                libname

{- | auxiliary function for convertNodes if the given list of nodes is
emtpy, it returns the conversion maps unchanged otherwise it adds the
converted first node to the abstract graph and to the affected
conversion maps and afterwards calls itself with the remaining node
list -}
convertNodesAux :: ConversionMaps -> Descr -> GraphInfo ->
                     [LNode DGNodeLab] -> LIB_NAME -> IO ConversionMaps
convertNodesAux convMaps _ _ [] _ = return convMaps
convertNodesAux convMaps descr grInfo ((node,dgnode) : lNodes) libname =
  do let nodetype = getDGNodeType dgnode
     AGV.Result newDescr _ <- addnode descr
                                nodetype
                                (getDGNodeName dgnode)
                                grInfo
     convertNodesAux convMaps
       { dgAndabstrNode = InjMap.insert (libname, node) newDescr
                          (dgAndabstrNode convMaps)
       } descr grInfo lNodes libname

{- | converts the edges of the development graph
works the same way as convertNods does-}
convertEdges :: ConversionMaps -> Descr -> GraphInfo -> DGraph
                  -> LIB_NAME -> IO ConversionMaps
convertEdges convMaps descr grInfo dgraph libname
  | isEmptyDG dgraph = return convMaps
  | otherwise = convertEdgesAux convMaps
                                descr
                                grInfo
                                (labEdgesDG dgraph)
                                libname

-- | auxiliary function for convertEges
convertEdgesAux :: ConversionMaps -> Descr -> GraphInfo ->
                    [LEdge DGLinkLab] -> LIB_NAME -> IO ConversionMaps
convertEdgesAux convMaps _ _ [] _ = return convMaps
convertEdgesAux convMaps descr grInfo (ledge@(src,tar,edgelab) : lEdges)
                libname =
  do let srcnode = InjMap.lookupWithA (libname,src) (dgAndabstrNode convMaps)
         tarnode = InjMap.lookupWithA (libname,tar) (dgAndabstrNode convMaps)
     case (srcnode, tarnode) of
      (Just s, Just t) -> do
        AGV.Result newDescr msg <- addlink descr (getDGLinkType edgelab)
                                   "" (Just ledge) s t grInfo
        case msg of
          Nothing -> return ()
          Just err -> fail err
        newConvMaps <- convertEdgesAux convMaps
            { dgAndabstrEdge = InjMap.insert (libname,
                                              (src, tar, showDoc edgelab ""))
                  newDescr (dgAndabstrEdge convMaps)
            } descr grInfo lEdges libname
        return newConvMaps
      _ -> error "Cannot find nodes"

-- | show library referened by a DGRef node (=node drawn as a box)
showReferencedLibrary :: Descr -> GInfo -> ConvFunc -> LibFunc
                      -> IO (Descr, GraphInfo, ConversionMaps)
showReferencedLibrary 
  descr gInfo@(GInfo {libEnvIORef = ioRefProofStatus,
                                     conversionMapsIORef = convRef,
                                     gi_GraphInfo = actGraphInfo,
                                     gi_hetcatsOpts = opts}) convGraph
  showLib = do
  convMaps <- readIORef convRef
  libname2dgMap <- readIORef ioRefProofStatus
  case InjMap.lookupWithB descr (dgAndabstrNode convMaps) of
    Just (libname,node) ->
         case Map.lookup libname libname2dgMap of
          Just gctx ->
            do let dgraph = devGraph gctx
                   (_,(DGRef _ refLibname _ _ _ _)) =
                       labNode' (contextDG dgraph node)
               case Map.lookup refLibname libname2dgMap of
                 Just _ -> do
                   (_,next) <- readIORef actGraphInfo
                   let gInfo' = gInfo {graphId = next}
                   gInfo'' <- setGInfo gInfo' refLibname libname2dgMap opts
                   convGraph gInfo'' "development graph" showLib
                 Nothing -> error $ "The referenced library ("
                                     ++ show refLibname
                                     ++ ") is unknown"
          Nothing -> error $ "Selected node belongs to unknown library: "
                         ++ show libname
    Nothing ->
      error $ "there is no node with the descriptor " ++ show descr

-- | prune displayed graph to subtree of selected node
showJustSubtree :: Descr -> Descr -> GInfo
                -> IO (Descr, [[Node]], Maybe String)
showJustSubtree descr abstractGraph
                (GInfo {libEnvIORef = ioRefProofStatus,
                        conversionMapsIORef = convRef,
                        visibleNodesIORef = visibleNodesRef,
                        gi_GraphInfo = actGraphInfo}) = do
  convMaps <- readIORef convRef
  libname2dgMap <- readIORef ioRefProofStatus
  visibleNodes <- readIORef visibleNodesRef
  case InjMap.lookupWithB descr (dgAndabstrNode convMaps) of
    Just (libname,parentNode) ->
      case Map.lookup libname libname2dgMap of
        Just gctx  ->
          do let dgraph = devGraph gctx
                 allNodes = getNodeDescriptors (head visibleNodes)
                                            libname convMaps
                 dgNodesOfSubtree = nub (parentNode:(getNodesOfSubtree dgraph
                                               (head visibleNodes) parentNode))
                 -- the selected node (parentNode) shall not be hidden either,
                 -- and we already know its descriptor (descr)
                 nodesOfSubtree = getNodeDescriptors dgNodesOfSubtree
                                  libname convMaps
                 nodesToHide = filter (`notElem` nodesOfSubtree) allNodes
             AGV.Result eventDescr errorMsg <- hidenodes abstractGraph
                                             nodesToHide actGraphInfo
             return (eventDescr, (dgNodesOfSubtree:visibleNodes), errorMsg)
        Nothing -> error $
           "showJustSubtree: Selected node belongs to unknown library: "
           ++ show libname
    Nothing -> error $ "showJustSubtree: there is no node with the descriptor "
                 ++ show descr

getNodeDescriptors :: [Node] -> LIB_NAME -> ConversionMaps -> [Descr]
getNodeDescriptors [] _ _ = []
getNodeDescriptors (node:nodelist) libname convMaps =
    case InjMap.lookupWithA (libname, node) (dgAndabstrNode convMaps) of
    Just descr -> descr:(getNodeDescriptors nodelist libname convMaps)
    Nothing -> error $ "getNodeDescriptors: There is no descriptor for dgnode "
                      ++ show node

getNodesOfSubtree :: DGraph -> [Node] -> Node -> [Node]
getNodesOfSubtree dgraph visibleNodes node =
    concat (map (getNodesOfSubtree dgraph remainingVisibleNodes) predOfNode)
    ++ predOfNode
    where predOfNode = [ n | n <- (preDG dgraph node), elem n visibleNodes]
          remainingVisibleNodes =
              [ n | n <- visibleNodes, notElem n predOfNode]

-- | apply the changes of first history item (computed by proof rules,
-- see folder Proofs) to the displayed development graph
applyChanges :: Descr -> LIB_NAME -> GraphInfo -> Descr -> IORef [[Node]]
             -> ConversionMaps -> [([DGRule],[DGChange])]
             -> IO (Descr, ConversionMaps)
applyChanges _ _ _ eventDescr _ convMaps [] = return (eventDescr,convMaps)
applyChanges gid libname grInfo eventDescr ioRefVisibleNodes
             convMaps ((_, historyElem) : _) =
        applyChangesAux gid libname grInfo ioRefVisibleNodes
        (eventDescr, convMaps) $ removeContraryChanges historyElem

-- | auxiliary function for applyChanges
applyChangesAux :: Descr -> LIB_NAME -> GraphInfo -> IORef [[Node]]
                -> (Descr, ConversionMaps) -> [DGChange]
                -> IO (Descr, ConversionMaps)
applyChangesAux gid libname grInfo ioRefVisibleNodes
            (eventDescr, convMaps) changeList =
  case changeList of
    [] -> return (eventDescr, convMaps)
    changes@(_:_) -> do
      visibleNodes <- readIORef ioRefVisibleNodes
      (newVisibleNodes, newEventDescr, newConvMaps) <-
          applyChangesAux2 gid libname grInfo visibleNodes
                      eventDescr convMaps changes
      writeIORef ioRefVisibleNodes newVisibleNodes
      return (newEventDescr, newConvMaps)

-- | auxiliary function for applyChanges
applyChangesAux2 :: Descr -> LIB_NAME -> GraphInfo -> [[Node]] -> Descr
                  -> ConversionMaps -> [DGChange]
                  -> IO ([[Node]], Descr, ConversionMaps)
applyChangesAux2  _ _ _ visibleNodes eventDescr convMaps [] =
  return (visibleNodes, eventDescr+1, convMaps)
applyChangesAux2 gid libname grInfo visibleNodes _ convMaps (change:changes) =
  case change of
    SetNodeLab _ (node, newLab) -> do
      let nodetype = getDGNodeType newLab
          nodename = getDGNodeName newLab
          dgNode = (libname, node)
      case InjMap.lookupWithA dgNode (dgAndabstrNode convMaps) of
           Just abstrNode -> do
                AGV.Result descr err <-
                     changeNodeType gid abstrNode nodetype grInfo
                case err of
                     Nothing -> do
                         let newConvMaps = convMaps
                               { dgAndabstrNode = InjMap.updateBWithA dgNode
                                     descr (dgAndabstrNode convMaps) }

                         applyChangesAux2 gid libname grInfo visibleNodes
                                              (descr+1) newConvMaps changes
                     Just msg ->
                          error $ "applyChangesAux2: could not set node "
                          ++ show node ++" with name "
                          ++ show nodename ++ "\n" ++ msg
           Nothing -> error $ "applyChangesAux2: could not set node "
                          ++ show node ++ " with name "
                          ++ show nodename ++ ": " ++
                          "node does not exist in abstraction graph"
    InsertNode (node, nodelab) -> do
      let nodetype = getDGNodeType nodelab
          nodename = getDGNodeName nodelab
      AGV.Result descr err <-
          addnode gid nodetype nodename grInfo
      case err of
        Nothing ->
          do let dgNode = (libname,node)
                 newVisibleNodes = map (node :) visibleNodes
                 newConvMaps = convMaps
                   { dgAndabstrNode = InjMap.insert dgNode descr
                         (dgAndabstrNode convMaps) }
             applyChangesAux2 gid libname grInfo newVisibleNodes (descr+1)
                             newConvMaps changes
        Just msg ->
               error $ "applyChangesAux2: could not add node " ++ show node
                      ++" with name " ++ show nodename ++ "\n" ++ msg
    DeleteNode (node, nodelab) -> do
      let nodename = getDGNodeName nodelab
          dgnode = (libname,node)
      case InjMap.lookupWithA dgnode (dgAndabstrNode convMaps) of
        Just abstrNode -> do
          AGV.Result descr err <- delnode gid abstrNode grInfo
          case err of
            Nothing -> do
                let newVisibleNodes = map (filter (/= node)) visibleNodes
                    newConvMaps = convMaps
                      { dgAndabstrNode = InjMap.delete dgnode abstrNode
                            (dgAndabstrNode convMaps) }
                applyChangesAux2 gid libname grInfo newVisibleNodes (descr+1)
                                newConvMaps changes
            Just msg -> error $ "applyChangesAux2: could not delete node "
                               ++ show node ++ " with name "
                               ++ show nodename ++ "\n" ++ msg
        Nothing -> error $ "applyChangesAux2: could not delete node "
                          ++ show node ++ " with name "
                          ++ show nodename ++": " ++
                          "node does not exist in abstraction graph"
    InsertEdge ledge@(src,tgt,edgelab) ->
      do let dgAndabstrNodeMap = dgAndabstrNode convMaps
         case (InjMap.lookupWithA (libname, src) dgAndabstrNodeMap,
                     InjMap.lookupWithA (libname, tgt) dgAndabstrNodeMap) of
           (Just abstrSrc, Just abstrTgt) ->
             do let dgEdge = (libname, (src,tgt,showDoc edgelab ""))
                AGV.Result descr err <-
                   addlink gid (getDGLinkType edgelab)
                              "" (Just ledge) abstrSrc abstrTgt grInfo
                case err of
                  Nothing ->
                    do let newConvMaps = convMaps
                              { dgAndabstrEdge = InjMap.insert dgEdge descr
                                    (dgAndabstrEdge convMaps) }
                       applyChangesAux2 gid libname grInfo visibleNodes
                                 (descr + 1) newConvMaps changes
                  Just msg ->
                   error $ "applyChangesAux2: could not add link from "
                          ++ show src ++ " to " ++ show tgt ++ ":\n"
                          ++ show msg
           _ -> error $ "applyChangesAux2: could not add link " ++ show src
                      ++ " to " ++ show tgt ++ ": illegal end nodes"

    DeleteEdge (src,tgt,edgelab) ->
      do let dgEdge = (libname, (src,tgt,showDoc edgelab ""))
             dgAndabstrEdgeMap = dgAndabstrEdge convMaps
         case (InjMap.lookupWithA dgEdge dgAndabstrEdgeMap) of
            Just abstrEdge ->
              do AGV.Result descr err <- dellink gid abstrEdge grInfo
                 case err of
                   Nothing ->
                     do let newConvMaps = convMaps
                                { dgAndabstrEdge = InjMap.delete dgEdge
                                      abstrEdge (dgAndabstrEdge convMaps) }
                        applyChangesAux2 gid libname grInfo visibleNodes
                                 (descr + 1) newConvMaps changes
                   Just msg -> error $
                               "applyChangesAux2: could not delete edge "
                                      ++ shows abstrEdge ":\n" ++ msg
            Nothing -> error $ "applyChangesAux2: deleted edge from "
                              ++ shows src " to " ++ shows tgt
                              " of type " ++ showDoc (dgl_type edgelab)
                              " and origin " ++ shows (dgl_origin edgelab)
                              " of development "
                         ++ "graph does not exist in abstraction graph"

-- | display a window of translated graph with maximal sublogic.
openTranslateGraph :: LibEnv -> LIB_NAME -> HetcatsOpts
                   -> Res.Result G_sublogics -> ConvFunc -> LibFunc -> IO ()
openTranslateGraph libEnv ln opts (Res.Result diagsSl mSublogic) convGraph
  showLib =
    -- if an error existed by the search of maximal sublogicn
    -- (see GUI.DGTranslation.getDGLogic), the process need not to go on.
    if hasErrors diagsSl then
        errorMess $ unlines $ map show
                  $ filter (relevantDiagKind . diagKind) diagsSl
       else
         do case mSublogic of
             Just sublogic -> do
                 let paths = findComorphismPaths logicGraph sublogic
                 if null paths then
                     errorMess "This graph has no comorphism to translation."
                   else do
                       Res.Result diagsR i <- runResultT ( do
                         -- the user choose one
                         sel <- lift $ listBox "Choose a logic translation"
                                (map show paths)
                         case sel of
                           Just j -> return j
                           _ -> liftR $ fail "no logic translation chosen")
                       let aComor = paths !! fromJust i
                       -- graph translation.
                       case libEnv_translation libEnv aComor of
                         Res.Result diagsTrans (Just newLibEnv) -> do
                             showDiags opts (diagsSl ++ diagsR ++ diagsTrans)
                             if hasErrors (diagsR ++ diagsTrans) then
                                    errorMess $ unlines $ map show
                                      $ filter (relevantDiagKind . diagKind)
                                      $ diagsR ++ diagsTrans
                                  else dg_showGraphAux
                                   (\gI -> do
                                     gInfo <- setGInfo gI ln newLibEnv opts
                                     convGraph gInfo "translation Graph"
                                       showLib)
                         Res.Result diagsTrans Nothing ->
                             errorMess $ unlines $ map show
                               $ filter  (relevantDiagKind . diagKind)
                               $ diagsSl ++ diagsR ++ diagsTrans
             Nothing -> errorMess "the maximal sublogic is not found."
  where relevantDiagKind Error = True
        relevantDiagKind Warning = verbose opts >= 2
        relevantDiagKind Hint = verbose opts >= 4
        relevantDiagKind Debug  = verbose opts >= 5
        relevantDiagKind MessageW = False

dg_showGraphAux :: (GInfo -> IO (Descr, GraphInfo, ConversionMaps)) -> IO ()
dg_showGraphAux convFct = do
  useHTk    -- All messages are displayed in TK dialog windows
            -- from this point on
  gInfo <- emptyGInfo
  (gid, gv, _cmaps) <- convFct gInfo
  redisplay gid gv
  return ()
