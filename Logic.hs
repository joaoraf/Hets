-- needs ghc -fglasgow-exts 

{- HetCATS/Logic.hs
   $Id$
   Till Mossakowski
   
   Provides data structures for logics (with symbols)
   and logic representations. Logics are
   a type class with an "identitiy" type (usually interpreted
   by a singleton set) which serves to treat logics as 
   data. All the functions in the type class take the
   identity as first argument in order to determine the logic.
   Logic representations are just collections of
   functions between (some of) the types of logics.

   References:

   J. A. Goguen and R. M. Burstall
   Institutions: Abstract Model Theory for Specification and
     Programming
   JACM 39, p. 95--146, 1992
   (general notion of logic - model theory only)

   J. Meseguer
   General Logics
   Logic Colloquium 87, p. 275--329, North Holland, 1989
   (general notion of logic - also proof theory;
    notion of logic representation, called map there)

   T. Mossakowski: 
   Specification in an arbitrary institution with symbols
   14th WADT 1999, LNCS 1827, p. 252--270
   (treatment of symbols and raw symbols, see also CASL semantics)

   T. Mossakowski, B. Klin:
   Institution Independent Static Analysis for CASL
   15h WADT 2001, LNCS
   (what is needed for static anaylsis)

   S. Autexier and T. Mossakowski
   Integrating HOLCASL into the Development Graph Manager MAYA
   FroCoS 2002, to appear
   (interface to provers)

   Todo:
   Errors (via Monad)
   ATerm, XML
   ID auslagern
   Sublanguages more abstractly (lattice)
   Weak amalgamability
-}

module Logic where

-- maps and sets, just a quick thing

type Set a = [a]
type Map a = [(a,a)]


-- diagrams, nodes are just integers

type Node = Int
type Edge morphism = (Node,morphism,Node)
data Diagram object morphism = Diagram [(Node,object)] [Edge morphism] 
empty_diagram :: Diagram o m
empty_diagram = Diagram [] []
add_node :: Diagram o m -> o -> (Node,Diagram o m)
add_node (Diagram nodes edges) obj = 
         (node,Diagram ((node,obj):nodes) edges) where
            node = maximum (map fst nodes)
add_edge :: Diagram o m -> Edge m -> Diagram o m
add_edge (Diagram nodes edges) edge =
         Diagram nodes (edge:edges)
object_at_node :: Node -> Diagram o m -> Maybe (Node,o)
object_at_node node (Diagram nodes edges) =
         case lookup node nodes of
           Just obj -> Just (node,obj)
           Nothing -> Nothing
diagram_nodes :: Diagram o m  -> [(Node,o)]
diagram_nodes (Diagram nodes edges) = nodes
diagram_edges :: Diagram o m -> [Edge m]
diagram_edges (Diagram nodes edges) = edges


-- identifiers, fixed for all logics

data ID = Simple_Id String
        | Compound_Id (String,[ID])


-- Categories are given by a quotient,
-- i.e. we need equality
-- Should we allow arbitrary composition graphs and build paths?

class (Eq object, Eq morphism) => 
      Category id object morphism | id ->, id -> morphism where
         ide :: id -> object -> morphism
         o :: id -> morphism -> morphism -> Maybe morphism
         dom, cod :: id -> morphism -> object
         legal_obj :: id -> object -> Bool
         legal_mor :: id -> morphism -> Bool


-- abstract syntax, parsing and printing

class (Read basic_spec, Read sentence, Read symb_items, 
       Read symb_map_items, Read anno,
       Show basic_spec, Show sentence, Show symb_items, 
       Show symb_map_items, Show anno) =>
      Syntax basic_spec sentence symb_items symb_map_items anno


-- sublogics

data Sublogic basic_spec sentence symb_items symb_map_items anno
              sign morphism symbol raw_symbol =
     Sublogic {sublogic_name :: String,
               is_in_basic_spec :: basic_spec -> Bool,
               is_in_sentence :: sentence -> Bool,
               is_in_symb_items :: symb_items -> Bool,
               is_in_symb_map_items :: symb_map_items -> Bool,
               is_in_anno :: anno -> Bool,
               is_in_sign :: sign -> Bool,
               is_in_morphism :: morphism -> Bool,
               is_in_symbol :: symbol -> Bool,
               is_in_raw_symbol :: raw_symbol -> Bool
              }


-- theories and theory morphisms

data Theory sign sen = 
     Theory {sign_of :: sign, 
             ax_of :: [(String,sen)]
            }

data TheoryMorphism sign sen mor = 
     TheoryMorphism {t_source, t_target :: Theory sign sen,
                     t_morphism :: mor
                    } 


-- proofs and provers

type Rule = String

data Proof_tree sen = Axiom sen
                    | Branch (sen,Rule,[Proof_tree sen])  -- add substitutions here?

type Tactic_script = String  -- the file name

data Proof_status sen = Open sen
                      | Disproved sen 
                      | Proved(sen,[sen],Proof_tree sen,Tactic_script)

data Prover sen symbol = 
     Prover { prover_name :: String,
              prover_sublogic :: String,
              add_sym :: symbol -> IO(Bool),  -- returns True if succeeded
              remove_sym :: symbol -> IO(Bool), -- returns True if succeeded
              prove :: sen -> IO([Proof_status sen]) -- proof status for goal and lemmas
            }

