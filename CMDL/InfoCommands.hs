{-# OPTIONS -cpp #-}
{- |
Module      :$Header$
Description : CMDL interface commands
Copyright   : uni-bremen and DFKI
License     : similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  : r.pascanu@jacobs-university.de
Stability   : provisional
Portability : portable

CMDL.InfoCommands contains all commands
that provides information about the state
of the development graph and selected
theories
-}

module CMDL.InfoCommands
       ( cNodes
       , cShowDgGoals
       , cDisplayGraph
       , cShowNodePGoals
       , cShowNodePGoalsCurrent
       , cRedoHistory
       , cShowTaxonomy
       , cShowTaxonomyCurrent
       , cShowTheory
       , cShowTheoryCurrent
       , cShowTheoryGoals
       , cShowTheoryGoalsCurrent
       , cUndoHistory
       , cDetails
       , cShowNodeUGoals
       , cEdges
       , cShowNodeUGoalsCurrent
       , cShowNodeAxioms
       , cInfo
       , cShowNodeAxiomsCurrent
       , cInfoCurrent
       , cShowConcept
       , cNodeNumber
       , cShowConceptCurrent
       ) where


#ifdef UNI_PACKAGE
import Common.UniUtils
import GUI.Taxonomy
import GUI.ShowGraph
#endif

import CMDL.DataTypes
import CMDL.Utils
import CMDL.Shell
import CMDL.DataTypesUtils

import Static.GTheory
import Static.DevGraph
import Static.PrintDevGraph

import Common.DocUtils
import Common.AS_Annotation
import Common.ExtSign
import Common.Taxonomy
import qualified Common.OrderedMap as OMap

import Data.Graph.Inductive.Graph
import qualified Data.Set as Set
import Data.List
import qualified Data.Map as Map

import Logic.Logic

import Driver.Options

import Interfaces.Command
import Interfaces.DataTypes
import Interfaces.Utils

-- show list of all goals(i.e. prints their name)
cShowDgGoals :: CMDL_State -> IO CMDL_State
cShowDgGoals state
 = case i_state $ intState state of
    -- nothing to print
    Nothing -> return state
    Just dgState ->
     do
     -- compute list of node goals
     let nodeGoals = nodeNames $ getAllGoalNodes state

         -- list of all nodes
         ls  = getAllNodes dgState
         lsGE= getAllGoalEdges state
         -- list of all goal edge names
         edgeGoals = createEdgeNames ls lsGE
     -- print sorted version of the list
     return $ genMessage [] (unlines $ sort (nodeGoals++edgeGoals))
                  state


-- local function that computes the theory of a node but it
-- keeps only the goal theory
getGoalThS :: CMDL_UseTranslation -> Int -> CMDL_State -> [String]
getGoalThS useTrans x state
 = case getTh useTrans x state of
    Nothing -> []
    Just th ->
      let nwth = case th of
                  G_theory x1 x2 x3 thSens x4 ->
                    G_theory x1 x2 x3
                       (OMap.filter (\s-> (not(isAxiom s)) &&
                                          (not(isProvenSenStatus s)))
                       thSens) x4
      in [showDoc nwth "\n"]

--local function that computes the theory of a node
--that takes into consideration translated theories in
--the selection too and returns the theory as a string
getThS :: CMDL_UseTranslation -> Int -> CMDL_State -> [String]
getThS useTrans x state
 = case getTh useTrans x state of
    Nothing -> ["Could not find a theory"]
    Just th -> [showDoc th "\n"]


-- show theory of all goals
cShowTheoryGoals :: String -> CMDL_State
                    -> IO CMDL_State
cShowTheoryGoals input state
 = case i_state $ intState state of
    --nothing to print
    Nothing -> return state
    Just dgState ->
     do
     -- compute the input nodes
     let (nds,_,_,errs) = decomposeIntoGoals input
         tmpErrs = prettyPrintErrList errs
     case nds of
      [] -> return $ genErrorMsg tmpErrs state
      _  ->
       do
       --list of all nodes
       let lsNodes = getAllNodes dgState
           -- list of input nodes
           (errs',listNodes) = obtainNodeList nds lsNodes
           -- list of all goal theories
           nodeTh = concatMap (\x->case x of
                                  (n,_) ->getGoalThS Do_translate n state
                                  ) $ listNodes
           tmpErrs' = tmpErrs ++ (prettyPrintErrList errs')
       return $ genMessage tmpErrs' (unlines nodeTh) state

cShowNodeUGoals :: String -> CMDL_State -> IO CMDL_State
cShowNodeUGoals input state
 = case i_state $ intState state of
    --nothing to print
    Nothing -> return state
    Just dgState ->
     do
     -- compute input nodes
     let (nds,_,_,errs) = decomposeIntoGoals input
         tmpErrs = prettyPrintErrList errs
     case nds of
      [] -> return state
      _  ->
       do
       -- list of all nodes
       let lsNodes = getAllNodes dgState
           -- list of input nodes
           (errs',listNodes) = obtainNodeList nds lsNodes
           -- list of all goal names
           goalNames =
             concatMap
              (\x ->case x of
                     (n,_) -> case getTh Dont_translate n state of
                               Nothing -> []
                               Just th->
                                case th of
                                 G_theory _ _ _ sens _->
                                  OMap.keys $
                                  OMap.filter
                                  (\s -> (not $ isAxiom s) &&
                                  (not $ isProvenSenStatus s))
                                   sens) listNodes
           tmpErrs' = tmpErrs ++ (prettyPrintErrList errs')
       return $ genMessage tmpErrs' (unlines goalNames) state

cShowNodeUGoalsCurrent :: CMDL_State -> IO CMDL_State
cShowNodeUGoalsCurrent state
 = case i_state $ intState state of
    Nothing -> return state
    Just pState ->
     do
      let glls = concatMap (\(Element _ nb) ->
                              case getTh Dont_translate nb state of
                               Nothing -> []
                               Just th ->
                                case th of
                                 G_theory _ _ _ sens _ ->
                                   OMap.keys $
                                   OMap.filter
                                   (\s -> (not $ isAxiom s) &&
                                   (not $ isProvenSenStatus s))
                                   sens) $ elements pState
      return $ genMessage [] (unlines glls) state

cShowNodePGoals :: String -> CMDL_State -> IO CMDL_State
cShowNodePGoals input state
 = case i_state $ intState state of
    Nothing -> return state
    Just dgState ->
     do
     let (nds,_,_,errs) = decomposeIntoGoals input
         tmpErrs = prettyPrintErrList errs
     case nds of
      [] -> return state
      _  ->
       do
        let lsNodes = getAllNodes dgState
            (errs',listNodes) = obtainNodeList nds lsNodes
            goalNames =
             concatMap
              (\x -> case x of
                      (n,_) -> case getTh Do_translate n state of
                                Nothing -> []
                                Just th ->
                                 case th of
                                  G_theory _ _ _ sens _ ->
                                   OMap.keys $
                                   OMap.filter
                                   (\s -> (not $ isAxiom s)&&
                                   (isProvenSenStatus s))
                                   sens) listNodes
            tmpErrs' = tmpErrs ++ (prettyPrintErrList errs')
        return $ genMessage tmpErrs' (unlines goalNames) state

cShowNodeAxioms :: String -> CMDL_State -> IO CMDL_State
cShowNodeAxioms input state
 = case i_state $ intState state of
    Nothing -> return state
    Just dgState ->
     do
     let (nds,_,_,errs) = decomposeIntoGoals input
         tmpErrs = prettyPrintErrList errs
     case nds of
      [] -> return state
      _ ->
       do
       let lsNodes = getAllNodes dgState
           (errs',listNodes) = obtainNodeList nds lsNodes
           goalNames =
            concatMap
             (\x ->case x of
                    (n,_)-> case getTh Do_translate n state of
                             Nothing -> []
                             Just th ->
                              case th of
                               G_theory _ _ _ sens _->
                                OMap.keys $ OMap.filter
                                isAxiom sens) listNodes
           tmpErrs' = tmpErrs ++ (prettyPrintErrList errs')
       return $ genMessage tmpErrs' (unlines goalNames) state

cShowNodePGoalsCurrent :: CMDL_State -> IO CMDL_State
cShowNodePGoalsCurrent state
 = case i_state $ intState state of
    Nothing -> return state
    Just pState ->
     do
      let glls = concatMap
                  (\(Element _ nb) ->
                     case getTh Do_translate nb state of
                      Nothing -> []
                      Just th ->
                       case th of
                        G_theory _ _ _ sens _ ->
                         OMap.keys $
                         OMap.filter
                         (\s -> (not $ isAxiom s) &&
                         (isProvenSenStatus s)) sens) $
                                   elements pState
      return $ genMessage [] (unlines glls) state

cShowNodeAxiomsCurrent :: CMDL_State -> IO CMDL_State
cShowNodeAxiomsCurrent state
 = case i_state $ intState state of
    Nothing -> return state
    Just pState ->
     do
      let glls = concatMap (\(Element _ nb) ->
                              case getTh Do_translate nb state of
                               Nothing -> []
                               Just th ->
                                case th of
                                 G_theory _ _ _ sens _ ->
                                   OMap.keys $
                                   OMap.filter isAxiom sens) $
                                   elements pState
      return $ genMessage [] (unlines glls) state

cShowTheoryGoalsCurrent :: CMDL_State -> IO CMDL_State
cShowTheoryGoalsCurrent state
 = case i_state $ intState state of
     Nothing -> return state
     Just pState ->
      do
       -- list of selected theories
       let thls = concatMap (\(Element _ nb) ->
                              getGoalThS Do_translate nb state)
                    $ elements pState
       return $ genMessage [] (unlines thls) state

-- show theory of selection
cShowTheoryCurrent :: CMDL_UseTranslation -> CMDL_State -> IO CMDL_State
cShowTheoryCurrent useTrans state
 = case i_state $ intState state of
    Nothing -> return state
    Just pState ->
     do
      -- list of selected theories
      let thls = concatMap (\(Element _ nb) ->
                              getThS useTrans nb state)
                     $ elements pState
      return $ genMessage [] (unlines thls) state

-- show theory of input nodes
cShowTheory :: CMDL_UseTranslation -> String -> CMDL_State -> IO CMDL_State
cShowTheory useTrans input state
 = case i_state $ intState state of
    Nothing -> return state
    Just dgState -> do
     -- compute the input nodes
     let (nds,_,_,errs) = decomposeIntoGoals input
         tmpErrs  = prettyPrintErrList errs
     case nds of
       [] -> return state
       _  ->
        do
        --list of all nodes
        let lsNodes = getAllNodes dgState
            -- list of input nodes
            (errs',listNodes) = obtainNodeList nds lsNodes
            -- list of theories that need to be printed
            thls =concatMap(\(x,_)->getThS useTrans x state) listNodes
         -- sort before printing !?
            tmpErrs' = tmpErrs ++ (prettyPrintErrList errs')
        return $ genMessage tmpErrs' (unlines thls) state


-- | Given a node it returns the information that needs to
-- be printed as a string
showNodeInfo::CMDL_State -> LNode DGNodeLab -> String
showNodeInfo state (nb,nd)
 =let
    -- node name
      name'= "dgn_name : " ++ showName (dgn_name nd) ++ "\n"
      -- origin of the node
      orig'= if isDGRef nd then "dgn_orig : no origin (ref node)"
             else "dgn_orig : " ++ dgOriginHeader (dgn_origin nd) ++ "\n"
      -- conservativity annotations
      th = getTh Do_translate nb state
  in
   case th of
    Nothing ->name' ++ orig'++"Theory could not be evaluated\n"
    Just t@(G_theory x (ExtSign y _) _ thSens _) ->
     let
      -- find out the sublogic of the theory if we found
      -- a theory
      sublog = "   sublogic :"++ show
                              (sublogicOfTh t) ++ "\n"
      -- compute the number of axioms by counting the
      -- number of symbols of the signature !?
      nbAxm = "   number of axioms :"++(show $ OMap.size $
                                   OMap.filter isAxiom thSens) ++"\n"
      -- compute the number of symbols as the number of
      -- sentences that are axioms in the senstatus of the
      -- theory
      nbSym = "   number of symbols :"++(show $
                    Set.size $ sym_of x y)++ "\n"
      -- compute the number of proven theorems as the
      -- number of sentences that have no theorem status
      -- left
      nbThm = let n'=OMap.size $ OMap.filter (\s -> (not (isAxiom s))
                      && (isProvenSenStatus s)) thSens
              in "   number of proven theorems :"++
                     (show n') ++ "\n"
      -- compute the number of unproven theorems as the
      -- sentences that have something in their theorem
      -- status
      nbUThm = let n'=OMap.size $ OMap.filter(\s -> (not (isAxiom s))
                       && (not (isProvenSenStatus s))) thSens
               in "   number of unproven theorems :"++
                     (show n') ++ "\n"
      -- compute the final theory (i.e.just add partial
      -- results obtained before (sublogic, nbAxm..)
      th' = "dgl_theory :\n"++ sublog ++ nbAxm
                         ++ nbSym ++ nbThm ++ nbUThm
     in name' ++ orig' ++ th'


-- | Given an edge it returns the information that needs to
--   be printed as a string
showEdgeInfo::CMDL_State -> LEdge DGLinkLab -> String
showEdgeInfo state (x, y, dglab)
 = case i_state $ intState state of
   Nothing -> ""
   Just dgS ->
    let
     ls = getAllNodes dgS
     nameOf x' l = case find ((== x') . fst) l of
                   Nothing -> "Unknown node"
                   Just (_, n) -> showName $ dgn_name n
     nm = "dgl_name : "++ nameOf x ls ++ " -> " ++
               nameOf y ls
     orig = "dgl_origin : " ++ dgLinkOriginHeader (dgl_origin dglab)
     defS = "definition"
     mkDefS = (++ " " ++ defS)
     ltype= "dgl_type : " ++
       case edgeTypeModInc $  getRealDGLinkType dglab of
         GlobalDef -> mkDefS "global"
         HetDef -> mkDefS "het"
         HidingDef -> mkDefS "hiding"
         LocalDef -> mkDefS "local"
         FreeOrCofreeDef -> defS
         ThmType thm isPrvn _ _ ->
           let prvn = (if isPrvn then "" else "un") ++ "proven"
               thmS = "theorem"
           in case thm of
                HidingThm -> unwords [prvn, "hiding", thmS]
                FreeOrCofreeThm -> unwords [prvn, thmS]
                GlobalOrLocalThm scope isHom ->
                   let het = if isHom then [] else ["het"]
                       sc = case scope of
                              Local -> "local"
                              Global -> "global"
                   in unwords $ het ++ [sc, prvn, thmS]
    in unlines [nm, orig, ltype]


 -- show all information of selection
