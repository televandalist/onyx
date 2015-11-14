{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import OnyxiteDisplay.Draw
import OnyxiteDisplay.Process
import Control.Monad.Trans.Reader
import Control.Monad.IO.Class
import qualified JavaScript.Web.Canvas as C
import JavaScript.Web.AnimationFrame (waitForAnimationFrame)
import Control.Applicative (liftA2)
import Linear (V2(..), V4(..))
import Linear.Affine (Point (..))
import JavaScript.Web.XMLHttpRequest
import qualified Sound.MIDI.File.Load as Load
import qualified Sound.MIDI.Parser.Report as MIDIParser
import qualified Data.ByteString.Lazy as BL
import Control.Monad.Trans.StackTrace (runStackTrace)
import qualified RockBand.File                    as RB
import RockBand.Common (Difficulty(..))
import qualified Data.EventList.Absolute.TimeBody as ATB
import           Control.Monad                    (unless)
import qualified Data.Map.Strict                  as Map
import qualified RockBand.Events                  as Events
import qualified RockBand.FiveButton              as Five
import qualified Sound.MIDI.Util                  as U
import           Data.Maybe                       (listToMaybe)
import qualified Data.EventList.Relative.TimeBody as RTB

import GHCJS.Types

import qualified Audio
import Images

newtype DrawCanvas a = DrawCanvas
  { runDrawCanvas :: ReaderT (C.Canvas, C.Context, ImageID -> C.Image) IO a
  } deriving (Functor, Applicative, Monad, MonadIO)

instance MonadDraw DrawCanvas where
  getDims = do
    (canv, _, _) <- DrawCanvas ask
    liftIO $ liftA2 V2 (canvasWidth canv) (canvasHeight canv)
  setColor (V4 r g b a) = do
    (_, ctx, _) <- DrawCanvas ask
    liftIO $ C.fillStyle (fromIntegral r) (fromIntegral g) (fromIntegral b) (fromIntegral a / 255) ctx
  fillRect (P (V2 x y)) (V2 w h) = do
    (_, ctx, _) <- DrawCanvas ask
    liftIO $ C.fillRect (fromIntegral x) (fromIntegral y) (fromIntegral w) (fromIntegral h) ctx
  drawImage iid (P (V2 x y)) = do
    (_, ctx, getImage) <- DrawCanvas ask
    let img = getImage iid
    w <- liftIO $ imageWidth img
    h <- liftIO $ imageHeight img
    liftIO $ C.drawImage (getImage iid) x y w h ctx

foreign import javascript unsafe "$1.width"
  canvasWidth :: C.Canvas -> IO Int
foreign import javascript unsafe "$1.height"
  canvasHeight :: C.Canvas -> IO Int

foreign import javascript unsafe "$1.width"
  imageWidth :: C.Image -> IO Int
foreign import javascript unsafe "$1.height"
  imageHeight :: C.Image -> IO Int

foreign import javascript unsafe "document.getElementById('the-canvas')"
  theCanvas :: C.Canvas

foreign import javascript unsafe
  " $1.width = window.innerWidth; \
  \ $1.height = window.innerHeight; "
  resizeCanvas :: C.Canvas -> IO ()

main :: IO ()
main = do
  resp <- xhrByteString $ Request
    { reqMethod = GET
    , reqURI = "songs/liquid-tension-experiment/914/gen/plan/album/2p/notes.mid"
    , reqLogin = Nothing
    , reqHeaders = []
    , reqWithCredentials = False
    , reqData = NoData
    }
  midbs <- case contents resp of
    Just bs -> return bs
    Nothing -> error "couldn't get MIDI as bytestring"
  mid <- case MIDIParser.result $ Load.maybeFromByteString $ BL.fromStrict midbs of
    Right mid -> return mid
    Left _ -> error "couldn't parse MIDI from bytestring"
  song <- case runStackTrace $ RB.readMIDIFile mid of
    (Right song, _) -> return song
    (Left _, _) -> error "Error when reading MIDI file"
  let gtr = processFive (Just $ 170 / 480) (RB.s_tempos song)
        $ foldr RTB.merge RTB.empty [ t | RB.PartGuitar t <- RB.s_tracks song ]
      bass = processFive (Just $ 170 / 480) (RB.s_tempos song)
        $ foldr RTB.merge RTB.empty [ t | RB.PartBass t <- RB.s_tracks song ]
      keys = processFive Nothing (RB.s_tempos song)
        $ foldr RTB.merge RTB.empty [ t | RB.PartKeys t <- RB.s_tracks song ]
      drums = processDrums (RB.s_tempos song)
        $ foldr RTB.merge RTB.empty [ t | RB.PartDrums t <- RB.s_tracks song ]
      prokeys = processProKeys (RB.s_tempos song)
        $ foldr RTB.merge RTB.empty [ t | RB.PartRealKeys Expert t <- RB.s_tracks song ]
      beat = processBeat (RB.s_tempos song)
        $ foldr RTB.merge RTB.empty [ t | RB.Beat t <- RB.s_tracks song ]

  ctx <- C.getContext theCanvas
  getImage <- imageGetter
  howl <- Audio.load ["songs/liquid-tension-experiment/914/gen/plan/album/preview-audio.ogg"]

  let pxToSecs targetY now px = let
        secs = fromIntegral (targetY - px) * 0.003 + realToFrac now :: Rational
        in if secs < 0 then 0 else realToFrac secs
      secsToPx targetY now px = round (negate $ (realToFrac px - realToFrac now) / 0.003 - targetY :: Rational)

  let fiveNull      five = all Map.null $ Map.elems $                         fiveNotes five
      fiveOnlyGreen five = all Map.null $ Map.elems $ Map.delete Five.Green $ fiveNotes five
      gtrNull = fiveNull gtr
      bassNull = fiveNull bass
      keysNull = fiveNull keys || fiveOnlyGreen keys
      drumsNull = Map.null $ drumNotes drums
      proKeysNull = all Map.null $ Map.elems $ proKeysNotes prokeys
      endEvent = listToMaybe $ do
        RB.Events t <- RB.s_tracks song
        (bts, Events.End) <- ATB.toPairList $ RTB.toAbsoluteEventList 0 t
        return $ U.applyTempoMap (RB.s_tempos song) bts
      drawFrame :: U.Seconds -> IO ()
      drawFrame t = do
        resizeCanvas theCanvas
        windowW <- canvasWidth theCanvas
        windowH <- canvasHeight theCanvas
        C.fillStyle 54 59 123 1.0 ctx
        C.fillRect 0 0 (fromIntegral windowW) (fromIntegral windowH) ctx
        let targetY :: (Num a) => a
            targetY = fromIntegral windowH - 50
        (\act -> runReaderT (runDrawCanvas act) (theCanvas, ctx, getImage)) $ do
          unless gtrNull     $ drawFive    (pxToSecs targetY t) (secsToPx targetY t) (P $ V2 50  targetY) gtr     beat
          unless bassNull    $ drawFive    (pxToSecs targetY t) (secsToPx targetY t) (P $ V2 275 targetY) bass    beat
          unless drumsNull   $ drawDrums   (pxToSecs targetY t) (secsToPx targetY t) (P $ V2 500 targetY) drums   beat
          unless keysNull    $ drawFive    (pxToSecs targetY t) (secsToPx targetY t) (P $ V2 689 targetY) keys    beat
          unless proKeysNull $ drawProKeys (pxToSecs targetY t) (secsToPx targetY t) (P $ V2 914 targetY) prokeys beat
  drawFrame 0
  msStart <- waitForAnimationFrame
  _ <- Audio.play howl
  let loop = do
        ms <- waitForAnimationFrame
        drawFrame $ realToFrac $ (ms - msStart) / 1000
        loop
  loop
