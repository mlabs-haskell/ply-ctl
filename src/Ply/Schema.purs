module Ply.Schema
  ( SchemaDescription(..)
  , TypedBlueprint
  , normalizeSchemaDescription
  ) where

import Prelude

import Aeson (class DecodeAeson, Aeson, JsonDecodeError(..), caseAesonArray, caseAesonObject, caseAesonString, decodeAeson)
import Control.Alternative ((<|>))
import Data.Argonaut as Argo
import Data.Array (sortBy)
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NE
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Generic.Rep (class Generic)
import Data.List (List(..), elem, (:))
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), maybe)
import Data.Show.Generic (genericShow)
import Data.String (Pattern(Pattern), stripPrefix)
import Data.Traversable (traverse)
import Data.TraversableWithIndex (forWithIndex, traverseWithIndex)
import Data.Tuple (Tuple(Tuple), fst, snd)
import Foreign.Object (Object, lookup)

type TypedBlueprint =
  { validators ::
      { title :: String
      , parameters :: Array { schema :: SchemaDescription }
      }
  , definitions :: Map String SchemaDescription
  }

data SchemaDescription
  = SimpleType String
  | ListType SchemaDescription
  | PairType SchemaDescription SchemaDescription
  | DataListType SchemaDescription
  | MapType SchemaDescription SchemaDescription
  | ConstrType (NonEmptyArray (Array SchemaDescription))
  | SchemaRef String

-- ^ Reference to a schema definition from the top-level `definitions` field.

derive instance Eq SchemaDescription
derive instance Generic SchemaDescription _

instance Show SchemaDescription where
  show x = genericShow x

instance DecodeAeson SchemaDescription where
  decodeAeson = caseAesonObject (Left $ Named "SchemaDescription" $ TypeMismatch "Object") $ \obj ->
    refParser obj <|> multiConstrTypeParser obj <|> do
      res <- maybe (Left $ AtKey "dataType" MissingValue) pure $ lookup "dataType" obj
      caseAesonString (Left $ AtKey "Schema.dataType" $ TypeMismatch "String") (lmap (AtKey "Schema.dataType") <<< parseOtherSchema obj) res
    where
    refParser :: Object Aeson -> Either JsonDecodeError SchemaDescription
    refParser obj = assertKey obj "$ref" >>=
      caseAesonString (Left $ AtKey "Schema.$ref" $ TypeMismatch "String") (lmap (AtKey "Schema.$ref") <<< parseRefName)

    parseRefName :: String -> Either JsonDecodeError SchemaDescription
    parseRefName t = maybe (Left $ UnexpectedValue (Argo.fromString t)) (pure <<< SchemaRef) $ stripPrefix refPrefix t

    multiConstrTypeParser :: Object Aeson -> Either JsonDecodeError SchemaDescription
    multiConstrTypeParser obj = assertAnyKey obj "oneOf" "anyOf" >>=
      caseAesonArray (Left $ AtKey "Schema.oneOf" $ TypeMismatch "Array") (lmap (AtKey "Schema.oneOf") <<< parseConstrVariants)

    parseConstrVariants :: Array Aeson -> Either JsonDecodeError SchemaDescription
    parseConstrVariants constrs = do
      ivariants <-
        forWithIndex constrs $ \i ->
          caseAesonObject (Left $ TypeMismatch "Object") $ lmap (AtIndex i) <<< parseConstrVariant
      let
        sortedVariants :: Array (Array SchemaDescription)
        sortedVariants = map snd $ sortBy (comparing fst) ivariants
      case NE.fromArray sortedVariants of
        Nothing -> Left $ AtIndex 0 MissingValue
        Just arr -> pure $ ConstrType arr

    parseConstrVariant :: Object Aeson -> Either JsonDecodeError (Tuple Int (Array SchemaDescription))
    parseConstrVariant obj = do
      res <- assertKey obj "dataType"
      let
        sanityF = caseAesonString (Left $ AtKey "Schema.dataType" $ TypeMismatch "Object") $ \s ->
          unless (s == "constructor") $ Left $ AtKey "Schema.dataType" $ UnexpectedValue $ Argo.fromString s
      sanityF res
      ix :: Int <- assertKey obj "index" >>= decodeAeson
      fields <- assertKey obj "fields" >>=
        caseAesonArray (Left $ AtKey "Schema.constructor[$].fields" $ TypeMismatch "Array") (traverseWithIndex (\i -> lmap (AtIndex i) <<< decodeAeson))
      pure $ Tuple ix (fields)

    parseOtherSchema :: Object Aeson -> String -> Either JsonDecodeError SchemaDescription
    parseOtherSchema obj ident
      | ident `elem` simpleIdents = pure $ SimpleType ident
      | otherwise = case ident of
          "#list" -> do
            res <- assertKey obj "items"
            ListType <$> decodeAeson res
          "#pair" -> do
            res1 <- assertKey obj "left"
            res2 <- assertKey obj "right"
            PairType <$> decodeAeson res1 <*> decodeAeson res2
          "list" -> do
            res <- assertKey obj "items"
            DataListType <$> decodeAeson res
          "map" -> do
            res1 <- assertKey obj "keys"
            res2 <- assertKey obj "values"
            MapType <$> decodeAeson res1 <*> decodeAeson res2
          "constructor" -> do
            -- This is the single variant case.
            fields <- assertKey obj "fields" >>=
              caseAesonArray (Left $ AtKey "Schema.constructor[$].fields" $ TypeMismatch "Array") (traverseWithIndex (\i -> lmap (AtIndex i) <<< decodeAeson))
            pure $ ConstrType $ NE.cons' fields []
          _ -> Left $ TypeMismatch $ "Unrecognized dataType: " <> ident

    simpleIdents :: List String
    simpleIdents = "#integer" : "#bytes" : "#string" : "#unit" : "#boolean" : "integer" : "bytes" : Nil

    assertKey :: Object Aeson -> String -> Either JsonDecodeError Aeson
    assertKey obj key = maybe (Left $ AtKey key MissingValue) pure $ lookup key obj

    assertAnyKey :: Object Aeson -> String -> String -> Either JsonDecodeError Aeson
    assertAnyKey obj key1 key2 = do
      maybe (Left $ AtKey key1 MissingValue) pure $ (lookup key1 obj) <|> (lookup key2 obj)

{- | Resolves all references within given schema (using the given definitions map) and returns the normalized schema.

References are recursively resolved. i.e If a schema retrieved from the definitions map is also a reference, it'll be
resolved further.
-}
normalizeSchemaDescription :: Map String SchemaDescription -> SchemaDescription -> Either String SchemaDescription
normalizeSchemaDescription refMap schema = case schema of
  SimpleType t -> Right $ SimpleType t
  ListType t -> ListType <$> helper t
  PairType t1 t2 -> PairType <$> helper t1 <*> helper t2
  DataListType t -> DataListType <$> helper t
  MapType t1 t2 -> MapType <$> helper t1 <*> helper t2
  ConstrType ts -> ConstrType <$> ttraverse helper ts
  SchemaRef t -> case Map.lookup t refMap of
    Nothing -> Left t
    Just d -> normalizeSchemaDescription refMap d
  where
  ttraverse f = traverse (traverse f)
  helper = normalizeSchemaDescription refMap

refPrefix :: Pattern
refPrefix = Pattern "#/definitions/"