cInfoCurrent::CMDL_State -> IO CMDL_State
cInfoCurrent state
 = case i_state $ intState state of
    -- nothing selected
    Nothing -> return state
    Just ps ->
       do
       -- get node by number
       let getNNb x l' = case find (\y->case y of
                                      (nb,_) -> nb==x
                                      ) l' of
                               Nothing -> []
                               Just sm -> [sm]
           -- get all nodes
           ls = getAllNodes ps
           -- get node numbers of selected nodes
           nodesNb = map (\x -> case x of
                                 Element _ z -> z)
                                    $ elements ps
           -- obtain the selected nodes
           selN = concatMap (\x-> getNNb x ls) nodesNb
       return $ genMessage [] (unlines
                                  $ map (\x->showNodeInfo state x) selN) state

-- show all information of input
cInfo::String -> CMDL_State -> IO CMDL_State
cInfo input state
 = case i_state $ intState state of
    -- error message
    Nothing -> return $ genErrorMsg "No library loaded" state
    Just dgS -> do
     let (nds,edg,nbEdg,errs) = decomposeIntoGoals input
         tmpErrs = prettyPrintErrList errs
     case (nds,edg,nbEdg) of
      ([],[],[]) -> return $ genErrorMsg ("Nothing from the input "
                                       ++"could be processed") state
      (_,_,_) ->
       do
        let lsNodes = getAllNodes dgS
            lsEdges = getAllEdges dgS
            (errs'',listEdges) = obtainEdgeList edg nbEdg lsNodes
                             lsEdges
            (errs',listNodes) = obtainNodeList nds lsNodes
            strsNode = map (\x -> showNodeInfo state x)
                               listNodes
            strsEdge = map (\x -> showEdgeInfo state x)
                               listEdges
            tmpErrs' = tmpErrs ++ (prettyPrintErrList errs')
            tmpErrs''= tmpErrs'++ (prettyPrintErrList errs'')
        return $ genMessage tmpErrs'' (unlines (strsNode++strsEdge))
                        state

