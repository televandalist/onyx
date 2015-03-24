{-# LANGUAGE TemplateHaskell #-}
module Config where

import Data.Aeson.Types
import Data.Aeson.TH

import Audio
import TH
import qualified Data.HashMap.Strict as Map
import Control.Applicative ((<|>))
import Data.Monoid (mempty)
import qualified Data.Text as T

data Song = Song
  { _title :: String
  , _artist :: String
  , _album :: String
  , _genre :: String
  , _subgenre :: String
  , _year :: Int
  , _vocalGender :: Maybe Gender
  , _fileAlbumArt :: FilePath
  , _trackNumber :: Int
  , _jammitTitle :: Maybe String
  , _jammitArtist :: Maybe String
  , _audio :: Map.HashMap String (AudioConfig Double)
  , _config :: [Instrument]
  , _fileCountin :: FilePath
  } deriving (Eq, Show)

data Instrument = Drums | Bass | Guitar
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

data Gender = Male | Female
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

data AudioConfig t
  = AudioSimple (Audio t SourceFile)
  | AudioStems (Map.HashMap String (Audio t FilePath))
  deriving (Eq, Show)

data SourceFile = SourceFile
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

instance FromJSON SourceFile where
  parseJSON (String s) | s == T.pack "source" = return SourceFile
  parseJSON _                                 = mempty

$(deriveFromJSON
  defaultOptions
    { fieldLabelModifier = camelToHyphens . drop 1
    , omitNothingFields = True
    }
  ''Song
  )

$(deriveFromJSON
  defaultOptions
    { allNullaryToStringTag = True
    , constructorTagModifier = drop 1 . camelToHyphens
    }
  ''Instrument
  )

$(deriveFromJSON
  defaultOptions
    { allNullaryToStringTag = True
    , constructorTagModifier = drop 1 . camelToHyphens
    }
  ''Gender
  )

instance (FromJSON t) => FromJSON (AudioConfig t) where
  parseJSON v = fmap AudioSimple (parseJSON v) <|> fmap AudioStems (parseJSON v)
