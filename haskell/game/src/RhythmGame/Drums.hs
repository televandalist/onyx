{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}
module RhythmGame.Drums where

import           Codec.Picture
import           Control.Concurrent        (threadDelay)
import           Control.Exception         (bracket, bracket_)
import           Control.Monad             (forM_, when)
import           Control.Monad.IO.Class    (MonadIO (..))
import           Control.Monad.Trans.State
import qualified Data.ByteString           as B
import           Data.FileEmbed            (embedFile, makeRelativeToProject)
import           Data.Foldable             (toList)
import           Data.List                 (partition)
import qualified Data.Map.Strict           as Map
import           Data.Map.Strict.Internal  (Map (..))
import           Data.Maybe                (fromMaybe)
import qualified Data.Text                 as T
import qualified Data.Vector.Storable      as VS
import           Foreign
import           Foreign.C
import           GHC.ByteOrder
import           Graphics.GL.Core33
import           Graphics.GL.Types
import           Linear                    (M44, V2 (..), V3 (..), V4 (..),
                                            (!*!))
import qualified Linear                    as L
import qualified RockBand.Codec.Drums      as D
import qualified SDL
import qualified SDL.Font                  as Font
import qualified SDL.Raw                   as Raw

data Note t a
  = Upcoming a
  | Hit t a
  | Missed a
  deriving (Eq, Ord, Show, Read)

data Track t a = Track
  { trackNotes    :: Map t [Note t a] -- ^ lists must be non-empty
  , trackOverhits :: Map t [a] -- ^ lists must be non-empty
  , trackTime     :: t -- ^ the latest timestamp we have reached
  , trackWindow   :: t -- ^ the half-window of time on each side of a note
  } deriving (Eq, Ord, Show, Read)

-- | Efficiently updates the range @(k1, k2)@ of values.
updateRange :: (Ord k) => (k -> a -> a) -> k -> k -> Map k a -> Map k a
updateRange f k1 k2 = let
  go = \case
    Tip -> Tip
    Bin size k v mL mR -> if k <= k1
      then Bin size k v mL (go mR)
      else if k2 <= k
        then Bin size k v (go mL) mR
        else let
          v' = f k v
          in v' `seq` Bin size k v' (go mL) (go mR)
  in go

traverseRange_ :: (Applicative f, Ord k) => (k -> a -> f ()) -> Bool -> k -> k -> Map k a -> f ()
traverseRange_ f asc k1 k2 = let
  go = \case
    Tip -> pure ()
    Bin _ k v mL mR -> if k <= k1
      then go mR
      else if k2 <= k
        then go mL
        else if asc
          then go mL *> f k v *> go mR
          else go mR *> f k v *> go mL
  in go

updateTime :: (Num t, Ord t) => t -> Track t a -> Track t a
updateTime t trk = let
  f _ = map $ \case
    Upcoming x -> Missed x
    evt        -> evt
  in trk
    { trackTime = t
    , trackNotes = updateRange f (trackTime trk - trackWindow trk) (t - trackWindow trk) $ trackNotes trk
    }

