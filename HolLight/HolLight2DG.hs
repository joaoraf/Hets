{- |
Module      :  $Header$
Description :  Import data generated by hol2hets into a DG
Copyright   :  (c) Jonathan von Schroeder, DFKI GmbH 2010
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  jonathan.von_schroeder@dfki.de
Stability   :  experimental
Portability :  portable

-}

module HolLight.HolLight2DG where

import Static.GTheory
import Static.DevGraph
import Static.History
import Static.ComputeTheory

import Logic.Logic
import Logic.Prover
import Logic.ExtSign
import Logic.Grothendieck

import Common.LibName
import Common.Id
import Common.AS_Annotation
import Common.Result

import HolLight.Sign
import HolLight.Sentence
import HolLight.Term
import HolLight.Logic_HolLight

import Driver.Options

import Data.Graph.Inductive.Graph
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.List as List

import qualified System.FilePath.Posix

importData :: FilePath -> IO ([([Char],[([Char], Term)],([(String,Int)], [([Char], [HolType])]))],[([Char],[Char])])
importData fp = do
    s <- readFile fp
    let (libs,lnks) = (read s) :: ([([Char],[([Char], Term)],([(String,Int)], [([Char], [HolType])]))],[([Char],[Char])])
    return (libs, lnks)

makeSig :: [(String,Int)] -> [([Char],[HolType])] -> Sign
makeSig tps opsM = Sign {
                    types = foldl (\m (k,v) -> Map.insert k v m) Map.empty tps
                   ,ops = foldl (\m (k,v) -> Map.insert k (Set.fromList v) m) Map.empty opsM }

makeSentence :: [Char] -> Term -> Sentence
makeSentence n t = Sentence { name = n, term = t, proof = Nothing }

_insNodeDG :: Sign -> [Sentence] -> [Char] -> (DGraph, Map.Map [Char] (Sign,Node,DGNodeLab)) -> (DGraph, Map.Map [Char] (Sign,Node,DGNodeLab))
_insNodeDG sig sens n (dg,m) = let gt = G_theory HolLight (makeExtSign HolLight sig) startSigId
                                          (toThSens $ map (makeNamed "") sens) startThId
                                   n' = snd (System.FilePath.Posix.splitFileName n)
                                   labelK = newInfoNodeLab
                                          (makeName (mkSimpleId n'))
                                          (newNodeInfo DGEmpty)
                                          gt
                                   k = getNewNodeDG dg
                                   m' = Map.insert n (sig,k,labelK) m
                                   insN = [InsertNode (k,labelK)]
                                   newDG = changesDGH dg insN
                                   labCh = [SetNodeLab labelK (k, labelK
                                         { globalTheory = computeLabelTheory Map.empty newDG
                                           (k, labelK) })]
                                   newDG1 = changesDGH newDG labCh in (newDG1,m')

anaHolLightFile :: HetcatsOpts -> FilePath -> IO (Maybe (LibName, LibEnv))
anaHolLightFile _opts path = do
   (libs, _lnks) <- importData path
   let sigM = Map.fromList (map (\(lname,t,sdata) -> (lname,(t,sdata))) libs)
       leaves = let ns = map (\(lname,_,_) -> lname) libs
                in (List.\\) ns (map (\(_,t) -> t) _lnks)
   let libSigInclusions l n = (let pnodes = map snd $ filter ((n==).fst) _lnks
                               in (case Map.lookup n l of
                                     Just (_,(term,sdata)) -> foldl (\l' p -> case Map.lookup p l' of
                                                                            Just (d,(term',sdata')) -> libSigInclusions (Map.insert p
                                                                              (d,(term' `List.union` term,
                                                                               sdata' `List.union` sdata)) l') p
                                                                            Nothing -> l') l pnodes
                                     Nothing -> l))
   let libs' = foldl libSigInclusions sigM leaves
   let libs'' = map (\(lname,(term,sdata)) -> (lname,term,sdata)) (Map.toList libs')
   let (dg',m) = foldr ( \(lname,terms,(tps,opsM)) (dg,m') ->
           let sig = makeSig tps opsM
               sens = map (\(n,t) -> makeSentence n t) terms in
           _insNodeDG sig sens lname (dg,m')) (emptyDG,Map.empty) libs''
       dg'' = foldr (\(source,target) dg -> case Map.lookup source m of
                                           Just (sig,k,lk) -> case Map.lookup target m of
                                             Just (sig1,k1,lk1) -> case resultToMaybe $ subsig_inclusion HolLight sig sig1 of
                                                            Nothing -> dg
                                                            Just incl ->
                                                              let inclM = gEmbed $ mkG_morphism HolLight incl
                                                                  insE = [InsertEdge (k, k1,globDefLink inclM DGLinkImports)]
                                                                  newDG = changesDGH dg insE
                                                                  updL = [SetNodeLab lk1 (k1, lk1
                                                                          { globalTheory = computeLabelTheory Map.empty newDG
                                                                           (k1, lk1) }),
                                                                          SetNodeLab lk (k, lk
                                                                          { globalTheory = computeLabelTheory Map.empty newDG
                                                                           (k, lk) })]
                                                              in changesDGH newDG updL
                                             Nothing -> dg
                                           Nothing -> dg) dg' _lnks
       ln = emptyLibName "example_binom"
       le = Map.insert ln dg'' (Map.empty)
   return (Just (ln, le))

-- data SenInfo = SenInfo Int Bool [Int] String deriving (Read,Show)

-- term_sig :: Term -> Sign
-- term_sig (Var s _) = Sign (Set.singleton s)
-- term_sig (Comb t1 t2) = sigUnion (term_sig t1) (term_sig t2)
-- term_sig (Abs t1 t2) = sigUnion (term_sig t1) (term_sig t2)
-- term_sig _ = Sign Set.empty

-- anaHol2HetsFile :: HetcatsOpts -> FilePath -> IO (Maybe (LibName, LibEnv))
-- anaHol2HetsFile _ fp = do
--   s <- readFile fp
--   let s' = (read s) :: [(Term,SenInfo)]
--   let (dg,lnks,m) = foldl (\(dg,ls,mp) (t,SenInfo id axiom inc name) ->
--                      let gt = G_theory HolLight (makeExtSign HolLight (term_sig t)) startSigId (toThSens [makeNamed name (Sentence name t Nothing)]) startThId in
--                      let (n,dg') = insGTheory dg (NodeName (mkSimpleId name) "" 0 [])  DGEmpty gt in
--                    (dg',ls++(Prelude.map (\i -> (i,n)) inc),Map.insert id (n) mp)
--                  ) (emptyDG,[],Map.empty) s'
--   let dg' = foldl (\d (i,n) ->
--             let n1 = case Map.lookup i m of
--                       Just s -> s
--                       Nothing -> error "encountered internal error while importing data exported from Hol Light" in
--             let incl = subsig_inclusion HolLight (case n1 of (NodeSig _ s) -> case s of (G_sign _ s' _) -> case s' of (ExtSign s'' _) -> s'') (case n1 of (NodeSig _ s) -> case s of (G_sign _ s' _) -> case s' of (ExtSign s'' _) -> s'') in
--             let gm = case maybeResult incl of
--                      Nothing -> error "encountered an internal error importing data exported from Hol Light"
--                      Just inc -> gEmbed $ mkG_morphism HolLight inc in
--             insLink d gm globalDef TEST (getNode n1) (getNode n)

--            ) dg lnks
--   let ln = emptyLibName fp
--       lib = Map.singleton ln $
--               computeDGraphTheories Map.empty dg
--   return $ Just (ln, lib)

