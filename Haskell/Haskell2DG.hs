{- HetCATS/Haskell/Haskell2DG.hs
   Authors: S. Groening
   Year:    2003
-}

module Haskell.Haskell2DG (anaHaskellFile) where

import Options
import Haskell.Hatchet.MultiModule  (expandDotsInTyCons,
                                     filterModuleInfo,
                                     importSpecToExportSpec)
import Haskell.Hatchet.HsParseMonad (ParseResult (..))
import Haskell.Hatchet.SynConvert   (toAHsModule)
import Haskell.Hatchet.HsParsePostProcess (fixFunBindsInModule)
import Haskell.Hatchet.HaskellPrelude
                                (tyconsMembersHaskellPrelude, 
                                 preludeDefs, 
                                 preludeSynonyms,
                                 preludeTyconAndClassKinds,
                                 preludeClasses,
                                 preludeInfixDecls,
                                 preludeDataCons)
import Haskell.Hatchet.Type     (assumpToPair)
import Haskell.Hatchet.HsParser (parse)
import Haskell.Hatchet.AnnotatedHsSyn (AHsDecl, 
                                       AModule (..), 
                                       AHsModule)
import Haskell.Hatchet.Rename   (IdentTable)
import Haskell.Hatchet.KindInference (KindEnv)
import Haskell.Hatchet.Representation (Scheme)
import Haskell.Hatchet.Class    (ClassHierarchy)
import Haskell.Hatchet.Env      (Env, listToEnv)
import Haskell.Hatchet.MultiModuleBasics (ModuleInfo (..),
                                          joinModuleInfo,
                                          getTyconsMembers,
                                          getInfixDecls,
                                          concatModuleInfos)
import Haskell.Hatchet.TIModule (tiModule, Timing)
import Haskell.Hatchet.HsSyn    (SrcLoc (..), HsModule (..))
import Haskell.Hatchet.Utils    (getAModuleName)
    
import Static.DevGraph          (DGNodeLab (..),
                                 DGLinkLab (..),
                                 DGLinkType (..),
                                 DGOrigin (..),
                                 DGraph,
                                 LibEnv,
                                 GlobalEntry(..),
                                 NodeSig(..),
                                 getNode,
                                 get_dgn_name)
import Syntax.AS_Library        (LIB_NAME (..),
                                 LIB_ID (..))
import Haskell.Hatchet.AnnotatedHsSyn
import Logic.Grothendieck        (G_sign (..),
                                  G_l_sentence_list (..),
                                  G_morphism (..),
                                  gEmbed)
import Logic.Logic               
import Common.Lib.Graph          (Node,
                                  empty,
                                  insNode,
                                  insEdge,
                                  newNodes,
                                  labNodes,
                                  match)

import Common.Id                 (Token (..),
                                  SIMPLE_ID,
                                  nullPos)
import Haskell.Logic_Haskell     (Haskell (..))
import Haskell.HaskellUtils      (extractSentences)
import qualified Common.Lib.Map as Map
import Common.GlobalAnnotations  (emptyGlobalAnnos)

data HaskellEnv = 
     HasEnv Timing       -- timing values for each stage
            (Env Scheme) -- output variable assumptions (may
                         -- be local, and pattern variables) 
            (Env Scheme) -- output data cons assumptions 
            ClassHierarchy -- output class Hierarchy 
            KindEnv      -- output kinds 
            IdentTable   -- info about identifiers in 
                         -- the module
            AHsModule    -- renamed module 
            [AHsDecl]    -- synonyms defined in this module

-- toplevel function: Creates DevGraph and 
--   LibEnv from a .hs file
--   (including all imported modules)
anaHaskellFile :: HetcatsOpts 
                   -> String
                   -> IO (Maybe (LIB_NAME, -- filename
                                 HsModule, -- as tree
                                 DGraph,   -- development graph
                                 LibEnv))  -- DGraphs for 
                                            -- imported modules 
                                            --  incl. main module
