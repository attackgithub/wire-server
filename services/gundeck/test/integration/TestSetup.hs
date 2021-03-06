{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# OPTIONS_GHC -fprint-potential-instances #-}
module TestSetup
    ( test
    , tsManager
    , tsGundeck
    , tsCannon
    , tsCannon2
    , tsBrig
    , tsCass
    , tsLogger
    , TestM(..)
    , TestSetup(..)
    , BrigR(..)
    , CannonR(..)
    , GundeckR(..)
    ) where

import Imports
import Test.Tasty          (TestName, TestTree)
import Test.Tasty.HUnit    (Assertion, testCase)
import Control.Lens        ((^.), makeLenses)
import Control.Monad.Catch (MonadCatch, MonadMask, MonadThrow)
import Bilge (HttpT(..), Manager, MonadHttp, Request, runHttpT)

import qualified Cassandra           as Cql
import qualified System.Logger       as Log

newtype TestM a =
  TestM { runTestM :: ReaderT TestSetup (HttpT IO) a
        }
    deriving ( Functor
             , Applicative
             , Monad
             , MonadReader TestSetup
             , MonadIO
             , MonadCatch
             , MonadThrow
             , MonadMask
             , MonadHttp
             , MonadUnliftIO
             )

newtype BrigR    = BrigR    { runBrigR    :: Request -> Request }
newtype CannonR  = CannonR  { runCannonR  :: Request -> Request }
newtype GundeckR = GundeckR { runGundeckR :: Request -> Request }

data TestSetup = TestSetup
  { _tsManager :: Manager
  , _tsGundeck :: GundeckR
  , _tsCannon  :: CannonR
  , _tsCannon2 :: CannonR
  , _tsBrig    :: BrigR
  , _tsCass    :: Cql.ClientState
  , _tsLogger  :: Log.Logger
  }

makeLenses ''TestSetup

test :: IO TestSetup -> TestName -> TestM a -> TestTree
test s n h = testCase n runTest
  where
    runTest :: Assertion
    runTest = do
        setup <- s
        void . runHttpT (setup ^. tsManager) . flip runReaderT setup . runTestM $ h
