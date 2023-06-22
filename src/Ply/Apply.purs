module Ply.Apply (class ApplyParam, applyParam, (##), applyParamJoin, (#!)) where

import Prelude
import Data.Either (Either(..))
import Contract.PlutusData (class ToData, PlutusData, toData)
import Contract.Scripts (applyArgs)
import Ply.Types (ScriptRole, TypedScript(..), PlyError(..), AsData)
import Ply.TypeList (TyList, Cons)

-- Does not give any optimization as CTL only provides `applyArgs`
-- It can only take `AsData` types because `applyArgs` can only apply
-- Data.
class ApplyParam param input | param -> input where
  applyParam
    :: forall (role :: ScriptRole) (paramRest :: TyList Type)
     . TypedScript role (Cons param paramRest)
    -> input
    -> Either PlyError (TypedScript role paramRest)

instance ToData param => ApplyParam (AsData param) param where
  applyParam (TypedScriptConstr script) p =
    case applyArgs script [ (toData p) ] of
      Right applied -> Right $ TypedScriptConstr applied
      Left err -> Left $ ApplicationError err

instance ApplyParam PlutusData PlutusData where
  applyParam (TypedScriptConstr script) p =
    case applyArgs script [ p ] of
      Right applied -> Right $ TypedScriptConstr applied
      Left err -> Left $ ApplicationError err

infixl 8 applyParam as ##

applyParamJoin
  :: forall (role :: ScriptRole) (param :: Type) (paramRest :: TyList Type) (input :: Type)
   . ApplyParam param input
  => Either PlyError (TypedScript role (Cons param paramRest))
  -> input
  -> Either PlyError (TypedScript role paramRest)
applyParamJoin script p = script >>= flip applyParam p

infixl 8 applyParamJoin as #!
