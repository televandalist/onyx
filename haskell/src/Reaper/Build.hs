{-# LANGUAGE LambdaCase #-}
module Reaper.Build (makeReaper, makeReaperIO) where

import           Reaper.Base

import           Control.Monad                         (forM_, unless, when,
                                                        (>=>))
import           Control.Monad.Extra                   (mapMaybeM)
import           Control.Monad.IO.Class                (MonadIO (liftIO))
import           Control.Monad.Trans.Class             (lift)
import           Control.Monad.Trans.StackTrace        (Staction, lg, stackIO)
import           Control.Monad.Trans.Writer
import qualified Data.ByteString                       as B
import qualified Data.ByteString.Base64                as B64
import qualified Data.ByteString.Char8                 as B8
import qualified Data.ByteString.Lazy                  as BL
import           Data.Char                             (toLower)
import qualified Data.EventList.Absolute.TimeBody      as ATB
import qualified Data.EventList.Relative.TimeBody      as RTB
import           Data.Functor.Identity                 (runIdentity)
import           Data.List                             (find, findIndex,
                                                        isInfixOf, isSuffixOf,
                                                        nub, sortOn)
import           Data.Maybe                            (fromMaybe, listToMaybe)
import qualified Data.Text                             as T
import qualified Data.Text.Encoding                    as TE
import           Development.Shake                     (need)
import           Numeric                               (showHex)
import qualified Numeric.NonNegative.Class             as NNC
import qualified Numeric.NonNegative.Wrapper           as NN
import           Resources                             (colorMapDrums,
                                                        colorMapGHL,
                                                        colorMapGRYBO)
import           RockBand.Codec.File                   (FlexPartName (..),
                                                        identifyFlexTrack)
import qualified RockBand.Codec.Vocal                  as Vox
import           RockBand.Common                       (Key (..), showKey)
import           Scripts                               (loadTemposIO)
import qualified Sound.File.Sndfile                    as Snd
import qualified Sound.MIDI.File                       as F
import qualified Sound.MIDI.File.Event                 as E
import qualified Sound.MIDI.File.Event.Meta            as Meta
import qualified Sound.MIDI.File.Event.SystemExclusive as SysEx
import qualified Sound.MIDI.File.Load                  as Load
import qualified Sound.MIDI.Message                    as Message
import qualified Sound.MIDI.Message.Channel            as C
import qualified Sound.MIDI.Message.Channel.Voice      as V
import qualified Sound.MIDI.Util                       as U
import           System.FilePath                       (makeRelative,
                                                        takeDirectory,
                                                        takeExtension,
                                                        takeFileName, (</>))

line :: (Monad m) => String -> [String] -> WriterT [Element] m ()
line k atoms = tell [Element k atoms Nothing]

block :: (Monad m) => String -> [String] -> WriterT [Element] m () -> WriterT [Element] m ()
block k atoms sub = do
  sublines <- lift $ execWriterT sub
  tell [Element k atoms $ Just sublines]

rpp :: (Monad m) => String -> [String] -> WriterT [Element] m () -> m Element
rpp k atoms sub = do
  sublines <- execWriterT sub
  return $ Element k atoms $ Just sublines

processTempoTrack :: (NNC.C t) => RTB.T t E.T -> RTB.T t (Meta.Tempo, Maybe (Int, Int))
processTempoTrack = go 500000 . RTB.collectCoincident where
  go tempo rtb = case RTB.viewL rtb of
    Nothing -> RTB.empty
    Just ((dt, evts), rtb') -> let
      newTempo = listToMaybe [ t          | E.MetaEvent (Meta.SetTempo t     ) <- evts ]
      newSig   = listToMaybe [ (n, 2 ^ d) | E.MetaEvent (Meta.TimeSig n d _ _) <- evts ]
      in case (newTempo, newSig) of
        (Nothing, Nothing)  -> RTB.delay dt $ go tempo rtb'
        (Just tempo', _)    -> RTB.cons dt (tempo', newSig) $ go tempo' rtb'
        (Nothing, Just sig) -> RTB.cons dt (tempo, Just sig) $ go tempo rtb'

tempoTrack :: (Monad m) =>
  ATB.T U.Seconds (Meta.Tempo, Maybe (Int, Int)) -> WriterT [Element] m ()
tempoTrack trk = block "TEMPOENVEX" [] $ do
  forM_ (ATB.toPairList trk) $ \(posn, (uspqn, tsig)) -> do
    let secs, bpm :: Double
        secs = realToFrac posn
        bpm = 60000000 / fromIntegral uspqn
    line "PT" $ [show secs, show bpm, "1"] ++ case tsig of
      Nothing           -> []
      Just (num, denom) -> [show $ num + denom * 0x10000, "0", "1"]

event :: (Monad m) => Int -> E.T -> WriterT [Element] m ()
event tks = \case
  E.MIDIEvent e -> let
    bs = Message.toByteString $ Message.Channel $ case e of
      C.Cons chan (C.Voice (V.NoteOff p _)) -> C.Cons chan $ C.Voice $ V.NoteOff p $ V.toVelocity 96
      _ -> e
    -- the above intentionally ignores the velocity of note-offs.
    -- this is done because if the `midi` package parses a note-off with
    -- a wrong velocity (outside of 0..127) it will crash upon evaluating
    -- the velocity.
    showByte n = case showHex n "" of
      [c] -> ['0', c]
      s   -> s
    in line "E" $ show tks : map showByte (BL.unpack bs)
  E.MetaEvent Meta.TimeSig{} -> return ()
  E.MetaEvent Meta.SetTempo{} -> return ()
  E.MetaEvent e -> let
    stringBytes = TE.encodeUtf8 . T.pack
    bytes = B.cons 0xFF <$> case e of
      Meta.TextEvent s -> Just $ B.cons 1 $ stringBytes s
      Meta.Copyright s -> Just $ B.cons 2 $ stringBytes s
      Meta.TrackName s -> Just $ B.cons 3 $ stringBytes s
      Meta.InstrumentName s -> Just $ B.cons 4 $ stringBytes s
      Meta.Lyric s -> Just $ B.cons 5 $ stringBytes s
      Meta.Marker s -> Just $ B.cons 6 $ stringBytes s
      Meta.CuePoint s -> Just $ B.cons 7 $ stringBytes s
      Meta.SequencerSpecific{} -> Nothing
      _ -> error $ "unhandled case in reaper event parser: " ++ show e
    splitChunks bs = if B.length bs <= 40
      then [bs]
      else case B.splitAt 40 bs of
        (x, y) -> x : splitChunks y
    in case bytes of
      Nothing -> return ()
      Just bs -> block "X" [show tks, "0"] $ forM_ (splitChunks bs) $ \chunk -> do
        line (B8.unpack $ B64.encode chunk) []
  E.SystemExclusive sysex -> let
    bytes = B.pack $ case sysex of
      SysEx.Regular bs -> 0xF0 : bs
      SysEx.Escape  _  -> error $ "unhandled case (escaped sysex) in reaper event parser: " ++ show sysex
    splitChunks bs = if B.length bs <= 40
      then [bs]
      else case B.splitAt 40 bs of
        (x, y) -> x : splitChunks y
    in block "X" [show tks, "0"] $ forM_ (splitChunks bytes) $ \chunk -> do
      line (B8.unpack $ B64.encode chunk) []

track :: (Monad m, NNC.C t, Integral t) => [(FlexPartName, [Int])] -> NN.Int -> U.Seconds -> NN.Int -> RTB.T t E.T -> WriterT [Element] m ()
track tunings lenTicks lenSecs resn trk = let
  name = fromMaybe "untitled track" $ U.trackName trk
  fpart = identifyFlexTrack name
  tuning = fromMaybe [] $ fpart >>= (`lookup` tunings)
  in block "TRACK" [] $ do
    line "NAME" [name]
    let yellow = (255, 255, 0)
        green = (0, 255, 0)
        red = (255, 0, 0)
        blue = (0, 0, 255)
        orange = (255, 128, 0)
        color = fpart >>= \case
          FlexDrums -> Just yellow
          FlexGuitar -> Just blue
          FlexBass -> Just red
          FlexVocal -> Just orange
          FlexKeys -> Just green
          _ -> Nothing
    case color of
      Nothing -> return ()
      Just (r, g, b) -> let
        encoded :: Int
        encoded = 0x1000000 + 0x10000 * b + 0x100 * g + r
        in line "PEAKCOL" [show encoded]
    line "TRACKHEIGHT" ["0", "0"]
    let (fxActive, fxPresent, fx)
          | "PART REAL_KEYS_" `isInfixOf` name
          = (False, True, mutePitches 0 47 >> mutePitches 73 127 >> pitchProKeys)
          | any (`isSuffixOf` name) ["PART VOCALS", "HARM1", "HARM2", "HARM3"]
          = (False, True, mutePitches 0 35 >> mutePitches 85 127 >> pitchVox)
          | any (`isSuffixOf` name) ["PART GUITAR", "PART BASS", "T1 GEMS"]
          = (True, True, previewGtr >> mutePitches 0 94 >> mutePitches 101 127 >> woodblock)
          | "PART KEYS" `isSuffixOf` name
          = (True, True, previewKeys >> mutePitches 0 94 >> mutePitches 101 127 >> woodblock)
          | any (`isSuffixOf` name) ["PART DRUMS", "PART DRUMS_2X", "PART REAL_DRUMS_PS"]
          = (True, True, previewDrums >> mutePitches 0 94 >> mutePitches 101 127 >> woodblock)
          | "PART REAL_GUITAR" `isInfixOf` name
          = (False, True, hearProtar False >> pitchProGtr)
          | "PART REAL_BASS" `isInfixOf` name
          = (False, True, hearProtar True >> pitchProGtr)
          | otherwise
          = (False, False, return ())
        mutePitches pmin pmax = do
          line "BYPASS" ["0", "0", "0"]
          block "JS" ["IX/MIDI_Tool II", ""] $ do
            line "0.000000" $ show (pmin :: Int) : show (pmax :: Int) : words "0.000000 0.000000 0.000000 100.000000 0.000000 0.000000 127.000000 0.000000 0.000000 1.000000 0.000000 0.000000 - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
          line "FLOATPOS" ["0", "0", "0", "0"]
          line "WAK" ["0"]
        vst label dll num enabled b64 = do
          line "BYPASS" [if enabled then "0" else "1", "0", "0"]
          block "VST" [label, dll, "0", label, show (num :: Integer)] b64
          line "FLOATPOS" ["0", "0", "0", "0"]
          line "WAK" ["0"]
        pitchProKeys = vst "VSTi: ReaSynth (Cockos)" "reasynth.vst.dylib" 1919251321 True $ do
          line "eXNlcu9e7f4AAAAAAgAAAAEAAAAAAAAAAgAAAAAAAAA8AAAAAAAAAAAAEADvvq3eDfCt3qabxDsXt9E6MzMTPwAAAAAAAAAAAACAP+lniD0AAAAAAAAAPwAAgD8AAIA/" []
          line "AACAPwAAgD8AABAAAAA=" [] -- pro keys: tuned up one octave
        pitchVox = vst "VSTi: ReaSynth (Cockos)" "reasynth.vst.dylib" 1919251321 True $ do
          line "eXNlcu9e7f4AAAAAAgAAAAEAAAAAAAAAAgAAAAAAAAA8AAAAAAAAAAAAEADvvq3eDfCt3qabxDsXt9E6MzMTPwAAAAAAAAAAAACAP+lniD0AAAAAAAAAPwAAgD8AAIA/" []
          line "AAAAPwAAgD8AABAAAAA=" [] -- vox: normal tuning
        pitchProGtr = vst "VSTi: ReaSynth (Cockos)" "reasynth.vst.dylib" 1919251321 True $ do
          line "eXNlcu9e7f4AAAAAAgAAAAEAAAAAAAAAAgAAAAAAAAA8AAAAAAAAAAAAEAA=" []
          line "776t3g3wrd6mm8Q7F7fROpzEQD8X2U4/AACAP6tyoz/O4BA8AAAAAAAAAD8MIJk+RItsPwAAAD8AAAAA" []
          line "AAAQAAAA" [] -- pro guitar pitches: normal tuning, square + decay
        woodblock = vst "VSTi: ReaSynth (Cockos)" "reasynth.vst.dylib" 1919251321 False $ do
          line "eXNlcu9e7f4AAAAAAgAAAAEAAAAAAAAAAgAAAAAAAAA8AAAAAAAAAAAAEAA=" []
          line "776t3g3wrd6mm8Q7F7fROgAAAAAAAAAAAAAAAFmzJj8BTB06AAAAAAAAAD8AAAAAAACAPwAAAAAAAAAA" []
          line "AAAQAAAA" []
        previewGtr = vst "VSTi: RBN Preview (RBN)" "rbprev_vst.dll" 1919053942 True $ do
          line "dnBicu5e7f4AAAAAAgAAAAEAAAAAAAAAAgAAAAAAAAAEAAAAAQAAAAAAEAA=" []
          line "AwCqAA==" []
          line "AAAQAAAA" []
        previewKeys = vst "VSTi: RBN Preview (RBN)" "rbprev_vst.dll" 1919053942 True $ do
          line "dnBicu5e7f4AAAAAAgAAAAEAAAAAAAAAAgAAAAAAAAAEAAAAAQAAAAAAEAA=" []
          line "AwOqAA==" []
          line "AAAQAAAA" []
        previewDrums = vst "VSTi: RBN Preview (RBN)" "rbprev_vst.dll" 1919053942 True $ do
          line "dnBicu5e7f4AAAAAAgAAAAEAAAAAAAAAAgAAAAAAAAAEAAAAAQAAAAAAEAA=" []
          line "AwGqAA==" []
          line "AAAQAAAA" []
        hearProtar isBass = do
          line "BYPASS" ["0", "0", "0"]
          block "JS" ["C3/progtr", ""] $ do
            let bool b = if b then "1" else "0"
                tuning' = reverse $ take 6 $ tuning ++ repeat (0 :: Int)
                expert = 3 :: Int
                outChannel = 0 :: Int
                passthroughNonNotes = True
            line (bool isBass)
              $ [show expert]
              ++ map show tuning'
              ++ [show outChannel, bool passthroughNonNotes]
              ++ words "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
          line "FLOATPOS" ["0", "0", "0", "0"]
          line "WAK" ["0"]
    line "FX" [if fxActive then "1" else "0"]
    case find (\(sfx, _) -> sfx `isSuffixOf` name)
      [ ("PART DRUMS", drumNoteNames)
      , ("PART DRUMS_2X", drumNoteNames)
      , ("PART REAL_DRUMS_PS", drumNoteNames)
      , ("PART GUITAR", gryboNoteNames False)
      , ("PART BASS", gryboNoteNames False)
      , ("T1 GEMS", gryboNoteNames False)
      , ("PART RHYTHM", gryboNoteNames False)
      , ("PART GUITAR COOP", gryboNoteNames False)
      , ("PART KEYS", gryboNoteNames True)
      , ("PART GUITAR GHL", ghlNoteNames)
      , ("PART BASS GHL", ghlNoteNames)
      , ("PART REAL_KEYS_X", proKeysNoteNames)
      , ("PART REAL_KEYS_H", proKeysNoteNames)
      , ("PART REAL_KEYS_M", proKeysNoteNames)
      , ("PART REAL_KEYS_E", proKeysNoteNames)
      , ("BEAT", [(13, "Up Beats"), (12, "Downbeat")])
      , ("PART VOCALS", vocalNoteNames)
      , ("HARM1", vocalNoteNames)
      , ("HARM2", vocalNoteNames)
      , ("HARM3", vocalNoteNames)
      , ("PART REAL_GUITAR", proGuitarNoteNames)
      , ("PART REAL_GUITAR_22", proGuitarNoteNames)
      , ("PART REAL_BASS", proGuitarNoteNames)
      , ("PART REAL_BASS_22", proGuitarNoteNames)
      , ("MELODY'S ESCAPE", melodyNoteNames)
      , ("LIGHTING", venuegenLightingNames)
      , ("CAMERA", venuegenCameraNames)
      ] of
      Nothing -> return ()
      Just (_, names) -> do
        block "MIDINOTENAMES" [] $ do
          -- Reaper 5 (or some newer version) supports starting these lines with -1, meaning all channels.
          -- Reaper 4.22 (C3 recommended) does not, so we have to stick with 0 (first channel).
          forM_ names $ \(pitch, noteName) -> line "0" [show pitch, noteName]
    -- note: even if no FX, you still need empty FXCHAIN so note names work
    block "FXCHAIN" [] $ when fxPresent $ do
      line "SHOW" ["0"]
      line "LASTSEL" ["0"]
      line "DOCKED" ["0"]
      fx
    block "ITEM" [] $ do
      line "POSITION" ["0"]
      line "LOOP" ["0"]
      line "LENGTH" [show (realToFrac lenSecs :: Double)]
      line "NAME" [name]
      block "SOURCE" ["MIDI"] $ do
        line "HASDATA" ["1", show resn, "QN"]
        forM_ (RTB.toPairList trk) $ \(tks, e) -> event (fromIntegral tks) e
        let lastEvent = case reverse $ ATB.getTimes $ RTB.toAbsoluteEventList 0 trk of
              t : _ -> fromIntegral t
              []    -> 0
        line "E" [show $ lenTicks NNC.-| lastEvent, "b0", "7b", "00"]
        case find (\(sfx, _) -> sfx `isSuffixOf` name)
          [ ("PART DRUMS", "colormap_drums.png")
          , ("PART DRUMS_2X", "colormap_drums.png")
          , ("PART REAL_DRUMS_PS", "colormap_drums.png")
          , ("PART GUITAR", "colormap_grybo.png")
          , ("PART BASS", "colormap_grybo.png")
          , ("PART RHYTHM", "colormap_grybo.png")
          , ("PART GUITAR COOP", "colormap_grybo.png")
          , ("PART KEYS", "colormap_grybo.png")
          , ("PART GUITAR GHL", "colormap_ghl.png")
          , ("PART BASS GHL", "colormap_ghl.png")
          ] of
          Nothing        -> return ()
          Just (_, cmap) -> line "COLORMAP" [cmap]

audio :: (Monad m) => U.Seconds -> FilePath -> WriterT [Element] m ()
audio len path = let
  name = takeFileName path
  in block "TRACK" [] $ do
    line "NAME" [name]
    -- reapitch up 1 octave (disabled)
    line "FX" ["0"]
    block "FXCHAIN" [] $ do
      line "SHOW" ["0"]
      line "LASTSEL" ["0"]
      line "DOCKED" ["0"]
      line "BYPASS" ["0", "0", "0"]
      block "VST" ["VST: ReaPitch (Cockos)", "reapitch.vst.dylib", "0", "VST: ReaPitch (Cockos)", "1919250531"] $ do
        line "Y3Blcu5e7f4CAAAAAQAAAAAAAAACAAAAAAAAAAIAAAABAAAAAAAAAAIAAAAAAAAATAAAAAEAAAAAABAA" []
        line "AAAAAP////8BAAAALAAAAAIAAAAAAAAAAACAPwAAAAAAAAAAAACAPwAAAD8AAAA/AAAAPwAAQD8AAAA/AAAAPwAAAD8AAIA/AAAAPw==" []
        line "AAAQAAAA" []
      line "FLOATPOS" ["0", "0", "0", "0"]
      line "WAK" ["0"]
    block "ITEM" [] $ do
      line "POSITION" ["0"]
      line "LOOP" ["0"]
      line "LENGTH" [show (realToFrac len :: Double)]
      line "NAME" [name]
      let fmt = case map toLower $ takeExtension path of
            ".wav" -> "WAVE"
            ".mp3" -> "MP3"
            ".ogg" -> "VORBIS"
            ".flac" -> "FLAC"
            _ -> error $ "While generating a Reaper project: I don't know the audio format of this file: " ++ show path
      block "SOURCE" [fmt] $ do
        line "FILE" [path]

drumNoteNames :: [(Int, String)]
drumNoteNames = execWriter $ do
  o 127 "Roll Marker 2-Lane"
  o 126 "Roll Marker 1-Lane"
  x 125
  o 124 "DRUM FILL"
  o 123 "DRUM FILL"
  o 122 "DRUM FILL"
  o 121 "DRUM FILL"
  o 120 "DRUM FILL (use all 5)"
  x 118
  o 116 "OVERDRIVE"
  x 114
  o 112 "PRO Green Tom"
  o 111 "PRO Blue Tom"
  o 110 "PRO Yellow Tom"
  x 108
  o 103 "Solo Marker"
  x 102
  o 100 "EXPERT Green"
  o 99 "EXPERT Blue"
  o 98 "EXPERT Yellow"
  o 97 "EXPERT Red"
  o 96 "EXPERT Kick"
  o 95 "PS Left Kick"
  x 92
  o 88 "HARD Green"
  o 87 "HARD Blue"
  o 86 "HARD Yellow"
  o 85 "HARD Red"
  o 84 "HARD Kick"
  x 80
  o 76 "MEDIUM Green"
  o 75 "MEDIUM Blue"
  o 74 "MEDIUM Yellow"
  o 73 "MEDIUM Red"
  o 72 "MEDIUM Kick"
  x 68
  o 64 "EASY Green"
  o 63 "EASY Blue"
  o 62 "EASY Yellow"
  o 61 "EASY Red"
  o 60 "EASY Kick"
  x 56
  o 52 "--DRUM ANIMATION--"
  o 51 "FLOOR TOM RH"
  o 50 "FLOOR TOM LH"
  o 49 "TOM2 RH"
  o 48 "TOM2 LH"
  o 47 "TOM1 RH"
  o 46 "TOM1 LH"
  o 45 "CRASH2 SOFT LH"
  o 44 "CRASH2 HARD LH"
  o 43 "RIDE CYM LH"
  o 42 "RIDE CYM RH"
  o 41 "CRASH1 CHOKE" -- docs incorrectly say CRASH2 CHOKE
  o 40 "CRASH2 CHOKE" -- docs incorrectly say CRASH1 CHOKE
  o 39 "CRASH2 SOFT RH"
  o 38 "CRASH2 HARD RH"
  o 37 "CRASH1 SOFT RH"
  o 36 "CRASH1 HARD RH"
  o 35 "CRASH1 SOFT LH"
  o 34 "CRASH1 HARD LH"
  -- 33 unused
  o 32 "PERCUSSION RH"
  o 31 "HI-HAT RH"
  o 30 "HI-HAT LH"
  o 29 "SNARE SOFT RH"
  o 28 "SNARE SOFT LH"
  o 27 "SNARE HARD RH"
  o 26 "SNARE HARD LH"
  o 25 "HI-HAT OPEN"
  o 24 "KICK RF"
  where o k v = tell [(k, v)]
        x k = tell [(k, "----")]

gryboNoteNames :: Bool -> [(Int, String)]
gryboNoteNames isKeys = execWriter $ do
  o 127 "Trill Marker"
  unless isKeys $ o 126 "Tremolo Marker"
  x 125
  o 124 "BRE"
  o 123 "BRE"
  o 122 "BRE"
  o 121 "BRE"
  o 120 "BRE (use all 5)"
  x 118
  o 116 "OVERDRIVE"
  x 115
  o 103 "Solo Marker"
  o 102 $ if isKeys then "(Keytar) HOPO Off" else "Force HOPO Off"
  o 101 $ if isKeys then "(Keytar) HOPO On"  else "Force HOPO On"
  o 100 "EXPERT Orange"
  o 99 "EXPERT Blue"
  o 98 "EXPERT Yellow"
  o 97 "EXPERT Red"
  o 96 "EXPERT Green"
  x 95
  o 90 $ if isKeys then "(Keytar) HOPO Off" else "Force HOPO Off"
  o 89 $ if isKeys then "(Keytar) HOPO On"  else "Force HOPO On"
  o 88 "HARD Orange"
  o 87 "HARD Blue"
  o 86 "HARD Yellow"
  o 85 "HARD Red"
  o 84 "HARD Green"
  x 77
  o 76 "MEDIUM Orange"
  o 75 "MEDIUM Blue"
  o 74 "MEDIUM Yellow"
  o 73 "MEDIUM Red"
  o 72 "MEDIUM Green"
  x 65
  o 64 "EASY Orange"
  o 63 "EASY Blue"
  o 62 "EASY Yellow"
  o 61 "EASY Red"
  o 60 "EASY Green"
  unless isKeys $ do
    o 59 "Left Hand Highest"
    forM_ [58, 57 .. 41] $ \i -> o i "-"
    o 40 "Left Hand Lowest"
  where o k v = tell [(k, v)]
        x k = tell [(k, "----")]

proKeysNoteNames :: [(Int, String)]
proKeysNoteNames = execWriter $ do
  o 127 "Trill Marker"
  o 126 "Glissando Marker"
  x 125
  o 120 "BRE"
  x 118
  o 116 "OVERDRIVE"
  o 115 "Solo Marker"
  x 114
  o 72 "C3 (highest)"
  o 71 "B2"
  o 70 "A#2"
  o 69 "A2"
  o 68 "G#2"
  o 67 "G2"
  o 66 "F#2"
  o 65 "F2"
  o 64 "E2"
  o 63 "D#2"
  o 62 "D2"
  o 61 "C#2"
  o 60 "C2"
  o 59 "B1"
  o 58 "A#1"
  o 57 "A1"
  o 56 "G#1"
  o 55 "G1"
  o 54 "F#1"
  o 53 "F1"
  o 52 "E1"
  o 51 "D#1"
  o 50 "D1"
  o 49 "C#1"
  o 48 "C1 (lowest)"
  x 12
  o 9 "Range A1 to C3"
  o 7 "Range G1 to B2"
  o 5 "Range F1 to A2"
  o 4 "Range E1 to G2"
  o 2 "Range D1 to F2"
  o 0 "Range C1 to E2"
  where o k v = tell [(k, v)]
        x k = tell [(k, "----")]

vocalNoteNames :: [(Int, String)]
vocalNoteNames = execWriter $ do
  o 116 "OVERDRIVE"
  o 106 "Phrase (Face-Off P2)"
  o 105 "Phrase"
  x 104
  o 97 "Percussion Sound"
  o 96 "Percussion"
  x 85
  forM_ [maxBound, pred maxBound .. minBound] $ \voxpitch -> do
    let midpitch = fromEnum voxpitch + 36
        str = case voxpitch of
          Vox.Octave36 C -> "C (lowest)"
          Vox.Octave36 p -> showKey False p
          Vox.Octave48 p -> showKey False p
          Vox.Octave60 p -> showKey False p
          Vox.Octave72 p -> showKey False p
          Vox.Octave84C  -> "C (highest) (bugged)"
    o midpitch str
  x 35
  o 1 "Lyric Shift"
  o 0 "Range Shift"
  where o k v = tell [(k, v)]
        x k = tell [(k, "----")]

ghlNoteNames :: [(Int, String)]
ghlNoteNames = execWriter $ do
  o 116 "OVERDRIVE"
  x 115
  o 103 "Solo Marker"
  o 102 "Force HOPO Off"
  o 101 "Force HOPO On"
  o 100 "EXPERT Black 3"
  o 99 "EXPERT Black 2"
  o 98 "EXPERT Black 1"
  o 97 "EXPERT White 3"
  o 96 "EXPERT White 2"
  o 95 "EXPERT White 1"
  o 94 "EXPERT Open Note"
  x 93
  o 90 "Force HOPO Off"
  o 89 "Force HOPO On"
  o 88 "HARD Black 3"
  o 87 "HARD Black 2"
  o 86 "HARD Black 1"
  o 85 "HARD White 3"
  o 84 "HARD White 2"
  o 83 "HARD White 1"
  o 82 "HARD Open Note"
  x 81
  o 78 "Force HOPO Off"
  o 77 "Force HOPO On"
  o 76 "MEDIUM Black 3"
  o 75 "MEDIUM Black 2"
  o 74 "MEDIUM Black 1"
  o 73 "MEDIUM White 3"
  o 72 "MEDIUM White 2"
  o 71 "MEDIUM White 1"
  o 70 "MEDIUM Open Note"
  x 69
  o 66 "Force HOPO Off"
  o 65 "Force HOPO On"
  o 64 "EASY Black 3"
  o 63 "EASY Black 2"
  o 62 "EASY Black 1"
  o 61 "EASY White 3"
  o 60 "EASY White 2"
  o 59 "EASY White 1"
  o 58 "EASY Open Note"
  where o k v = tell [(k, v)]
        x k = tell [(k, "----")]

proGuitarNoteNames :: [(Int, String)]
proGuitarNoteNames = execWriter $ do
  o 127 "Trill"
  o 126 "Tremolo" -- not visible in game? see Roundabout
  o 125 "BRE"
  o 124 "BRE"
  o 123 "BRE"
  o 122 "BRE"
  o 121 "BRE"
  o 120 "BRE (use all 6)"
  o 116 "OVERDRIVE"
  o 115 "Solo Marker"
  o 108 "Left Hand Position"
  o 107 "EXPERT Show All Numbers"
  -- 106 was marked as ??? in my original file, is it a used pitch?
  o 105 "EXPERT Strum Direction"
  o 104 "EXPERT Arpeggio Marker"
  o 103 "EXPERT Slide Marker"
  o 102 "EXPERT Force HOPO"
  o 101 "EXPERT E String (HIGH)"
  o 100 "EXPERT B String"
  o 99 "EXPERT G String"
  o 98 "EXPERT D String"
  o 97 "EXPERT A String"
  o 96 "EXPERT E String (LOW)"
  x 95
  o 94 "(Note channels:)"
  o 93 "(1 Normal)"
  o 92 "(2 Arpeggio phantom)"
  o 91 "(3 String bend)"
  o 90 "(4 Muted)"
  o 89 "(5 Tapped)"
  o 88 "(6 Harmonic)"
  o 87 "(7 Pinch harmonic)"
  x 86
  o 83 "HARD Show All Numbers"
  o 81 "HARD Strum Direction"
  o 80 "HARD Arpeggio Marker"
  o 79 "HARD Slide Marker"
  o 78 "HARD Force HOPO"
  o 77 "HARD E String (HIGH)"
  o 76 "HARD B String"
  o 75 "HARD G String"
  o 74 "HARD D String"
  o 73 "HARD A String"
  o 72 "HARD E String (LOW)"
  x 71
  o 56 "MEDIUM Arpeggio Marker"
  o 55 "MEDIUM Slide Marker"
  o 53 "MEDIUM E String (HIGH)"
  o 52 "MEDIUM B String"
  o 51 "MEDIUM G String"
  o 50 "MEDIUM D String"
  o 49 "MEDIUM A String"
  o 48 "MEDIUM E String (LOW)"
  x 47
  o 32 "EASY Arpeggio Marker"
  o 31 "EASY Slide Marker"
  o 29 "EASY E String (HIGH)"
  o 28 "EASY B String"
  o 27 "EASY G String"
  o 26 "EASY D String"
  o 25 "EASY A String"
  o 24 "EASY E String (LOW)"
  x 23
  o 21 "CHORD NAMES:"
  o 18 "Flat Note Name"
  o 17 "Hide Chord Names"
  o 16 "Slash Chord"
  o 15 "Chord Root D#"
  o 14 "Chord Root D"
  o 13 "Chord Root C#"
  o 12 "Chord Root C"
  o 11 "Chord Root B"
  o 10 "Chord Root A#"
  o 9  "Chord Root A"
  o 8  "Chord Root G#"
  o 7  "Chord Root G"
  o 6  "Chord Root F#"
  o 5  "Chord Root F"
  o 4  "Chord Root E"
  where o k v = tell [(k, v)]
        x k = tell [(k, "----")]

venuegenLightingNames :: [(Int, String)]
venuegenLightingNames = execWriter $ do
  o 71 "Default"
  o 70 "Color_Muted"
  o 69 "Video_Grainy"
  o 68 "16mm Film"
  o 67 "Shitty_TV"
  o 66 "Bloom"
  o 65 "Sepia_Ink"
  o 64 "Silvertone"
  o 63 "Film_BW"
  o 62 "Video_BW"
  o 61 "Contrast BW"
  o 60 "Photocopy"
  o 59 "Blue_Filter"
  o 58 "Desat_Blue"
  o 57 "Video_Security"
  o 55 "Bright"
  o 54 "Posterize"
  o 53 "Clean_Trails"
  o 52 "Video_Trails"
  o 51 "Flicker_Trails"
  o 50 "Desat_Posterize"
  o 49 "Film_Contrast"
  o 48 "Film_Contrast_Blue"
  o 47 "Film_Contrast_Green"
  o 46 "Film_Contrast_Red"
  o 45 "Horror_Movie"
  o 44 "Photo_Negative"
  o 43 "Mirror"
  o 42 "Psych_Blue_Red"
  o 41 "Space_Woosh"
  o 39 "Verse"
  o 38 "Chorus"
  o 37 "Manual_Cool"
  o 36 "Manual_Warm"
  o 35 "Dischord"
  o 34 "Stomp"
  o 32 "first"
  o 31 "prev"
  o 30 "next"
  o 28 "Loop_Cool"
  o 27 "Loop_Warm"
  o 26 "Harmony"
  o 25 "Frenzy"
  o 24 "Silhouettes"
  o 23 "Silhouettes_Spot"
  o 22 "Searchlights"
  o 21 "Sweep"
  o 20 "Strobe_Slow"
  o 19 "Strobe_Fast"
  o 18 "Blackout_Slow"
  o 17 "Blackout_Fast"
  o 16 "Blackout_Spot"
  o 15 "Flare_Slow"
  o 14 "Flare_Fast"
  o 13 "BRE"
  o 11 "BONUSFX"
  o 10 "BONUSFX_Opt"
  where o k v = tell [(k, v)]

venuegenCameraNames :: [(Int, String)]
venuegenCameraNames = execWriter $ do
  o 102 "RANDOM"
  o 100 "All_Behind"
  o 99  "All_Far"
  o 98  "All_Near"
  o 96  "Front_Behind"
  o 95  "Front_Near"
  o 93  "D_Behind"
  o 92  "D_Near"
  o 91  "V_Behind"
  o 90  "V_Near"
  o 89  "B_Behind"
  o 88  "B_Near"
  o 87  "G_Behind"
  o 86  "G_Near"
  o 85  "K_Behind"
  o 84  "K_Near"
  o 82  "D_Hand"
  o 81  "D_Head"
  o 80  "V_Closeup"
  o 79  "B_Hand"
  o 78  "B_Head"
  o 77  "G_Hand"
  o 76  "G_Head"
  o 75  "K_Hand"
  o 74  "K_Head"
  o 72  "DV_Near"
  o 71  "BD_Near"
  o 70  "DG_Near"
  o 69  "BV_Behind"
  o 68  "BV_Near"
  o 67  "GV_Behind"
  o 66  "GV_Near"
  o 65  "KV_Behind"
  o 64  "KV_Near"
  o 63  "BG_Behind"
  o 62  "BG_Near"
  o 61  "BK_Behind"
  o 60  "BK_Near"
  o 59  "GK_Behind"
  o 58  "GK_Near"
  o 56  "D_All"
  o 55  "D_All_Cam"
  o 54  "D_All_LT*"
  o 53  "D_All_Yeah"
  o 52  "D_BRE"
  o 51  "D_BRE_Jump"
  o 49  "D_Drums_NP"
  o 48  "D_Bass_NP"
  o 47  "D_Gtr_NP"
  o 46  "D_Vox_NP"
  o 45  "D_Keys_NP"
  o 43  "D_Drums"
  o 42  "D_Drums_LT*"
  o 41  "D_Vocals"
  o 40  "D_Bass"
  o 39  "D_Gtr"
  o 38  "D_Keys"
  o 36  "D_Vox_Cam_PR"
  o 35  "D_Vox_Cam_PT"
  o 34  "D_Gtr_Cam_PR"
  o 33  "D_Gtr_Cam_PT"
  o 32  "D_Keys_Cam"
  o 31  "D_Bass_Cam"
  o 29  "D_Stagedive"
  o 28  "D_Crowdsurf"
  o 26  "D_Vox_CLS"
  o 25  "D_Bass_CLS*"
  o 24  "D_Gtr_CLS*"
  o 23  "D_Drums_KD*"
  o 21  "D_Drums_Point"
  o 20  "D_Crowd_Gtr"
  o 19  "D_Crowd_Bass"
  o 17  "D_Duo_Drums"
  o 16  "D_Duo_Gtr"
  o 15  "D_Duo_Bass"
  o 14  "D_Duo_KV"
  o 13  "D_Duo_GB"
  o 12  "D_Duo_KB"
  o 11  "D_Duo_KG"
  o 10  "D_Crowd*"
  where o k v = tell [(k, v)]

melodyNoteNames :: [(Int, String)]
melodyNoteNames = execWriter $ do
  o 87 "Intensity FLYING"
  o 86 "Intensity RUNNING"
  o 85 "Intensity JOGGING"
  o 84 "Intensity WALKING"
  x 83
  o 75 "Color UP"
  o 74 "Color RIGHT"
  o 73 "Color LEFT"
  o 72 "Color DOWN"
  x 71
  o 64 "Obstacle UP CUTSCENE"
  o 63 "Obstacle UP"
  o 62 "Obstacle RIGHT"
  o 61 "Obstacle LEFT"
  o 60 "Obstacle DOWN"
  where o k v = tell [(k, v)]
        x k = tell [(k, "----")]

sortTracks :: (NNC.C t) => [RTB.T t E.T] -> [RTB.T t E.T]
sortTracks = sortOn $ U.trackName >=> \name -> findIndex (`isSuffixOf` name)
  [ "PART DRUMS"
  , "PART DRUMS_2X"
  , "PART REAL_DRUMS_PS"
  , "PART BASS"
  , "PART REAL_BASS"
  , "PART REAL_BASS_22"
  , "PART GUITAR"
  , "PART REAL_GUITAR"
  , "PART REAL_GUITAR_22"
  , "PART VOCALS"
  , "HARM1"
  , "HARM2"
  , "HARM3"
  , "PART KEYS"
  , "PART REAL_KEYS_X"
  , "PART REAL_KEYS_H"
  , "PART REAL_KEYS_M"
  , "PART REAL_KEYS_E"
  , "PART KEYS_ANIM_RH"
  , "PART KEYS_ANIM_LH"
  , "EVENTS"
  , "VENUE"
  , "LIGHTING"
  , "CAMERA"
  , "BEAT"
  ]

makeReaperIO :: (MonadIO m) => [(FlexPartName, [Int])] -> FilePath -> FilePath -> [FilePath] -> FilePath -> m ()
makeReaperIO tunings evts tempo audios out = liftIO $ do
  lenAudios <- flip mapMaybeM audios $ \aud -> do
    info <- Snd.getFileInfo aud
    return $ case Snd.frames info of
      0 -> Nothing
      f -> Just (fromIntegral f / fromIntegral (Snd.samplerate info), aud)
  mid <- Load.fromFile evts
  tmap <- loadTemposIO tempo
  tempoMid <- Load.fromFile tempo
  let getLastTime :: (NNC.C t, Num t) => [RTB.T t a] -> t
      getLastTime = foldr max NNC.zero . map getTrackLastTime
      getTrackLastTime trk = case reverse $ ATB.getTimes $ RTB.toAbsoluteEventList NNC.zero trk of
        []    -> NNC.zero
        t : _ -> t
      lastEventSecs = case U.decodeFile mid of
        Left beatTracks -> U.applyTempoMap tmap $ getLastTime beatTracks
        Right secTracks -> getLastTime secTracks
      midiLenSecs = 5 + foldr max lastEventSecs (map fst lenAudios)
      midiLenTicks resn = floor $ U.unapplyTempoMap tmap midiLenSecs * fromIntegral resn
      writeTempoTrack = case tempoMid of
        F.Cons F.Parallel (F.Ticks resn) (theTempoTrack : _) -> let
          t_ticks = processTempoTrack theTempoTrack
          t_beats = RTB.mapTime (\tks -> fromIntegral tks / fromIntegral resn) t_ticks
          t_secs = U.applyTempoTrack tmap t_beats
          in tempoTrack $ RTB.toAbsoluteEventList 0 t_secs
        F.Cons F.Mixed (F.Ticks resn) tracks -> let
          merged = foldr RTB.merge RTB.empty tracks
          t_ticks = processTempoTrack merged
          t_beats = RTB.mapTime (\tks -> fromIntegral tks / fromIntegral resn) t_ticks
          t_secs = U.applyTempoTrack tmap t_beats
          in tempoTrack $ RTB.toAbsoluteEventList 0 t_secs
        _ -> error "Unsupported MIDI format for Reaper project generation"
  let project = runIdentity $
        rpp "REAPER_PROJECT" ["0.1", "5.0/OSX64", "1449358215"] $ do
          line "VZOOMEX" ["0"]
          line "SAMPLERATE" ["44100", "0", "0"]
          block "METRONOME" ["6", "2"] $ return () -- disables metronome
          writeTempoTrack
          case mid of
            F.Cons F.Parallel (F.Ticks resn) (_ : trks) -> do
              forM_ (sortTracks trks) $ track tunings (midiLenTicks resn) midiLenSecs resn
            F.Cons F.Mixed (F.Ticks resn) tracks -> let
              merged = foldr RTB.merge RTB.empty tracks
              in track tunings (midiLenTicks resn) midiLenSecs resn merged
            _ -> error "Unsupported MIDI format for Reaper project generation"
          forM_ lenAudios $ \(len, aud) -> do
            audio len $ makeRelative (takeDirectory out) aud
      findColorMaps = \case
        Element "COLORMAP" [cmap] _ -> [cmap]
        Element _ _ Nothing -> []
        Element _ _ (Just sub) -> concatMap findColorMaps sub
  writeRPP out project
  forM_ (nub $ findColorMaps project) $ \cmap -> case cmap of
    "colormap_drums.png" -> B.writeFile (takeDirectory out </> cmap) colorMapDrums
    "colormap_grybo.png" -> B.writeFile (takeDirectory out </> cmap) colorMapGRYBO
    "colormap_ghl.png"   -> B.writeFile (takeDirectory out </> cmap) colorMapGHL
    _ -> return ()

makeReaper :: [(FlexPartName, [Int])] -> FilePath -> FilePath -> [FilePath] -> FilePath -> Staction ()
makeReaper tunings evts tempo audios out = do
  lift $ lift $ need $ evts : tempo : audios
  lg $ "Generating a REAPER project at " ++ out
  stackIO $ makeReaperIO tunings evts tempo audios out
