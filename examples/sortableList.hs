{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecursiveDo #-}
{-# LANGUAGE ScopedTypeVariables #-}
import Control.Lens
import Control.Monad.Identity
import Control.Monad.IO.Class
import Data.Dependent.Map (DMap)
import Data.Functor.Constant
import Data.Functor.Misc
import Data.List
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Monoid
import Data.Ord
import qualified Data.Text as T
import Data.Time.Clock
import Reflex.Dom
import System.Random

main :: IO ()
main = mainWidget $ do
  let f k (a, b, c) = el "tr" $ do
        mapM_ (el "td" . text . T.pack . show) [k, a, b, c]
        _ <- el "td" $ inputElement def
        return ()
  let numKeys = 1000 :: Int
      keys = take numKeys [0 :: Int ..]
      values :: [(Int, Int, Int)]
      values = zip3 (randoms (mkStdGen 0)) (randoms (mkStdGen 1)) (randoms (mkStdGen 2))
      testMap = Map.fromList $ zip keys values
      resortButtons = el "div" $ leftmost <$> sequence
        [ (comparing (view _1) <$) <$> button "1 ASC"
        , (flip (comparing (view _1)) <$) <$> button "1 DESC"
        , (comparing (view _2) <$) <$> button "2 ASC"
        , (flip (comparing (view _2)) <$) <$> button "2 DESC"
        , (comparing (view _3) <$) <$> button "3 ASC"
        , (flip (comparing (view _3)) <$) <$> button "3 DESC"
        ]
  el "h1" $ text "Improved list sorting"
  el "p" $ text $ "This app shows a table of " <> T.pack (show numKeys) <> " items, and allows you to re-sort by columns a, b, and c, which are full of pseudorandom numbers."
  el "h3" $ text "Re-sort the list the OLD way (by redrawing everything)"
  resortSlow <- resortButtons
  displayRedrawTime resortSlow
  el "h3" $ text "Re-sort the list the NEW way (by reordering existing elements)"
  resort <- resortButtons
  displayRedrawTime resort
  el "hr" blank
  el "table" $ do
    el "tr" $ do
      el "th" $ text "Key"
      el "th" $ text "A"
      el "th" $ text "B"
      el "th" $ text "C"
      el "th" $ text "Stateful Element (textbox)"
    simpleSortableList f testMap resort resortSlow
  return ()

displayRedrawTime :: (DomBuilder t m, MonadHold t m, PostBuild t m, PerformEvent t m, TriggerEvent t m, MonadIO (Performable m)) => Event t a -> m ()
displayRedrawTime e = do
  et1 <- performEvent $ liftIO getCurrentTime <$ e
  et1' <- delay 0 et1
  diff <- performEvent $ ffor et1' $ \t1 -> do
    t2 <- liftIO getCurrentTime
    return $ t2 `diffUTCTime` t1
  text "Time: "
  dynText =<< holdDyn "not yet run" (T.pack . show <$> diff)

mapMapWithAdjustWithMove :: forall t m k v v'. (MonadAdjust t m, Ord k) => (k -> v -> m v') -> Map k v -> Event t (PatchMapWithMove k v) -> m (Map k v', Event t (PatchMapWithMove k v'))
mapMapWithAdjustWithMove f m0 m' = do
  (out0 :: DMap (Const2 k v) (Constant v'), out') <- traverseDMapWithKeyWithAdjustWithMove (\(Const2 k) (Identity v) -> Constant <$> f k v) (mapToDMap m0) (const2PatchDMapWithMoveWith Identity <$> m')
  return (dmapToMapWith (\(Constant v') -> v') out0, patchDMapWithMoveToPatchMapWithMoveWith (\(Constant v') -> v') <$> out')

simpleSortableList :: forall t m k v. (MonadHold t m, MonadFix m, MonadAdjust t m, Ord k) => (k -> v -> m ()) -> Map k v -> Event t (v -> v -> Ordering) -> Event t (v -> v -> Ordering) -> m ()
simpleSortableList f m0 resortFunc resortSlowFunc = do
  rec let resortPatch = attachWith (flip patchThatSortsMapWith) (currentIncremental m) resortFunc
          redrawPatch :: Map k v -> (v -> v -> Ordering) -> PatchMapWithMove k v
          redrawPatch d cmp = unsafePatchMapWithMove $ fmap (MapEdit_Insert False) $ Map.fromList $ zip (Map.keys d) (sortBy cmp $ Map.elems d)
          resortPatchSlow = attachWith redrawPatch (currentIncremental m) resortSlowFunc
      m <- holdIncremental m0 resortPatch
  _ <- mapMapWithAdjustWithMove f m0 $ leftmost
    [ resortPatch
    , resortPatchSlow
    ]
  return ()
