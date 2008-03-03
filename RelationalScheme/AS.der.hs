{- |
Module      :  $Header$
Description :  abstract syntax for Relational Schemes
Copyright   :  Dominik Luecke, Uni Bremen 2008
License     :  similar to LGPL, see Hets/LICENSE.txt or LIZENZ.txt

Maintainer  :  luecke@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable

Abstract syntax for Relational Schemes
-}

module RelationalScheme.AS 
        (
            RSRelType(..)
        ,   RSQualId(..)
        ,   RSRel(..)
        ,   RSRelationships(..)
        ,   RSScheme(..)
        ,   Sentence
        ,   map_relships
        ,   map_rel
        )
        where

import Common.Id
import Common.AS_Annotation
import Common.Doc
import Common.DocUtils
import RelationalScheme.Keywords
import RelationalScheme.Sign
import qualified Data.Map as Map
import Common.Result

-- DrIFT command
{-! global: UpPos !-}

data RSRelType = RSone_to_one | RSone_to_many | RSmany_to_one | RSmany_to_many
                 deriving (Eq, Ord)

-- first Id is TableId, second is columnId
data RSQualId = RSQualId Id Id Range
                deriving (Eq, Ord)

data RSRel = RSRel [RSQualId] [RSQualId] RSRelType Range
             deriving (Eq, Ord)

data RSRelationships =  RSRelationships [Annoted RSRel] Range
                        deriving (Eq, Ord)

data RSScheme = RSScheme RSTables RSRelationships Range
                deriving (Eq, Ord)

type Sentence = RSRel

-- Pretty printing stuff

instance Show RSScheme where
    show s = case s of
                RSScheme t r _ -> (show t) ++ "\n" ++ (show r)

instance Show RSRelationships where
    show r = case r of
                RSRelationships r1 _ -> 
                    case r1 of 
                        [] -> ""
                        _  -> rsRelationships ++ "\n" ++
                                        (unlines $ map (show . item) r1)

instance Show RSRel where
    show r = case r of
        RSRel i1 i2 tp _ -> (concatComma $ map show i1) ++ " " ++ rsArrow ++ " "++
                            (concatComma $ map show i2) ++ " " ++ show tp

instance Show RSQualId where
    show q = case q of
        RSQualId i1 i2 _ -> (show i1) ++ "." ++ (show i2)

instance Show RSRelType where
    show r = case r of
        RSone_to_one   -> rs1to1
        RSone_to_many  -> rs1tom
        RSmany_to_one  -> rsmto1
        RSmany_to_many -> rsmtom

instance Pretty RSScheme where
    pretty = text . show

instance Pretty RSRel where
    pretty = text . show  
                  
map_qualId :: RSMorphism -> RSQualId -> Result RSQualId
map_qualId mor qid = 
    let
        (tid, rid, rn) = case qid of
            RSQualId i1 i2 rn1 -> (i1, i2,rn1)
    in
        do 
            mtid <- Map.lookup tid $ table_map mor
            rmor <- Map.lookup tid $ column_map mor
            mrid <- Map.lookup rid $ col_map rmor 
            return $ RSQualId mtid mrid rn
            
             
map_rel :: RSMorphism -> RSRel -> Result RSRel
map_rel mor rel =
    let 
        (q1, q2, rt, rn) = case rel of
            RSRel qe1 qe2 rte rne -> (qe1, qe2, rte, rne) 
    in
      do
        mq1 <- mapM (map_qualId mor) q1
        mq2 <- mapM (map_qualId mor) q2
        return $ RSRel mq1 mq2 rt rn
        

map_arel :: RSMorphism -> (Annoted RSRel) -> Result (Annoted RSRel)
map_arel mor arel =
    let 
        rel = item arel
        (q1, q2, rt, rn) = case rel of
            RSRel qe1 qe2 rte rne -> (qe1, qe2, rte, rne) 
    in
      do
        mq1 <- mapM (map_qualId mor) q1
        mq2 <- mapM (map_qualId mor) q2
        return $ arel
                    {
                        item = RSRel mq1 mq2 rt rn
                    }
                    

map_relships :: RSMorphism -> RSRelationships -> Result RSRelationships
map_relships mor rsh =
    let
        (arel, rn) = case rsh of
            RSRelationships arel1 rn1 -> (arel1, rn1)
    in
        do
            orel <- mapM (map_arel mor) arel
            return $ RSRelationships orel rn
                                                                                        