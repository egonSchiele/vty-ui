{-# LANGUAGE ExistentialQuantification, DeriveDataTypeable #-}
module Graphics.Vty.Widgets.Collections
    ( Collection
    , CollectionError(..)
    , newCollection
    , addToCollection
    , setCurrent
    )
where

import Data.Typeable
import Control.Monad.Trans
import Control.Exception
import Graphics.Vty
import Graphics.Vty.Widgets.Core

-- Ultimately we'd want support for "stacks" to provide things like
-- overlaid dialogs, but for now we'll just implement a "collection"
-- type which allows is to have a collection of widgets and switch
-- between them.

data CollectionError = EmptyCollection
                     | BadCollectionIndex Int
                       deriving (Show, Typeable)

instance Exception CollectionError

data Entry = forall a. (Show a) => Entry (Widget a)

data Collection =
    Collection { entries :: [Entry]
               , currentEntryNum :: Int
               }

instance Show Collection where
    show (Collection es num) = concat [ "Collection { "
                                      , "entries = <", show $ length es, "entries>"
                                      , ", currentEntryNum = ", show num
                                      , " }"
                                      ]

renderEntry :: (MonadIO m) => Entry -> DisplayRegion -> RenderContext -> m Image
renderEntry (Entry w) = render w

positionEntry :: Entry -> DisplayRegion -> IO ()
positionEntry (Entry w) = setCurrentPosition w

entryHandleKeyEvent :: (MonadIO m) => Entry -> Key -> [Modifier] -> m Bool
entryHandleKeyEvent (Entry w) k mods = handleKeyEvent w k mods

entryFocusGroup :: Entry -> IO (Maybe (Widget FocusGroup))
entryFocusGroup (Entry w) = getFocusGroup w

entryGrowHorizontal :: Entry -> IO Bool
entryGrowHorizontal (Entry w) = growHorizontal w

entryGrowVertical :: Entry -> IO Bool
entryGrowVertical (Entry w) = growVertical w

newCollection :: (MonadIO m) => m (Widget Collection)
newCollection = do
  wRef <- newWidget
  updateWidget wRef $ \w ->
      w { state = Collection { entries = []
                             , currentEntryNum = -1
                             }
        , growHorizontal_ = \st -> do
            case currentEntryNum st of
              (-1) -> throw EmptyCollection
              i -> do
                let e = entries st !! i
                liftIO $ entryGrowHorizontal e

        , growVertical_ = \st -> do
            case currentEntryNum st of
              (-1) -> throw EmptyCollection
              i -> do
                let e = entries st !! i
                liftIO $ entryGrowVertical e

        , focusGroup =
            \this -> do
              st <- getState this
              case currentEntryNum st of
                (-1) -> return Nothing
                i -> do
                       let e = entries st !! i
                       entryFocusGroup e

        , render_ = \this size ctx -> do
                   st <- getState this
                   case currentEntryNum st of
                     (-1) -> throw EmptyCollection
                     i -> do
                       let e = entries st !! i
                       renderEntry e size ctx

        , setCurrentPosition_ =
            \this pos -> do
              st <- getState this
              case currentEntryNum st of
                (-1) -> throw EmptyCollection
                i -> do
                  let e = entries st !! i
                  positionEntry e pos
        }

  wRef `onKeyPressed`
           \this key mods -> do
                  st <- getState this
                  case currentEntryNum st of
                    (-1) -> return False
                    i -> do
                      let e = entries st !! i
                      entryHandleKeyEvent e key mods

  return wRef

addToCollection :: (MonadIO m, Show a) => Widget Collection -> Widget a -> m (m ())
addToCollection cRef wRef = do
  i <- (length . entries) <~~ cRef
  updateWidgetState cRef $ \st ->
      st { entries = (entries st) ++ [Entry wRef]
         , currentEntryNum = if currentEntryNum st == -1
                             then 0
                             else currentEntryNum st
         }
  return $ setCurrent cRef i

setCurrent :: (MonadIO m) => Widget Collection -> Int -> m ()
setCurrent cRef i = do
  st <- state <~ cRef
  if i < length (entries st) && i >= 0 then
      updateWidgetState cRef $ \s -> s { currentEntryNum = i } else
      throw $ BadCollectionIndex i