taxoShowGeneric:: TaxoGraphKind -> CMDL_State
                      -> [LNode DGNodeLab] -> IO()
taxoShowGeneric kind state ls
 = case ls of
#ifdef UNI_PACKAGE
    (nb,nlab):ll ->
     case i_state $ intState state of
      Nothing -> return ()
      Just _ ->
       do
       case getTh Do_translate nb state of
       -- the theory was computed
        Just th ->
         do
          -- display graph
          graph <- displayGraph kind
                    (showName $ dgn_name nlab) th
          case graph of
           -- if successfully displayed sync the two threads
           -- so that one does not loose control on the
           -- interface while the graph is displayed
           Just g ->
            do sync (destroyed g)
               -- go to next
               taxoShowGeneric kind state ll
           Nothing ->
               -- graph was not displayed, then just
               -- go to next
               taxoShowGeneric kind state ll
        -- theory couldn't be computed so just go next
        _ -> taxoShowGeneric kind state ll
#endif
    _ -> return ()

-- show taxonomy of selection
cShowTaxonomyCurrent::CMDL_State -> IO CMDL_State
cShowTaxonomyCurrent state
 = case i_state $ intState state of
    -- nothing selected
    Nothing -> return state
    -- else
    Just ps ->
       do
     -- get node by number
       let getNNb x ks = case find (\y -> case y of
                                       (nb,_) -> nb==x
                                       ) ks of
                           Nothing -> []
                           Just sm -> [sm]
           -- get all nodes
           ls = getAllNodes ps
           -- get node numbers of selected nodes
           nodesNb = map (\x -> case x of
                                 Element _ z ->z)
                                     $ elements ps
           -- obtain the selected nodes
           selN = concatMap (\x-> getNNb x ls) nodesNb
       taxoShowGeneric KSubsort state selN
       return state

