{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}

module Snap.Snaplet.Auth.Types where

------------------------------------------------------------------------------
import           Control.Applicative
import           Control.Monad.CatchIO
import           Control.Monad.Trans.Error
import           Crypto.PasswordStore
import           Data.Aeson
import           Data.ByteString       (ByteString)
import           Data.HashMap.Strict   (HashMap)
import qualified Data.HashMap.Strict   as HM
import           Data.Hashable         (Hashable)
import           Data.Time
import           Data.Text             (Text)
import           Data.Typeable


------------------------------------------------------------------------------
-- | Password is clear when supplied by the user and encrypted later when
-- returned from the db.
data Password = ClearText ByteString
              | Encrypted ByteString
  deriving (Read, Show, Ord, Eq)


------------------------------------------------------------------------------
-- | Default strength level to pass into makePassword.
defaultStrength :: Int
defaultStrength = 12


-------------------------------------------------------------------------------
-- | The underlying encryption function, in case you need it for
-- external processing.
encrypt :: ByteString -> IO ByteString
encrypt = flip makePassword defaultStrength


------------------------------------------------------------------------------
-- | Turn a 'ClearText' password into an 'Encrypted' password, ready to
-- be stuffed into a database.
encryptPassword :: Password -> IO Password
encryptPassword p@(Encrypted {}) = return p
encryptPassword (ClearText p)    = Encrypted `fmap` encrypt p 


