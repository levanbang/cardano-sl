{-| Demo cluster of wallet nodes. See cluster/README.md -}

module Cardano.Cluster
    (
    -- * Types
      NodeName (..)
    , NodeType (..)
    , RunningNode (..)

    -- * Start Cluster
    , startCluster
    , startNode

    -- * Monitor cluster
    , MaxWaitingTime (..)
    , waitForNode
    ) where

import           Universum

import           Control.Concurrent (threadDelay)
import           Control.Concurrent.Async (Async, race)
import           Control.Lens (at)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import           Options.Applicative (handleParseResult, info)
import           System.Environment (getEnvironment)

import           Cardano.Cluster.Environment (Env, prepareEnvironment,
                     withStateDirectory, withSystemStart)
import           Cardano.Cluster.Util (execParserEnv, oneSecond, runAsync,
                     stripFilterPrefix, unsafePOSIXTimeFromString,
                     varFromParser)
import           Cardano.Wallet.Action (actionWithWallet)
import           Cardano.Wallet.API.V1.Types (ForceNtpCheck (..))
import           Cardano.Wallet.Client (ClientError (..), ServantError (..),
                     WalletClient (getNodeInfo))
import           Cardano.Wallet.Server.CLI (NewWalletBackendParams (..),
                     walletBackendParamsParser)
import           Pos.Client.CLI.NodeOptions (commonNodeArgsParser,
                     nodeArgsParser)
import           Pos.Client.CLI.Params (loggingParams)
import           Pos.Infra.Network.Types (NodeName (..), NodeType (..))
import           Pos.Launcher (LoggingParams (..), actionWithCoreNode,
                     launchNode)
import           Pos.Util.CompileInfo (withCompileInfo)


-- | A type representing a running node. The process is captured within the
-- 'Async' handle. For wallet nodes, there's an exta 'WalletClient' configured
-- to talk to the underlying node API.
data RunningNode m
    = RunningCoreNode   NodeName Env (Async ())
    | RunningRelayNode  NodeName Env (Async ())
    | RunningWalletNode NodeName Env (WalletClient m) (Async ())


-- | Start a cluster of wallet nodes in different threads.
-- Nodes get their (optional) arguments from the ENV.
--
-- For more details, look at cluster/README.md
startCluster
    :: String                 -- ^ A prefix. Only ENV vars with this prefix will be considered
    -> [(NodeName, NodeType)] -- ^ A list of node names forming the cluster
    -> IO [RunningNode IO]
startCluster prefix nodes = do
    env0 <- (Map.fromList . stripFilterPrefix prefix) <$> getEnvironment
    handles <- forM nodes $ \node@(nodeId, nodeType) -> runAsync $ \yield ->
        withStateDirectory (env0 ^. at "STATE_DIR") $ \stateDir -> do
            let offset = maybe 10 unsafePOSIXTimeFromString
                    (env0 ^. at "SYSTEM_START_OFFSET")

            (actions, nodeEnv) <-
                prepareEnvironment node nodes stateDir <$> withSystemStart offset env0

            let (initGenesis, initTopology, initLoggerConfig, initTLS) = actions

            case nodeType of
                NodeCore -> do
                    void (initGenesis >> initTopology >> initLoggerConfig)
                    yield (RunningCoreNode nodeId nodeEnv)

                NodeRelay -> do
                    void (initTopology >> initLoggerConfig)
                    yield (RunningRelayNode nodeId nodeEnv)

                NodeEdge -> do
                    nodeClient <- initTopology >> initLoggerConfig >> initTLS
                    yield (RunningWalletNode nodeId nodeEnv nodeClient)

            startNode node nodeEnv

    return $ map (\(h, running) -> running h) handles


-- | Start a demo node (with wallet) using the given environment as a context.
-- This action never returns, unless the node crashes.
startNode
    :: (NodeName, NodeType) -- ^ The actual node name
    -> Env                  -- ^ A "simulation" of the system ENV as a 'Map String String'
    -> IO ()
startNode (NodeName nodeIdT, nodeType) env = do
    nArgs <- parseNodeArgs
    cArgs <- parseCommonNodeArgs
    let lArgs = getLoggingArgs cArgs
    case nodeType of
        NodeEdge -> do
            wArgs <- parseWalletArgs
            withCompileInfo $ launchNode nArgs cArgs lArgs (actionWithWallet wArgs)

        _ ->
            withCompileInfo $ launchNode nArgs cArgs lArgs actionWithCoreNode
  where
    parseNodeArgs = do
        let nVars = varFromParser nodeArgsParser
        let nInfo = info nodeArgsParser mempty
        handleParseResult $ execParserEnv env nVars nInfo

    parseCommonNodeArgs = do
        let cVars = varFromParser commonNodeArgsParser
        let cInfo = info commonNodeArgsParser mempty
        handleParseResult $ execParserEnv env cVars cInfo

    parseWalletArgs = do
        let wVars = varFromParser walletBackendParamsParser
        let wInfo = info walletBackendParamsParser mempty
        NewWalletBackendParams <$> handleParseResult (execParserEnv env wVars wInfo)

    -- NOTE
    -- Logging to the console is disabled. This is just noise when multiple
    -- nodes are running at the same time. Logs are available in the logfiles
    -- inside the state directory anyway. `tail -f` is a friend.
    getLoggingArgs cArgs = (loggingParams (fromString $ T.unpack nodeIdT) cArgs)
        { lpConsoleLog = Just False }


-- | Maximum time, in second, a function should for something
newtype MaxWaitingTime = MaxWaitingTime Int deriving (Eq, Show)


-- | Make HttpRequest continuously for a while to wait after the node
waitForNode
    :: WalletClient IO -- ^ A Wallet Client configured against a given node
    -> MaxWaitingTime  -- ^ Maximum waiting time, in seconds
    -> IO ()
waitForNode wc (MaxWaitingTime s) = do
    res <- race (threadDelay $ s * oneSecond) waitForNode'
    case res of
        Left _ ->
            fail $ "Giving up waiting for node to start: it takes too long"

        Right _ ->
            return ()
  where
    waitForNode' :: IO ()
    waitForNode' = do
        resp <- getNodeInfo wc NoNtpCheck
        case resp of
            Right _ ->
                return ()

            Left (ClientHttpError ConnectionError{}) ->
                threadDelay oneSecond >> waitForNode'

            Left err ->
                fail $ "Failed to wait for node to start: " <> show err
