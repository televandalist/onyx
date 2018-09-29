module Draw (draw, getWindowDims, numMod, _M, _B) where

import           Prelude

import           Control.MonadZero  (guard)
import           Data.Array         (concat, uncons)
import           Data.Int           (round, toNumber)
import           Data.Maybe         (Maybe (..))
import           Data.Time.Duration (Seconds (..))
import           Data.Traversable   (or)
import           Data.Tuple         (Tuple (..), lookup)
import           Effect             (Effect)
import           Graphics.Canvas    as C

import           Draw.Common        (AppTime (..), Draw, Settings, drawImage,
                                     fillRect, onContext, setFillStyle,
                                     showTimestamp)
import           Draw.Drums         (drawDrums)
import           Draw.Five          (drawFive)
import           Draw.ProKeys       (drawProKeys)
import           Draw.Protar        (drawProtar)
import           Draw.Six           (drawSix)
import           Draw.Vocal         (drawVocal)
import           Draw.Amplitude     (drawAmplitude)
import           Images             (ImageID (..))
import           Song               (Flex (..), Song (..))
import           Style              (customize)

foreign import getWindowDims :: Effect {width :: Number, height :: Number}

foreign import numMod :: Number -> Number -> Number

draw :: Draw Unit
draw stuff = do
  dims@{width: windowW, height: windowH} <- getWindowDims
  cdims <- C.getCanvasDimensions stuff.canvas
  when (cdims /= dims) (C.setCanvasDimensions stuff.canvas dims)
  setFillStyle customize.background stuff
  fillRect { x: 0.0, y: 0.0, width: windowW, height: windowH } stuff
  -- Draw timestamp
  onContext (\ctx -> C.setFont ctx customize.timestampFont) stuff
  setFillStyle customize.timestampColor stuff
  onContext
    (\ctx -> do
      void $ C.setTextAlign ctx C.AlignRight
      C.fillText ctx
        (showTimestamp stuff.time)
        (windowW - 20.0)
        (windowH - 20.0)
    ) stuff
  -- Draw the visible instrument tracks in sequence
  let drawTracks targetX trks = case uncons trks of
        Nothing -> pure unit
        Just {head: trk, tail: trkt} -> do
          drawResult <- trk targetX
          case drawResult of
            Just targetX' -> drawTracks targetX' trkt
            Nothing       -> drawTracks targetX  trkt
  let song = case stuff.song of Song s -> s

  let partEnabled pname ptype dname sets = or do
        part <- sets.parts
        guard $ part.partName == pname
        fpart <- part.flexParts
        guard $ fpart.partType == ptype
        diff <- fpart.difficulties
        guard $ diff.diffName == dname
        pure diff.enabled
      drawParts someStuff = drawTracks (_M + _B + _M) $ concat $ flip map song.parts \(Tuple part (Flex flex)) -> do
        fn <-
          [ \diff i -> drawPart (flex.five      >>= lookup diff) (partEnabled part "five"      diff) drawFive      i someStuff
          , \diff i -> drawPart (flex.six       >>= lookup diff) (partEnabled part "six"       diff) drawSix       i someStuff
          , \diff i -> drawPart (flex.drums     >>= lookup diff) (partEnabled part "drums"     diff) drawDrums     i someStuff
          , \diff i -> drawPart (flex.prokeys   >>= lookup diff) (partEnabled part "prokeys"   diff) drawProKeys   i someStuff
          , \diff i -> drawPart (flex.protar    >>= lookup diff) (partEnabled part "protar"    diff) drawProtar    i someStuff
          , \diff i -> drawPart (flex.amplitude >>= lookup diff) (partEnabled part "amplitude" diff) drawAmplitude i someStuff
          ]
        map fn ["X+", "X", "H", "M", "E", "S/X", "A", "I", "B"] -- TODO do this whole thing better
  if stuff.app.settings.staticVert
    then let
      betweenTargets = windowH * 0.65
      Seconds now = stuff.time
      bottomTarget = windowH - toNumber customize.targetPositionVert - numMod (now * customize.trackSpeed) betweenTargets
      topTarget = bottomTarget - betweenTargets
      unseenTarget = bottomTarget + betweenTargets
      drawTarget y = do
        let drawBottom = y + toNumber customize.targetPositionVert
            drawTop = drawBottom - betweenTargets + toNumber _M
        when (0.0 < drawBottom && drawTop < windowH) do
          void $ C.save stuff.context
          void $ C.beginPath stuff.context
          void $ C.rect stuff.context { x: 0.0, y: drawTop, width: windowW, height: drawBottom - drawTop }
          void $ C.clip stuff.context
          drawParts stuff
            { pxToSecsVert = \px -> Seconds $ (toNumber px - windowH + y) / customize.trackSpeed
            , secsToPxVert = \(Seconds secs) -> round $ windowH - y + customize.trackSpeed * secs
            }
          void $ C.restore stuff.context
      in do
        -- TODO just draw once and then copy
        drawTarget bottomTarget
        drawTarget topTarget
        drawTarget unseenTarget
    else drawParts stuff

  drawTracks 0 $ concat $ flip map song.parts \(Tuple part (Flex flex)) -> do
    map (\mode i -> drawPart (flex.vocal >>= lookup mode) (partEnabled part "vocal" mode) drawVocal i stuff) ["H", "1"]
  let playPause = case stuff.app.time of
        Paused  _ -> Image_button_play
        Playing _ -> Image_button_pause
  drawImage playPause (toNumber _M) (windowH - 2.0 * toNumber _M - 2.0 * toNumber _B) stuff
  drawImage Image_button_gear (toNumber _M) (windowH - toNumber _M - toNumber _B) stuff
  let timelineH = windowH - 4.0 * toNumber _M - 2.0 * toNumber _B - 2.0
      filled = unSeconds (stuff.time) / unSeconds (case stuff.song of Song o -> o.end)
      unSeconds (Seconds s) = s
  setFillStyle customize.progressBorder stuff
  fillRect { x: toNumber _M, y: toNumber _M, width: toNumber _B, height: timelineH + 2.0 } stuff
  setFillStyle customize.progressEmpty stuff
  fillRect { x: toNumber _M + 1.0, y: toNumber _M + 1.0, width: toNumber _B - 2.0, height: timelineH } stuff
  setFillStyle customize.progressFilled stuff
  fillRect
    { x: toNumber _M + 1.0
    , y: toNumber _M + 1.0 + timelineH * (1.0 - filled)
    , width: toNumber _B - 2.0
    , height: timelineH * filled
    } stuff

drawPart
  :: forall a r
  .  Maybe a
  -> (Settings -> Boolean)
  -> (a -> Int -> Draw r)
  -> Int
  -> Draw (Maybe r)
drawPart getPart see drawIt targetX stuff = do
  let settings = stuff.app.settings
  case getPart of
    Just part | see settings -> map Just $ drawIt part targetX stuff
    _                        -> pure Nothing

-- | Height/width of margins
_M :: Int
_M = customize.marginWidth

-- | Height/width of buttons
_B :: Int
_B = customize.buttonWidth
