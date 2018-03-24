module Ampersand.Prototype.ValidateSQL (validateRulesSQL) where

import           Ampersand.Basics
import           Ampersand.ADL1
import           Ampersand.Core.ShowAStruct
import           Ampersand.FSpec
import           Ampersand.Misc
import           Ampersand.Prototype.PHP
import           Data.List
import qualified Data.Set as Set
{-
Validate the generated SQL for all rules in the fSpec, by comparing the evaluation results
with the results from Haskell-based Ampersand rule evaluator. The latter is much simpler and
therefore most likely to be correct in case of discrepancies.
-}

validateRulesSQL :: FSpec -> IO [String]
validateRulesSQL fSpec =
 do { case filter (not . isSignal . fst) (allViolations fSpec) of
         []    -> return()
         viols -> exitWith . ViolationsInDatabase . map stringify $ viols
    ; hSetBuffering stdout NoBuffering

    ; verboseLn (getOpts fSpec)  "Initializing temporary database (this could take a while)"
    ; succes <- createTempDatabase fSpec
    ; if succes 
      then actualValidation 
      else do { putStrLn "Error: Database creation failed. No validation could be done."
              ; return []
              }
    } 
  where
   actualValidation = do
    { let allExps = getAllInterfaceExps fSpec ++
                    getAllRuleExps fSpec ++
                    getAllPairViewExps fSpec ++
                    getAllIdExps fSpec ++
                    getAllViewExps fSpec

    ; verboseLn (getOpts fSpec)  $ "Number of expressions to be validated: "++show (length allExps)
    ; results <- mapM (validateExp fSpec) allExps

    ; case [ ve | (ve, False) <- results] of
        [] -> do { verboseLn (getOpts fSpec) "\nValidation successful.\nWith the provided populations, all generated SQL code has passed validation."
                 ; return []
                 }
        ves -> return $ "Validation error. The following expressions failed validation:"
                      : map showVExp ves
                             
               
    }
stringify :: (Rule,AAtomPairs) -> (String,[String])
stringify (rule,pairs) = (name rule, map f . Set.elems $ pairs )
  where f pair = "("++showValADL (apLeft pair)++", "++showValADL (apRight pair)++")"


-- functions for extracting all expressions from the context

getAllInterfaceExps :: FSpec -> [ValidationExp]
getAllInterfaceExps fSpec = concat [ getObjExps (name ifc) $ ifcObj ifc
                                   | ifc <- interfaceS fSpec ++ interfaceG fSpec ]
 where getObjExps iName objDef = (objExpression objDef, "interface " ++ show iName) :
                                 concatMap (getObjExps iName) (fields objDef)

-- we check the complement of the rule, since that is the expression evaluated in the prototype
getAllRuleExps :: FSpec -> [ValidationExp]
getAllRuleExps fSpec = map getRuleExp . Set.elems $ vrules fSpec `Set.union` grules fSpec
 where getRuleExp rule = (notCpl (formalExpression rule), "rule "++show (name rule))

getAllPairViewExps :: FSpec -> [ValidationExp]
getAllPairViewExps fSpec = concatMap getPairViewExps . Set.elems $ vrules fSpec `Set.union` grules fSpec
 where getPairViewExps r@Ru{rrviol = Just (PairView pvsegs)} =
         [ (expr, "violation view for rule "++show (name r)) | PairViewExp _ _ expr <- pvsegs ]
       getPairViewExps _    = []

getAllIdExps :: FSpec -> [ValidationExp]
getAllIdExps fSpec = concatMap getIdExps $ vIndices fSpec
 where getIdExps identity = [ (objExpression objDef, "identity "++show (name identity))
                            | IdentityExp objDef <- identityAts identity ]

getAllViewExps :: FSpec -> [ValidationExp]
getAllViewExps fSpec = concatMap getViewExps $ vviews fSpec
 where getViewExps view = [ (expr, "view "++show (name view))
                          | ViewExp expr <- map vsmLoad (vdats view) ]

type ValidationExp = (Expression, String)
-- a ValidationExp is an expression together with the place in the context where we
-- obtained it from (e.g. rule/interface/..)
showVExp :: (Expression, String) -> String
showVExp (expr, orig) = "Origin: "++orig++", expression: "++showA expr

-- validate a single expression and report the results
validateExp :: FSpec -> ValidationExp -> IO (ValidationExp, Bool)
validateExp _  vExp@(EDcD{}, _)   = -- skip all simple relations
 do { putStr "."
    ; return (vExp, True)
    }
validateExp fSpec vExp@(expr, orig) =
 do { violationsSQL <- evaluateExpSQL fSpec (tempDbName (getOpts fSpec)) expr
    ; let violationsAmp = [(showValADL (apLeft p), showValADL (apRight p)) | p <- Set.elems $ pairsInExpr fSpec expr]
    ; if sort violationsSQL == sort violationsAmp
      then
       do { putStr "."
          ; return (vExp, True)
          }
      else
       do { putStrLn ""
          ; putStrLn $ "Checking "++orig ++": expression = "++showA expr
          ; putStrLn ""
          ; putStrLn "Mismatch between SQL and Ampersand"
          ; putStrLn $ showVExp vExp
          ; putStrLn "SQL violations:"
          ; print violationsSQL
          ; putStrLn "Ampersand violations:"
          ; print violationsAmp
          ; return (vExp, False)
          }
    }

