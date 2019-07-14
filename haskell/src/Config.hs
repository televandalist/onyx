{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DeriveFoldable    #-}
{-# LANGUAGE DeriveFunctor     #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms   #-}
{-# LANGUAGE RankNTypes        #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TupleSections     #-}
module Config where

import qualified Amplitude.File                 as Amp
import           Audio
import           Control.Arrow                  (first)
import           Control.Monad.Codec            (CodecFor (..), (=.))
import           Control.Monad.Trans.Class      (lift)
import           Control.Monad.Trans.Reader
import           Control.Monad.Trans.StackTrace
import qualified Data.Aeson                     as A
import           Data.Char                      (isDigit, isSpace)
import           Data.Conduit.Audio             (Duration (..))
import           Data.Default.Class
import qualified Data.DTA.Serialize.GH2         as GH2
import qualified Data.DTA.Serialize.Magma       as Magma
import           Data.DTA.Serialize.RB3         (AnimTempo (..))
import           Data.Fixed                     (Milli)
import           Data.Foldable                  (toList)
import           Data.Hashable                  (Hashable (..))
import qualified Data.HashMap.Strict            as Map
import           Data.Maybe                     (fromMaybe)
import           Data.Monoid                    ((<>))
import           Data.Scientific                (Scientific, toRealFloat)
import qualified Data.Text                      as T
import           Data.Traversable
import qualified Data.Vector                    as V
import           GHC.Generics                   (Generic (..))
import           JSONData
import           RockBand.Codec.File            (FlexPartName (..), getPartName,
                                                 readPartName)
import           RockBand.Codec.ProGuitar       (GtrBase (..), GtrTuning (..))
import           RockBand.Common                (Key (..), SongKey (..),
                                                 Tonality (..), readpKey,
                                                 showKey, songKeyUsesFlats)
import qualified Sound.Jammit.Base              as J
import qualified Sound.MIDI.Util                as U
import qualified Text.ParserCombinators.ReadP   as ReadP
import           Text.Read                      (readMaybe)
import qualified Text.Read.Lex                  as Lex

parsePitch :: (SendMessage m) => ValueCodec m A.Value Key
parsePitch = Codec
  { codecOut = makeOut $ A.toJSON . showKey False -- no way of getting accidental
  , codecIn = do
    t <- codecIn stackJSON
    case ReadP.readP_to_S (readpKey <* ReadP.eof) $ T.unpack t of
      (sk, _) : _ -> return sk
      []          -> expected "a key"
  }

parseSongKey :: (SendMessage m) => ValueCodec m A.Value SongKey
parseSongKey = Codec
  { codecOut = makeOut $ \sk@(SongKey k t) -> A.toJSON $ concat
    [ showKey (songKeyUsesFlats sk) k
    , case t of Major -> " major"; Minor -> " minor"
    ]
  , codecIn = codecIn stackJSON >>= \t -> let
    parse = do
      key <- readpKey
      tone <- ReadP.choice
        [ ReadP.string " major" >> return Major
        , ReadP.string " minor" >> return Minor
        ,                          return Major
        ]
      ReadP.eof
      return $ SongKey key tone
    in case ReadP.readP_to_S parse $ T.unpack t of
      (sk, _) : _ -> return sk
      []          -> expected "a key and optional tonality"
  }

parseJammitInstrument :: (Monad m) => ValueCodec m A.Value J.Instrument
parseJammitInstrument = enumCodec "a jammit instrument name" $ \case
  J.Guitar   -> "guitar"
  J.Bass     -> "bass"
  J.Drums    -> "drums"
  J.Keyboard -> "keys"
  J.Vocal    -> "vocal"

parseGender :: (Monad m) => ValueCodec m A.Value Magma.Gender
parseGender = enumCodec "a gender (male or female)" $ \case
  Magma.Female -> "female"
  Magma.Male   -> "male"

data AudioInfo = AudioInfo
  { _md5      :: Maybe T.Text
  , _frames   :: Maybe Integer
  , _filePath :: Maybe FilePath
  , _commands :: [T.Text]
  , _rate     :: Maybe Int
  , _channels :: Int
  } deriving (Eq, Ord, Show, Read)

data AudioFile
  = AudioFile AudioInfo
  | AudioSnippet
    { _expr :: Audio Duration AudioInput
    }
  deriving (Eq, Ord, Show, Read)

instance StackJSON AudioFile where
  stackJSON = Codec
    { codecIn = decideKey
      [ ("expr", object $ do
        _expr <- requiredKey "expr" fromJSON
        expectedKeys ["expr"]
        return AudioSnippet{..}
        )
      ] $ object $ do
        _md5      <- optionalKey "md5"       fromJSON
        _frames   <- optionalKey "frames"    fromJSON
        _filePath <- optionalKey "file-path" fromJSON
        _commands <- fromMaybe [] <$> optionalKey "commands" fromJSON
        _rate     <- optionalKey "rate"      fromJSON
        _channels <- fromMaybe 2 <$> optionalKey "channels" fromJSON
        expectedKeys ["md5", "frames", "file-path", "commands", "rate", "channels"]
        return $ AudioFile AudioInfo{..}
    , codecOut = makeOut $ \case
      AudioFile AudioInfo{..} -> A.object $ concat
        [ map ("md5"       .=) $ toList _md5
        , map ("frames"    .=) $ toList _frames
        , map ("file-path" .=) $ toList _filePath
        , ["commands" .= _commands | not $ null _commands]
        , map ("rate"      .=) $ toList _rate
        , ["channels"      .= _channels]
        ]
      AudioSnippet{..} -> A.object
        [ "expr" .= toJSON _expr
        ]
    }

data JammitTrack = JammitTrack
  { _jammitTitle  :: Maybe T.Text
  , _jammitArtist :: Maybe T.Text
  } deriving (Eq, Ord, Show, Read)

instance StackJSON JammitTrack where
  stackJSON = asStrictObject "JammitTrack" $ do
    _jammitTitle  <- _jammitTitle  =. opt Nothing "title"  stackJSON
    _jammitArtist <- _jammitArtist =. opt Nothing "artist" stackJSON
    return JammitTrack{..}

data PlanAudio t a = PlanAudio
  { _planExpr :: Audio t a
  , _planPans :: [Double]
  , _planVols :: [Double]
  } deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable)

instance (StackJSON t, StackJSON a) => StackJSON (PlanAudio t a) where
  stackJSON = Codec
    { codecIn = decideKey
      [ ("expr", object $ do
        _planExpr <- requiredKey "expr" fromJSON
        _planPans <- fromMaybe [] <$> optionalKey "pans" fromJSON
        _planVols <- fromMaybe [] <$> optionalKey "vols" fromJSON
        expectedKeys ["expr", "pans", "vols"]
        return PlanAudio{..}
        )
      ] $ (\expr -> PlanAudio expr [] []) <$> fromJSON
    , codecOut = makeOut $ \case
      PlanAudio expr [] [] -> toJSON expr
      PlanAudio{..} -> A.object $ concat
        [ ["expr" .= _planExpr]
        , ["pans" .= _planPans]
        , ["vols" .= _planVols]
        ]
    }

data PartAudio a
  = PartSingle a
  | PartDrumKit
    { drumsSplitKick  :: Maybe a
    , drumsSplitSnare :: Maybe a
    , drumsSplitKit   :: a
    }
  deriving (Eq, Ord, Show, Read, Functor, Foldable, Traversable)

instance (StackJSON a) => StackJSON (PartAudio a) where
  stackJSON = Codec
    { codecIn = decideKey
      [ ("kit", object $ do
        drumsSplitKick <- optionalKey "kick" fromJSON
        drumsSplitSnare <- optionalKey "snare" fromJSON
        drumsSplitKit <- requiredKey "kit" fromJSON
        expectedKeys ["kick", "snare", "kit"]
        return PartDrumKit{..}
        )
      ] $ PartSingle <$> fromJSON
    , codecOut = makeOut $ \case
      PartSingle x -> toJSON x
      PartDrumKit{..} -> A.object $ concat
        [ map ("kick"  .=) $ toList drumsSplitKick
        , map ("snare" .=) $ toList drumsSplitSnare
        , ["kit" .= drumsSplitKit]
        ]
    }

newtype Parts a = Parts { getParts :: Map.HashMap FlexPartName a }
  deriving (Eq, Show, Functor, Foldable, Traversable)

instance (StackJSON a) => StackJSON (Parts a) where
  stackJSON = Codec
    { codecIn = Parts . Map.fromList . map (first readPartName) . Map.toList <$> mapping fromJSON
    , codecOut = makeOut $ \(Parts hm) -> mappingToJSON $ Map.fromList $ map (first getPartName) $ Map.toList hm
    }

data Plan
  = Plan
    { _song         :: Maybe (PlanAudio Duration AudioInput)
    , _countin      :: Countin
    , _planParts    :: Parts (PartAudio (PlanAudio Duration AudioInput))
    , _crowd        :: Maybe (PlanAudio Duration AudioInput)
    , _planComments :: [T.Text]
    , _tuningCents  :: Int
    }
  | MoggPlan
    { _moggMD5      :: T.Text
    , _moggParts    :: Parts (PartAudio [Int])
    , _moggCrowd    :: [Int]
    , _pans         :: [Double]
    , _vols         :: [Double]
    , _planComments :: [T.Text]
    , _karaoke      :: Bool
    , _multitrack   :: Bool
    , _silent       :: [Int]
    , _tuningCents  :: Int
    }
  deriving (Eq, Show)

getKaraoke, getMultitrack :: Plan -> Bool
getKaraoke = \case
  Plan{..} -> Map.keys (getParts _planParts) == [FlexVocal]
  MoggPlan{..} -> _karaoke
getMultitrack = \case
  Plan{..} -> not $ Map.null $ Map.delete FlexVocal $ getParts _planParts
  MoggPlan{..} -> _multitrack

newtype Countin = Countin [(Either U.MeasureBeats U.Seconds, Audio Duration AudioInput)]
  deriving (Eq, Ord, Show)

instance StackJSON Countin where
  stackJSON = Codec
    { codecIn = do
      hm <- mapping fromJSON
      fmap Countin $ forM (Map.toList hm) $ \(k, v) -> (, v) <$> parseFrom k parseCountinTime
    , codecOut = makeOut $ \(Countin pairs) -> A.Object $ Map.fromList $ flip map pairs $ \(t, v) -> let
      k = case t of
        Left mb    -> showMeasureBeats mb
        Right secs -> T.pack $ show (realToFrac secs :: Milli)
      in (k, toJSON v)
    }

-- | Parses any of \"measure|beats\", \"seconds\", or \"minutes:seconds\".
parseCountinTime :: (SendMessage m) => StackParser m T.Text (Either U.MeasureBeats U.Seconds)
parseCountinTime = do
  t <- lift ask
  inside ("Countin timestamp " ++ show t)
    $                  fmap Left                 parseMeasureBeats
    `catchError` \_ -> fmap (Right . realToFrac) (parseFrom (A.String t) parseMinutes)
    `catchError` \_ -> parseFrom (A.String t) $ expected "a timestamp in measure|beats, seconds, or minutes:seconds"

parseMeasureBeats :: (Monad m) => StackParser m T.Text U.MeasureBeats
parseMeasureBeats = lift ask >>= \t -> let
  parser :: ReadP.ReadP U.MeasureBeats
  parser = do
    measures <- Lex.readDecP
    _ <- ReadP.char '|'
    beats <- parseDecimal ReadP.+++ parsePlusFrac
    return (measures, beats)
  parseDecimal, parsePlusFrac :: ReadP.ReadP U.Beats
  parseDecimal = Lex.lex >>= \case
    Lex.Number n -> return $ realToFrac $ Lex.numberToRational n
    _ -> ReadP.pfail
  parsePlusFrac = do
    a <- Lex.readDecP
    _ <- ReadP.char '+'
    _ <- ReadP.char '('
    b <- Lex.readDecP
    _ <- ReadP.char '/'
    c <- Lex.readDecP
    _ <- ReadP.char ')'
    return $ a + (b / c)
  in case map fst $ filter (all isSpace . snd) $ ReadP.readP_to_S parser $ T.unpack t of
    mb : _ -> return mb
    []     -> fatal "Couldn't parse as measure|beats"

showMeasureBeats :: U.MeasureBeats -> T.Text
showMeasureBeats (msr, bts) = T.pack $ show msr ++ "|" ++ show (realToFrac bts :: Scientific)

instance StackJSON Plan where
  stackJSON = Codec
    { codecIn = decideKey
      [ ("mogg-md5", object $ do
        _moggMD5 <- requiredKey "mogg-md5" fromJSON
        _moggParts <- requiredKey "parts" fromJSON
        _moggCrowd <- fromMaybe [] <$> optionalKey "crowd" fromJSON
        _pans <- requiredKey "pans" fromJSON
        _vols <- requiredKey "vols" fromJSON
        _planComments <- fromMaybe [] <$> optionalKey "comments" fromJSON
        _karaoke    <- fromMaybe False          <$> optionalKey "karaoke"    fromJSON
        _multitrack <- fromMaybe (not _karaoke) <$> optionalKey "multitrack" fromJSON
        _silent     <- fromMaybe []             <$> optionalKey "silent"     fromJSON
        _tuningCents <- fromMaybe 0 <$> optionalKey "tuning-cents" fromJSON
        expectedKeys ["mogg-md5", "parts", "crowd", "pans", "vols", "comments", "karaoke", "multitrack", "silent", "tuning-cents"]
        return MoggPlan{..}
        )
      ] $ object $ do
        _song <- optionalKey "song" fromJSON
        _countin <- fromMaybe (Countin []) <$> optionalKey "countin" fromJSON
        _planParts <- fromMaybe (Parts Map.empty) <$> optionalKey "parts" fromJSON
        _crowd <- optionalKey "crowd" fromJSON
        _planComments <- fromMaybe [] <$> optionalKey "comments" fromJSON
        _tuningCents <- fromMaybe 0 <$> optionalKey "tuning-cents" fromJSON
        expectedKeys ["song", "countin", "parts", "crowd", "comments", "tuning-cents"]
        return Plan{..}
    , codecOut = makeOut $ \case
      Plan{..} -> A.object $ concat
        [ map ("song" .=) $ toList _song
        , ["countin" .= _countin | _countin /= Countin []]
        , ["parts" .= _planParts]
        , map ("crowd" .=) $ toList _crowd
        , ["comments" .= _planComments | not $ null _planComments]
        , ["tuning-cents" .= _tuningCents | _tuningCents /= 0]
        ]
      MoggPlan{..} -> A.object $ concat
        [ ["mogg-md5" .= _moggMD5]
        , ["parts" .= _moggParts]
        , ["crowd" .= _moggCrowd | not $ null _moggCrowd]
        , ["pans" .= _pans]
        , ["vols" .= _vols]
        , ["comments" .= _planComments | not $ null _planComments]
        , ["karaoke" .= _karaoke]
        , ["multitrack" .= _multitrack]
        , ["silent" .= _silent | not $ null _silent]
        , ["tuning-cents" .= _tuningCents | _tuningCents /= 0]
        ]
    }

data AudioInput
  = Named T.Text
  | JammitSelect J.AudioPart T.Text
  deriving (Eq, Ord, Show, Read)

instance StackJSON AudioInput where
  stackJSON = Codec
    { codecIn = decideKey
      [ ("only", do
        algebraic2 "only"
          (\part str -> JammitSelect (J.Only part) str)
          (fromJSON >>= \title -> case J.titleToPart title of
            Just part -> return part
            Nothing   -> expected "a Jammit part name"
            )
          fromJSON
        )
      , ("without", do
        algebraic2 "without"
          (\inst str -> JammitSelect (J.Without inst) str)
          (codecIn parseJammitInstrument)
          fromJSON
        )
      ] (Named <$> fromJSON)
    , codecOut = makeOut $ \case
      Named t -> toJSON t
      JammitSelect (J.Only p) t -> A.object
        [ "only" .= [toJSON $ jammitPartToTitle p, toJSON t]
        ]
      JammitSelect (J.Without i) t -> A.object
        [ "without" .= [makeValue parseJammitInstrument i, toJSON t]
        ]
    }

jammitPartToTitle :: J.Part -> T.Text
jammitPartToTitle = \case
  J.PartGuitar1 -> "Guitar 1"
  J.PartGuitar2 -> "Guitar 2"
  J.PartBass1 -> "Bass 1"
  J.PartBass2 -> "Bass 2"
  J.PartDrums1 -> "Drums 1"
  J.PartDrums2 -> "Drums 2"
  J.PartKeys1 -> "Keys 1"
  J.PartKeys2 -> "Keys 2"
  J.PartPiano -> "Piano"
  J.PartSynth -> "Synth"
  J.PartOrgan -> "Organ"
  J.PartVocal -> "Vocal"
  J.PartBVocals -> "B Vocals"

instance StackJSON Edge where
  stackJSON = enumCodecFull "an audio edge (start or end)" $ \case
    Start -> is "start" |?> is "begin"
    End   -> is "end"

algebraic1 :: (Monad m) => T.Text -> (a -> b) -> StackParser m A.Value a -> StackParser m A.Value b
algebraic1 k f p1 = object $ onlyKey k $ do
  x <- lift ask
  fmap f $ inside "ADT field 1 of 1" $ parseFrom x p1

algebraic2 :: (Monad m) => T.Text -> (a -> b -> c) ->
  StackParser m A.Value a -> StackParser m A.Value b -> StackParser m A.Value c
algebraic2 k f p1 p2 = object $ onlyKey k $ lift ask >>= \case
  A.Array v -> case V.toList v of
    [x, y] -> f
      <$> do inside "ADT field 1 of 2" $ parseFrom x p1
      <*> do inside "ADT field 2 of 2" $ parseFrom y p2
    _ -> expected "an array of 2 ADT fields"
  _ -> expected "an array of 2 ADT fields"

algebraic3 :: (Monad m) => T.Text -> (a -> b -> c -> d) ->
  StackParser m A.Value a -> StackParser m A.Value b -> StackParser m A.Value c -> StackParser m A.Value d
algebraic3 k f p1 p2 p3 = object $ onlyKey k $ lift ask >>= \case
  A.Array v -> case V.toList v of
    [x, y, z] -> f
      <$> do inside "ADT field 1 of 3" $ parseFrom x p1
      <*> do inside "ADT field 2 of 3" $ parseFrom y p2
      <*> do inside "ADT field 3 of 3" $ parseFrom z p3
    _ -> expected "an array of 3 ADT fields"
  _ -> expected "an array of 3 ADT fields"

decideKey :: (Monad m) => [(T.Text, StackParser m A.Value a)] -> StackParser m A.Value a -> StackParser m A.Value a
decideKey opts dft = lift ask >>= \case
  A.Object hm -> case [ p | (k, p) <- opts, Map.member k hm ] of
    p : _ -> p
    []    -> dft
  _ -> dft

instance (StackJSON t, StackJSON a) => StackJSON (Audio t a) where
  stackJSON = Codec
    { codecIn = let
      supplyEdge s f = lift ask >>= \case
        OneKey _ (A.Array v)
          | V.length v == 2 -> algebraic2 s (f Start)  fromJSON fromJSON
          | V.length v == 3 -> algebraic3 s f fromJSON fromJSON fromJSON
        _ -> expected $ "2 or 3 fields in the " ++ show s ++ " ADT"
      in decideKey
        [ ("silence", algebraic2 "silence" Silence fromJSON fromJSON)
        , ("mix"        , object $ onlyKey "mix"         $ Mix         <$> fromJSON)
        , ("merge"      , object $ onlyKey "merge"       $ Merge       <$> fromJSON)
        , ("concatenate", object $ onlyKey "concatenate" $ Concatenate <$> fromJSON)
        , ("gain", algebraic2 "gain" Gain fromJSON fromJSON)
        , ("take", supplyEdge "take" Take)
        , ("drop", supplyEdge "drop" Drop)
        , ("trim", supplyEdge "trim" Drop)
        , ("fade", supplyEdge "fade" Fade)
        , ("pad" , supplyEdge "pad"  Pad )
        , ("resample", algebraic1 "resample" Resample fromJSON)
        , ("channels", algebraic2 "channels" Channels fromJSON fromJSON)
        , ("stretch", algebraic2 "stretch" StretchSimple fromJSON fromJSON)
        , ("stretch", algebraic3 "stretch" StretchFull fromJSON fromJSON fromJSON)
        , ("mask", algebraic3 "mask" Mask fromJSON fromJSON fromJSON)
        ] (fmap Input fromJSON `catchError` \_ -> expected "an audio expression")
    , codecOut = makeOut $ \case
      Silence chans t -> A.object ["silence" .= [toJSON chans, toJSON t]]
      Input x -> toJSON x
      Mix auds -> A.object ["mix" .= auds]
      Merge auds -> A.object ["merge" .= auds]
      Concatenate auds -> A.object ["concatenate" .= auds]
      Gain d aud -> A.object ["gain" .= [toJSON d, toJSON aud]]
      Take e t aud -> A.object ["take" .= [toJSON e, toJSON t, toJSON aud]]
      Drop e t aud -> A.object ["drop" .= [toJSON e, toJSON t, toJSON aud]]
      Fade e t aud -> A.object ["fade" .= [toJSON e, toJSON t, toJSON aud]]
      Pad e t aud -> A.object ["pad" .= [toJSON e, toJSON t, toJSON aud]]
      Resample aud -> A.object ["resample" .= aud]
      Channels ns aud -> A.object ["channels" .= [toJSON ns, toJSON aud]]
      StretchSimple d aud -> A.object ["stretch" .= [toJSON d, toJSON aud]]
      StretchFull t p aud -> A.object ["stretch" .= [toJSON t, toJSON p, toJSON aud]]
      Mask tags seams aud -> A.object ["mask" .= [toJSON tags, toJSON seams, toJSON aud]]
    }

(.=) :: (StackJSON a) => T.Text -> a -> (T.Text, A.Value)
k .= x = (k, toJSON x)

instance (StackJSON t) => StackJSON (Seam t) where
  stackJSON = Codec
    { codecIn = object $ do
      seamCenter <- requiredKey "center" (codecIn stackJSON)
      valueFade <- fromMaybe (A.Number 0) <$> optionalKey "fade" (codecIn stackJSON)
      seamFade <- parseFrom valueFade (codecIn stackJSON)
      seamTag <- requiredKey "tag" (codecIn stackJSON)
      expectedKeys ["center", "fade", "tag"]
      return Seam{..}
    , codecOut = makeOut $ \Seam{..} -> A.object
      [ "center" .= seamCenter
      , "fade" .= seamFade
      , "tag" .= seamTag
      ]
    }

parseMinutes :: (SendMessage m) => StackParser m A.Value Scientific
parseMinutes = lift ask >>= \case
  A.String minstr
    | (minutes@(_:_), ':' : secstr) <- span isDigit $ T.unpack minstr
    , Just seconds <- readMaybe secstr
    -> return $ read minutes * 60 + seconds
  A.String secstr
    | Just seconds <- readMaybe $ T.unpack secstr
    -> return seconds
  _ -> codecIn stackJSON -- will succeed if JSON number

showTimestamp :: Milli -> A.Value
showTimestamp s = let
  mins = floor $ s / 60 :: Int
  secs = s - fromIntegral mins * 60
  in case mins of
    0 -> A.toJSON s
    _ -> A.toJSON $ show mins ++ ":" ++ (if secs < 10 then "0" else "") ++ show secs

instance StackJSON Duration where
  stackJSON = Codec
    { codecIn = lift ask >>= \case
      OneKey "frames" v -> inside "frames duration" $ Frames <$> parseFrom v fromJSON
      OneKey "seconds" v -> inside "seconds duration" $ Seconds . toRealFloat <$> parseFrom v parseMinutes
      _ -> inside "unitless (seconds) duration" (Seconds . toRealFloat <$> parseMinutes)
        `catchError` \_ -> expected "a duration in frames or seconds"
    , codecOut = makeOut $ \case
      Frames f -> A.object ["frames" .= f]
      Seconds s -> showTimestamp $ realToFrac s
    }

instance StackJSON FlexPartName where
  stackJSON = Codec
    { codecIn = fmap readPartName fromJSON
    , codecOut = makeOut $ A.toJSON . getPartName
    }

data Difficulty
  = Tier Integer -- ^ [1..7]: 1 = no dots, 7 = devil dots
  | Rank Integer -- ^ [1..]
  deriving (Eq, Ord, Show, Read)

instance StackJSON Difficulty where
  stackJSON = Codec
    { codecOut = makeOut $ \case
      Tier i -> A.object ["tier" .= i]
      Rank i -> A.object ["rank" .= i]
    , codecIn = lift ask >>= \case
      OneKey "tier" (A.Number n) -> return $ Tier $ round n
      OneKey "rank" (A.Number n) -> return $ Rank $ round n
      A.Number n -> return $ Tier $ round n
      _ -> expected "a difficulty value (tier or rank)"
    }

data PartGRYBO = PartGRYBO
  { gryboDifficulty    :: Difficulty
  , gryboHopoThreshold :: Int
  , gryboFixFreeform   :: Bool
  , gryboDropOpenHOPOs :: Bool
  , gryboSustainGap    :: Int -- ticks, 480 per beat
  } deriving (Eq, Ord, Show, Read)

instance StackJSON PartGRYBO where
  stackJSON = asStrictObject "PartGRYBO" $ do
    gryboDifficulty    <- gryboDifficulty    =. fill (Tier 1) "difficulty"      stackJSON
    gryboHopoThreshold <- gryboHopoThreshold =. opt  170      "hopo-threshold"  stackJSON
    gryboFixFreeform   <- gryboFixFreeform   =. opt  True     "fix-freeform"    stackJSON
    gryboDropOpenHOPOs <- gryboDropOpenHOPOs =. opt  False    "drop-open-hopos" stackJSON
    gryboSustainGap    <- gryboSustainGap    =. opt  60       "sustain-gap"     stackJSON
    return PartGRYBO{..}

instance Default PartGRYBO where
  def = fromEmptyObject

data PartProKeys = PartProKeys
  { pkDifficulty  :: Difficulty
  , pkFixFreeform :: Bool
  } deriving (Eq, Ord, Show, Read)

instance StackJSON PartProKeys where
  stackJSON = asStrictObject "PartProKeys" $ do
    pkDifficulty  <- pkDifficulty  =. fill (Tier 1) "difficulty"   stackJSON
    pkFixFreeform <- pkFixFreeform =. opt  True     "fix-freeform" stackJSON
    return PartProKeys{..}

data PartProGuitar = PartProGuitar
  { pgDifficulty    :: Difficulty
  , pgHopoThreshold :: Int
  , pgTuning        :: GtrTuning
  , pgFixFreeform   :: Bool
  } deriving (Eq, Ord, Show, Read)

tuningBaseFormat :: (SendMessage m) => ValueCodec m A.Value GtrBase
tuningBaseFormat = Codec
  { codecIn = lift ask >>= \case
    A.Null              -> return Guitar6
    A.String "guitar-6" -> return Guitar6
    A.String "guitar-7" -> return Guitar7
    A.String "guitar-8" -> return Guitar8
    A.String "bass-4"   -> return Bass4
    A.String "bass-5"   -> return Bass5
    A.String "bass-6"   -> return Bass6
    A.Array _           -> GtrCustom <$> codecIn (listCodec stackJSON)
    _                   -> expected "a guitar/bass tuning base"
  , codecOut = makeOut $ \case
    Guitar6 -> "guitar-6"
    Guitar7 -> "guitar-7"
    Guitar8 -> "guitar-8"
    Bass4 -> "bass-4"
    Bass5 -> "bass-5"
    Bass6 -> "bass-6"
    GtrCustom ps -> A.toJSON ps
  }

tuningFormat :: (SendMessage m) => ValueCodec m A.Value GtrTuning
tuningFormat = asStrictObject "GtrTuning" $ do
  gtrBase    <- gtrBase    =. opt Guitar6 "base"    tuningBaseFormat
  gtrOffsets <- gtrOffsets =. opt []      "offsets" stackJSON
  gtrGlobal  <- gtrGlobal  =. opt 0       "global"  stackJSON
  return GtrTuning{..}

instance StackJSON PartProGuitar where
  stackJSON = asStrictObject "PartProGuitar" $ do
    pgDifficulty    <- pgDifficulty    =. fill (Tier 1) "difficulty"     stackJSON
    pgHopoThreshold <- pgHopoThreshold =. opt  170      "hopo-threshold" stackJSON
    pgTuning        <- pgTuning        =. opt  def      "tuning"         tuningFormat
    pgFixFreeform   <- pgFixFreeform   =. opt  True     "fix-freeform"   stackJSON
    return PartProGuitar{..}

data PartGHL = PartGHL
  { ghlDifficulty    :: Difficulty
  , ghlHopoThreshold :: Int
  } deriving (Eq, Ord, Show, Read)

instance StackJSON PartGHL where
  stackJSON = asStrictObject "PartGHL" $ do
    ghlDifficulty    <- ghlDifficulty    =. fill (Tier 1) "difficulty"     stackJSON
    ghlHopoThreshold <- ghlHopoThreshold =. opt  170      "hopo-threshold" stackJSON
    return PartGHL{..}

data DrumKit
  = HardRockKit
  | ArenaKit
  | VintageKit
  | TrashyKit
  | ElectronicKit
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance StackJSON DrumKit where
  stackJSON = enumCodecFull "the name of a drum kit or null" $ \case
    HardRockKit   -> is A.Null |?> fuzzy "Hard Rock Kit"
    ArenaKit      -> fuzzy "Arena Kit"
    VintageKit    -> fuzzy "Vintage Kit"
    TrashyKit     -> fuzzy "Trashy Kit"
    ElectronicKit -> fuzzy "Electronic Kit"

data DrumLayout
  = StandardLayout
  | FlipYBToms
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance StackJSON DrumLayout where
  stackJSON = enumCodecFull "the name of a drum kit layout or null" $ \case
    StandardLayout -> is A.Null |?> is "standard-layout"
    FlipYBToms     -> is "flip-yb-toms"

data DrumMode
  = Drums4
  | Drums5
  | DrumsPro
  | DrumsReal
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance StackJSON DrumMode where
  stackJSON = enumCodec "a drum mode (4, 5, pro, real)" $ \case
    Drums4    -> A.Number 4
    Drums5    -> A.Number 5
    DrumsPro  -> "pro"
    DrumsReal -> "real"

data OrangeFallback = FallbackBlue | FallbackGreen
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance StackJSON OrangeFallback where
  stackJSON = enumCodec "an orange drum note fallback color (blue, green)" $ \case
    FallbackBlue  -> "blue"
    FallbackGreen -> "green"

data Kicks = Kicks1x | Kicks2x | KicksBoth
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance StackJSON Kicks where
  stackJSON = enumCodecFull "number of bass pedals (1, 2, both)" $ \case
    Kicks1x   -> is (A.Number 1) |?> is "1" |?> is A.Null
    Kicks2x   -> is (A.Number 2) |?> is "2"
    KicksBoth -> is "both"

data PartDrums = PartDrums
  { drumsDifficulty  :: Difficulty
  , drumsMode        :: DrumMode
  , drumsKicks       :: Kicks
  , drumsFixFreeform :: Bool
  , drumsKit         :: DrumKit
  , drumsLayout      :: DrumLayout
  , drumsFallback    :: OrangeFallback
  } deriving (Eq, Ord, Show, Read)

instance StackJSON PartDrums where
  stackJSON = asStrictObject "PartDrums" $ do
    drumsDifficulty  <- drumsDifficulty  =. fill    (Tier 1)       "difficulty"   stackJSON
    drumsMode        <- drumsMode        =. opt     DrumsPro       "mode"         stackJSON
    drumsKicks       <- drumsKicks       =. warning Kicks1x        "kicks"        stackJSON
    drumsFixFreeform <- drumsFixFreeform =. opt     True           "fix-freeform" stackJSON
    drumsKit         <- drumsKit         =. opt     HardRockKit    "kit"          stackJSON
    drumsLayout      <- drumsLayout      =. opt     StandardLayout "layout"       stackJSON
    drumsFallback    <- drumsFallback    =. opt     FallbackGreen  "fallback"     stackJSON
    return PartDrums{..}

data VocalCount = Vocal1 | Vocal2 | Vocal3
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance StackJSON VocalCount where
  stackJSON = enumCodec "a vocal part count (1 to 3)" $ \case
    Vocal1 -> A.Number 1
    Vocal2 -> A.Number 2
    Vocal3 -> A.Number 3

data PartVocal = PartVocal
  { vocalDifficulty :: Difficulty
  , vocalCount      :: VocalCount
  , vocalGender     :: Maybe Magma.Gender
  , vocalKey        :: Maybe Key
  } deriving (Eq, Ord, Show, Read)

instance StackJSON PartVocal where
  stackJSON = asStrictObject "PartVocal" $ do
    vocalDifficulty <- vocalDifficulty =. fill (Tier 1) "difficulty" stackJSON
    vocalCount      <- vocalCount      =. opt  Vocal1   "count"      stackJSON
    vocalGender     <- vocalGender     =. opt  Nothing  "gender"     (maybeCodec parseGender)
    vocalKey        <- vocalKey        =. opt  Nothing  "key"        (maybeCodec parsePitch)
    return PartVocal{..}

data PartAmplitude = PartAmplitude
  { ampInstrument :: Amp.Instrument
  } deriving (Eq, Ord, Show, Read)

instance StackJSON PartAmplitude where
  stackJSON = asStrictObject "PartAmplitude" $ do
    ampInstrument <- ampInstrument =. req "instrument" stackJSON
    return PartAmplitude{..}

instance StackJSON Amp.Instrument where
  stackJSON = enumCodec "amplitude instrument type" $ \case
    Amp.Drums  -> "drums"
    Amp.Bass   -> "bass"
    Amp.Synth  -> "synth"
    Amp.Vocal  -> "vocal"
    Amp.Guitar -> "guitar"

data Part = Part
  { partGRYBO     :: Maybe PartGRYBO
  , partGHL       :: Maybe PartGHL
  , partProKeys   :: Maybe PartProKeys
  , partProGuitar :: Maybe PartProGuitar
  , partDrums     :: Maybe PartDrums
  , partVocal     :: Maybe PartVocal
  , partAmplitude :: Maybe PartAmplitude
  } deriving (Eq, Ord, Show, Read)

instance StackJSON Part where
  stackJSON = asStrictObject "Part" $ do
    partGRYBO     <- partGRYBO     =. opt Nothing "grybo"      stackJSON
    partGHL       <- partGHL       =. opt Nothing "ghl"        stackJSON
    partProKeys   <- partProKeys   =. opt Nothing "pro-keys"   stackJSON
    partProGuitar <- partProGuitar =. opt Nothing "pro-guitar" stackJSON
    partDrums     <- partDrums     =. opt Nothing "drums"      stackJSON
    partVocal     <- partVocal     =. opt Nothing "vocal"      stackJSON
    partAmplitude <- partAmplitude =. opt Nothing "amplitude"  stackJSON
    return Part{..}

instance Default Part where
  def = fromEmptyObject

instance StackJSON Magma.AutogenTheme where
  stackJSON = enumCodecFull "the name of an autogen theme or null" $ \case
    Magma.DefaultTheme -> is A.Null |?> fuzzy "Default"
    theme              -> fuzzy $ T.pack $ show theme

data Rating
  = FamilyFriendly
  | SupervisionRecommended
  | Mature
  | Unrated
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance StackJSON Rating where
  stackJSON = enumCodecFull "a valid content rating or null" $ \case
    FamilyFriendly         -> fuzzy "Family Friendly"         |?> fuzzy "FF"
    SupervisionRecommended -> fuzzy "Supervision Recommended" |?> fuzzy "SR"
    Mature                 -> fuzzy "Mature"                  |?> fuzzy "M"
    Unrated                -> fuzzy "Unrated"                 |?> fuzzy "UR"

data PreviewTime
  = PreviewSection T.Text
  | PreviewMIDI    U.MeasureBeats
  | PreviewSeconds U.Seconds
  deriving (Eq, Ord, Show, Generic)

instance Hashable PreviewTime where
  hashWithSalt s = hashWithSalt s . \case
    PreviewSection x -> '1' : show x
    PreviewMIDI    x -> '2' : show x
    PreviewSeconds x -> '3' : show x

instance StackJSON PreviewTime where
  stackJSON = Codec
    { codecIn = let
      traceNum = do
        d <- fromJSON
        return $ PreviewSeconds $ realToFrac (d :: Double)
      traceStr = do
        str <- fromJSON
        case T.stripPrefix "prc_" str of
          Just prc -> return $ PreviewSection prc
          Nothing -> let
            p = parseFrom str $ either PreviewMIDI PreviewSeconds <$> parseCountinTime
            in p `catchError` \_ -> expected "a preview time: prc_something, timestamp, or measure|beats"
      in traceNum `catchError` \_ -> traceStr
    , codecOut = makeOut $ \case
      PreviewSection str -> A.toJSON $ "prc_" <> str
      PreviewMIDI mb -> A.toJSON $ showMeasureBeats mb
      PreviewSeconds secs -> showTimestamp $ realToFrac secs
    }

-- | Extra information with no gameplay effect.
data Metadata = Metadata
  { _title        :: Maybe T.Text
  , _artist       :: Maybe T.Text
  , _album        :: Maybe T.Text
  , _genre        :: Maybe T.Text
  , _subgenre     :: Maybe T.Text
  , _year         :: Maybe Int
  , _fileAlbumArt :: Maybe FilePath
  , _trackNumber  :: Maybe Int
  , _comments     :: [T.Text]
  , _key          :: Maybe SongKey
  , _autogenTheme :: Magma.AutogenTheme
  , _animTempo    :: Either AnimTempo Integer
  , _author       :: Maybe T.Text
  , _rating       :: Rating
  , _previewStart :: Maybe PreviewTime
  , _previewEnd   :: Maybe PreviewTime
  , _languages    :: [T.Text]
  , _convert      :: Bool
  , _rhythmKeys   :: Bool
  , _rhythmBass   :: Bool
  , _catEMH       :: Bool
  , _expertOnly   :: Bool
  , _cover        :: Bool
  , _difficulty   :: Difficulty
  } deriving (Eq, Show)

parseAnimTempo :: (SendMessage m) => ValueCodec m A.Value (Either AnimTempo Integer)
parseAnimTempo = eitherCodec
  (enumCodecFull "an animation speed" $ \case
    KTempoSlow   -> is "slow" |?> is A.Null
    KTempoMedium -> is "medium"
    KTempoFast   -> is "fast"
  )
  stackJSON

instance StackJSON Metadata where
  stackJSON = asStrictObject "Metadata" $ do
    let stripped = fmap (fmap T.strip) stackJSON
    _title        <- _title        =. warning Nothing        "title"          stripped
    _artist       <- _artist       =. warning Nothing        "artist"         stripped
    _album        <- _album        =. opt     Nothing        "album"          stripped
    _genre        <- _genre        =. warning Nothing        "genre"          stripped
    _subgenre     <- _subgenre     =. opt     Nothing        "subgenre"       stripped
    _year         <- _year         =. warning Nothing        "year"           stackJSON
    _fileAlbumArt <- _fileAlbumArt =. opt     Nothing        "file-album-art" stackJSON
    _trackNumber  <- _trackNumber  =. opt     Nothing        "track-number"   stackJSON
    _comments     <- _comments     =. opt     []             "comments"       stackJSON
    _key          <- _key          =. opt     Nothing        "key"            (maybeCodec parseSongKey)
    _autogenTheme <- _autogenTheme =. opt     Magma.DefaultTheme "autogen-theme" stackJSON
    _animTempo    <- _animTempo    =. opt     (Left KTempoMedium) "anim-tempo" parseAnimTempo
    _author       <- _author       =. warning Nothing        "author"         stripped
    _rating       <- _rating       =. opt     Unrated        "rating"         stackJSON
    _previewStart <- _previewStart =. opt     Nothing        "preview-start"  stackJSON
    _previewEnd   <- _previewEnd   =. opt     Nothing        "preview-end"    stackJSON
    _languages    <- _languages    =. opt     []             "languages"      stackJSON
    _convert      <- _convert      =. opt     False          "convert"        stackJSON
    _rhythmKeys   <- _rhythmKeys   =. opt     False          "rhythm-keys"    stackJSON
    _rhythmBass   <- _rhythmBass   =. opt     False          "rhythm-bass"    stackJSON
    _catEMH       <- _catEMH       =. opt     False          "cat-emh"        stackJSON
    _expertOnly   <- _expertOnly   =. opt     False          "expert-only"    stackJSON
    _cover        <- _cover        =. opt     False          "cover"          stackJSON
    _difficulty   <- _difficulty   =. fill    (Tier 1)       "difficulty"     stackJSON
    return Metadata{..}

instance Default Metadata where
  def = fromEmptyObject

getTitle, getArtist, getAlbum, getAuthor :: Metadata -> T.Text
getTitle  m = case _title  m of Just x | not $ T.null x -> x; _ -> "Untitled"
getArtist m = case _artist m of Just x | not $ T.null x -> x; _ -> "Unknown Artist"
getAlbum  m = case _album  m of Just x | not $ T.null x -> x; _ -> "Unknown Album"
getAuthor m = case _author m of Just x | not $ T.null x -> x; _ -> "Unknown Author"

getYear, getTrackNumber :: Metadata -> Int
getYear        = fromMaybe 1960 . _year
getTrackNumber = fromMaybe 1    . _trackNumber

data TargetCommon = TargetCommon
  { tgt_Speed :: Maybe Double
  , tgt_Plan  :: Maybe T.Text
  , tgt_Title :: Maybe T.Text -- override base song title
  , tgt_Label :: Maybe T.Text -- suffix after title
  , tgt_Start :: Maybe SegmentEdge
  , tgt_End   :: Maybe SegmentEdge
  } deriving (Eq, Ord, Show, Generic, Hashable)

parseTargetCommon :: (SendMessage m) => ObjectCodec m A.Value TargetCommon
parseTargetCommon = do
  tgt_Speed <- tgt_Speed =. opt Nothing "speed" stackJSON
  tgt_Plan  <- tgt_Plan  =. opt Nothing "plan"  stackJSON
  tgt_Title <- tgt_Title =. opt Nothing "title" stackJSON
  tgt_Label <- tgt_Label =. opt Nothing "label" stackJSON
  tgt_Start <- tgt_Start =. opt Nothing "start" stackJSON
  tgt_End   <- tgt_End   =. opt Nothing "end"   stackJSON
  return TargetCommon{..}

data SegmentEdge = SegmentEdge
  { seg_FadeStart :: Maybe PreviewTime
  , seg_FadeEnd   :: Maybe PreviewTime
  , seg_Notes     :: PreviewTime
  } deriving (Eq, Ord, Show, Generic, Hashable)

parseSegmentEdge :: (SendMessage m) => ObjectCodec m A.Value SegmentEdge
parseSegmentEdge = do
  seg_FadeStart <- seg_FadeStart =. opt Nothing "fade-start" stackJSON
  seg_FadeEnd   <- seg_FadeEnd   =. opt Nothing "fade-end"   stackJSON
  seg_Notes     <- seg_Notes     =. req         "notes"      stackJSON
  return SegmentEdge{..}

instance StackJSON SegmentEdge where
  stackJSON = asStrictObject "SegmentEdge" parseSegmentEdge

data TargetRB3 = TargetRB3
  { rb3_Common      :: TargetCommon
  , rb3_2xBassPedal :: Bool
  , rb3_SongID      :: Maybe (Either Integer T.Text)
  , rb3_Version     :: Maybe Integer
  , rb3_Harmonix    :: Bool
  , rb3_FileMilo    :: Maybe FilePath
  , rb3_Guitar      :: FlexPartName
  , rb3_Bass        :: FlexPartName
  , rb3_Drums       :: FlexPartName
  , rb3_Keys        :: FlexPartName
  , rb3_Vocal       :: FlexPartName
  } deriving (Eq, Ord, Show, Generic, Hashable)

parseTargetRB3 :: (SendMessage m) => ObjectCodec m A.Value TargetRB3
parseTargetRB3 = do
  rb3_Common      <- rb3_Common      =. parseTargetCommon
  rb3_2xBassPedal <- rb3_2xBassPedal =. opt False      "2x-bass-pedal" stackJSON
  rb3_SongID      <- rb3_SongID      =. opt Nothing    "song-id"       stackJSON
  rb3_Version     <- rb3_Version     =. opt Nothing    "version"       stackJSON
  rb3_Harmonix    <- rb3_Harmonix    =. opt False      "harmonix"      stackJSON
  rb3_FileMilo    <- rb3_FileMilo    =. opt Nothing    "file-milo"     stackJSON
  rb3_Guitar      <- rb3_Guitar      =. opt FlexGuitar "guitar"        stackJSON
  rb3_Bass        <- rb3_Bass        =. opt FlexBass   "bass"          stackJSON
  rb3_Drums       <- rb3_Drums       =. opt FlexDrums  "drums"         stackJSON
  rb3_Keys        <- rb3_Keys        =. opt FlexKeys   "keys"          stackJSON
  rb3_Vocal       <- rb3_Vocal       =. opt FlexVocal  "vocal"         stackJSON
  return TargetRB3{..}

instance StackJSON TargetRB3 where
  stackJSON = asStrictObject "TargetRB3" parseTargetRB3

instance Default TargetRB3 where
  def = fromEmptyObject

data TargetRB2 = TargetRB2
  { rb2_Common      :: TargetCommon
  , rb2_2xBassPedal :: Bool
  , rb2_SongID      :: Maybe (Either Integer T.Text)
  , rb2_LabelRB2    :: Bool
  , rb2_Version     :: Maybe Integer
  , rb2_Guitar      :: FlexPartName
  , rb2_Bass        :: FlexPartName
  , rb2_Drums       :: FlexPartName
  , rb2_Vocal       :: FlexPartName
  } deriving (Eq, Ord, Show, Generic, Hashable)

parseTargetRB2 :: (SendMessage m) => ObjectCodec m A.Value TargetRB2
parseTargetRB2 = do
  rb2_Common      <- rb2_Common      =. parseTargetCommon
  rb2_2xBassPedal <- rb2_2xBassPedal =. opt False      "2x-bass-pedal" stackJSON
  rb2_SongID      <- rb2_SongID      =. opt Nothing    "song-id"       stackJSON
  rb2_LabelRB2    <- rb2_LabelRB2    =. opt False      "label-rb2"     stackJSON
  rb2_Version     <- rb2_Version     =. opt Nothing    "version"       stackJSON
  rb2_Guitar      <- rb2_Guitar      =. opt FlexGuitar "guitar"        stackJSON
  rb2_Bass        <- rb2_Bass        =. opt FlexBass   "bass"          stackJSON
  rb2_Drums       <- rb2_Drums       =. opt FlexDrums  "drums"         stackJSON
  rb2_Vocal       <- rb2_Vocal       =. opt FlexVocal  "vocal"         stackJSON
  return TargetRB2{..}

instance StackJSON TargetRB2 where
  stackJSON = asStrictObject "TargetRB2" parseTargetRB2

instance Default TargetRB2 where
  def = fromEmptyObject

data TargetPS = TargetPS
  { ps_Common     :: TargetCommon
  , ps_FileVideo  :: Maybe FilePath
  , ps_Guitar     :: FlexPartName
  , ps_Bass       :: FlexPartName
  , ps_Drums      :: FlexPartName
  , ps_Keys       :: FlexPartName
  , ps_Vocal      :: FlexPartName
  , ps_Rhythm     :: FlexPartName
  , ps_GuitarCoop :: FlexPartName
  } deriving (Eq, Ord, Show, Generic, Hashable)

parseTargetPS :: (SendMessage m) => ObjectCodec m A.Value TargetPS
parseTargetPS = do
  ps_Common     <- ps_Common     =. parseTargetCommon
  ps_FileVideo  <- ps_FileVideo  =. opt Nothing                   "file-video"  stackJSON
  ps_Guitar     <- ps_Guitar     =. opt FlexGuitar                "guitar"      stackJSON
  ps_Bass       <- ps_Bass       =. opt FlexBass                  "bass"        stackJSON
  ps_Drums      <- ps_Drums      =. opt FlexDrums                 "drums"       stackJSON
  ps_Keys       <- ps_Keys       =. opt FlexKeys                  "keys"        stackJSON
  ps_Vocal      <- ps_Vocal      =. opt FlexVocal                 "vocal"       stackJSON
  ps_Rhythm     <- ps_Rhythm     =. opt (FlexExtra "rhythm"     ) "rhythm"      stackJSON
  ps_GuitarCoop <- ps_GuitarCoop =. opt (FlexExtra "guitar-coop") "guitar-coop" stackJSON
  return TargetPS{..}

instance StackJSON TargetPS where
  stackJSON = asStrictObject "TargetPS" parseTargetPS

instance Default TargetPS where
  def = fromEmptyObject

data GH2Coop = GH2Bass | GH2Rhythm
  deriving (Eq, Ord, Show, Read, Enum, Bounded, Generic, Hashable)

instance StackJSON GH2Coop where
  stackJSON = enumCodecFull "bass or rhythm" $ \case
    GH2Bass   -> is "bass" |?> is A.Null
    GH2Rhythm -> is "rhythm"

data TargetGH2 = TargetGH2
  { gh2_Common    :: TargetCommon
  , gh2_Guitar    :: FlexPartName
  , gh2_Bass      :: FlexPartName
  , gh2_Rhythm    :: FlexPartName
  , gh2_Drums     :: FlexPartName
  , gh2_Vocal     :: FlexPartName
  , gh2_Keys      :: FlexPartName
  , gh2_Coop      :: GH2Coop
  , gh2_Quickplay :: GH2.Quickplay
  } deriving (Eq, Ord, Show, Generic, Hashable)

instance Default GH2.Quickplay where
  def = GH2.Quickplay GH2.Classic GH2.LesPaul GH2.Big -- whatever

instance StackJSON GH2.Quickplay where
  stackJSON = Codec
    { codecIn = return def
    , codecOut = makeOut $ const A.Null
    } -- TODO actual parser

parseTargetGH2 :: (SendMessage m) => ObjectCodec m A.Value TargetGH2
parseTargetGH2 = do
  gh2_Common    <- gh2_Common    =. parseTargetCommon
  gh2_Guitar    <- gh2_Guitar    =. opt FlexGuitar           "guitar"    stackJSON
  gh2_Bass      <- gh2_Bass      =. opt FlexBass             "bass"      stackJSON
  gh2_Rhythm    <- gh2_Rhythm    =. opt (FlexExtra "rhythm") "rhythm"    stackJSON
  gh2_Drums     <- gh2_Drums     =. opt FlexDrums            "drums"     stackJSON
  gh2_Keys      <- gh2_Keys      =. opt FlexKeys             "keys"      stackJSON
  gh2_Vocal     <- gh2_Vocal     =. opt FlexVocal            "vocal"     stackJSON
  gh2_Coop      <- gh2_Coop      =. opt GH2Bass              "coop"      stackJSON
  gh2_Quickplay <- gh2_Quickplay =. opt def                  "quickplay" stackJSON
  return TargetGH2{..}

instance StackJSON TargetGH2 where
  stackJSON = asStrictObject "TargetGH2" parseTargetGH2

instance Default TargetGH2 where
  def = fromEmptyObject

data Target
  = RB3 TargetRB3
  | RB2 TargetRB2
  | PS  TargetPS
  | GH2 TargetGH2
  deriving (Eq, Ord, Show, Generic, Hashable)

addKey :: (forall m. (SendMessage m) => ObjectCodec m A.Value a) -> T.Text -> A.Value -> a -> A.Value
addKey codec k v x = A.Object $ Map.insert k v $ Map.fromList $ makeObject (objectId codec) x

instance StackJSON Target where
  stackJSON = Codec
    { codecIn = object $ do
      target <- requiredKey "game" fromJSON
      hm <- lift ask
      parseFrom (A.Object $ Map.delete "game" hm) $ case target :: T.Text of
        "rb3" -> fmap RB3 fromJSON
        "rb2" -> fmap RB2 fromJSON
        "ps"  -> fmap PS  fromJSON
        "gh2" -> fmap GH2 fromJSON
        _     -> fatal $ "Unrecognized target game: " ++ show target
    , codecOut = makeOut $ \case
      RB3 rb3 -> addKey parseTargetRB3 "game" "rb3" rb3
      RB2 rb2 -> addKey parseTargetRB2 "game" "rb2" rb2
      PS  ps  -> addKey parseTargetPS  "game" "ps"  ps
      GH2 gh2 -> addKey parseTargetGH2 "game" "gh2" gh2
    }

data SongYaml = SongYaml
  { _metadata :: Metadata
  , _audio    :: Map.HashMap T.Text AudioFile
  , _jammit   :: Map.HashMap T.Text JammitTrack
  , _plans    :: Map.HashMap T.Text Plan
  , _targets  :: Map.HashMap T.Text Target
  , _parts    :: Parts Part
  } deriving (Eq, Show)

instance StackJSON SongYaml where
  stackJSON = asStrictObject "SongYaml" $ do
    _metadata <- _metadata =. opt def       "metadata" stackJSON
    _audio    <- _audio    =. opt Map.empty "audio"    (dict stackJSON)
    _jammit   <- _jammit   =. opt Map.empty "jammit"   (dict stackJSON)
    _plans    <- _plans    =. opt Map.empty "plans"    (dict stackJSON)
    _targets  <- _targets  =. opt Map.empty "targets"  (dict stackJSON)
    _parts    <- _parts    =. req           "parts"    stackJSON
    return SongYaml{..}

getPart :: FlexPartName -> SongYaml -> Maybe Part
getPart fpart = Map.lookup fpart . getParts . _parts
