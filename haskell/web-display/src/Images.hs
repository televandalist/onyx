{-# LANGUAGE LambdaCase      #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE JavaScriptFFI #-}
module Images where

import           Data.List           (stripPrefix)
import qualified Data.Map.Strict     as Map
import Data.JSString (JSString, pack)
import qualified JavaScript.Web.Canvas as C

import           OnyxiteDisplay.Draw (ImageID (..))

loadImage :: ImageID -> IO C.Image
loadImage iid = let
  filename = case stripPrefix "Image_" $ show iid of
    Nothing -> error $ "getImageByteString: couldn't get filename for " ++ show iid
    Just s -> "images/" ++ map (\case '_' -> '-'; c -> c) s ++ ".png"
  in js_loadImage $ pack filename

foreign import javascript interruptible
  " var i = new Image(); \
  \ i.addEventListener('load', function(){ $c(i); }); \
  \ i.src = $1; "
  js_loadImage :: JSString -> IO C.Image

imageGetter :: IO (ImageID -> C.Image)
imageGetter = do
  let iids = [minBound .. maxBound]
  imgs <- mapM loadImage iids
  let table = Map.fromList $ zip iids imgs
      getImage iid = case Map.lookup iid table of
        Nothing -> error $ "imageGetter: couldn't find image for " ++ show iid
        Just img -> img
  return getImage
