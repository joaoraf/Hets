-- Based on DrIFT 1.0 by Noel Winstanley
--  hacked for Haskell 98 by Malcolm Wallace, University of York, Feb 1999.
--  modified by various people, now maintained by John Meacham
module Main(process,main,envGlobalRules,env,addGlobals) where
import ChaseImports
import UserRules
import StandardRules 
import RuleUtils (commentLine,texts)
import PreludData(preludeData)
import DataP
import Pretty 
import List (partition,isSuffixOf,sort)
import qualified System
import IO hiding(try)
import GetOpt
import Monad(unless)
import RuleUtils(Rule,Tag)
import Version

data Op = OpList | OpDerive | OpVersion

data Env = Env { 
    envVerbose :: Bool, 
    envOutput :: (Maybe String), 
    envOperation :: Op, 
    envNoline :: Bool, 
    envArgs :: [(String,String)],
    envResultsOnly :: Bool,
    envGlobalRules :: [Tag]
    }


env = Env { 
    envVerbose = False, 
    envOutput = Nothing,
    envOperation = OpDerive,
    envNoline = False,
    envArgs = [],
    envResultsOnly = False,
    envGlobalRules = []
    } 

putErrDie s = hPutStr stderr s >> System.exitFailure
exitSuccess = System.exitWith System.ExitSuccess

getOutput e = maybe (return stdout) (\fn -> openFile fn WriteMode) (envOutput e) 

options :: [OptDescr (Env -> Env)]
options =
    [ Option ['v'] ["verbose"] (NoArg (\e->e{envVerbose = True}))       "chatty output on stderr"
    , Option ['V'] ["version"] (NoArg (\e->e{envOperation = OpVersion}))       "show version number"
    , Option ['l'] ["list"] (NoArg (\e->e{envOperation = OpList}))       "list available derivations"
    , Option ['L'] ["noline"] (NoArg (\e->e{envNoline = True}))    "omit line pragmas from output"
    , Option ['o'] ["output"]  (ReqArg (\x e->e{envOutput = (Just x)}) "FILE")  "output FILE"
    , Option ['s'] ["set"]    (ReqArg setArg "name:value")  "set argument to value"
    , Option ['r'] ["resultsonly"] (NoArg (\e->e{envResultsOnly = True}))  "output only results, do not include source file"
    , Option ['g'] ["global"]  (ReqArg addGlobalRule "rule") "addition rules to apply globally"   
    ]

setArg x e = e {envArgs = (n, tail rest):(envArgs e)} where
    (n,rest) = span (/= ':') x
addGlobalRule x e = e {envGlobalRules = x:(envGlobalRules e)}

header = "Usage: DrIFT [OPTION...] file"
main = do	
    argv <- System.getArgs
    (env,n) <- case (getOpt Permute options argv) of
	(as,n,[]) -> return (foldr ($) env as ,n)
	(_,_,errs) -> putErrDie (concat errs ++ usageInfo header options)
    case env of 
	Env { envOperation = OpList } -> mapM_ putStrLn (sort $ map fst rules)
	Env { envOperation = OpVersion} -> putStr ("Version " ++ fullName ++ "\n")
	_ -> case n of 
	    [n] -> derive env n
	    _ -> putErrDie ("single input file must be specified.\n" ++ usageInfo header options)


derive env fname = do
	file <- readFile fname
	handle <- getOutput env
        hPutStr handle $ "{- Generated by " ++ package ++ " (Automatic class derivations for Haskell) -}\n"
	unless (envNoline env) $ hPutStr handle $ "{-# LINE 1 \""  ++ fname ++ "\" #-}\n"
	let 
	    (body,_) = userCode file
	    b = ".lhs" `isSuffixOf` fname --isLiterate body
	    (docs,dats,todo) = process  . (addGlobals (envGlobalRules env)) . parser . fromLit b $ body
	moreDocs <- fmap ((\(x,_,_) -> x) . process) (chaseImports body todo)
	let 
	    result = toLit b . (\r -> codeSeperator ++ '\n':r) . 
	     render . vsep $ (docs ++ sepDoc:moreDocs)
	unless (envResultsOnly env) $ hPutStr handle body
	hPutStr handle result

addGlobals             :: [Tag] -> ToDo -> ToDo
addGlobals tags tds    =  (tags,Directive):tds

rules = userRules ++ standardRules
-- codeRender doc = fullRender PageMode 80 1 doc "" -- now obsolete
vsep = vcat . map ($$ (text ""))
sepDoc = commentLine . text $ " Imported from other files :-"

backup :: FilePath -> FilePath
backup f = (reverse . dropWhile (/= '.') . reverse ) f ++ "bak"

newfile :: FilePath -> FilePath
newfile f = (reverse . dropWhile (/= '.') . reverse ) f ++ "DrIFT"

-- Main Pass - Takes parsed data and rules and combines to create instances...
-- Returns all parsed data, ande commands calling for files to be imported if
-- datatypes aren't located in this module.

process :: ToDo -> ([Doc],[Data],ToDo)
process i = (concatMap g dats ++ concatMap h moreDats,parsedData,imports)
       where
	g (tags,d) = [(find t rules) d | t <- (tags ++ directives)]
	h (tags,d) = [(find t rules) d | t <- tags]
	directives = concatMap fst globals
	(dats,commands) = partition (isData . snd) i
	(globals,fors) = partition (\(_,d) -> d == Directive) commands
	(moreDats,imports) = resolve parsedData fors ([],[])
	parsedData = map snd dats ++ preludeData

find :: Tag -> [Rule] -> (Data -> Doc)
find t r = case filter ((==t) . fst) $ r of
               [] -> const (commentLine warning)
               (x:xs) -> snd x
   where
   warning = hsep . texts $ ["Warning : Rule",t,"not found."]                 