-- show taxonomy of input
cShowTaxonomy::String -> CMDL_State -> IO CMDL_State
cShowTaxonomy input state
 = case i_state $ intState state of
    -- nothing to print
    Nothing -> return state
    Just dgS -> do
     let (nds,_,_,errs) = decomposeIntoGoals input
         tmpErrs = prettyPrintErrList errs
     case nds of
      [] -> return state
      _  ->
       do
        -- list of all nodes
        let ls = getAllNodes dgS
        -- list of input nodes
            (errs',lsNodes) = obtainNodeList nds ls
            tmpErrs' = tmpErrs ++ (prettyPrintErrList errs')
        taxoShowGeneric KSubsort state lsNodes
        return $ genMessage tmpErrs' [] state

-- show concept of selection
cShowConceptCurrent::CMDL_State -> IO CMDL_State
cShowConceptCurrent state
 = case i_state $ intState state of
    -- nothing selected
    Nothing -> return state
    -- else
    Just ps ->
       do
     -- get node by number
       let getNNb x ks = case find (\y -> case y of
                                       (nb,_) -> nb==x
                                       ) ks of
                           Nothing -> []
                           Just sm -> [sm]
           -- get all nodes
           ls = getAllNodes ps
           -- get node numbers of selected nodes
           nodesNb = map (\x -> case x of
                                 Element _ z -> z)
                                    $ elements ps
           -- obtain the selected nodes
           selN = concatMap (\x-> getNNb x ls) nodesNb
       taxoShowGeneric KConcept state selN
       return $ genMessage [] [] state

