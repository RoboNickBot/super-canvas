import Hyper.Canvas
import Control.Concurrent (threadDelay)

main = startCanvas "main" 
                   (900,500) 
                   "background: lightgray;"
                   ["main"]
                   (\_ -> return ())
       >>= test

test sc = threadDelay 1000000 >> animate sc "main" 20 (42 * 1000) (s as)

as = combine [ (travel (90,140) (circle (300,300) 20 True Green)) 
             , (travel (380, -30) (circle (100,450) 25 True Red))
             , (travel (0, 150) (text (450,-50) (300,80) "Science!"))]

s a = combine (a : [ (rekt (10,10) (30,200) True Blue) 
                   , (rekt (45,15) (30,200) True Green) ])
