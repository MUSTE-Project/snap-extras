{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE OverloadedStrings         #-}

module Snap.Extras.FlashNotice
    ( initFlashNotice
    , flashInfo
    , flashWarning
    , flashSuccess
    , flashError
    , flashSplice
    , flashCSplice
    ) where

-------------------------------------------------------------------------------
import           Control.Lens
import           Control.Monad
import           Control.Monad.Trans
import qualified Data.Map.Syntax      as MS
import           Data.Maybe
import           Data.Monoid          (mempty)
import           Data.Text            (Text)
import qualified Data.Text            as T
import           Heist
import qualified Heist.Compiled       as C
import           Heist.Interpreted
import           Snap.Snaplet
import           Snap.Snaplet.Heist
import           Snap.Snaplet.Session
import           Text.XmlHtml
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- | Initialize the flash notice system. All you have to do now is to
-- add some flash tags in your application template. See 'flashSplice'
-- for examples.
initFlashNotice
    :: HasHeist b
    => Snaplet (Heist b) -> SnapletLens b SessionManager -> Initializer b v ()
initFlashNotice h session = do
    let splices = ("flash" MS.## flashSplice session)
        csplices = ("flash" MS.## flashCSplice session)
    addConfig h $ mempty & scCompiledSplices .~ csplices
                         & scInterpretedSplices .~ splices

-------------------------------------------------------------------------------
-- | Display an info message on next load of a page
flashInfo :: SnapletLens b SessionManager -> Text -> Handler b b ()
flashInfo session msg = withSession session $ with session $ setInSession "_info" msg


-------------------------------------------------------------------------------
-- | Display an warning message on next load of a page
flashWarning :: SnapletLens b SessionManager -> Text -> Handler b b ()
flashWarning session msg = withSession session $ with session $ setInSession "_warning" msg


-------------------------------------------------------------------------------
-- | Display a success message on next load of a page
flashSuccess :: SnapletLens b SessionManager -> Text -> Handler b b ()
flashSuccess session msg = withSession session $ with session $ setInSession "_success" msg


-------------------------------------------------------------------------------
-- | Display an error message on next load of a page
flashError :: SnapletLens b SessionManager -> Text -> Handler b b ()
flashError session msg = withSession session $ with session $ setInSession "_error" msg


-------------------------------------------------------------------------------
-- | A splice for rendering a given flash notice dirctive.
--
-- Ex: <flash type='warning'/>
-- Ex: <flash type='success'/>
flashSplice :: SnapletLens b SessionManager -> SnapletISplice b
flashSplice session = do
    typ <- liftM (getAttribute "type") getParamNode
    let typ' = maybe "warning" id typ
    let k = T.concat ["_", typ']
    msg <- lift $ withTop session $ getFromSession k
    case msg of
      Nothing -> return []
      Just msg' -> do
        lift $ withTop session $ deleteFromSession k >> commitSession
        callTemplateWithText "_flash" $ do
             "type" MS.## typ'
             "message" MS.## msg'


-------------------------------------------------------------------------------
-- | A compiled splice for rendering a given flash notice dirctive.
--
-- Ex: <flash type='warning'/>
-- Ex: <flash type='success'/>
flashCSplice :: SnapletLens b SessionManager -> SnapletCSplice b
flashCSplice session = do
    n <- getParamNode
    let typ = maybe "warning" id $ getAttribute "type" n
        k = T.concat ["_", typ]
        getVal = lift $ withTop session $ getFromSession k
        ss = do
          "type" MS.## return $ C.yieldPureText typ
          "message" MS.## return $ C.yieldRuntimeText
                              $ liftM (fromMaybe "Flash notice cookie error")
                                getVal
    flashTemplate <- C.withLocalSplices ss mempty (C.callTemplate "_flash")
    return $ C.yieldRuntime $ do
        msg <- getVal
        case msg of
          Nothing -> return mempty
          Just _ -> do
            res <- C.codeGen flashTemplate
            lift $ withTop session $ do
              deleteFromSession k
              commitSession
            return res
