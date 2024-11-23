{-# LANGUAGE OverloadedStrings #-}

module ClickHaskell.DeSerialization where

-- Internal dependencies
import ClickHaskell.Versioning (ProtocolRevision(..), SinceRevision (..), afterRevision)
import ClickHaskell.DbTypes

-- GHC included
import Data.Binary.Get
import Data.Binary.Get.Internal (readN)
import Data.Binary.Put
import Data.Bits (Bits (..))
import Data.ByteString as BS (length, take)
import Data.ByteString.Builder (Builder, word8)
import Data.Coerce (coerce)
import Data.Typeable (Proxy (..))
import GHC.Generics
import GHC.TypeLits (KnownNat, natVal)

-- * Deserialization

class
  Deserializable chType
  where
  default deserialize :: (Generic chType, GDeserializable (Rep chType)) => ProtocolRevision -> Get chType
  deserialize :: ProtocolRevision -> Get chType
  deserialize rev = to <$> gDeserialize rev


-- ** Generics

class GDeserializable f
  where
  gDeserialize :: ProtocolRevision -> Get (f p)

instance
  GDeserializable f
  =>
  GDeserializable (D1 c (C1 c2 f))
  where
  {-# INLINE gDeserialize #-}
  gDeserialize rev = M1 . M1 <$> gDeserialize rev

instance
  GDeserializable (left :*: (right1 :*: right2))
  =>
  GDeserializable ((left :*: right1) :*: right2)
  where
  {-# INLINE gDeserialize #-}
  gDeserialize rev = (\(l :*: (r1 :*: r2)) -> (l :*: r1) :*: r2) <$> gDeserialize rev

instance
  (GDeserializable (S1 metaSel field), GDeserializable right)
  =>
  GDeserializable (S1 metaSel field :*: right)
  where
  {-# INLINE gDeserialize #-}
  gDeserialize rev = (:*:) <$> gDeserialize rev <*> gDeserialize rev

instance
  Deserializable chType
  =>
  GDeserializable (S1 (MetaSel (Just typeName) a b f) (Rec0 chType))
  where
  {-# INLINE gDeserialize #-}
  gDeserialize rev =  M1 . K1 <$> deserialize @chType rev


-- ** Versioning

instance
  ( KnownNat revision
  , Deserializable chType
  )
  =>
  Deserializable (SinceRevision chType revision)
  where
  deserialize rev =
    if rev >= (fromIntegral . natVal) (Proxy @revision)
    then MkSinceRevision <$> deserialize @chType rev
    else pure NotPresented

instance Deserializable ProtocolRevision where
  deserialize rev = coerce <$> deserialize @UVarInt rev


-- ** Database types

instance Deserializable ChUUID where
  deserialize _ = MkChUUID <$> (flip Word128 <$> getWord64le <*> getWord64le)

instance Deserializable ChString where
  deserialize rev = do
    strSize <- fromIntegral <$> deserialize @UVarInt rev
    toChType <$> readN strSize (BS.take strSize)


instance Deserializable ChInt8 where deserialize _ = toChType <$> getInt8
instance Deserializable ChInt16 where deserialize _ = toChType <$> getInt16le
instance Deserializable ChInt32 where deserialize _ = toChType <$> getInt32le
instance Deserializable ChInt64 where deserialize _ = toChType <$> getInt64le
instance Deserializable ChInt128 where deserialize _ = toChType <$> (flip Int128 <$> getWord64le <*> getWord64le)
instance Deserializable ChUInt8 where deserialize _ = toChType <$> getWord8
instance Deserializable ChUInt16 where deserialize _ = toChType <$> getWord16le
instance Deserializable ChUInt32 where deserialize _ = toChType <$> getWord32le
instance Deserializable ChUInt64 where deserialize _ = toChType <$> getWord64le
instance Deserializable ChUInt128 where deserialize _ = toChType <$> (flip Word128 <$> getWord64le <*> getWord64le)
instance Deserializable ChDateTime where deserialize _ = toChType <$> getWord32le
instance Deserializable ChDate where deserialize _ = toChType <$> getWord16le

instance Deserializable UVarInt where
  deserialize _ = go 0 (0 :: UVarInt)
    where
    go i o | i < 10 = do
      byte <- getWord8
      let o' = o .|. ((fromIntegral byte .&. 0x7f) `unsafeShiftL` (7 * i))
      if byte .&. 0x80 == 0 then pure $! o' else go (i + 1) $! o'
    go _ _ = fail "input exceeds varuint size"






-- * Serialization

class Serializable chType
  where
  default serialize :: (Generic chType, GSerializable (Rep chType)) => ProtocolRevision -> chType -> Builder
  serialize :: ProtocolRevision -> chType -> Builder
  serialize rev = gSerialize rev . from


-- ** Versioning

instance
  ( KnownNat revision
  , Serializable chType
  )
  =>
  Serializable (SinceRevision chType revision)
  where
  serialize rev (MkSinceRevision val) = afterRevision @revision rev (serialize rev val)
  serialize rev NotPresented          = afterRevision @revision rev (error "Unexpected error")

instance Serializable ProtocolRevision where
  serialize rev = serialize @UVarInt rev . coerce


-- ** Database types
instance Serializable UVarInt where
  serialize _ = go
    where
    go i
      | i < 0x80 = word8 (fromIntegral i)
      | otherwise = word8 (setBit (fromIntegral i) 7) <> go (unsafeShiftR i 7)

instance Serializable ChString where
  serialize rev str
    =  (serialize @UVarInt rev . fromIntegral . BS.length . fromChType) str
    <> (execPut . putByteString . fromChType) str

instance Serializable ChUUID where serialize _ = execPut . (\(hi, lo) -> putWord64le lo <> putWord64le hi) . fromChType
instance Serializable ChInt8 where serialize _ = execPut . putInt8 . fromChType
instance Serializable ChInt16 where serialize _ = execPut . putInt16le . fromChType
instance Serializable ChInt32 where serialize _ = execPut . putInt32le . fromChType
instance Serializable ChInt64 where serialize _ = execPut . putInt64le . fromChType
instance Serializable ChInt128 where serialize _ = execPut . (\(Int128 hi lo) -> putWord64le lo <> putWord64le hi) . fromChType
instance Serializable ChUInt8 where serialize _ = execPut . putWord8 . fromChType
instance Serializable ChUInt16 where serialize _ = execPut . putWord16le . fromChType
instance Serializable ChUInt32 where serialize _ = execPut . putWord32le . fromChType
instance Serializable ChUInt64 where serialize _ = execPut . putWord64le . fromChType
instance Serializable ChUInt128 where serialize _ = execPut . (\(Word128 hi lo) -> putWord64le lo <> putWord64le hi) . fromChType
instance Serializable ChDateTime where serialize _ = execPut . putWord32le . fromChType
instance Serializable ChDate where serialize _ = execPut . putWord16le . fromChType




-- ** Generics

class GSerializable f
  where
  gSerialize :: ProtocolRevision -> f p -> Builder

instance
  GSerializable f
  =>
  GSerializable (D1 c (C1 c2 f))
  where
  {-# INLINE gSerialize #-}
  gSerialize rev (M1 (M1 re)) = gSerialize rev re

instance
  GSerializable (left1 :*: (left2 :*: right))
  =>
  GSerializable ((left1 :*: left2) :*: right)
  where
  {-# INLINE gSerialize #-}
  gSerialize rev ((l1 :*: l2) :*: r) = gSerialize rev (l1 :*: (l2 :*: r))

instance
  Serializable chType
  =>
  GSerializable (S1 (MetaSel (Just typeName) a b f) (Rec0 chType))
  where
  {-# INLINE gSerialize #-}
  gSerialize rev = serialize rev . unK1 . unM1

instance
  (Serializable chType, GSerializable right)
  =>
  GSerializable (S1 (MetaSel (Just typeName) a b f) (Rec0 chType) :*: right)
  where
  {-# INLINE gSerialize #-}
  gSerialize rev (left :*: right)
    = (serialize rev . unK1 . unM1 $ left) <> gSerialize rev right
