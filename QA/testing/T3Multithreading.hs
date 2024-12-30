{-# LANGUAGE
    DataKinds
  , DeriveAnyClass
  , DeriveGeneric
  , DerivingStrategies
  , TypeApplications
#-}

module T3Multithreading where

-- Internal
import ClickHaskell

-- GHC included
import Control.Concurrent.Async (replicateConcurrently_)
import GHC.Generics (Generic)
import GHC.Stack (HasCallStack)


t3 :: HasCallStack => Connection -> IO ()
t3 connection = do
  replicateConcurrently_ 10000 (
    select
      @ExampleColumns
      @ExampleData
      connection
      (toChType "SELECT * FROM generateRandom('a1 Int64', 1, 10, 2) LIMIT 1")
    )
  print "Multithreading: Ok"

data ExampleData = MkExampleData
  { a1 :: ChInt64
  }
  deriving (Generic)
  deriving anyclass (ReadableFrom (Columns ExampleColumns))


type ExampleColumns =
 '[ Column "a1" ChInt64
  ]