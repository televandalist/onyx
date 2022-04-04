{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DerivingVia        #-}
{-# LANGUAGE LambdaCase         #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE RecordWildCards    #-}
module PowerGig.MIDI where

import           Control.Monad.Codec
import           Control.Monad.Trans.Class        (lift)
import           Control.Monad.Trans.State.Strict (modify)
import qualified Data.EventList.Relative.TimeBody as RTB
import qualified Data.Map                         as Map
import qualified Data.Text                        as T
import           DeriveHelpers
import           GHC.Generics                     (Generic)
import           RockBand.Codec
import qualified RockBand.Codec.Drums             as D
import           RockBand.Codec.File              (ParseFile (..), fileTrack)
import qualified RockBand.Codec.Five              as F
import           RockBand.Codec.Vocal             (Pitch)
import           RockBand.Common
import           Sound.MIDI.Message.Channel.Voice (toPitch)

data GuitarDifficulty t = GuitarDifficulty
  { guitarGems             :: RTB.T t (Edge () (Maybe F.Color))
  , guitarPowerChordsE     :: RTB.T t (Edge () (Maybe F.Color))
  , guitarPowerChordsA     :: RTB.T t (Edge () (Maybe F.Color))
  , guitarPowerChordsGRYBO :: RTB.T t (Edge () (Maybe F.Color)) -- normal notes used in power chord sections
  , guitarHOPO             :: RTB.T t Bool
  , guitarPowerChordMode   :: RTB.T t Bool
  , guitarMojoDrummer      :: RTB.T t Bool
  , guitarMojoVocalist     :: RTB.T t Bool
  -- rest unknown
  , guitarController7      :: RTB.T t Int
  -- TODO others seen: controller 0, controller 32, controller 80
  } deriving (Show, Generic)
    deriving (Semigroup, Monoid, Mergeable) via GenericMerge (GuitarDifficulty t)

instance ParseTrack GuitarDifficulty where
  parseTrack = do
    let allGems = Nothing : map Just each
    guitarGems <- (guitarGems =.) $ translateEdges $ condenseMap $ eachKey allGems $ edges . \case
      Nothing       -> 60
      Just F.Green  -> 62
      Just F.Red    -> 64
      Just F.Yellow -> 65
      Just F.Blue   -> 67
      Just F.Orange -> 69
    guitarPowerChordsGRYBO <- (guitarPowerChordsGRYBO =.) $ translateEdges $ condenseMap $ eachKey allGems $ edges . \case
      Nothing       -> 96
      Just F.Green  -> 98
      Just F.Red    -> 100
      Just F.Yellow -> 101
      Just F.Blue   -> 103
      Just F.Orange -> 105
    guitarPowerChordsE <- (guitarPowerChordsE =.) $ translateEdges $ condenseMap $ eachKey allGems $ edges . \case
      Nothing       -> 108
      Just F.Green  -> 109
      Just F.Red    -> 110
      Just F.Yellow -> 111
      Just F.Blue   -> 112
      Just F.Orange -> 113
    guitarPowerChordsA <- (guitarPowerChordsA =.) $ translateEdges $ condenseMap $ eachKey allGems $ edges . \case
      Nothing       -> 114
      Just F.Green  -> 115
      Just F.Red    -> 116
      Just F.Yellow -> 117
      Just F.Blue   -> 118
      Just F.Orange -> 119
    guitarHOPO           <- guitarHOPO           =. controllerBool 68 -- "legato pedal"
    guitarPowerChordMode <- guitarPowerChordMode =. controllerBool 86
    guitarMojoDrummer    <- guitarMojoDrummer    =. controllerBool 81
    guitarMojoVocalist   <- guitarMojoVocalist   =. controllerBool 82
    guitarController7    <- guitarController7    =. controller_ 7
    return GuitarDifficulty{..}

data DrumDifficulty t = DrumDifficulty
  { drumGems          :: RTB.T t (D.Gem ())
  , drumFreestyle     :: RTB.T t (Edge () (D.Gem ())) -- not sure what this is, just a guess. appears in lower difficulties?
  , drumMojoGuitarist :: RTB.T t Bool
  , drumMojoVocalist  :: RTB.T t Bool
  -- TODO program change (ch 9), probably switches between e.g. <kit kit_number="0" ...>
  -- rest unknown
  , drumController64  :: RTB.T t Int
  -- TODO others seen: note pitch 61, note pitch 66, note pitch 84, controller 10, controller 7
  } deriving (Show, Generic)
    deriving (Semigroup, Monoid, Mergeable) via GenericMerge (DrumDifficulty t)

instance ParseTrack DrumDifficulty where
  parseTrack = do
    let allDrums = [D.Kick, D.Red, D.Pro D.Yellow (), D.Pro D.Blue (), D.Pro D.Green ()]
    drumGems <- (drumGems =.) $ fatBlips (1/8) $ condenseMap_ $ eachKey allDrums $ blip . \case
      D.Pro D.Green  () -> 62
      D.Red             -> 64
      D.Pro D.Yellow () -> 65
      D.Pro D.Blue   () -> 67
      D.Kick            -> 69
      D.Orange          -> error "panic! orange case in powergig drums"
    drumFreestyle <- (drumFreestyle =.) $ translateEdges $ condenseMap $ eachKey allDrums $ edges . \case
      D.Pro D.Green  () -> 86
      D.Red             -> 88
      D.Pro D.Yellow () -> 89
      D.Pro D.Blue   () -> 91
      D.Kick            -> 93
      D.Orange          -> error "panic! orange case in powergig drums"
    drumMojoGuitarist <- drumMojoGuitarist =. controllerBool 80
    drumMojoVocalist  <- drumMojoVocalist  =. controllerBool 82
    drumController64  <- drumController64  =. controller_ 64
    return DrumDifficulty{..}

data VocalDifficulty t = VocalDifficulty
  { vocalNotes             :: RTB.T t (Pitch, Bool) -- not sure of range
  , vocalTalkies           :: RTB.T t Bool
  , vocalLyrics            :: RTB.T t T.Text
  , vocalPhraseEnd         :: RTB.T t ()
  , vocalUnknownBackslashN :: RTB.T t ()
  , vocalFreestyle         :: RTB.T t Bool
  , vocalGlue              :: RTB.T t Bool
  , vocalMojoGuitarist     :: RTB.T t Bool
  , vocalMojoDrummer       :: RTB.T t Bool
  } deriving (Show, Generic)
    deriving (Semigroup, Monoid, Mergeable) via GenericMerge (VocalDifficulty t)

instance ParseTrack VocalDifficulty where
  parseTrack = do
    vocalNotes             <- vocalNotes             =. condenseMap (eachKey each $ edges . (+ 36) . fromEnum)
    vocalTalkies           <- vocalTalkies           =. edges 0
    vocalLyrics            <- vocalLyrics            =. lyrics
    vocalPhraseEnd         <- vocalPhraseEnd         =. powerGigText "\\r"
    vocalUnknownBackslashN <- vocalUnknownBackslashN =. powerGigText "\\n"
    vocalFreestyle         <- vocalFreestyle         =. controllerBool 64 -- "hold pedal"
    vocalGlue              <- vocalGlue              =. controllerBool 68 -- "legato pedal"
    vocalMojoGuitarist     <- vocalMojoGuitarist     =. controllerBool 80
    vocalMojoDrummer       <- vocalMojoDrummer       =. controllerBool 81
    return VocalDifficulty{..}

data BeatTrack t = BeatTrack
  { beatLines :: RTB.T t ()
  } deriving (Show, Generic)
    deriving (Semigroup, Monoid, Mergeable) via GenericMerge (BeatTrack t)

instance ParseTrack BeatTrack where
  parseTrack = do
    -- these can be any pitch apparently
    Codec
      { codecIn = lift $ modify $ \mt -> mt
        { midiNotes = Map.singleton (toPitch 60) $ mconcat $ Map.elems $ midiNotes mt
        }
      , codecOut = const $ return ()
      }
    beatLines <- beatLines =. blip 60
    return BeatTrack{..}

data PGFile t = PGFile

  { pgGuitarBeginner :: GuitarDifficulty t
  , pgGuitarEasy     :: GuitarDifficulty t
  , pgGuitarMedium   :: GuitarDifficulty t
  , pgGuitarHard     :: GuitarDifficulty t
  , pgGuitarExpert   :: GuitarDifficulty t
  , pgGuitarMaster   :: GuitarDifficulty t

  , pgDrumsBeginner  :: DrumDifficulty t
  , pgDrumsEasy      :: DrumDifficulty t
  , pgDrumsMedium    :: DrumDifficulty t
  , pgDrumsHard      :: DrumDifficulty t
  , pgDrumsExpert    :: DrumDifficulty t
  , pgDrumsMaster    :: DrumDifficulty t

  , pgVocalsBeginner :: VocalDifficulty t
  , pgVocalsEasy     :: VocalDifficulty t
  , pgVocalsMedium   :: VocalDifficulty t
  , pgVocalsHard     :: VocalDifficulty t
  , pgVocalsExpert   :: VocalDifficulty t
  , pgVocalsMaster   :: VocalDifficulty t

  , pgBeat           :: BeatTrack t

  } deriving (Show, Generic)
    deriving (Semigroup, Monoid, Mergeable) via GenericMerge (PGFile t)

instance ParseFile PGFile where
  parseFile = do

    pgGuitarBeginner <- pgGuitarBeginner =. fileTrack (pure "guitar_1_beginner")
    pgGuitarEasy     <- pgGuitarEasy     =. fileTrack (pure "guitar_1_easy"    )
    pgGuitarMedium   <- pgGuitarMedium   =. fileTrack (pure "guitar_1_medium"  )
    pgGuitarHard     <- pgGuitarHard     =. fileTrack (pure "guitar_1_hard"    )
    pgGuitarExpert   <- pgGuitarExpert   =. fileTrack (pure "guitar_1_expert"  )
    pgGuitarMaster   <- pgGuitarMaster   =. fileTrack (pure "guitar_1_master"  )

    pgDrumsBeginner <- pgDrumsBeginner =. fileTrack (pure "drums_1_beginner")
    pgDrumsEasy     <- pgDrumsEasy     =. fileTrack (pure "drums_1_easy"    )
    pgDrumsMedium   <- pgDrumsMedium   =. fileTrack (pure "drums_1_medium"  )
    pgDrumsHard     <- pgDrumsHard     =. fileTrack (pure "drums_1_hard"    )
    pgDrumsExpert   <- pgDrumsExpert   =. fileTrack (pure "drums_1_expert"  )
    pgDrumsMaster   <- pgDrumsMaster   =. fileTrack (pure "drums_1_master"  )

    pgVocalsBeginner <- pgVocalsBeginner =. fileTrack (pure "vocals_1_beginner")
    pgVocalsEasy     <- pgVocalsEasy     =. fileTrack (pure "vocals_1_easy"    )
    pgVocalsMedium   <- pgVocalsMedium   =. fileTrack (pure "vocals_1_medium"  )
    pgVocalsHard     <- pgVocalsHard     =. fileTrack (pure "vocals_1_hard"    )
    pgVocalsExpert   <- pgVocalsExpert   =. fileTrack (pure "vocals_1_expert"  )
    pgVocalsMaster   <- pgVocalsMaster   =. fileTrack (pure "vocals_1_master"  )

    pgBeat <- pgBeat =. fileTrack (pure "beat")

    return PGFile{..}