-- show concept of input
cShowConcept::String -> CMDL_State -> IO CMDL_State
cShowConcept input state
 = case i_state $ intState state of
    -- nothing to print
    Nothing -> return state
    Just dgS -> do
     let (nds,_,_,errs) = decomposeIntoGoals input
         tmpErrs = prettyPrintErrList errs
     case nds of
      [] -> return state
      _  ->
       do
        -- list of all nodes
        let ls = getAllNodes dgS
        -- list of input nodes
            (errs',lsNodes) = obtainNodeList nds ls
            tmpErrs' = tmpErrs ++ (prettyPrintErrList errs')
        taxoShowGeneric KSubsort state lsNodes
        return $ genMessage tmpErrs' [] state

-- show node number of input
cNodeNumber::String -> CMDL_State -> IO CMDL_State
cNodeNumber input state
 = case i_state $ intState state of
    Nothing -> return state
    Just dgState -> do
     -- compute the input nodes
     let (nds,_,_,errs) = decomposeIntoGoals input
         tmpErrs = prettyPrintErrList errs
     case nds of
      [] -> return state
      _  ->
       do
        -- list og all nodes
        let lsNodes = getAllNodes dgState
        -- list of input nodes
            (errs',listNodes)=obtainNodeList nds lsNodes
        -- nodes numbers to print
            ls = map(\ x -> showName (dgn_name $ snd x) ++ " is node number "
                                  ++ show (fst x)) listNodes
            tmpErrs' = tmpErrs ++ (prettyPrintErrList errs')
        return $ genMessage tmpErrs' (unlines ls) state

