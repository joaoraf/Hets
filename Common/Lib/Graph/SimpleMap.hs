--
-- Simple Finite Maps
--
--   balanced (AVL) binary search trees
--   use names of ghc util
--

module SimpleMap (FiniteMap(..),             --transparent(not yet abstract)
                  emptyFM,addToFM,delFromFM,
                  updFM,                     -- applies function to stored entry
                  accumFM,                   -- defines or aggregates entries
                  splitFM,                   -- combines delFrom & lookup
                  isEmptyFM,sizeFM,lookupFM,elemFM,
                  rangeFM,                   -- applies lookup to an interval
                  minFM,maxFM,predFM,succFM,
                  splitMinFM,                -- combines splitFM & minFM
                  fmToList
                 ) where

import Maybe (isJust)              

data Ord a => FiniteMap a b =
    Empty | Node Int (FiniteMap a b) (a,b) (FiniteMap a b)
    deriving (Eq)


----------------------------------------------------------------------
-- UTILITIES
----------------------------------------------------------------------


-- pretty printing
--
showsMap :: (Show a,Show b,Ord a) => FiniteMap a b -> ShowS
showsMap Empty            = id
showsMap (Node _ l (i,x) r) = showsMap l . (' ':) . 
                              shows i . ("->"++) . shows x . showsMap r
                
instance (Show a,Show b,Ord a) => Show (FiniteMap a b) where
  showsPrec _ m = showsMap m


-- other
--
splitMax :: Ord a => FiniteMap a b -> (FiniteMap a b,(a,b))
splitMax (Node h l x Empty) = (l,x)
splitMax (Node h l x r)     = (avlBalance l x m,y) where (m,y) = splitMax r

merge :: Ord a => FiniteMap a b -> FiniteMap a b -> FiniteMap a b
merge l Empty = l
merge Empty r = r
merge l r     = avlBalance l' x r where (l',x) = splitMax l


----------------------------------------------------------------------
-- MAIN FUNCTIONS
----------------------------------------------------------------------

emptyFM :: Ord a => FiniteMap a b
emptyFM  = Empty

addToFM :: Ord a => FiniteMap a b -> a -> b -> FiniteMap a b
addToFM Empty            i x              =  node Empty (i,x) Empty
addToFM (Node h l (j,y) r) i x
    | i<j        =  avlBalance (addToFM l i x) (j,y) r
    | i>j        =  avlBalance l (j,y) (addToFM r i x) 
    | otherwise  =  Node h l (j,x) r  

updFM :: Ord a => FiniteMap a b -> a -> (b -> b) -> FiniteMap a b
updFM Empty              _ _              =  Empty
updFM (Node h l (j,x) r) i f | i<j        =  Node h (updFM l i f) (j,x) r
                             | i>j        =  Node h l (j,x) (updFM r i f) 
                             | otherwise  =  Node h l (j,f x) r  

-- accumFM combines addToFM and updFM

accumFM :: Ord a => FiniteMap a b -> a -> (b -> b -> b) -> b -> FiniteMap a b
accumFM Empty              i f x              =  node Empty (i,x) Empty
accumFM (Node h l (j,y) r) i f x 
    | i<j        =  avlBalance (accumFM l i f x) (j,y) r
    | i>j        =  avlBalance l (j,y) (accumFM r i f x) 
    | otherwise  =  Node h l (j,f x y) r  

delFromFM :: Ord a => FiniteMap a b -> a -> FiniteMap a b
delFromFM Empty              _              =  Empty
delFromFM (Node h l (j,x) r) i
    | i<j        =  avlBalance (delFromFM l i) (j,x) r
    | i>j        =  avlBalance l (j,x) (delFromFM r i) 
    | otherwise  =  merge l r  

isEmptyFM :: FiniteMap a b -> Bool
isEmptyFM Empty = True
isEmptyFM _     = False

sizeFM :: Ord a => FiniteMap a b -> Int
sizeFM Empty          = 0
sizeFM (Node h l x r) = sizeFM l + 1 + sizeFM r

lookupFM :: Ord a => FiniteMap a b -> a -> Maybe b
lookupFM Empty _ = Nothing
lookupFM (Node h l (j,x) r) i | i<j        =  lookupFM l i
                              | i>j        =  lookupFM r i 
                              | otherwise  =  Just x