data Cons_checker morphism = 
     Cons_checker {cons_checker_name :: String,
                   cons_checker_sublogic :: String,
                   cons_check :: morphism -> IO(Bool, Tactic_script)
                  }


-- logics

class (Syntax basic_spec sentence symb_items symb_map_items anno,
       Show sign, Show morphism, Show symbol, Show raw_symbol,
       Ord symbol, --  needed for efficient symbol tables
       Category id sign morphism) =>
      Logic id
        basic_spec sentence symb_items symb_map_items anno
        sign morphism symbol raw_symbol 
        | id -> basic_spec, id -> sentence, id -> symb_items,
          id -> symb_map_items, id -> anno,
          id -> sign, id -> morphism, id ->symbol, id -> raw_symbol
       where
         logic_name :: id -> String

         -- sentence translation
         map_sen :: id -> morphism -> sentence -> sentence

         -- static analysis of basic specifications and symbol maps
         basic_analysis :: id -> 
                           (basic_spec,sign,[anno]) -> 
                           (sign,[(String,sentence)])
         stat_symb_map_items :: id -> [symb_map_items] -> Map raw_symbol
         stat_symb_items :: id -> [symb_items] -> [raw_symbol] 

         -- architectural sharing analysis for one morphism
         ensures_amalgamability :: id ->
              (Diagram sign morphism, Node, sign, Edge morphism, morphism) -> 
               Diagram sign morphism
         -- do we need it also for sinks consisting of two morphisms?

         -- symbols and symbol maps
         symbol_to_raw :: id -> symbol -> raw_symbol
         id_to_raw :: id -> ID -> raw_symbol 
         sym_of :: id -> sign -> Set symbol
         symmap_of :: id -> morphism -> Map symbol
         matches :: id -> symbol -> raw_symbol -> Bool
         name :: id -> symbol -> ID 
   
         -- operations on signatures and morphisms
         empty_signature :: id -> sign
         signature_union :: id -> sign -> sign -> sign
         final_union :: id -> sign -> sign -> sign
         is_subsig :: id -> sign -> sign -> Bool
         generated_sign, cogenerated_sign :: id -> [raw_symbol] -> sign -> morphism
         induced_from_morphism :: id -> Map raw_symbol -> sign -> morphism
         induced_from_to_morphism :: id -> Map raw_symbol -> sign -> sign -> morphism 

         -- sublogics
         sublogics :: [Sublogic basic_spec sentence symb_items symb_map_items anno
                       sign morphism symbol raw_symbol]
         included_logic :: String -> String -> Bool

         -- provers
         provers :: [Prover sentence symbol]
         cons_checkers :: [Cons_checker (TheoryMorphism sign sentence morphism)] 

         -- derived operations, need not to be given

         -- parsing, printing, accessible via logic identity
         read_basic_spec :: id -> String -> basic_spec
         read_sentence :: id -> String -> sentence
         read_symb_items :: id -> String -> symb_items
         read_symb_map_items :: id -> String -> symb_map_items
         read_anno :: id -> String -> anno

         read_basic_spec _ = read
         read_sentence _ = read
         read_symb_items _ = read
         read_symb_map_items _ = read
         read_anno _ = read
 
         show_basic_spec :: id -> basic_spec -> String
         show_sentence :: id -> sentence -> String
         show_symb_items :: id -> symb_items -> String
         show_symb_map_items :: id -> symb_map_items -> String
         show_anno :: id -> anno -> String
         show_sign :: id -> sign -> String
         show_morphism :: id -> morphism -> String
         show_symbol :: id -> symbol -> String
         show_raw_symbol :: id -> raw_symbol -> String 

         show_basic_spec _ = show
         show_sentence _ = show
         show_symb_items _ = show
         show_symb_map_items _ = show
         show_anno _ = show
         show_sign _ = show
         show_morphism _ = show
         show_symbol _ = show
         show_raw_symbol _ = show


-- Simple logic representations (possibly also morphisms via adjointness)

data (Logic id1
        basic_spec1 sentence1 symb_items1 symb_map_items1 anno1
        sign1 morphism1 symbol1 raw_symbol1,
      Logic id2
        basic_spec2 sentence2 symb_items2 symb_map_items2 anno2
        sign2 morphism2 symbol2 raw_symbol2) =>
  LogicRepr id1 basic_spec1 sentence1 symb_items1 symb_map_items1 anno1 sign1 morphism1 symbol1 raw_symbol1
            id2 basic_spec2 sentence2 symb_items2 symb_map_items2 anno2 sign2 morphism2 symbol2 raw_symbol2
     =
     LogicRepr {repr_name :: String,
                source :: id1,
                target :: id2,
                map_basic_spec :: basic_spec1->basic_spec2,
                map_sentence :: sign1 -> sentence1 -> Maybe sentence2, -- also cover semi-representations
                map_anno :: anno1 -> anno2,
                map_sign :: sign1 -> sign2,
                project_sign :: Maybe (sign2 -> sign1,morphism2),  -- right adjoint and counit
                map_morphism :: morphism1 -> morphism2,
                map_symbol :: symbol1 -> symbol2
               }

