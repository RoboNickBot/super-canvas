{-# LANGUAGE CPP, FlexibleInstances, 
    ForeignFunctionInterface, JavaScriptFFI,
    BangPatterns #-}

module Hyper.Canvas.JS ( getCanvas
                       , attachButton
                       , attachField
                       , clearcan
                       , insertCanvas
                       , writeToCanvas
                       , attachClickHandler
                       , changeElem
                       , readElem
                       , changeInput
                       , readInput
                       , now
                       , startBrowserPageRun
                       , Context ) where

import Data.Default (def)
import Data.Text (pack, unpack)
import System.Random (newStdGen)
import qualified Data.Map as M

import GHCJS.Foreign
import GHCJS.Types
import JavaScript.Canvas
import JavaScript.JQuery hiding (animate)

import Data.Queue
import Control.Event.Handler (Handler)
import Control.Concurrent.STM 
import Control.Concurrent
import Control.Applicative
import Control.Monad

import Hyper.Canvas.Types

selp = select . pack . ("#" ++)

selp' = select . pack

changeElem name val = do x <- selp name
                         setText (pack val) x
                         return ()

readElem name = do x <- selp name
                   t <- unpack <$> getText x
                   return t

changeInput name val = do x <- selp name
                          setVal (pack val) x
                          return ()

readInput name = do x <- selp name
                    t <- unpack <$> getVal x
                    return t

canvasName name = "sc-" ++ name ++ "-canvas"
divName name = "sc-" ++ name ++ "-div"

insertCanvas :: String -> BoundingBox -> String -> IO Context
insertCanvas name (x,y) style = 
  do let cantext = ("<canvas id=\""
                    ++ canvasName name
                    ++ "\" height=\""
                    ++ show y
                    ++ "\" width=\""
                    ++ show x
                    ++ "\" style=\""
                    ++ style
                    ++ "\"></canvas>")
     c <- selp' cantext
     -- putStrLn cantext
     d <- selp (divName name)
     -- putStrLn (divName name)
     appendJQuery c d
     getContext' c

getCanvas name = selp (canvasName name)
                 >>= getContext'

getContext' jq = (indexArray 0 . castRef) jq >>= getContext

attachClickHandler name c = 
  do can <- selp (canvasName name)
     let h ev = c =<< getMousePos (canvasName name) ev
     click h def can 
     return ()

attachButton :: String -> IO (a) -> Handler a -> IO ()
attachButton name io b = do but <- selp name
                            let h ev = io >>= b
                            click h def but
                            return ()

attachField name f = do field <- selp name
                        let d = do val <- getVal field
                                   return (unpack val)
                            h ev = f =<< d
                        keyup h def field
                        return ()

getMousePos :: String -> Event -> IO (Double, Double)
getMousePos name ev = 
  do x <- ffiGetMX (toJSString name)
                   ev
     y <- ffiGetMY (toJSString name)
                   ev
     return (fromIntegral x, fromIntegral y)

clearcan (x,y) = clearRect 0 0 x y

data CState = CState { writeQ :: TChan (IO ())
                     , delayQ :: TChan Double
                     , nextTime :: TVar Double }

writeToCanvas :: BoundingBox  
              -> Context 
              -> [Draw] 
              -> IO ()
writeToCanvas size c prims = 
  clearcan size c >> sequence_ (fmap (writePrim c) prims)

writeStep size t c d ps = 
  atomically (do enqueue (writeQ t) 
                         (clearcan size c 
                          >> sequence_ (fmap (writePrim c) ps))
                 enqueue (delayQ t) (fromIntegral d))

startBrowserPageRun :: IO () -> IO ()
startBrowserPageRun action = 
  syncCallback NeverRetain False action >>= browserPageRun

-- initCState :: IO CState
-- initCState = do wQ <- (newFifo :: IO (TChan (IO ())))
--                 dQ <- (newFifo :: IO (TChan Double))
--                 nT <- newTVarIO 0
--                 let cState = CState wQ dQ nT
--                 s <- syncCallback NeverRetain 
--                                   False 
--                                   (execNext cState)
--                 browserPageRun s
--                 return cState

-- execNext :: CState -> IO ()
-- execNext (CState wQ dQ nT) = 
--   do time <- now
--      mio <- atomically 
--               (do nextTime <- readTVar nT
--                   if time >= nextTime
--                      then do mt <- (dequeue :: TChan Double -> STM (Maybe Double)) dQ 
--                              mw <- (dequeue :: TChan (IO ()) -> STM (Maybe (IO ()))) wQ
--                              case (mw,mt) of
--                                (Just w,Just t) -> do writeTVar nT (time + t)
--                                                      return (Just w)
--                                _ -> return (Nothing)
--                      else return (Nothing))
--      case mio of
--        Just io -> io
--        _ -> return ()

writePrim :: Context -> Draw -> IO ()
writePrim c (l,p) = 
  let prim = p
      (x,y) = l
  in case prim of
       Circle r f col -> 
         do let (rc, gc, bc) = style col
            -- putStrLn ("Drawing a circle...")
            beginPath c 
            fillStyle rc gc bc 255 c
            lineWidth 2 c
            strokeStyle 0 0 0 255 c
            arc x y r 0 (2 * pi) True c
            if f
               then fill c >> stroke c
               else strokeStyle rc gc bc 255 c 
                    >> stroke c 
            return ()
       Line (xd,yd) w col ->
         do -- putStrLn ("Drawing a line...")
            let (rc,gc,bc) = style col
            beginPath c
            moveTo x y c
            lineTo (x + xd) (y + yd) c
            lineWidth w c
            strokeStyle rc gc bc 255 c
            stroke c
            return ()
       Text (w,h) s ->
         do fillStyle 0 0 0 255 c
            drawTextCenter (x,y) w h s c 
       Rekt (w,h) fill col ->
         do let (rc, gc, bc) = style col
            -- putStrLn ("Drawing a rekt...")
            lineWidth 2 c
            if fill
               then fillStyle rc gc bc 255 c
                    >> fillRect x y w h c 
               else strokeStyle rc gc bc 255 c
                    >> strokeRect x y w h c
            return ()

-- style White = (255,255,255)
-- style Gray = (90,90,90)
-- style Black = (0,0,0)
-- sytle LightRed = (255,80,80)
-- style LightGreen = (204,255,153)
-- style LightBlue = (0,204,255)
-- style LightYellow = (255,255,153)
-- style Red = (255, 0, 0)
-- style Green = (0, 190, 0)
-- style Blue = (0, 0, 230)
-- style Yellow = (255, 170, 0)

style color = case color of
                White -> (255,255,255)
                Gray -> (160,160,160)
                DarkGray -> (90,90,90)
                Black -> (0,0,0)
                LightRed -> (255,80,80)
                LightGreen -> (153,255,102) -- (204,255,153)
                LightBlue -> (0,204,255)
                LightYellow -> (255,255,102)
                Manilla -> (255,255,153)
                FlatBlue -> (102,102,255)
                Purple -> (153,102,255)
                LightPurple -> (204,102,255)
                Orange -> (255,153,51)
                Red -> (255, 0, 0)
                Green -> (0, 190, 0)
                Blue -> (0, 0, 230)
                Yellow -> (255, 170, 0)
                _ -> (2,2,2)

type Coord = (Double, Double)

drawTextCenter :: Coord   -- location at which to center the text
               -> Double  -- maximum width of the text
               -> Double  -- maximum height of the text
               -> String  -- the text to be drawn
               -> Context -- the canvas context
               -> IO ()
drawTextCenter (x,y) maxW maxH s c =
  do (a,b) <- setFont maxH maxW s c
     fillText (pack s) (x - (a / 2)) (y + (b / 2)) c

-- same as drawTextCenter, but floors the text at the coordinates
drawTextFloor :: Coord -> Double -> Double -> String -> Context -> IO ()
drawTextFloor (x,y) maxW maxH s c =
  do (a,_) <- setFont maxH maxW s c
     fillText (pack s) (x - (a / 2)) y c

setFont :: Double -> Double -> String -> Context -> IO (Double, Double)
setFont maxHeight maxWidth s c = try maxWidth maxHeight s c

fontPrecision = 6 -- size of steps taken when choosing a font
panicSize = 1 -- size to choose if algorithm bottoms out
try d f s c = do font (pack ((show ((floor f)::Int)) ++ "pt Calibri")) c
                 x <- measureText (pack s) c
                 if x > d
                    then if x > 0
                            then try d (f - fontPrecision) s c 
                            else return (panicSize,f)
                    else return (x,f)

foreign import javascript safe "$r = $2.clientX - document.getElementById($1).getBoundingClientRect().left;"
   ffiGetMX :: JSString -> JavaScript.JQuery.Event -> IO Int

foreign import javascript safe "$r = $2.clientY - document.getElementById($1).getBoundingClientRect().top;"
   ffiGetMY :: JSString -> JavaScript.JQuery.Event -> IO Int

foreign import javascript unsafe "var req = window.requestAnimationFrame || window.mozRequestAnimationFrame || window.webkitRequestAnimationFrame || window.msRequestAnimationFrame; var f = function() { $1(); req(f); }; req(f);"
   browserPageRun :: JSFun (IO ()) -> IO ()

foreign import javascript safe "Date.now()"
   now :: IO Double
