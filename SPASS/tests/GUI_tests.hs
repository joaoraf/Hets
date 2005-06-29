
-- | some GUI tests to use from ghci
module GUI_tests where 

import qualified Common.Lib.Map as Map 

import Common.AS_Annotation
import Logic.Prover

import SPASS.Sign
import SPASS.Prove


printStatus :: IO [Proof_status ()] -> IO ()
printStatus act = do st <- act
                     putStrLn (show st)

sign1 :: SPASS.Sign.Sign
sign1 = emptySign {sortMap = Map.insert "s" Nothing Map.empty,
                  predMap = Map.fromList [("P",["s"]),("Q",["s"])] }

term_x :: SPTerm 
term_x = SPSimpleTerm (SPCustomSymbol "x")

axiom1 :: Named SPTerm
axiom1 = NamedSen "Ax" True (SPQuantTerm SPForall [term_x] (SPComplexTerm SPEquiv [SPComplexTerm (SPCustomSymbol "P") [term_x],SPComplexTerm (SPCustomSymbol "Q") [term_x]]))

goal1 :: Named SPTerm
goal1 = NamedSen "Go" False (SPQuantTerm SPForall [term_x] (SPComplexTerm SPImplies [SPComplexTerm (SPCustomSymbol "Q") [term_x],SPComplexTerm (SPCustomSymbol "P") [term_x] ]))

theory1 :: Theory SPASS.Sign.Sign SPTerm
theory1 = (Theory sign1 [axiom1, goal1])

test1 :: IO ()
test1 = printStatus (spassProveGUI "Foo" theory1)

test1b :: IO ()
test1b = printStatus (spassProveBatch "Foo" theory1)