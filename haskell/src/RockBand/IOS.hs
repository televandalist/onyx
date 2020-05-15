{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TupleSections   #-}
module RockBand.IOS where

import           Control.Monad        (replicateM)
import           Crypto.Cipher.AES
import           Crypto.Cipher.Types
import           Crypto.Error
import           Data.Binary.Get
import qualified Data.ByteString      as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text            as T
import qualified Data.Text.Encoding   as TE
import           Data.Word
import           System.FilePath      (dropExtension)

data Blob = Blob
  { blobMagic         :: Word32 -- CB 8E F1 02 (but read little endian)
  , blobUnk1          :: Word32 -- 3
  , blobUnk2          :: Maybe Word32 -- 1 but only for Reloaded
  , blobUnk3          :: Word32 -- likely a song ID, unique number per song
  , blobTitle         :: T.Text
  , blobArtist        :: T.Text
  , blobDescriptionUS :: T.Text
  , blobDescriptionUK :: T.Text
  , blobDescriptionES :: T.Text
  , blobDescriptionFR :: T.Text
  , blobDescriptionIT :: T.Text
  , blobUnkFollowing  :: [Word32] -- 1 number for original, 5 for reloaded. probably includes song difficulty
  , blobDATKeys       :: [B.ByteString] -- ^ 9 16-byte AES keys
  } deriving (Show)

getBlob :: Get Blob
getBlob = do
  blobMagic <- getWord32le
  blobUnk1 <- getWord32le
  x <- getWord32le
  y <- lookAhead getWord32le
  (isReloaded, blobUnk2, blobUnk3) <- if y < 0x10000
    then (True, Just x,) <$> getWord32le -- we assume Reloaded format
    else return (False, Nothing, x) -- we assume original format
  let str = do
        len <- getWord16le
        s <- getByteString $ fromIntegral len * 2
        return $ TE.decodeUtf16LE s -- TODO handle decode errors
  blobTitle <- str
  blobArtist <- str
  blobDescriptionUS <- str
  blobDescriptionUK <- str
  blobDescriptionES <- str
  blobDescriptionFR <- str
  blobDescriptionIT <- str
  blobUnkFollowing <- replicateM (if isReloaded then 5 else 1) getWord32le
  blobDATKeys <- replicateM 9 $ getByteString 16
  return Blob{..}

decodeFileWithIV :: (MonadFail m) => B.ByteString -> B.ByteString -> m B.ByteString
decodeFileWithIV key input = do
  let (ivBytes, restBytes) = B.splitAt 16 input
  Just iv <- return $ makeIV ivBytes
  CryptoPassed cipher <- return $ cipherInit key
  return $ cbcDecrypt (cipher :: AES128) iv restBytes

decodeBlob :: FilePath -> IO B.ByteString
decodeBlob blobPath = B.readFile blobPath >>= decodeFileWithIV blobKey

blobKey :: B.ByteString
blobKey = B.pack [228, 197, 27, 48, 219, 126, 14, 32, 21, 181, 216, 46, 26, 246, 63, 110]

loadBlob :: FilePath -> IO (Blob, [(FilePath, B.ByteString)])
loadBlob blobPath = do
  let pathBase = dropExtension blobPath -- "path/to/a0" without .blob
  blob <- runGet getBlob . BL.fromStrict <$> decodeBlob blobPath -- TODO handle Get errors
  let datPaths = map (\(x, y) -> (pathBase <> x, pathBase <> y))
        [ ("_mid.dat", ".mid")
        , ("_bass_solo.dat", "_bass_solo.ogg")
        , ("_bass_trks.dat", "_bass_trks.ogg")
        , ("_drums_solo.dat", "_drums_solo.ogg")
        , ("_drums_trks.dat", "_drums_trks.ogg")
        , ("_gtr_solo.dat", "_gtr_solo.ogg")
        , ("_gtr_trks.dat", "_gtr_trks.ogg")
        , ("_vox_solo.dat", "_vox_solo.ogg")
        , ("_vox_trks.dat", "_vox_trks.ogg")
        ]
      readDat key (datPath, decPath) = do
        bs <- B.readFile datPath
        dec <- decodeFileWithIV key bs
        return (decPath, dec)
  datContents <- sequence $ zipWith readDat (blobDATKeys blob) datPaths
  return (blob, datContents)