anaHaskellFile _ srcFile = anaHaskellFileAux srcFile

anaHaskellFileAux :: String -> -- DGraph -> 
                       IO (Maybe (LIB_NAME, HsModule, 
                                  DGraph, LibEnv))
anaHaskellFileAux srcFile =
  do 
     moduleSyntax <- parseFile srcFile
     (hasEnv, modInfo, le) <- typeInference moduleSyntax
     let libName = Lib_id(Indirect_link srcFile [])
    -- convert HaskellEnv to DGraph, build up corresponding LibEnv
     let (dg',le') = hasEnv2DG libName hasEnv modInfo le
     return (Just(libName, moduleSyntax, dg', le'))

parseFile :: String -> IO HsModule
parseFile srcFile =
  do
     src <- readFile srcFile
     return (parseHsSource src)

typeInference :: HsModule 
              -> IO (HaskellEnv, ModuleInfo, LibEnv)
typeInference moduleSyntax =
   do
    -- re-group matches into their associated 
    -- funbinds (patch up the output from the parser)
     let moduleSyntaxFixedFunBinds = fixFunBindsInModule moduleSyntax

    -- map the abstract syntax into the annotated abstract syntax
     let annotatedSyntax = toAHsModule moduleSyntaxFixedFunBinds

     (modInfos, le) <- anaImportDecls annotatedSyntax

     -- concat all modInfos
     let importedModInfo = concatModuleInfos modInfos

    -- this is the ModuleInfo that we were passing into tiModule
    -- earlier (just the Prelude stuff)
     let preludeModInfo =
           ModuleInfo {
             moduleName = AModule "Prelude",
             varAssumps = (listToEnv $ map assumpToPair preludeDefs),
             tyconsMembers = tyconsMembersHaskellPrelude, 
             dconsAssumps = (listToEnv $ map assumpToPair preludeDataCons),
             classHierarchy = listToEnv preludeClasses,
             kinds = (listToEnv preludeTyconAndClassKinds),
             infixDecls = preludeInfixDecls,
             synonyms = preludeSynonyms
           }

     let initialModInfo = joinModuleInfo preludeModInfo importedModInfo

    -- call the type inference code for this module 
     (timings, 
      moduleEnv, 
      dataConEnv,
      newClassHierarchy, 
      newKindInfoTable,
      moduleIds,
      moduleRenamed,
      moduleSynonyms) <- tiModule [] annotatedSyntax initialModInfo

     let modInfo = ModuleInfo { varAssumps = moduleEnv, 
                                moduleName = getAModuleName annotatedSyntax,
                                dconsAssumps = dataConEnv, 
                                classHierarchy = newClassHierarchy,
                                kinds = newKindInfoTable,
                                tyconsMembers = getTyconsMembers moduleRenamed,
                                infixDecls = getInfixDecls moduleRenamed,
                                synonyms = moduleSynonyms }

     let hasEnv = HasEnv timings 
                         moduleEnv
                         dataConEnv
                         newClassHierarchy
                         newKindInfoTable
                         moduleIds
                         moduleRenamed
                         moduleSynonyms

     return (hasEnv, modInfo, le)



anaImportDecls :: AHsModule -> IO ([ModuleInfo], LibEnv)
anaImportDecls (AHsModule _ _ idecls _) = anaImports idecls [] Map.empty

anaImports :: [AHsImportDecl] -> [ModuleInfo] -> LibEnv 
                              -> IO ([ModuleInfo], LibEnv)
