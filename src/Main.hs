{-# OPTIONS_GHC -Wall #-}
module Main where

import Control.Monad
import Data.List
import Data.Function (on)
import System.FilePath        (replaceExtension,combine)
import System.Exit
import Prelude hiding (putStr,readFile,writeFile)
import Data.GraphViz hiding (addExtension, C)
import DatabaseDesign.Ampersand_Prototype.ObjBinGen    (phpObjInterfaces)
import DatabaseDesign.Ampersand_Prototype.Apps.RAP   (atlas2context, atlas2populations)
import DatabaseDesign.Ampersand_Prototype.Apps.RAPImport
import DatabaseDesign.Ampersand_Prototype.CoreImporter
import DatabaseDesign.Ampersand_Prototype.Version
import DatabaseDesign.Ampersand_Prototype.GenBericht
import DatabaseDesign.Ampersand_Prototype.ValidateSQL (validateRuleSQL)

fatal :: Int -> String -> a
fatal = fatalMsg "Main"

-- TODO: should be cleaned up
main :: IO ()
main
 = do opts <- getOptions
      if showVersion opts || showHelp opts
       then mapM_ putStr (helpNVersionTexts prototypeVersionStr opts)
       else do aCtx <- parseAndTypeCheck opts
               let fspc = makeFspec opts aCtx
               generateProtoStuff opts fspc
  where
  parseAndTypeCheck :: Options -> IO A_Context 
  parseAndTypeCheck opts 
   = do { verboseLn opts "Start parsing...."
        ; pCtxOrErr <- parseContext opts (fileName opts)
        ; case pCtxOrErr of
           Left pErr ->
            do { Prelude.putStrLn $ "Parse error:"
               ; Prelude.putStrLn $ show pErr
               ; exitWith $ ExitFailure 10 
               }
           Right p_context ->  
            do { let importFilename = importfile opts
               ; pPops <- if null importFilename then return [] 
                          else
                           do popsText <- readFile importFilename
                              case fileformat opts of
                                Adl1PopFormat -> parsePopulations popsText opts importFilename
                                Adl1Format -> do verbose opts ("Importing "++importFilename++" in RAP... ")
                                                 imppCtxOrErr <- parseContext opts (importfile opts)
                                                 case imppCtxOrErr of
                                                   (Right imppcx) -> let (aCtxOrErr,_,_) = typeCheck imppcx [] in
                                                                     case aCtxOrErr of
                                                                      Checked a_context  -> importfspec  (makeFspec opts a_context) opts
                                                                      Errors _           -> importfailed imppCtxOrErr opts 
                                                   (Left _)       -> importfailed imppCtxOrErr opts 
               ; verboseLn opts "Type checking..."
               ; let (actxOrErrs,stTypeGraph,condensedGraph) = typeCheck p_context pPops
               ; if typeGraphs opts
                 then do { condensedGraphPath<-runGraphvizCommand Dot condensedGraph Png (replaceExtension ("Condensed_Graph_of_"++baseName opts) ".png")
                         ; putStr ("\n"++condensedGraphPath++" written.")
                         ; stDotGraphPath<-runGraphvizCommand Dot stTypeGraph Png (replaceExtension ("stGraph_of_"++baseName opts) ".png")
                         ; putStr ("\n"++stDotGraphPath++" written.")
                         }
                 else do { putStr "" }
               ; case actxOrErrs of
                  Errors type_errors-> do { Prelude.putStrLn $ "The following type errors were found:\n"
                                          ; Prelude.putStrLn $ intercalate "\n\n" (map show type_errors)
                                          ; exitWith $ ExitFailure 20
                                          }
                  Checked actx      -> return actx
               }
        }

generateProtoStuff :: Options -> Fspc -> IO ()
generateProtoStuff opts fSpec | validateSQL opts =
 do { verboseLn opts "Validating SQL expressions..."
    ; isValid <- validateRuleSQL fSpec opts
    ; when (not isValid) $
        exitWith $ ExitFailure 30
    }
generateProtoStuff opts fSpec | export2adl opts && fileformat opts==Adl1Format =
 do { verboseLn opts "Exporting Atlas DB content to .adl-file..."
    ; cx<-atlas2context fSpec opts
    ; writeFile (combine (dirOutput opts) (outputfile opts)) (showADL cx)
    ; verboseLn opts $ "Context written to " ++ combine (dirOutput opts) (outputfile opts) ++ "."
    }
generateProtoStuff opts fSpec | export2adl opts && fileformat opts==Adl1PopFormat =
 do { verboseLn opts "Exporting Atlas DB content to .pop-file..."
    ; cxstr<-atlas2populations fSpec opts
    ; writeFile (combine (dirOutput opts) (outputfile opts)) cxstr
    ; verboseLn opts $ "Population of context written to " ++ combine (dirOutput opts) (outputfile opts) ++ "."
    }
generateProtoStuff opts fSpec | otherwise        =
 do { verboseLn opts "Generating..."
    ; when (genPrototype opts) $ doGenProto fSpec opts
    ; when (genBericht opts)   $ doGenBericht fSpec opts
    ; case testRule opts of Just ruleName -> ruleTest fSpec opts ruleName
                            Nothing       -> return ()
    ; when ((not . null $ allViolations fSpec) && (development opts || theme opts==StudentTheme)) $
        verboseLn opts "\nWARNING: There are rule violations (see above)."
    ; verboseLn opts "Done."  -- if there are violations, but we generated anyway (ie. with --dev or --theme=student), issue a warning
    }
               
doGenProto :: Fspc -> Options -> IO ()
doGenProto fSpec opts =
 do { verboseLn opts "Checking on rule violations..."
  --  ; let allViolations = violations fSpec
    ; reportViolations (allViolations fSpec)
    
    ; if (not . null) (allViolations fSpec) && not (development opts) && theme opts/=StudentTheme 
      then do { putStrLn "\nERROR: No prototype generated because of rule violations.\n(Compile with --dev to generate a prototype regardless of violations)"
              ; exitWith $ ExitFailure 40
              } 
      else do { verboseLn opts "Generating prototype..."
              ; phpObjInterfaces fSpec opts  
              ; verboseLn opts $ "Prototype files have been written to " ++ dirPrototype opts ++ "."
              ; if test opts then verboseLn opts $ show (vplugInfos fSpec) else verboseLn opts ""
              }
    }
 where reportViolations []    = verboseLn opts "No violations found."
       reportViolations viols =
         let ruleNamesAndViolStrings = [ (name r, show p) | (r,p) <- viols ]
         in  putStrLn $ intercalate "\n"
                          [ "Violations of rule "++show r++":\n"++ concatMap (\(_,p) -> "- "++ p ++"\n") rps 
                          | rps@((r,_):_) <- groupBy (on (==) fst) $ sort ruleNamesAndViolStrings
                          ]


ruleTest :: Fspc -> Options -> String -> IO ()
ruleTest fSpec _ ruleName =
 case [ rule | rule <- grules fSpec ++ vrules fSpec, name rule == ruleName ] of
   [] -> putStrLn $ "\nRule test error: rule "++show ruleName++" not found." 
   (rule:_) -> do { putStrLn $ "\nContents of rule "++show ruleName++ ": "++showADL (rrexp rule)
                  ; putStrLn $ showContents rule
                  ; let ruleComplement = rule { rrexp = ECpl $ EBrk $rrexp rule }
                  ; putStrLn $ "\nViolations of "++show ruleName++" (contents of "++showADL (rrexp ruleComplement)++"):"
                  ; putStrLn $ showContents ruleComplement
                  } 
 where showContents rule = let pairs = [ "("++f++"," ++s++")" | (r,vs) <- allViolations fSpec, r == rule, (f,s) <- vs]
                           in  "[" ++ intercalate ", " pairs ++ "]" 
       
    