------------------------------------------------------------------------------
checkPassword :: Password -> Password -> Bool
checkPassword (ClearText pw) (Encrypted pw') = verifyPassword pw pw'
checkPassword (ClearText pw) (ClearText pw') = pw == pw'
checkPassword (Encrypted pw) (Encrypted pw') = pw == pw'
checkPassword _ _ =
  error "checkPassword failed. Make sure you pass ClearText passwords"


------------------------------------------------------------------------------
-- | Authentication failures indicate what went wrong during authentication.
-- They may provide useful information to the developer, although it is
-- generally not advisable to show the user the exact details about why login
-- failed.
data AuthFailure = UserNotFound
                 | IncorrectPassword
                 | PasswordMissing
                 | LockedOut UTCTime    -- ^ Locked out until given time
                 | AuthError String
  deriving (Read, Show, Ord, Eq, Typeable)

instance Exception AuthFailure

instance Error AuthFailure where
    strMsg = AuthError

------------------------------------------------------------------------------
-- | Internal representation of a 'User'. By convention, we demand that the
-- application is able to directly fetch a 'User' using this identifier.
--
-- Think of this type as a secure, authenticated user. You should normally
-- never see this type unless a user has been authenticated.
newtype UserId = UserId { unUid :: Text }
  deriving ( Read, Show, Ord, Eq, FromJSON, ToJSON, Hashable )


------------------------------------------------------------------------------
-- | This will be replaced by a role-based permission system.
data Role = Role ByteString
  deriving (Read, Show, Ord, Eq)


------------------------------------------------------------------------------
-- | Type representing the concept of a User in your application.
data AuthUser = AuthUser
    { userId               :: Maybe UserId
    , userLogin            :: Text
    , userPassword         :: Maybe Password
    , userActivatedAt      :: Maybe UTCTime
    , userSuspendedAt      :: Maybe UTCTime
    , userRememberToken    :: Maybe Text
    , userLoginCount       :: Int
    , userFailedLoginCount :: Int
    , userLockedOutUntil   :: Maybe UTCTime
    , userCurrentLoginAt   :: Maybe UTCTime
    , userLastLoginAt      :: Maybe UTCTime
    , userCurrentLoginIp   :: Maybe ByteString
    , userLastLoginIp      :: Maybe ByteString
    , userCreatedAt        :: Maybe UTCTime
    , userUpdatedAt        :: Maybe UTCTime
    , userRoles            :: [Role]
    , userMeta             :: HashMap Text Value
    }
  deriving (Show,Eq)


------------------------------------------------------------------------------
-- | Default AuthUser that has all empty values.
defAuthUser :: AuthUser
defAuthUser = AuthUser
    { userId               = Nothing
    , userLogin            = ""
    , userPassword         = Nothing
    , userActivatedAt      = Nothing
    , userSuspendedAt      = Nothing
    , userRememberToken    = Nothing
    , userLoginCount       = 0
    , userFailedLoginCount = 0
    , userLockedOutUntil   = Nothing
    , userCurrentLoginAt   = Nothing
    , userLastLoginAt      = Nothing
    , userCurrentLoginIp   = Nothing
    , userLastLoginIp      = Nothing
    , userCreatedAt        = Nothing
    , userUpdatedAt        = Nothing
    , userRoles            = []
    , userMeta             = HM.empty
    }


------------------------------------------------------------------------------
-- | Set a new password for the given user. Given password should be
-- clear-text; it will be encrypted into a 'Encrypted'.
setPassword :: AuthUser -> ByteString -> IO AuthUser
setPassword au pass = do
    pw <- Encrypted <$> makePassword pass defaultStrength
    return $! au { userPassword = Just pw }


------------------------------------------------------------------------------
-- | Authetication settings defined at initialization time
data AuthSettings = AuthSettings {
    asMinPasswdLen       :: Int
    -- ^ Currently not used/checked

  , asRememberCookieName :: ByteString
    -- ^ Name of the desired remember cookie

  , asRememberPeriod     :: Maybe Int
    -- ^ How long to remember when the option is used in rest of the API.
    -- 'Nothing' means remember until end of session.

  , asLockout            :: Maybe (Int, NominalDiffTime)
    -- ^ Lockout strategy: ([MaxAttempts], [LockoutDuration])

  , asSiteKey            :: FilePath
    -- ^ Location of app's encryption key
}


------------------------------------------------------------------------------
-- | Default settings for Auth.
--
-- > asMinPasswdLen = 8
-- > asRememberCookieName = "_remember"
-- > asRememberPeriod = Just (2*7*24*60*60) = 2 weeks
-- > asLockout = Nothing
-- > asSiteKey = "site_key.txt"
defAuthSettings :: AuthSettings
defAuthSettings = AuthSettings {
    asMinPasswdLen       = 8
  , asRememberCookieName = "_remember"
  , asRememberPeriod     = Just (2*7*24*60*60)
  , asLockout            = Nothing
  , asSiteKey            = "site_key.txt"
}


------------------------------------------------------------------------------
data BackendError = DuplicateLogin
                  | BackendError String
  deriving (Eq,Show,Read,Typeable)

instance Exception BackendError


                             --------------------
                             -- JSON Instances --
                             --------------------

------------------------------------------------------------------------------
instance ToJSON AuthUser where
  toJSON u = object
    [ "uid"                .= userId                u
    , "login"              .= userLogin             u
    , "pw"                 .= userPassword          u
    , "activated_at"       .= userActivatedAt       u
    , "suspended_at"       .= userSuspendedAt       u
    , "remember_token"     .= userRememberToken     u
    , "login_count"        .= userLoginCount        u
    , "failed_login_count" .= userFailedLoginCount  u
    , "locked_until"       .= userLockedOutUntil    u
    , "current_login_at"   .= userCurrentLoginAt    u
    , "last_login_at"      .= userLastLoginAt       u
    , "current_ip"         .= userCurrentLoginIp    u
    , "last_ip"            .= userLastLoginIp       u
    , "created_at"         .= userCreatedAt         u
    , "updated_at"         .= userUpdatedAt         u
    , "meta"               .= userMeta              u
    ]


------------------------------------------------------------------------------
instance FromJSON AuthUser where
  parseJSON (Object v) = AuthUser
    <$> v .: "uid"
    <*> v .: "login"
    <*> v .: "pw"
    <*> v .: "activated_at"
    <*> v .: "suspended_at"
    <*> v .: "remember_token"
    <*> v .: "login_count"
    <*> v .: "failed_login_count"
    <*> v .: "locked_until"
    <*> v .: "current_login_at"
    <*> v .: "last_login_at"
    <*> v .: "current_ip"
    <*> v .: "last_ip"
    <*> v .: "created_at"
    <*> v .: "updated_at"
    <*> return []
    <*> v .: "meta"
  parseJSON _ = error "Unexpected JSON input"


------------------------------------------------------------------------------
instance ToJSON Password where
  toJSON (Encrypted x) = toJSON x
  toJSON (ClearText _) =
      error "ClearText passwords can't be serialized into JSON"


------------------------------------------------------------------------------
instance FromJSON Password where
  parseJSON = fmap Encrypted . parseJSON