anaImports [] modInfos le = do return (modInfos, le)
anaImports (imp:imps) modInfos le = 
  do
    (newModInfo, le') <- anaOneImport imp le
    anaImports imps (newModInfo:modInfos) le'

anaOneImport :: AHsImportDecl -> LibEnv 
                              -> IO (ModuleInfo, LibEnv)
anaOneImport (AHsImportDecl _ aMod _ _ maybeListOfIdents) le =
 let ln = toLibName aMod
 in--  if Map.member ln le 
--      then do return (getModInfo ln le, le)
--      else              
      do modSyn <- parseFile (fileName aMod)
         (hasEnv, modInfo, leImports) <- typeInference modSyn
         let le' = le `Map.union` leImports
         let filteredModInfo = filtModInfo aMod modInfo maybeListOfIdents
         let annoSyn = getAbsSyn hasEnv
         case annoSyn of
              AHsModule modName _ [] _ -> 
                   let (dg,node) = addNode empty annoSyn filteredModInfo
                   in do return (filteredModInfo,
                                 (addDG2LibEnv le' ln node dg))
              AHsModule modName _ idecls _ -> 
                   let (dg,node) = addNode empty annoSyn filteredModInfo
                       dg' = addLinks idecls dg node le'
                   in do return (filteredModInfo,
                                 (addDG2LibEnv le' ln node dg'))

 where filtModInfo _ modInfo Nothing = modInfo
                              -- we're not imposing restrictions
       filtModInfo aModule modInfo (Just (_, importSpecs)) =
              filterModuleInfo aModule modInfo $
               expandDotsInTyCons aModule (tyconsMembers modInfo) $
                map importSpecToExportSpec importSpecs
       getAbsSyn (HasEnv _ _ _ _ _ _ absSyn _) = absSyn
--        getModInfo ln le = 
--                 let (_, _, dg) = Map.find ln le
--                 in findModInfo (ln2SimpleId ln) (getlabNodes dg)
--        findModInfo sid (lab:labs) = 
--                 let trySid = get_dgn_name lab
--                 in if sid == trySid then getMI (dgn_sign lab)
--                                     else findModInfo sid labs
--        getlabNodes dg = let (_, labs) = unzip (labNodes dg)
--                         in labs
--        getMI (G_sign Haskell modInfo) = modInfo

toLibName :: AModule -> LIB_NAME
toLibName aMod = Lib_id(Indirect_link (fileName aMod) [])

addLinks :: [AHsImportDecl] -> DGraph -> Node -> LibEnv 
                            -> DGraph
addLinks [] dg _ _ = dg
addLinks (idecl:idecls) dg mainNode le = 
         let ln = toLibName (getModName idecl)
             node = lookupNode ln le
             (dgWithRef, ref) = addDGRef ln dg node
             link = createDGLinkLabel idecl
                          -- insert new edge with LinkLabel
             linkedDG = insEdge (ref,mainNode,link) dgWithRef
         in addLinks idecls linkedDG mainNode le
         where getModName (AHsImportDecl _ name _ _ _) = name
               

hasEnv2DG :: LIB_NAME -> HaskellEnv -> ModuleInfo 
                      -> LibEnv -> (DGraph, LibEnv)
hasEnv2DG ln (HasEnv _ _ _ _ _ _ aMod _) modInfo le =
     let (dg, node) = addNode empty aMod modInfo
         dg' = addLinks (getImps aMod) dg node le
     in (dg', (addDG2LibEnv le ln node dg'))
     where getImps (AHsModule _ _ imps _) = imps

-- input: (so far generated) DGraph, 
--        a module's abstract syntax and its ModuleInfo
-- task: adds a new node (representing the module)
--       to the DGraph 
addNode :: DGraph -> AHsModule -> ModuleInfo
                  -> (DGraph, Node)
addNode dg (AHsModule name exps imps decls) modInfo = 
      -- create a node, representing the module
       let node_contents 
             | imps == [] =   -- module with no imports
                DGNode {
                  dgn_name = aHsMod2SimpleId name,
                  dgn_sign = G_sign Haskell modInfo,
                  dgn_sens = G_l_sentence Haskell 
                              (extractSentences (AHsModule name 
                                              exps imps decls)),
                  dgn_origin = DGBasic }
             | otherwise =    -- module with imports
                DGNode {
                  dgn_name = aHsMod2SimpleId name,
                  dgn_sign = G_sign Haskell modInfo,
                  dgn_sens = G_l_sentence Haskell
                              (extractSentences (AHsModule name
                                              exps imps decls)),
                  dgn_origin = DGExtension }
           [node] = newNodes 0 dg
          -- add node to DGraph
       in (insNode (node, node_contents) dg, node)

addDGRef :: LIB_NAME -> DGraph -> Node -> (DGraph, Node)
addDGRef ln dg node =
       let node_contents = 
            DGRef {
             dgn_renamed = ln2SimpleId ln,
             dgn_libname = ln,
             dgn_node = node }
           [newNode] = newNodes 0 dg
       in (insNode (newNode, node_contents) dg, newNode)

ln2SimpleId :: LIB_NAME -> Maybe (SIMPLE_ID)
ln2SimpleId (Lib_id (Indirect_link modName _)) =
               Just (Token { tokStr = modName, 
                             tokPos = nullPos })
ln2SimpleId (Lib_id (Direct_link modName _)) =
               Just (Token { tokStr = modName, 
                             tokPos = nullPos })
ln2SimpleId (Lib_version link _) = ln2SimpleId (Lib_id link)


-- --------------- utilities --------------- --

createDGLinkLabel :: AHsImportDecl -> DGLinkLab
createDGLinkLabel idecl = 
        case idecl of
          AHsImportDecl _ _ _ _ Nothing ->              -- no hiding
                     DGLink  {
                       dgl_morphism = gEmbed (G_morphism Haskell ()),
                       dgl_type = GlobalDef,
                       dgl_origin = DGExtension }
          AHsImportDecl _ _ _ _ (Just(False,_)) ->      -- no hiding
                     DGLink  {
                       dgl_morphism = gEmbed (G_morphism Haskell ()),
                       dgl_type = GlobalDef,
                       dgl_origin = DGExtension }
          AHsImportDecl _ _ _ _ (Just(True,_)) ->       -- hiding 
                     DGLink  {
                       dgl_morphism = gEmbed (G_morphism Haskell ()),
                       dgl_type = HidingDef,
                       dgl_origin = DGExtension }
                        
addDG2LibEnv :: LibEnv -> LIB_NAME -> Node -> DGraph -> LibEnv
addDG2LibEnv le libName n dg =
          let 
            Just(nodeLab) = getNodeContent n dg
            imp = EmptyNode (Logic Haskell)
            params = []
            parsig = dgn_sign nodeLab -- empty_signature Haskell
            body = NodeSig (n, (dgn_sign nodeLab))
            globalEnv = Map.insert (getDgn_name nodeLab) 
                                   (SpecEntry (imp,params,parsig,body)) 
                                   Map.empty
          in
            Map.insert libName (emptyGlobalAnnos, globalEnv, dg) le

lookupNode :: LIB_NAME -> LibEnv -> Node
lookupNode ln le = 
           let Just (_, globalEnv, _) = Map.lookup ln le
               (_, (SpecEntry (_, _, _, body))) = Map.elemAt 0 globalEnv
           in
               case (getNode body) of
                 Just n -> n
                 Nothing -> (-1)

aHsMod2SimpleId :: AModule -> Maybe SIMPLE_ID
aHsMod2SimpleId (AModule name) = Just (Token { tokStr = name, 
                                               tokPos = nullPos })

fileName :: AModule -> String
fileName (AModule name) = name ++ ".hs"

getNodeContent :: Node -> DGraph -> Maybe (DGNodeLab)
getNodeContent n dg =
               case (match n dg) of
                 (Just (_,_,nodeLab,_), _) -> Just (nodeLab)
                 _                         -> Nothing

getDgn_name :: DGNodeLab -> SIMPLE_ID
getDgn_name nl = let Just(n) = dgn_name nl
                 in  n

parseHsSource :: String -> HsModule
parseHsSource s = case parse s (SrcLoc 1 1) 0 [] of
                      Ok _ e -> e
                      Failed err -> error err