-- print the name of all edges
cEdges::CMDL_State -> IO CMDL_State
cEdges state
 = case i_state $ intState state of
    Nothing -> return state
    Just dgState ->
     do
      -- list of all nodes
      let lsNodes = getAllNodes dgState
          -- compute all edges names
          lsEdg = getAllEdges dgState
          lsEdges = createEdgeNames lsNodes lsEdg
      -- print edge list in a sorted fashion
      return $ genMessage [] (unlines $ sort lsEdges) state

cUndoHistory :: CMDL_State -> IO CMDL_State
cUndoHistory = return . cHistory True

cRedoHistory :: CMDL_State -> IO CMDL_State
cRedoHistory = return . cHistory False

cHistory :: Bool -> CMDL_State -> CMDL_State
cHistory isUndo state = genMessage []
  (unlines $ ((if isUndo then "Un" else "Re") ++ "do history :")
    : map (showCmd . command)
      ((if isUndo then undoList else redoList) $ i_hist $ intState state)
  ) state

-- print the name of all nodes
cNodes::CMDL_State -> IO CMDL_State
cNodes state
 = case i_state $ intState state of
    -- no library loaded, so nothing to print
    Nothing -> return state
    Just dgState ->
     do
     -- compute the list of node names
     let ls = nodeNames $ getAllNodes dgState
     -- print a sorted version of it
     return $ genMessage [] (unlines $ sort ls) state

-- draw graph
cDisplayGraph::CMDL_State -> IO CMDL_State
cDisplayGraph state
 = case i_state $ intState state of
#ifdef UNI_PACKAGE
    Just dgState ->
     do
      -- obtain the name of the last loaded library for
      -- documentation/debugging reasons
      let flnm = fileLoaded $  prompter state
      showGraph flnm defaultHetcatsOpts ( Just
                   (i_ln dgState, i_libEnv dgState))
      return state
#endif
   -- no development graph present
    _ -> return state