hitPad :: (Num t, Ord t, Eq a) => t -> a -> Track t a -> Track t a
hitPad t x trk = let
  p1 = Map.lookupLE t $ trackNotes trk
  p2 = Map.lookupGE t $ trackNotes trk
  closestNotes = case p1 of
    Nothing -> case p2 of
      Nothing      -> Nothing
      Just (k2, _) -> if k2 - t < trackWindow trk then p2 else Nothing
    Just (k1, _) -> case p2 of
      Nothing -> if t - k1 < trackWindow trk then p1 else Nothing
      Just (k2, _) -> let
        distance1 = t - k1
        distance2 = k2 - t
        in if distance1 < distance2
          then if distance1 < trackWindow trk then p1 else Nothing
          else if distance2 < trackWindow trk then p2 else Nothing
  overhit = trk { trackOverhits = Map.alter newOverhit t $ trackOverhits trk }
  newOverhit = Just . (x :) . fromMaybe []
  in case closestNotes of
    Nothing -> overhit
    Just (k, notes) -> case partition (== Upcoming x) notes of
      ([], _) -> overhit
      (_ : _, notes') ->
        trk { trackNotes = Map.insert k (Hit t x : notes') $ trackNotes trk }

drawDrums :: GLStuff -> Track Double (D.Gem ()) -> IO ()
drawDrums GLStuff{..} trk = do
  let drawCube (x1, y1, z1) (x2, y2, z2) (r, g, b) = do
        sendMatrix cubeModel
          $ translate4 (V3 ((x1 + x2) / 2) ((y1 + y2) / 2) ((z1 + z2) / 2))
          !*! L.scaled (V4 (x2 - x1) (y2 - y1) (z2 - z1) 1)
        glUniform3f cubeObjectColor r g b
        glDrawArrays GL_TRIANGLES 0 36
      nearZ = 2 :: Float
      nowZ = 0 :: Float
      farZ = -12 :: Float
      nowTime = trackTime trk :: Double
      farTime = nowTime + 1 :: Double
      timeToZ t = nowZ + farZ * realToFrac ((t - nowTime) / (farTime - nowTime))
      zToTime z = nowTime + farTime * realToFrac ((z - nowZ) / (farZ - nowZ))
      nearTime = zToTime nearZ
      drawGem t gem colorFn = let
        color = case gem of
          D.Kick            -> (153, 106, 6)
          D.Red             -> (202, 25, 7)
          D.Pro D.Yellow () -> (207, 180, 57)
          D.Pro D.Blue ()   -> (71, 110, 222)
          D.Pro D.Green ()  -> (58, 207, 68)
          D.Orange          -> (58, 207, 68) -- TODO
        (x1, x2) = case gem of
          D.Kick            -> (-1, 1)
          D.Red             -> (-1, -0.5)
          D.Pro D.Yellow () -> (-0.5, 0)
          D.Pro D.Blue ()   -> (0, 0.5)
          D.Pro D.Green ()  -> (0.5, 1)
          D.Orange          -> (0.5, 1) -- TODO
        (y1, y2) = case gem of
          D.Kick -> (-0.9, -1.1)
          _      -> (-0.8, -1.1)
        (z1, z2) = case gem of
          D.Kick -> (z + 0.1, z - 0.1)
          _      -> (z + 0.2, z - 0.2)
        z = timeToZ t
        in drawCube (x1, y1, z1) (x2, y2, z2) $ case color of
          (r, g, b) ->
            ( colorFn $ fromInteger r / 255
            , colorFn $ fromInteger g / 255
            , colorFn $ fromInteger b / 255
            )
      drawNotes t notes = forM_ notes $ \case
        Upcoming gem -> drawGem t gem id
        Hit t' gem -> if nowTime - t' < 0.1
          then drawGem nowTime gem sqrt
          else return ()
        Missed gem -> drawGem t gem (** 3)
      drawOverhits t notes = if nowTime - t < 0.1
        then forM_ notes $ \gem -> drawGem nowTime gem (** 3)
        else return ()
  drawCube (-1, -1, nearZ) (1, -1.1, farZ) (0.2, 0.2, 0.2)
  drawCube (-1, -0.98, 0.2) (1, -1.05, -0.2) (0.8, 0.8, 0.8)
  traverseRange_ drawNotes False nearTime farTime $ trackNotes trk
  traverseRange_ drawOverhits False nearTime farTime $ trackOverhits trk

compileShader :: GLenum -> B.ByteString -> IO GLuint
compileShader shaderType source = do
  shader <- glCreateShader shaderType
  B.useAsCString source $ \cs' -> with cs' $ \cs -> do
    glShaderSource shader 1 cs nullPtr
    glCompileShader shader
    alloca $ \success -> do
      allocaArray 512 $ \infoLog -> do
        glGetShaderiv shader GL_COMPILE_STATUS success
        peek success >>= \case
          GL_FALSE -> do
            glGetShaderInfoLog shader 512 nullPtr infoLog
            peekCString infoLog >>= error
          _ -> return shader

compileProgram :: [GLuint] -> IO GLuint
compileProgram shaders = do
  program <- glCreateProgram
  mapM_ (glAttachShader program) shaders
  glLinkProgram program
  alloca $ \success -> do
    allocaArray 512 $ \infoLog -> do
      glGetProgramiv program GL_LINK_STATUS success
      peek success >>= \case
        GL_FALSE -> do
          glGetProgramInfoLog program 512 nullPtr infoLog
          peekCString infoLog >>= error
        _ -> return program

withArrayBytes :: (Storable a, Num len) => [a] -> (len -> Ptr a -> IO b) -> IO b
withArrayBytes xs f = withArray xs $ \p -> let
  bytes = fromIntegral $ length xs * sizeOf (head xs)
  in f bytes p

cubeVertices :: [CFloat]
cubeVertices = [
  -0.5, -0.5, -0.5,  0.0,  0.0, -1.0,
   0.5, -0.5, -0.5,  0.0,  0.0, -1.0,
   0.5,  0.5, -0.5,  0.0,  0.0, -1.0,
   0.5,  0.5, -0.5,  0.0,  0.0, -1.0,
  -0.5,  0.5, -0.5,  0.0,  0.0, -1.0,
  -0.5, -0.5, -0.5,  0.0,  0.0, -1.0,

  -0.5, -0.5,  0.5,  0.0,  0.0, 1.0,
   0.5, -0.5,  0.5,  0.0,  0.0, 1.0,
   0.5,  0.5,  0.5,  0.0,  0.0, 1.0,
   0.5,  0.5,  0.5,  0.0,  0.0, 1.0,
  -0.5,  0.5,  0.5,  0.0,  0.0, 1.0,
  -0.5, -0.5,  0.5,  0.0,  0.0, 1.0,

  -0.5,  0.5,  0.5, -1.0,  0.0,  0.0,
  -0.5,  0.5, -0.5, -1.0,  0.0,  0.0,
  -0.5, -0.5, -0.5, -1.0,  0.0,  0.0,
  -0.5, -0.5, -0.5, -1.0,  0.0,  0.0,
  -0.5, -0.5,  0.5, -1.0,  0.0,  0.0,
  -0.5,  0.5,  0.5, -1.0,  0.0,  0.0,

   0.5,  0.5,  0.5,  1.0,  0.0,  0.0,
   0.5,  0.5, -0.5,  1.0,  0.0,  0.0,
   0.5, -0.5, -0.5,  1.0,  0.0,  0.0,
   0.5, -0.5, -0.5,  1.0,  0.0,  0.0,
   0.5, -0.5,  0.5,  1.0,  0.0,  0.0,
   0.5,  0.5,  0.5,  1.0,  0.0,  0.0,

  -0.5, -0.5, -0.5,  0.0, -1.0,  0.0,
   0.5, -0.5, -0.5,  0.0, -1.0,  0.0,
   0.5, -0.5,  0.5,  0.0, -1.0,  0.0,
   0.5, -0.5,  0.5,  0.0, -1.0,  0.0,
  -0.5, -0.5,  0.5,  0.0, -1.0,  0.0,
  -0.5, -0.5, -0.5,  0.0, -1.0,  0.0,

  -0.5,  0.5, -0.5,  0.0,  1.0,  0.0,
   0.5,  0.5, -0.5,  0.0,  1.0,  0.0,
   0.5,  0.5,  0.5,  0.0,  1.0,  0.0,
   0.5,  0.5,  0.5,  0.0,  1.0,  0.0,
  -0.5,  0.5,  0.5,  0.0,  1.0,  0.0,
  -0.5,  0.5, -0.5,  0.0,  1.0,  0.0
  ]

quadVertices :: [CFloat]
quadVertices =
  -- positions    texture coords
  [  1,  1, 0,    1, 1   -- top right
  ,  1, -1, 0,    1, 0   -- bottom right
  , -1, -1, 0,    0, 0   -- bottom left
  , -1,  1, 0,    0, 1   -- top left
  ]

quadIndices :: [GLuint]
quadIndices =
  [ 0, 1, 3 -- first triangle
  , 1, 2, 3 -- second triangle
  ]

rotate4 :: (Floating a) => a -> V3 a -> M44 a
rotate4 theta (V3 rx ry rz) = let
  sint = sin theta
  cost = cos theta
  len = sqrt $ rx * rx + ry * ry + rz * rz
  nx = rx / len
  ny = ry / len
  nz = rz / len
  in V4
    (V4
      (cost + (nx ** 2) * (1 - cost))
      (nx * ny * (1 - cost) - nz * sint)
      (nx * nz * (1 - cost) + ny * sint)
      0
    ) (V4
      (ny * nx * (1 - cost) + nz * sint)
      (cost + (ny ** 2) * (1 - cost))
      (ny * nz * (1 - cost) - nx * sint)
      0
    ) (V4
      (nz * nx * (1 - cost) - ny * sint)
      (nz * ny * (1 - cost) + nx * sint)
      (cost + (nz ** 2) * (1 - cost))
      0
    ) (V4
      0
      0
      0
      1
    )

translate4 :: (Num a) => V3 a -> M44 a
translate4 (V3 x y z) = V4
  (V4 1 0 0 x)
  (V4 0 1 0 y)
  (V4 0 0 1 z)
  (V4 0 0 0 1)

degrees :: (Floating a) => a -> a
degrees d = (d / 180) * pi

sendMatrix :: (MonadIO m) => GLint -> M44 Float -> m ()
sendMatrix loc m = liftIO $ withArray (toList m >>= toList)
  $ glUniformMatrix4fv loc 1 GL_TRUE {- <- this means row major order -}

objectVS, objectFS :: B.ByteString
objectVS = $(makeRelativeToProject "shaders/object.vert" >>= embedFile)
objectFS = $(makeRelativeToProject "shaders/object.frag" >>= embedFile)

quadVS, quadFS :: B.ByteString
quadVS = $(makeRelativeToProject "shaders/quad.vert" >>= embedFile)
quadFS = $(makeRelativeToProject "shaders/quad.frag" >>= embedFile)

data GLStuff = GLStuff
  { cubeShader      :: GLuint
  , cubeVAO         :: GLuint
  , cubeModel       :: GLint
  , cubeView        :: GLint
  , cubeProjection  :: GLint
  , cubeObjectColor :: GLint
  , cubeLightColor  :: GLint
  , cubeLightPos    :: GLint
  , testFont        :: Font.Font
  , quadShader      :: GLuint
  , quadVAO         :: GLuint
  , quadTransform   :: GLint
  }

class (Pixel a) => GLPixel a where
  glPixelInternalFormat :: a -> GLint
  glPixelFormat :: a -> GLenum
  glPixelType :: a -> GLenum

instance GLPixel PixelRGB8 where
  glPixelInternalFormat _ = GL_RGB
  glPixelFormat _ = GL_RGB
  glPixelType _ = GL_UNSIGNED_BYTE

instance GLPixel PixelRGBA8 where
  glPixelInternalFormat _ = GL_RGBA
  glPixelFormat _ = GL_RGBA
  glPixelType _ = GL_UNSIGNED_BYTE

data Texture = Texture
  { textureGL     :: GLuint
  , textureWidth  :: Int
  , textureHeight :: Int
  }

loadTexture :: (GLPixel a) => Bool -> Image a -> IO Texture
loadTexture linear img = do
  let pixelProp :: (a -> b) -> Image a -> b
      pixelProp f _ = f undefined
      flippedVert = generateImage
        (\x y -> pixelAt img x $ imageHeight img - y - 1)
        (imageWidth img)
        (imageHeight img)
  texture <- alloca $ \p -> glGenTextures 1 p >> peek p
  glBindTexture GL_TEXTURE_2D texture
  glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_S GL_REPEAT
  glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_T GL_REPEAT
  let filtering = if linear then GL_LINEAR_MIPMAP_LINEAR else GL_NEAREST
  glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER filtering
  glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER filtering
  VS.unsafeWith (imageData flippedVert) $ \p -> do
    glTexImage2D GL_TEXTURE_2D 0 (pixelProp glPixelInternalFormat img)
      (fromIntegral $ imageWidth flippedVert)
      (fromIntegral $ imageHeight flippedVert)
      0
      (pixelProp glPixelFormat img)
      (pixelProp glPixelType img)
      (castPtr p)
  when linear $ glGenerateMipmap GL_TEXTURE_2D
  return $ Texture texture (imageWidth img) (imageHeight img)

loadGLStuff :: IO GLStuff
loadGLStuff = do

  glEnable GL_DEPTH_TEST
  glEnable GL_BLEND
  glBlendFunc GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA

  -- cube stuff

  cubeShader <- bracket (compileShader GL_VERTEX_SHADER objectVS) glDeleteShader $ \vertexShader -> do
    bracket (compileShader GL_FRAGMENT_SHADER objectFS) glDeleteShader $ \fragmentShader -> do
      compileProgram [vertexShader, fragmentShader]
  cubeModel <- withCString "model" $ glGetUniformLocation cubeShader
  cubeView <- withCString "view" $ glGetUniformLocation cubeShader
  cubeProjection <- withCString "projection" $ glGetUniformLocation cubeShader
  cubeObjectColor <- withCString "objectColor" $ glGetUniformLocation cubeShader
  cubeLightColor <- withCString "lightColor" $ glGetUniformLocation cubeShader
  cubeLightPos <- withCString "lightPos" $ glGetUniformLocation cubeShader

  cubeVAO <- alloca $ \p -> glGenVertexArrays 1 p >> peek p
  cubeVBO <- alloca $ \p -> glGenBuffers 1 p >> peek p

  glBindVertexArray cubeVAO

  glBindBuffer GL_ARRAY_BUFFER cubeVBO
  withArrayBytes cubeVertices $ \size p -> do
    glBufferData GL_ARRAY_BUFFER size (castPtr p) GL_STATIC_DRAW

  glVertexAttribPointer 0 3 GL_FLOAT GL_FALSE
    (fromIntegral $ 6 * sizeOf (undefined :: CFloat))
    nullPtr
  glEnableVertexAttribArray 0
  glVertexAttribPointer 1 3 GL_FLOAT GL_FALSE
    (fromIntegral $ 6 * sizeOf (undefined :: CFloat))
    (intPtrToPtr $ fromIntegral $ 3 * sizeOf (undefined :: CFloat))
  glEnableVertexAttribArray 1

  -- quad stuff

  quadShader <- bracket (compileShader GL_VERTEX_SHADER quadVS) glDeleteShader $ \vertexShader -> do
    bracket (compileShader GL_FRAGMENT_SHADER quadFS) glDeleteShader $ \fragmentShader -> do
      compileProgram [vertexShader, fragmentShader]
  quadTransform <- withCString "transform" $ glGetUniformLocation quadShader

  quadVAO <- alloca $ \p -> glGenVertexArrays 1 p >> peek p
  quadVBO <- alloca $ \p -> glGenBuffers 1 p >> peek p
  quadEBO <- alloca $ \p -> glGenBuffers 1 p >> peek p

  glBindVertexArray quadVAO

  glBindBuffer GL_ARRAY_BUFFER quadVBO
  withArrayBytes quadVertices $ \size p -> do
    glBufferData GL_ARRAY_BUFFER size (castPtr p) GL_STATIC_DRAW

  glBindBuffer GL_ELEMENT_ARRAY_BUFFER quadEBO
  withArrayBytes quadIndices $ \size p -> do
    glBufferData GL_ELEMENT_ARRAY_BUFFER size (castPtr p) GL_STATIC_DRAW

  glVertexAttribPointer 0 3 GL_FLOAT GL_FALSE
    (fromIntegral $ 5 * sizeOf (undefined :: CFloat))
    nullPtr
  glEnableVertexAttribArray 0
  glVertexAttribPointer 1 2 GL_FLOAT GL_FALSE
    (fromIntegral $ 5 * sizeOf (undefined :: CFloat))
    (intPtrToPtr $ fromIntegral $ 3 * sizeOf (undefined :: CFloat))
  glEnableVertexAttribArray 1

  glUseProgram quadShader
  quadOurTexture <- withCString "ourTexture" $ glGetUniformLocation quadShader
  glUniform1i quadOurTexture 0

  -- test text rendering

  Font.initialize
  testFont <- Font.decode
    $(makeRelativeToProject "../../player/www/VarelaRound-Regular.ttf" >>= embedFile)
    30 -- point size

  return GLStuff{..}

drawTexture :: GLStuff -> SDL.Window -> Texture -> V2 Int -> Int -> IO ()
drawTexture GLStuff{..} window (Texture tex w h) (V2 x y) scale = do
  SDL.V2 screenW screenH <- SDL.glGetDrawableSize window
  glUseProgram quadShader
  glActiveTexture GL_TEXTURE0
  glBindTexture GL_TEXTURE_2D tex
  glBindVertexArray quadVAO
  let scaleX = fromIntegral (w * scale) / fromIntegral screenW
      scaleY = fromIntegral (h * scale) / fromIntegral screenH
      translateX = (fromIntegral x / fromIntegral screenW) * 2 - 1 + scaleX
      translateY = (fromIntegral y / fromIntegral screenH) * 2 - 1 + scaleY
  sendMatrix quadTransform
    $ translate4 (V3 translateX translateY 0)
    !*! L.scaled (V4 scaleX scaleY 1 1)
  glDrawElements GL_TRIANGLES 6 GL_UNSIGNED_INT nullPtr

freeTexture :: Texture -> IO ()
freeTexture (Texture tex _ _) = with tex $ glDeleteTextures 1

drawDrumsFull :: GLStuff -> SDL.Window -> Track Double (D.Gem ()) -> IO ()
drawDrumsFull glStuff@GLStuff{..} window trk' = do
  let V3 lightX lightY lightZ = V3 0 (-0.5) (0.5)
  SDL.V2 w h <- SDL.glGetDrawableSize window
  glViewport 0 0 (fromIntegral w) (fromIntegral h)
  glClearColor 0.2 0.3 0.3 1.0
  glClear $ GL_COLOR_BUFFER_BIT .|. GL_DEPTH_BUFFER_BIT

  glUseProgram cubeShader
  let view -- this should be doable with L.mkTransformation but not sure exactly how
        = rotate4 (degrees 20) (V3 1 0 0)
        !*! translate4 (V3 0 (-1) (-3))
      projection = L.perspective (degrees 45) (fromIntegral w / fromIntegral h) 0.1 100
  sendMatrix cubeView view
  sendMatrix cubeProjection projection
  glBindVertexArray cubeVAO
  glUniform3f cubeLightColor 1 1 1
  glUniform3f cubeLightPos lightX lightY lightZ
  drawDrums glStuff trk'

  let time = T.pack $ show $ trackTime trk'
  bracket (Font.blended testFont (SDL.V4 255 255 255 255) time) SDL.freeSurface $ \surf -> do
    bracket (surfaceToGL surf) freeTexture $ \text -> do
      drawTexture glStuff window text (V2 0 0) 1

surfaceToGL :: SDL.Surface -> IO Texture
surfaceToGL (SDL.Surface p _) = do
  texture <- alloca $ \ptex -> glGenTextures 1 ptex >> peek ptex
  glBindTexture GL_TEXTURE_2D texture
  glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_S GL_REPEAT
  glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_T GL_REPEAT
  glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_NEAREST
  glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_NEAREST
  let fmt = case targetByteOrder of -- this is SDL_PIXELFORMAT_RGBA32 but there's no hs binding
        BigEndian    -> Raw.SDL_PIXELFORMAT_RGBA8888
        LittleEndian -> Raw.SDL_PIXELFORMAT_ABGR8888
  (w, h) <- bracket (Raw.convertSurfaceFormat p fmt 0) Raw.freeSurface $ \raw -> do
    struct <- peek raw
    bracket_ (Raw.lockSurface raw) (Raw.unlockSurface raw) $ do
      -- flip rows vertically
      let rowLength = fromIntegral (Raw.surfaceW struct) * 4
          rowPointer r = Raw.surfacePixels struct `plusPtr` (r * rowLength)
      allocaBytes rowLength $ \tmp -> do
        forM_ [0 .. (quot (fromIntegral $ Raw.surfaceH struct) 2 - 1)] $ \r1 -> do
          let r2 = fromIntegral (Raw.surfaceH struct) - 1 - r1
          -- note, it's "copyBytes <destination> <source>"
          copyBytes tmp             (rowPointer r1) rowLength
          copyBytes (rowPointer r1) (rowPointer r2) rowLength
          copyBytes (rowPointer r2) tmp             rowLength
      glTexImage2D GL_TEXTURE_2D 0 GL_RGBA
        (fromIntegral $ Raw.surfaceW struct)
        (fromIntegral $ Raw.surfaceH struct)
        0
        GL_RGBA
        GL_UNSIGNED_BYTE
        (Raw.surfacePixels struct)
    return (fromIntegral $ Raw.surfaceW struct, fromIntegral $ Raw.surfaceH struct)
  return $ Texture texture w h

playDrums :: SDL.Window -> Track Double (D.Gem ()) -> IO ()
playDrums window trk = flip evalStateT trk $ do
  initTime <- SDL.ticks
  glStuff <- liftIO loadGLStuff
  let loop = SDL.pollEvents >>= processEvents >>= \b -> when b $ do
        timestamp <- SDL.ticks
        modify $ updateTime $ fromIntegral (timestamp - initTime) / 1000
        draw
        liftIO $ threadDelay 5000
        loop
      processEvents [] = return True
      processEvents (e : es) = case SDL.eventPayload e of
        SDL.QuitEvent -> return False
        SDL.KeyboardEvent SDL.KeyboardEventData
          { SDL.keyboardEventKeyMotion = SDL.Pressed
          , SDL.keyboardEventKeysym = ksym
          , SDL.keyboardEventRepeat = False
          } -> do
            let hit gem = modify $ hitPad t gem
                t = fromIntegral (SDL.eventTimestamp e - initTime) / 1000
            case SDL.keysymScancode ksym of
              SDL.ScancodeV     -> hit D.Red
              SDL.ScancodeB     -> hit $ D.Pro D.Yellow ()
              SDL.ScancodeN     -> hit $ D.Pro D.Blue ()
              SDL.ScancodeM     -> hit $ D.Pro D.Green ()
              SDL.ScancodeSpace -> hit D.Kick
              _                 -> return ()
            processEvents es
        _ -> processEvents es
      draw = do
        trk' <- get
        liftIO $ drawDrumsFull glStuff window trk'
        SDL.glSwapWindow window
  loop

previewDrums :: SDL.Window -> IO (Track Double (D.Gem ())) -> IO Double -> IO ()
previewDrums window getTrack getTime = do
  glStuff <- loadGLStuff
  let loop = SDL.pollEvents >>= processEvents >>= \b -> when b $ do
        t <- getTime
        trk <- getTrack
        drawDrumsFull glStuff window trk { trackTime = t }
        SDL.glSwapWindow window
        threadDelay 5000
        loop
      processEvents [] = return True
      processEvents (e : es) = case SDL.eventPayload e of
        SDL.QuitEvent -> return False
        _             -> processEvents es
  loop
