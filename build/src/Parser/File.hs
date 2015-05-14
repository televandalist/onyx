{-# LANGUAGE LambdaCase #-}
module Parser.File where

import qualified Sound.MIDI.File as F
import qualified Sound.MIDI.File.Event as E
import qualified Sound.MIDI.File.Event.Meta as Meta
import qualified Sound.MIDI.Util as U
import qualified Data.EventList.Relative.TimeBody as RTB
import qualified Data.EventList.Absolute.TimeBody as ATB
import qualified Numeric.NonNegative.Class as NNC
import Control.Monad (forM, forM_, liftM)
import Data.Maybe (catMaybes, fromJust)

import Parser
import Parser.Base
import qualified Parser.Drums as Drums
import qualified Parser.Events as Events
import qualified Parser.Beat as Beat
import qualified Parser.Countin as Countin
import qualified Parser.FiveButton as FiveButton
import qualified Parser.Vocals as Vocals
import qualified Parser.ProKeys as ProKeys

data Track t
  = PartDrums  (RTB.T t Drums.Event     )
  | PartGuitar (RTB.T t FiveButton.Event)
  | PartBass   (RTB.T t FiveButton.Event)
  | PartKeys   (RTB.T t FiveButton.Event)
  | PartRealKeys Difficulty (RTB.T t ProKeys.Event)
  | PartKeysAnimLH (RTB.T t ProKeys.Event)
  | PartKeysAnimRH (RTB.T t ProKeys.Event)
  | PartVocals (RTB.T t Vocals.Event    )
  | Harm1      (RTB.T t Vocals.Event    )
  | Harm2      (RTB.T t Vocals.Event    )
  | Harm3      (RTB.T t Vocals.Event    )
  | Countin    (RTB.T t Countin.Event   )
  | Events     (RTB.T t Events.Event    )
  | Beat       (RTB.T t Beat.Event      )
  deriving (Eq, Ord, Show)

data Song t = Song
  { s_tempos     :: U.TempoMap
  , s_signatures :: U.MeasureMap
  , s_tracks     :: [Track t]
  } deriving (Eq, Ord, Show)

-- | TODO: handle a non-encodeable time signature
showMIDIFile :: Song U.Beats -> F.T
showMIDIFile s = let
  tempos = fmap U.showTempo $ U.tempoMapToBPS $ s_tempos s
  sigs = fmap (fromJust . U.showSignature) $ U.measureMapToLengths $ s_signatures s
  tempoTrk = U.setTrackName "onyxbuild" $ RTB.merge tempos sigs
  in U.encodeFileBeats F.Parallel 480 $ tempoTrk : map showTrack (s_tracks s)

showTrack :: Track U.Beats -> RTB.T U.Beats E.T
showTrack = \case
  PartDrums  t -> U.setTrackName "PART DRUMS"  $ U.trackJoin $ fmap Drums.showEvent      t
  PartGuitar t -> U.setTrackName "PART GUITAR" $ U.trackJoin $ fmap FiveButton.showEvent t
  PartBass   t -> U.setTrackName "PART BASS"   $ U.trackJoin $ fmap FiveButton.showEvent t
  PartKeys   t -> U.setTrackName "PART KEYS"   $ U.trackJoin $ fmap FiveButton.showEvent t
  PartRealKeys d t -> U.setTrackName ("PART REAL_KEYS_" ++ take 1 (show d)) $
    U.trackJoin $ fmap ProKeys.showEvent t
  PartKeysAnimLH t -> U.setTrackName "PART KEYS_ANIM_LH" $ U.trackJoin $ fmap ProKeys.showEvent t
  PartKeysAnimRH t -> U.setTrackName "PART KEYS_ANIM_RH" $ U.trackJoin $ fmap ProKeys.showEvent t
  PartVocals t -> U.setTrackName "PART VOCALS" $ U.trackJoin $ fmap Vocals.showEvent t
  Harm1      t -> U.setTrackName "HARM1"       $ U.trackJoin $ fmap Vocals.showEvent     t
  Harm2      t -> U.setTrackName "HARM2"       $ U.trackJoin $ fmap Vocals.showEvent     t
  Harm3      t -> U.setTrackName "HARM3"       $ U.trackJoin $ fmap Vocals.showEvent     t
  Countin    t -> U.setTrackName "countin"     $ U.trackJoin $ fmap Countin.showEvent    t
  Events     t -> U.setTrackName "EVENTS"      $ U.trackJoin $ fmap Events.showEvent     t
  Beat       t -> U.setTrackName "BEAT"        $ U.trackJoin $ fmap Beat.showEvent       t

readMIDIFile :: (Monad m) => F.T -> ParserT m (Song U.Beats)
readMIDIFile mid = case U.decodeFile mid of
  Right _ -> fatal "SMPTE tracks not supported"
  Left trks -> let
    (tempoTrk, restTrks) = case trks of
      t : ts -> (t, ts)
      []     -> (RTB.empty, [])
    mmap = U.makeMeasureMap U.Error tempoTrk
    in do
      songTrks <- forM (zip ([1..] :: [Int]) restTrks) $ \(i, trk) ->
        inside ("track " ++ show i ++ " (0 is tempo track)") $ optional $ parseTrack mmap trk
      return $ Song
        { s_tempos     = U.makeTempoMap tempoTrk
        , s_signatures = mmap
        , s_tracks     = catMaybes songTrks
        }

-- | Strips comments and track names from the track before handing it to a track parser.
stripTrack :: (NNC.C t) => RTB.T t E.T -> RTB.T t E.T
stripTrack = RTB.filter $ \e -> case e of
  E.MetaEvent (Meta.TextEvent ('#' : _)) -> False
  E.MetaEvent (Meta.TrackName _        ) -> False
  _                                      -> True

makeTrackParser :: (Monad m) =>
  (E.T -> Maybe [a]) -> U.MeasureMap -> RTB.T U.Beats E.T -> ParserT m (RTB.T U.Beats a)
makeTrackParser p mmap trk = do
  let (good, bad) = RTB.partitionMaybe p $ stripTrack trk
  forM_ (ATB.toPairList $ RTB.toAbsoluteEventList 0 bad) $ \(bts, e) ->
    inside (showPosition $ U.applyMeasureMap mmap bts) $ warn $ "Unrecognized event: " ++ show e
  return $ RTB.flatten good

parseTrack :: (Monad m) => U.MeasureMap -> RTB.T U.Beats E.T -> ParserT m (Track U.Beats)
parseTrack mmap t = case U.trackName t of
  Nothing -> fatal "Track with no name"
  Just s -> inside ("track named " ++ show s) $ case s of
    "PART DRUMS"  -> liftM PartDrums  $ makeTrackParser Drums.readEvent      mmap t
    "PART GUITAR" -> liftM PartGuitar $ makeTrackParser FiveButton.readEvent mmap t
    "PART BASS"   -> liftM PartBass   $ makeTrackParser FiveButton.readEvent mmap t
    "PART KEYS"   -> liftM PartKeys   $ makeTrackParser FiveButton.readEvent mmap t
    "PART REAL_KEYS_E" -> liftM (PartRealKeys Easy) $ makeTrackParser ProKeys.readEvent mmap t
    "PART REAL_KEYS_M" -> liftM (PartRealKeys Medium) $ makeTrackParser ProKeys.readEvent mmap t
    "PART REAL_KEYS_H" -> liftM (PartRealKeys Hard) $ makeTrackParser ProKeys.readEvent mmap t
    "PART REAL_KEYS_X" -> liftM (PartRealKeys Expert) $ makeTrackParser ProKeys.readEvent mmap t
    "PART KEYS_ANIM_LH" -> liftM PartKeysAnimLH $ makeTrackParser ProKeys.readEvent mmap t
    "PART KEYS_ANIM_RH" -> liftM PartKeysAnimRH $ makeTrackParser ProKeys.readEvent mmap t
    "PART VOCALS" -> liftM PartVocals $ makeTrackParser Vocals.readEvent mmap t
    "HARM1"       -> liftM Harm1      $ makeTrackParser Vocals.readEvent mmap t
    "HARM2"       -> liftM Harm2      $ makeTrackParser Vocals.readEvent mmap t
    "HARM3"       -> liftM Harm3      $ makeTrackParser Vocals.readEvent mmap t
    "countin"     -> liftM Countin    $ makeTrackParser Countin.readEvent    mmap t
    "EVENTS"      -> liftM Events     $ makeTrackParser Events.readEvent     mmap t
    "BEAT"        -> liftM Beat       $ makeTrackParser Beat.readEvent       mmap t
    _ -> fatal "Unrecognized track name"

showPosition :: U.MeasureBeats -> String
showPosition (m, b) =
  "measure " ++ show (m + 1) ++ ", beat " ++ show (realToFrac b + 1 :: Double)
