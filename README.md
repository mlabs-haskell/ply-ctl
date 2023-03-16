# ply-ctl

`ply-ctl` provides Purescripts interfaces for [ply](https://github.com/mlabs-haskell/ply)'s typed-script envelope that is 
specialized for type-safe import, export, and application. 

__Note__, ply-ctl will only work with scripts exported with Ply version `v0.5.0` or later.

## Goals

- Similar API with Haskell `ply` library: Some changes are required to be made; however, general scheme of the 
  API is similar to `ply`. 

- Easy integration of custom types: User can add any custom type with `FromData` and `ToData` instance to work
  flawlessly with application. 

- Full type safety of `ply` in Purescripts: Checks every parameters and applications. 

## Dependency

Add following to `packages.dhall` to use `ply-ctl` with spago.

```dhall
ply-ctl =
{ dependencies =
  [ "effect"
  , "prelude"
  , "cardano-transaction-lib"
  , "bigints"
  , "aeson"
  , "either"
  , "newtype"
  , "node-buffer"
  , "node-fs"
  , "tuples"
  , "arrays"
  , "uint"
  , "node-process"
  , "integers"
  ]
, repo = "https://github.com/mlabs-haskell/ply-ctl.git"
, version = "v1.0.0"
}
```		

## Limitaiton

Due to limitation on CTL's `applyArgs` function, __only data encoded values can be applied__. The type of given value
must have `ToData` instance and `ply-ctl` will apply after converting value to `Data`. The scripts, as a result, needs to 
have `Data` or `AsData a` as it's parameter. For example, below, `badScripts` does not encode its parameters in `PAsData` 
thus `ply-ctl` is not able to apply. `goodScript` is how it should be. However, this will be notified by the type system and `ply-ctl` will disallow any unsafe application. 

```hs
badScript :: Term s (PInteger :--> PValue :--> PValidator)

goodScript :: Term s (PAsData PInteger :--> PAsData PValue :--> PValidator)
```

## Example

[Agora](https://github.com/Liqwid-Labs/agora/blob/271ce9cee0f35af7004b95445ac3b43540b2aa6a/agora/Agora/Bootstrap.hs#L56)
uses `ply` for script exportation and importation on Purescript offchain contracts. Because offchain is not open source, 
here are some snippets.

This is one of validator Agora needs to export to offchain contract. `ply-plutrach` will encode its types automatically.
Note, all parameters are wrapped in `PAsData` so they are all compatible with `ply-ctl`. `PTagged` and `PAssetClass` are 
custom types that are not defined by CTL. User must define `FromData`, `ToData`, `PlyTypeName` instance in Purescript for
each custom types. `FromData` and `ToData` instances in Purescript should match its counterpart in Haskell to work properly. 
`PlyTypeName` is a lookup-like type class that stores typenames. Since Purescript does not provide runtime typename reflection, 
this must be done manually via this typeclass. 

```hs
proposalValidator ::
  ClosedTerm
    ( PAsData (PTagged "StakeSTTag" PAssetClassData)
        :--> PAsData (PTagged "GovernorSTTag" PCurrencySymbol)
        :--> PAsData (PTagged "ProposalSTTag" PCurrencySymbol)
        :--> PAsData PInteger
        :--> PValidator
    )
	
{-
Along with raw and CBOR encoded hex, these type information will be written to the typed envelope.

"params": [
    "Ply.Core.Types:AsData#Data.Tagged:Tagged#GHC.TypeLits:\"StakeSTTag\"#Plutarch.Extra.AssetClass:AssetClass",
    "Ply.Core.Types:AsData#Data.Tagged:Tagged#GHC.TypeLits:\"GovernorSTTag\"#PlutusLedgerApi.V1.Value:CurrencySymbol",
    "Ply.Core.Types:AsData#Data.Tagged:Tagged#GHC.TypeLits:\"ProposalSTTag\"#PlutusLedgerApi.V1.Value:CurrencySymbol",
    "Ply.Core.Types:AsData#GHC.Num.Integer:Integer"
],
-}
```	

```purs
instance PlyTypeName Tagged where
  plyTypeName _ = "Data.Tagged:Tagged"
  
instance PlyTypeName AssetClass where
  plyTypeName _ = "Plutarch.Extra.AssetClass:AssetClass"
  
-- ToData and FromData instances omitted
    
-- Define type representation of what needs to be imported.
type ProposalValidator =
  TypedScript
    ValidatorRole
    ( Cons (AsData (Tagged (SProxy "StakeSTTag") AssetClass))
        ( Cons (AsData (Tagged (SProxy "GovernorSTTag") CurrencySymbol))
            ( Cons (AsData (Tagged (SProxy "ProposalSTTag") CurrencySymbol))
                ( Cons (AsData BigInt)
                    Nil
                )
            )
        )
    )
		
-- Apply proper parameters to script.	
mkScript = do
	...
	proposalValidator' <-
      raw.proposalValidator
      ## stakePolicyClass
      #! governorPolicyInfo
      #! proposalPolicyInfo
      #! (params.maximumCosigners # UInt.toInt # BigInt.fromInt)
	...
```


  
  
