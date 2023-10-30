{-# LANGUAGE
    DataKinds
  , DerivingStrategies
  , OverloadedStrings
  , UndecidableInstances
#-}
{-# OPTIONS_GHC -fprint-potential-instances #-}

module Example where

-- Internal dependencies
import ClickHaskell

-- GHC included libraries imports
import Data.ByteString (ByteString)
import Data.Int        (Int32)
import GHC.Generics    (Generic)


-- 1. Describe table
type ExampleTable =
  Table
    "example"
    '[ DefaultColumn "a1" ChInt64
     , DefaultColumn "a2" (LowCardinality ChString)
     , DefaultColumn "a3" ChDateTime
     , DefaultColumn "a4" ChUUID
     , DefaultColumn "a5" ChInt32
     ]
    '[ ExpectsFiltrationBy '["a1"]
     ]


data ExampleData = ExampleData
  { a1 :: Int64
  , a2 :: ByteString
  , a3 :: Word32
  , a4 :: ChUUID
  , a5 :: Int32
  } deriving (Generic)

instance SelectableFrom ExampleTable ExampleData
instance InsertableInto ExampleTable ExampleData


dataExample :: ExampleData
dataExample = ExampleData
  { a1 = 42
  , a2 = "text"
  , a4 = nilChUUID
  , a3 = 42 
  , a5 = 42 :: Int32
  }


-- >>> showSelect
-- "SELECT a1,a2,a3,a4,a5 FROM example.example WHERE a3=0000000042 AND a2='text' FORMAT TSV"
showSelect :: ByteString
showSelect = renderSelectQuery
  $ constructSelection
    @(InDatabase "example" ExampleTable)
    @(Result ExampleData
      %% EqualTo "a2" Variable
      %% EqualTo "a3" Variable
    )
    (toChType @Word32 42)
    (toChType @ByteString "text")


-- >>> showSelect2
-- "SELECT a1,a2,a3,a4,a5 FROM example.example FORMAT TSV"
showSelect2 :: ByteString
showSelect2 = renderSelectQuery
  $ constructSelection
    @(InDatabase "example" ExampleTable)
    @(Result ExampleData
    )
