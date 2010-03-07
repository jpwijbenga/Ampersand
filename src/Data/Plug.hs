{-# OPTIONS_GHC -Wall #-}  
module Data.Plug (Plug(..),Plugs
                 ,SqlField(..)
                 ,SqlType(..)
                 ,showSQL
                 ,field
                 ,PhpValue(..)
                 ,PhpType(..)
                 ,PhpArgs
                 ,PhpReturn(..)
                 ,PhpAction(..)
                 ,iskey
                 ,ActionType(..))
where
  import Adl
  import Collection            (rd)
  import FPA
  import Maybe
  
  type Plugs = [Plug]
  data Plug = PlugSql { plname   :: String
                      , fields   :: [SqlField]
                      , kernel   :: [Concept]   -- for generated plugs, the name is taken from the first concept.
                      , plfpa    :: FPA
                      }
            | PlugPhp { args     :: PhpArgs
                      , returns  :: PhpReturn
                      , function :: PhpAction
                      , phpfile  :: String
                      , plname   :: String 
                      , plfpa    :: FPA
                      } deriving (Show)

  data PhpValue = PhpNull | PhpObject {objectdf::ObjectDef,phptype::PhpType} deriving (Show)
  data PhpType = PhpString | PhpInt | PhpFloat | PhpArray deriving (Show)
  type PhpArgs = [(Int,PhpValue)]
  data PhpReturn = PhpReturn {retval::PhpValue} deriving (Show)
  --DO you need on::[Morphism]? makeFspec sets an empty list
  data PhpAction = PhpAction {action::ActionType, on::[Morphism]} deriving (Show)
  data ActionType = Create | Read | Update | Delete deriving (Show)

  field :: String->Expression->(Maybe SqlType)->Bool->Bool->SqlField
  field nm expr maybeTp nul uniq = Fld { fldname = nm
                                       , fldexpr = expr
                                       , fldtype = typ
                                       , fldnull = nul
                                       , flduniq = uniq
                                       , fldauto = (typ==SQLId) && not nul && uniq && isIdent expr
                                       }
                             where typ = fromMaybe (fldtyp (target expr)) maybeTp
  
  instance Identified PhpValue where
     name p = case p of {PhpNull -> "0"; PhpObject{objectdf=x} -> name x}

  --DESCR -> plugs are sorted to optimize some algoritms. 
  instance Eq Plug where
    x==y = name x==name y
  instance Ord Plug where
    compare x y = compare (name x) (name y)
  
  data SqlField = Fld { fldname     :: String
                      , fldexpr     :: Expression
                      , fldtype     :: SqlType
                      , fldnull     :: Bool -- can there be empty field-values?
                      , flduniq     :: Bool -- are all field-values unique?
                      , fldauto     :: Bool -- is the field auto increment?
                      } deriving (Eq, Show)

  instance Ord SqlField where
    compare a b = compare (fldname a) (fldname b)
  
  data SqlType = SQLChar    Int
               | SQLBlob              -- cannot compare, but can show (as a file)
               | SQLPass              -- password, encrypted: cannot show, but can compare
               | SQLSingle  
               | SQLDouble  
               | SQLText              -- cannot compare, but can show (as a text)
               | SQLuInt    Int
               | SQLsInt    Int
               | SQLId                -- autoincrement integer
               | SQLVarchar Int
               | SQLBool              -- exists y/n
               deriving (Eq, Ord,Show)
  
  showSQL :: SqlType -> String
  showSQL (SQLChar    n) = "CHAR("++show n++")"
  showSQL (SQLBlob     ) = "BLOB"
  showSQL (SQLPass     ) = "VARCHAR(255)"
  showSQL (SQLSingle   ) = "FLOAT" -- todo
  showSQL (SQLDouble   ) = "FLOAT"
  showSQL (SQLText     ) = "TEXT"
  showSQL (SQLuInt    n) = "INT("++show n++") UNSIGNED"
  showSQL (SQLsInt    n) = "INT("++show n++")"
  showSQL (SQLId       ) = "INT"
  showSQL (SQLVarchar n) = "VARCHAR("++show n++")"
  showSQL (SQLBool     ) = "BOOLEAN"
            
  iskey :: SqlField->Bool
  iskey f = flduniq f && not (fldnull f)
  fldtyp :: Concept->SqlType
  fldtyp nm = case name nm of { "BLOB"   -> SQLBlob;
                                "PASS"   -> SQLPass;
                                "STRING" -> SQLVarchar 255;
                                "TEXT"   -> SQLText;
                                _        -> SQLVarchar 255
                              }

  instance Identified Plug where
    name p = plname p

  instance Morphical SqlField where
    concs     f = [target e'|let e'=fldexpr f,isSur e']
    mors      f = (rd.map makeInline.mors.fldexpr) f
    morlist   f = morlist   (fldexpr f)
    decls     f = decls     (fldexpr f)
    closExprs f = closExprs (fldexpr f)
    
  instance Morphical Plug where
    concs     p@PlugSql{} = concs     (fields p)
    concs     PlugPhp{} = []                       -- To be done...
    mors      p@PlugSql{} = mors      (fields p)
    mors      PlugPhp{} = []                       -- To be done...
    morlist   p@PlugSql{} = morlist   (fields p)
    morlist   PlugPhp{} = []                       -- To be done...
    decls     p@PlugSql{} = decls     (fields p)
    decls     PlugPhp{} = []                       -- To be done...
    closExprs p@PlugSql{} = closExprs (fields p)
    closExprs PlugPhp{} = []                       -- To be done...
