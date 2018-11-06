{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE UndecidableInstances #-}
module Reflex.Dom.Prerender
       ( Prerender (..)
       , prerender
       , PrerenderClientConstraint
       ) where

import Control.Monad.Reader
import Control.Monad.Ref (Ref, MonadRef)
import Data.Constraint
import Data.Default
import Data.IORef (modifyIORef')
import Foreign.JavaScript.TH
import GHC.IORef (IORef)
import GHCJS.DOM.Types (MonadJSM)
import Reflex
import Reflex.Dom.Builder.Class
import Reflex.Dom.Builder.InputDisabled
import Reflex.Dom.Builder.Immediate
import Reflex.Dom.Builder.Hydration
import Reflex.Dom.Builder.Static
import Reflex.Host.Class

type PrerenderClientConstraint js m =
  ( HasJS js m
  , HasJS js (Performable m)
  , MonadJSM m
  , MonadJSM (Performable m)
  , HasJSContext m
  , HasJSContext (Performable m)
  , MonadFix m
  , MonadFix (Performable m)
--  , DomBuilderSpace m ~ GhcjsDomSpace
  )

class Monad m => Prerender js m | m -> js where
  prerenderClientDict :: Maybe (Dict (PrerenderClientConstraint js m))
  startPrerenderBlock :: m ()
  default startPrerenderBlock :: (Prerender js n, m ~ t n, MonadTrans t, Monad n) => m ()
  startPrerenderBlock = lift $ startPrerenderBlock
  endPrerenderBlock :: m ()
  default endPrerenderBlock :: (Prerender js n, m ~ t n, MonadTrans t, Monad n) => m ()
  endPrerenderBlock = lift $ endPrerenderBlock

-- | Draw one widget when prerendering (e.g. server-side) and another when the
-- widget is fully instantiated.  In a given execution of this function, there
-- will be exactly one invocation of exactly one of the arguments.
prerender :: forall js t m a. (Prerender js m, DomBuilder t m) => m a -> (PrerenderClientConstraint js m => m a) -> m a
prerender server client = do
  startPrerenderBlock
  a <- case prerenderClientDict :: Maybe (Dict (PrerenderClientConstraint js m)) of
    Nothing -> server
    Just Dict -> client
  endPrerenderBlock
  pure a

instance ( HasJS js m
         , HasJS js (Performable m)
         , HasJSContext m
         , HasJSContext (Performable m)
         , MonadJSM m
         , MonadJSM (Performable m)
         , MonadFix m
         , MonadFix (Performable m)
         , ReflexHost t
         ) => Prerender js (ImmediateDomBuilderT t m) where
  prerenderClientDict = Just Dict
  startPrerenderBlock = return ()
  endPrerenderBlock = return ()

instance ( HasJS js m
         , HasJS js (Performable m)
         , HasJSContext m
         , HasJSContext (Performable m)
         , MonadJSM m
         , MonadJSM (Performable m)
         , MonadFix m
         , MonadFix (Performable m)
         , ReflexHost t
         ) => Prerender js (HydrationDomBuilderT t m) where
  prerenderClientDict = Just Dict
  startPrerenderBlock = do
    depth <- HydrationDomBuilderT $ asks _hydrationDomBuilderEnv_prerenderDepth
    liftIO $ modifyIORef' depth succ
  endPrerenderBlock = do
    depth <- HydrationDomBuilderT $ asks _hydrationDomBuilderEnv_prerenderDepth
    liftIO $ modifyIORef' depth pred

data NoJavaScript -- This type should never have a HasJS instance

instance (Monad m, js ~ NoJavaScript, Adjustable t m, MonadIO m, MonadHold t m, MonadFix m, PerformEvent t m, MonadReflexCreateTrigger t m, MonadRef m, Ref m ~ IORef) => Prerender js (StaticDomBuilderT t m) where
  prerenderClientDict = Nothing
  startPrerenderBlock = void $ commentNode $ def { _commentNodeConfig_initialContents = "prerender-start" }
  endPrerenderBlock = void $ commentNode $ def { _commentNodeConfig_initialContents = "prerender-end" }


instance (Prerender js m, ReflexHost t) => Prerender js (PostBuildT t m) where
  prerenderClientDict = fmap (\Dict -> Dict) (prerenderClientDict :: Maybe (Dict (PrerenderClientConstraint js m)))

instance Prerender js m => Prerender js (DynamicWriterT t w m) where
  prerenderClientDict = fmap (\Dict -> Dict) (prerenderClientDict :: Maybe (Dict (PrerenderClientConstraint js m)))

instance Prerender js m => Prerender js (EventWriterT t w m) where
  prerenderClientDict = fmap (\Dict -> Dict) (prerenderClientDict :: Maybe (Dict (PrerenderClientConstraint js m)))

instance Prerender js m => Prerender js (ReaderT w m) where
  prerenderClientDict = fmap (\Dict -> Dict) (prerenderClientDict :: Maybe (Dict (PrerenderClientConstraint js m)))

instance Prerender js m => Prerender js (RequesterT t request response m) where
  prerenderClientDict = fmap (\Dict -> Dict) (prerenderClientDict :: Maybe (Dict (PrerenderClientConstraint js m)))

instance Prerender js m => Prerender js (QueryT t q m) where
  prerenderClientDict = fmap (\Dict -> Dict) (prerenderClientDict :: Maybe (Dict (PrerenderClientConstraint js m)))

instance Prerender js m => Prerender js (InputDisabledT m) where
  prerenderClientDict = fmap (\Dict -> Dict) (prerenderClientDict :: Maybe (Dict (PrerenderClientConstraint js m)))
