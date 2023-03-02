module Ply.Apply (applyParam, (#), applyParamJoin, (#!)) where

import Prelude
import Data.Either (Either(..))
import Contract.PlutusData (class ToData, toData)
import Contract.Scripts (applyArgs)
import Ply.Types (ScriptRole, TypedScript(..), PlyError(..), AsData)
import Ply.TypeList (TyList, Cons)

-- Does not give any optimization as CTL only provides `applyArgs`
-- It can only take `AsData` types because `applyArgs` can only apply
-- Data.
applyParam
  :: forall (role :: ScriptRole) (param :: Type) (paramRest :: TyList Type)
   . ToData param
  => TypedScript role (Cons (AsData param) paramRest)
  -> param
  -> Either PlyError (TypedScript role paramRest)
applyParam (TypedScriptConstr script) p =
  case applyArgs script [ (toData p) ] of
    Right applied -> Right $ TypedScriptConstr applied
    Left err -> Left $ ApplicationError err

infixl 8 applyParam as #

applyParamJoin
  :: forall (role :: ScriptRole) (param :: Type) (paramRest :: TyList Type)
   . ToData param
  => Either PlyError (TypedScript role (Cons (AsData param) paramRest))
  -> param
  -> Either PlyError (TypedScript role paramRest)
applyParamJoin script' p = do
  (TypedScriptConstr script) <- script'
  case applyArgs script [ (toData p) ] of
    Right applied -> Right $ TypedScriptConstr applied
    Left err -> Left $ ApplicationError err

infixl 8 applyParamJoin as #!
