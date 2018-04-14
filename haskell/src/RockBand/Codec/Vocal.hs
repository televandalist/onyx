{-# LANGUAGE LambdaCase      #-}
{-# LANGUAGE RecordWildCards #-}
module RockBand.Codec.Vocal where

import           Control.Monad.Codec
import qualified Data.EventList.Relative.TimeBody as RTB
import qualified Data.Text                        as T
import           RockBand.Codec
import           RockBand.Common
import           RockBand.Vocals                  (PercussionType (..),
                                                   Pitch (..))
import qualified Sound.MIDI.File.Event            as E
import qualified Sound.MIDI.File.Event.Meta       as Meta
import qualified Sound.MIDI.Util                  as U

data VocalTrack t = VocalTrack
  { vocalMood          :: RTB.T t Mood
  , vocalLyrics        :: RTB.T t T.Text
  , vocalPerc          :: RTB.T t () -- ^ playable percussion notes
  , vocalPercSound     :: RTB.T t () -- ^ nonplayable percussion, only triggers sound sample
  , vocalPercAnimation :: RTB.T t (PercussionType, Bool)
  , vocalPhrase1       :: RTB.T t Bool -- ^ General phrase marker (RB3) or Player 1 phrases (pre-RB3)
  , vocalPhrase2       :: RTB.T t Bool -- ^ Pre-RB3, used for 2nd player phrases in Tug of War
  , vocalOverdrive     :: RTB.T t Bool
  , vocalLyricShift    :: RTB.T t ()
  , vocalRangeShift    :: RTB.T t Bool
  , vocalNotes         :: RTB.T t (Pitch, Bool)
  } deriving (Eq, Ord, Show)

instance TraverseTrack VocalTrack where
  traverseTrack fn (VocalTrack a b c d e f g h i j k) = VocalTrack
    <$> fn a <*> fn b <*> fn c <*> fn d <*> fn e <*> fn f
    <*> fn g <*> fn h <*> fn i <*> fn j <*> fn k

instance ParseTrack VocalTrack where
  parseTrack = do
    vocalMood   <- vocalMood   =. command
    vocalLyrics <- vocalLyrics =. let
      fp = \case
        E.MetaEvent (Meta.Lyric t) -> Just $ T.pack t
        E.MetaEvent (Meta.TextEvent t) -> case readCommand txt :: Maybe [T.Text] of
          Nothing -> Just txt -- non-command text events get defaulted to lyrics
          Just _  -> Nothing
          where txt = T.pack t
        _ -> Nothing
      fs = E.MetaEvent . Meta.Lyric . T.unpack
      in single fp fs
    vocalPerc          <- vocalPerc          =. blip 96
    vocalPercSound     <- vocalPercSound     =. blip 97
    vocalPercAnimation <- vocalPercAnimation =. command
    vocalPhrase1       <- vocalPhrase1       =. edges 105
    vocalPhrase2       <- vocalPhrase2       =. edges 106
    vocalOverdrive     <- vocalOverdrive     =. edges 116
    vocalLyricShift    <- vocalLyricShift    =. blip 1
    vocalRangeShift    <- vocalRangeShift    =. edges 0
    vocalNotes         <- (vocalNotes        =.)
      $ condenseMap $ eachKey each $ edges . (+ 36) . fromEnum
    return VocalTrack{..}

fixGHVocals :: VocalTrack U.Beats -> VocalTrack U.Beats
fixGHVocals = undefined