rangeFM :: Ord a => FiniteMap a b -> a -> a -> [b]
rangeFM m i j = rangeFMa m i j []
--
rangeFMa Empty _ _ a = a
rangeFMa (Node h l (k,x) r) i j a
    | k<i       = rangeFMa r i j a
    | k>j       = rangeFMa l i j a
    | otherwise = rangeFMa l i j (x:rangeFMa r i j a)

minFM :: Ord a => FiniteMap a b -> Maybe (a,b)
minFM Empty              = Nothing
minFM (Node _ Empty x _) = Just x
minFM (Node _ l     x _) = minFM l

maxFM :: Ord a => FiniteMap a b -> Maybe (a,b)
maxFM Empty              = Nothing
maxFM (Node _ _ x Empty) = Just x
maxFM (Node _ _ x r)     = maxFM r

predFM :: Ord a => FiniteMap a b -> a -> Maybe (a,b)
predFM m i = predFM' m i Nothing
--
predFM' Empty              _ p              =  p
predFM' (Node _ l (j,x) r) i p | i<j        =  predFM' l i p
                               | i>j        =  predFM' r i (Just (j,x))
                               | isJust ml  =  ml 
                               | otherwise  =  p
                                 where ml = maxFM l
                           
succFM :: Ord a => FiniteMap a b -> a -> Maybe (a,b)
succFM m i = succFM' m i Nothing
--
succFM' Empty              _ p              =  p
succFM' (Node _ l (j,x) r) i p | i<j        =  succFM' l i (Just (j,x))
                               | i>j        =  succFM' r i p
                               | isJust mr  =  mr 
                               | otherwise  =  p
                                 where mr = minFM r

elemFM :: Ord a => FiniteMap a b -> a -> Bool
elemFM m i = case lookupFM m i of {Nothing -> False; _ -> True}

splitFM :: Ord a => FiniteMap a b -> a -> Maybe (FiniteMap a b,(a,b))
splitFM Empty              _ =  Nothing
splitFM (Node h l (j,x) r) i =
        if i<j then
           case splitFM l i of
                Just (l',y) -> Just (avlBalance l' (j,x) r,y)
                Nothing     -> Nothing  else
        if i>j then
           case splitFM r i of
                Just (r',y) -> Just (avlBalance l (j,x) r',y) 
                Nothing     -> Nothing  
        else {- i==j -}        Just (merge l r,(j,x))  

splitMinFM :: Ord a => FiniteMap a b -> Maybe (FiniteMap a b,(a,b))
splitMinFM Empty              =  Nothing
splitMinFM (Node _ Empty x r) = Just (r,x)
splitMinFM (Node _ l x r)     = Just (avlBalance l' x r,y) 
                                where Just (l',y) = splitMinFM l

fmToList :: Ord a => FiniteMap a b -> [(a,b)]
fmToList m = scan m []
             where scan Empty xs = xs
                   scan (Node _ l x r) xs = scan l (x:(scan r xs))

----------------------------------------------------------------------
-- AVL tree helper functions
----------------------------------------------------------------------

height :: Ord a => FiniteMap a b -> Int
height Empty          = 0
height (Node h _ _ _) = h

node :: Ord a => FiniteMap a b -> (a,b) -> FiniteMap a b -> FiniteMap a b
node l val r = Node h l val r
    where h=1+(height l `max` height r)

avlBalance :: Ord a => FiniteMap a b -> (a,b) -> FiniteMap a b -> FiniteMap a b
avlBalance l (i,x) r
    | (hr + 1 < hl) && (bias l < 0) = rotr (node (rotl l) (i,x) r)
    | (hr + 1 < hl)                 = rotr (node l (i,x) r)
    | (hl + 1 < hr) && (0 < bias r) = rotl (node l (i,x) (rotr r))
    | (hl + 1 < hr)                 = rotl (node l (i,x) r)
    | otherwise                     = node l (i,x) r
    where hl=height l; hr=height r

bias :: Ord a => FiniteMap a b -> Int
bias (Node _ l _ r) = height l - height r

rotr :: Ord a => FiniteMap a b -> FiniteMap a b
rotr (Node _ (Node _ l1 v1 r1) v2 r2) = node l1 v1 (node r1 v2 r2)

rotl :: Ord a => FiniteMap a b -> FiniteMap a b
rotl (Node _ l1 v1 (Node _ l2 v2 r2)) = node (node l1 v1 l2) v2 r2
