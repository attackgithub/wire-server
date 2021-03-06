{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Gundeck.Monad
    ( -- * Environment
      Env
    , reqId
    , monitor
    , options
    , applog
    , manager
    , cstate
    , createEnv

      -- * Gundeck monad
    , Gundeck
    , runDirect
    , runGundeck
    , fromJsonBody
    , ifNothing
    , posixTime
    ) where

import Imports
import Bilge hiding (Request, header, statusCode, options)
import Bilge.RPC
import Cassandra
import Control.Error hiding (err)
import Control.Lens hiding ((.=))
import Control.Monad.Catch hiding (tryJust)
import Data.Aeson (FromJSON)
import Data.Default (def)
import Data.Misc (Milliseconds (..))
import Gundeck.Env
import Network.Wai
import Network.Wai.Utilities
import Network.HTTP.Types
import System.Logger.Class hiding (Error, info)

import qualified Database.Redis.IO as Redis
import qualified System.Logger     as Logger

-- | TODO: 'Client' already has an 'Env'.  Why do we need two?  How does this even work?  We should
-- probably explain this here.
newtype Gundeck a = Gundeck
    { unGundeck :: ReaderT Env Client a
    } deriving ( Functor
               , Applicative
               , Monad
               , MonadIO
               , MonadThrow
               , MonadCatch
               , MonadMask
               , MonadReader Env
               , MonadClient
               )

instance MonadUnliftIO Gundeck where
    askUnliftIO =
        Gundeck $ ReaderT $ \r ->
        withUnliftIO $ \u ->
        return (UnliftIO (unliftIO u . flip runReaderT r . unGundeck))

instance Redis.MonadClient Gundeck where
    liftClient m = view rstate >>= \p -> Redis.runRedis p m

instance MonadLogger Gundeck where
    log l m = do
        e <- ask
        Logger.log (e^.applog) l (reqIdMsg (e^.reqId) . m)

instance MonadHttp Gundeck where
    handleRequestWithCont req handler = do
        httpManager <- view manager
        liftIO $ withResponse req httpManager handler

instance HasRequestId Gundeck where
    getRequestId = view reqId

runGundeck :: Env -> Request -> Gundeck ResponseReceived -> IO ResponseReceived
runGundeck e r m = runClient (e^.cstate) (runReaderT (unGundeck m) (e & reqId .~ lookupReqId r))

runDirect :: Env -> Gundeck a -> IO a
runDirect e m = runClient (e^.cstate) (runReaderT (unGundeck m) e)

lookupReqId :: Request -> RequestId
lookupReqId = maybe def RequestId . lookup requestIdName . requestHeaders
{-# INLINE lookupReqId #-}

fromJsonBody :: FromJSON a => JsonRequest a -> Gundeck a
fromJsonBody r = exceptT (throwM . Error status400 "bad-request") return (parseBody r)
{-# INLINE fromJsonBody #-}

ifNothing :: Error -> Maybe a -> Gundeck a
ifNothing e = maybe (throwM e) return
{-# INLINE ifNothing #-}

posixTime :: Gundeck Milliseconds
posixTime = view time >>= liftIO
{-# INLINE posixTime #-}
