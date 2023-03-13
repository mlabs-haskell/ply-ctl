{ name = "ply-ctl"
, dependencies =
  [ "prelude"
  , "cardano-transaction-lib"
  , "bigints"
  , "aeson"
  , "either"
  , "newtype"
  , "tuples"
  , "arrays"
  ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs"]
}
