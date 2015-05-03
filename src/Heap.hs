{-# LANGUAGE FlexibleInstances #-}

import Reactive.Banana
import Reactive.Banana.Frameworks

import Control.Monad.Writer.Lazy
import Control.Monad.Trans.Maybe
import Data.Monoid
import Text.Read (readMaybe)
import System.Random
import qualified Data.Map as M

import Super.Canvas
import Super.Trees
import Super.Trees2

main = startCanvas "main" 
                   (900,500) 
                   "background: lightgray;"
                   ["main","tree"]
                   (\_ -> return ())
       >>= startHeapGame

type StateModifier = GameState -> Writer [IO ()] GameState

data Env = Env { sc :: SuperCanvas
               , runM :: StateModifier -> IO () }

nodesize = (20,20)


startHeapGame :: SuperCanvas -> IO ()
startHeapGame sc = 
  do g <- newStdGen
     (gameManips,runManip) <- newAddHandler
     let env = Env sc runManip
     attachButton "restart" (restartGame env <$> readNewGame env) runManip
     initialGame <- readNewGame env
     compile (heapGame env
                       (initialGame, [writeState env initialGame])
                       gameManips
                       runManip) >>= actuate
     writeState env initialGame

restartGame :: Env -> GameState -> StateModifier
restartGame env newGame _ = tell [writeState env newGame] 
                            >> return newGame

readNewGame :: Env -> IO GameState
readNewGame env = 
  do num <- safeReadInput "numnodes" 8 
     g <- newStdGen
     let nodes = take num (fmap HeapNode (randomRs randRange g))
         heap = foldr insert newHeap nodes
     return (Valid heap)

heapGame env iGame gameMs runM = 
  do eGameMs <- fromAddHandler gameMs
     let gstate = fst <$> bGameM
         vstate = snd <$> bGameM
         bGameM =  accumB iGame (update <$> eGameMs)
     visuals <- changes vstate
     reactimate' (fmap sequence_ <$> visuals)
     return ()
     
update :: StateModifier -> (GameState,[IO ()]) -> (GameState,[IO ()])
update m (gs,_) = runWriter (m gs)

visualize :: Env -> VTrace HeapNode -> IO ()
visualize env = sequence_ . fmap (write (sc env) "tree" 
                                  . toForm nodesize zFindLoc nodeForm 
                                  . zTree)

writeState :: Env -> GameState -> IO ()
writeState env (Valid (Heap t)) = 
  do g <- newStdGen
     let tree = fitTreeArea env (toForm nodesize zFindLoc normalNodeForm t)

         doRemMin = (runM env) (modRemoveMin env)
         bRemMin = (fitControl1 env . addOnClick [doRemMin]) 
                     (rekt (0,0) (50,150) True Red)
                     
         newNode = (HeapNode . fst) (randomR randRange g)
         doAddNew = (runM env) (modInsertNew env newNode)
         bAddNew = (fitControl2 env . addOnClick [doAddNew]) 
                     (rekt (0,0) (50,150) True Blue)
     (write (sc env) "tree" . combine) [tree]
     (write (sc env) "main" . combine) [bRemMin,bAddNew]
writeState env (RemoveMin (EditTree t)) = 
  writeEditState env t (rmNodeForm env)
writeState env (InsertNew (EditTree t)) = 
  writeEditState env t (insNodeForm env)
writeState env (GameOver) = return ()

writeEditState env t nf = 
  let tree = fitTreeArea env (toForm nodesize zFindLoc nf (zTree t))
      doCommit = (runM env) (modValidate env)
      bCommit = (fitControl1 env . addOnClick [doCommit]) 
                  (rekt (0,0) (50,150) True Green)
  in (write (sc env) "tree" . combine) [tree]
     >> (write (sc env) "main" . combine) [bCommit]

normalNodeForm (ZTree (BiNode _ n _) _) = nodeForm n
normalNodeForm _ = (blank, const blank)

rmNodeForm :: Env -> NodeForm (QNode HeapNode Focus)
rmNodeForm env zt = 
  let (form,line) = nodeForm zt
  in case zt of
       ZTree _ (L (QNode _ Focused) _ _) -> 
         (addOnClick [(runM env) (modSwap env downHeapL)] form, line)
       ZTree _ (R _ (QNode _ Focused) _) -> 
         (addOnClick [(runM env) (modSwap env downHeapR)] form, line)
       _ -> (form,line)

insNodeForm :: Env -> NodeForm (QNode HeapNode Focus)
insNodeForm env zt = 
  let (form,line) = nodeForm zt
  in case zt of
       ZTree (BiNode (BiNode _ (QNode _ Focused) _) _ _) _ -> 
         (addOnClick [(runM env) (modSwap env upHeap)] form, line)
       ZTree (BiNode _ _ (BiNode _ (QNode _ Focused) _)) _ -> 
         (addOnClick [(runM env) (modSwap env upHeap)] form, line)
       _ -> (form,line)

modSwap :: Env 
        -> (EditTree (QNode HeapNode Focus) -> EditTree (QNode HeapNode Focus)) 
        -> StateModifier
modSwap env mod (RemoveMin et) = 
  let state = RemoveMin (mod et)
  in tell [writeState env state] >> return state

modValidate :: Env -> StateModifier
modValidate env (RemoveMin et) = modValidateValid env et
modValidate env (InsertNew et) = modValidateValid env et
modValidate _ s = return s

modValidateValid :: Env 
                 -> EditTree (QNode HeapNode Focus) 
                 -> Writer [IO ()] GameState
modValidateValid env et = 
  let (tree,trace) = validateM et
      state = case tree of
                Just h -> Valid h
                _ -> GameOver
  in tell [(visualize env trace)] 
     >> tell [(writeState env state)]
     >> return state

modRemoveMin :: Env -> StateModifier
modRemoveMin env (Valid h) = 
  tell [writeState env state] >> return state
  where state = RemoveMin (removeMin h)
modRemoveMin _ s = return s

modInsertNew :: Env -> HeapNode -> StateModifier
modInsertNew env n (Valid h) = 
  tell [writeState env state] >> return state
  where state = InsertNew (carelessInsert n h)
modInsertNew _ _ s = return s

fitTreeArea :: Env -> SuperForm -> SuperForm
fitTreeArea env = fit (50,50) (300,300)

fitControl1 :: Env -> SuperForm -> SuperForm
fitControl1 env = fit (450,50) (200,100)

fitControl2 :: Env -> SuperForm -> SuperForm
fitControl2 env = fit (450,300) (200,100)

type HeapTree = BiTree (Int, Bool)

data HeapNode = HeapNode Int deriving (Eq, Ord)

instance DrawableNode HeapNode where
  nodeForm (HeapNode v) = (text (0,0) (20,10) (show v)
                          ,(\ploc -> line (0,0) ploc 2 Black))

data QNode a s = QNode { qVal :: a
                       , qStatus :: s }
                       
instance DrawableNode (QNode HeapNode Focus) where
  nodeForm (QNode h Focused) = qForm h Yellow
  nodeForm (QNode h Unfocused) = qForm h White

instance DrawableNode (QNode HeapNode Status) where
  nodeForm (QNode h Unchecked) = nodeForm (QNode h Unfocused)
  nodeForm (QNode h Good) = 
    let (f,_) = qForm h Green
        l = (\ploc -> line (0,0) ploc 4 Green)
    in (f,l)
  nodeForm (QNode h BadChild) = 
    let (f,_) = qForm h Red
        l = (\ploc -> line (0,0) ploc 4 Red)
    in (f,l)
  nodeForm (QNode h BadParent) = qForm h Red

qForm :: HeapNode -> Color -> (SuperForm, LineForm) 
qForm h c = let (t,line) = nodeForm h
                r = rekt (-200,-100) (400,200) True c
            in (combine [r,t], line) 

instance Eq a => Eq (QNode a s) where
  (==) (QNode a _) (QNode b _) = a == b

instance (Eq a, Ord a) => Ord (QNode a s) where
  compare (QNode a _) (QNode b _) = compare a b

data Focus = Focused | Unfocused

data Status = Unchecked | Good | BadChild | BadParent

setQ :: q -> QNode a s -> QNode a q
setQ q (QNode n _) = QNode n q

makeQ :: q -> a -> QNode a q
makeQ q a = QNode a q 

carelessInsert :: Ord a => a -> Heap a -> EditTree (QNode a Focus)
carelessInsert a h = (EditTree 
                      . ztReplace (makeQ Focused a)
                      . fmap (makeQ Unfocused)
                      . bottom) h

removeMin :: Ord a => Heap a -> EditTree (QNode a Focus)
removeMin (Heap EmptyTree) = EditTree (zTop EmptyTree)
removeMin h = (EditTree 
               . ztReplace (setQ Focused v) 
               . ztUpMost 
               . ztCut) (ZTree b c)
  where (ZTree b c) = (fmap (makeQ Unfocused) . lastElem) h
        (BiNode _ v _) = b

data HeapGame = HeapGame { hgScore :: Int
                         , hgState :: GameState }
                         
data GameState = Valid (Heap HeapNode)
               | RemoveMin (EditTree (QNode HeapNode Focus))
               | InsertNew (EditTree (QNode HeapNode Focus))
               | GameOver

newGame :: [HeapNode] -> HeapGame
newGame ns = HeapGame 0 (Valid (Heap (makeHeap ns))) 

treestuff sc = 
  do t <- newAddHandler
     g <- newStdGen
     b <- newAddHandler
     attachButton "newnode" newStdGen (snd b)
     let thetrees :: HeapTree
         thetrees = randomHeapTree 8 g
     network <- compile (mkNet sc
                               (fst t)
                               (fst b)
                               (randomRs randRange g)
                               (snd t))
     actuate network
    -- write sc (format (prepSTree (fst thetrees)))
     (snd t) thetrees
     putStrLn "Started?"
     return ()

mkNet sc t b rs fire =
  do eTrees <- fromAddHandler t
     eButton <- fromAddHandler b
     let bAdd = stepper (\a -> EmptyTree) 
                        (fmap addNode' eAllTrees)
         eAllTrees = eTrees `union` (bAdd <@> eButton)
         eTreeForms = fmap (format4 fire) eAllTrees
         eForms = eTreeForms
     reactimate (fmap (write sc "main") eForms)


addNode' t g = addNode g t

addNode :: StdGen -> HeapTree -> HeapTree
addNode g = (\(a,_) -> a)
            . qtUpMost
            . insertNew' (newNode g) g
            . (\a -> (a,Top))
            . clean

randRange = (10,99)

newNode g = (fst $ randomR randRange g, True)

clean :: HeapTree -> HeapTree
clean = fmap (\(v,_) -> (v,False))

randomHeapTree i g = 
  makeHeap (fmap (\a -> (a,False)) (take i (randomRs randRange g)))

insertNew' node _ (t,c) = (heapCarelessInsert node t, c)

insertNew node g qt = 
  ( (\(t,c) -> (BiNode EmptyTree node EmptyTree,c))
  . randomChild g ) qt

format :: SuperForm -> SuperForm
format = translate (50,50)

tryread n s = case readMaybe s of
                Just i -> i
                _ -> n



format4 fire trees = fit (50,50) (800,400) (prepHeapTree fire trees)

validate :: Ord a => (a -> a -> Bool) -> EditTree a -> Maybe (Heap a)
validate comp (EditTree t) = 
  case (ztUpMost t) of
    (ZTree (BiNode l v r) _) -> 
      if valid v l && valid v r 
         then Just (Heap (BiNode l v r))
         else Nothing
    _ -> Just (Heap EmptyTree)
  where valid v (BiNode l u r) = 
          (comp v u) && valid v l && valid v r
        valid _ _ = True

stamp :: s -> ZTree (QNode a s) -> ZTree (QNode a s)
stamp s (ZTree (BiNode l (QNode v _) r) c) = 
  ZTree (BiNode l (QNode v s) r) c
stamp _ t = t

type Validator a = MaybeT (Writer (VTrace a)) 
                          (ZTree (QNode a Status))

type VTrace a = [ZTree (QNode a Status)]

validateM :: Ord a 
          => (EditTree (QNode a s)) 
          -> (Maybe (Heap a), VTrace a)
validateM (EditTree t) = 
  case nt of
    (ZTree (BiNode _ _ _) _) -> 
      let (res,trace) = runWriter (runMaybeT (check nt))
      in (fmap (Heap . zTree . ztUpMost . fmap qVal) res 
         ,trace)
    _ -> (Just (Heap EmptyTree), [])
  where nt = (fmap (setQ Unchecked) . ztUpMost) t
  
check :: Ord a => ZTree (QNode a Status) -> Validator a
check zt = ztUp <$> case zt of
                      (ZTree (BiNode l v r) c) -> investigate zt
                      _ -> return zt

investigate zt = (checkThisNode zt 
                  >>= (check . ztLeft) 
                  >>= (check . ztRight))

checkThisNode :: Ord a => ZTree (QNode a Status) -> Validator a
checkThisNode zt = (lookAt v . ztLeft) zt >>= (lookAt v . ztRight)
  where (ZTree (BiNode _ v _) _) = zt

lookAt :: Ord a => QNode a Status -> ZTree (QNode a Status) -> Validator a
lookAt u zt = case zt of
                (ZTree (BiNode _ v _) c) -> 
                  if u <= v
                     then markValid zt
                     else markFail zt
                _ -> return (ztUp zt)

markValid :: Ord a => ZTree (QNode a Status) -> Validator a
markValid zt = let nxt = (ztUp . stamp Good) zt
               in tell [nxt] >> return nxt

markFail :: Ord a => ZTree (QNode a Status) -> Validator a
markFail zt = let nxt = (stamp BadParent 
                         . ztUp 
                         . stamp BadChild) zt
              in tell [nxt] >> fail "Invalid Heap"
