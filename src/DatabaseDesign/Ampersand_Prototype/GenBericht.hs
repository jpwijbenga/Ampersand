module DatabaseDesign.Ampersand_Prototype.GenBericht where

import Prelude hiding (writeFile)
import Data.List
import Text.CSV
import System.FilePath
import System.Directory
import Control.Monad
import DatabaseDesign.Ampersand.ADL1
import DatabaseDesign.Ampersand.Basics
import DatabaseDesign.Ampersand.Misc
import DatabaseDesign.Ampersand.Fspec
import DatabaseDesign.Ampersand.Core.AbstractSyntaxTree

-- TODO: only show Rel and Flp Rel? give error otherwise?
--       what about Typ, Brk etc.?

doGenBericht :: Fspc -> Options -> IO ()
doGenBericht fSpec opts =
 do { verboseLn opts "Generating 'Berichtendefinities'..."
    ; createDirectoryIfMissing True $ combine (dirPrototype opts) "Berichten"
    ; let berichtenCSV = genBerichtInterfaces $ interfaceS fSpec
    ; when (development opts) $ verboseLn opts $ layout berichtenCSV
    ; genFile "Berichten/Berichten.csv" $ printSemicolonSeparated berichtenCSV
    }
 where genFile filename contents = 
        do { writeFile (combine (dirPrototype opts) filename) contents
           ; verboseLn opts $ "\nGenerated file "++filename
           }
           
genBerichtInterfaces :: [Interface] -> CSV
genBerichtInterfaces interfaces = ["Naam", "Card.", "Definitie", "Type"] :
                                  concatMap genBerichtInterface interfaces

genBerichtInterface :: Interface -> CSV
genBerichtInterface interface = genBerichtObjDef (ifcObj interface) ++ [["","","",""]]

genBerichtObjDef :: ObjectDef -> CSV
genBerichtObjDef objDef = 
    [ name objDef
    , card $ objctx objDef
    , def $ objctx objDef 
    , name (target $ objctx objDef)
    ] :
    case objmsub objDef of
      Nothing -> []
      Just (InterfaceRef name) -> [["INTERFACEREF "++name,"","",""]]
      Just (Box objs) -> indentHead 1 $ concatMap genBerichtObjDef objs           
 where card e = (if isTot e then "1" else "0")++".."++(if isUni e then "1" else "*")
       
       def (ERel (Rel{reldcl=Sgn{decMean=meaning}}))        = showMeaning meaning
       def (EFlp (ERel (Rel{reldcl=Sgn{decMean=meaning}}))) = "~ "++showMeaning meaning
       def _                                         = "meaningless"
       
       showMeaning meaning = concat [ aMarkup2String m | m@A_Markup{amLang=Dutch} <- ameaMrk meaning ]

indentHead i lines = [((concat $ replicate i ". ")++c1):line | (c1:line) <- lines]

-- Utils

layout :: [[String]] -> String
layout lines = 
  let columns = transpose lines
      widths = map (sum . map length) columns
      formatColumn col = let width = maximum . map length $ col
                         in  map (fill width) col
  in  unlines . map unwords . transpose . map formatColumn $ columns
 where fill i str = str ++ take (i - length str) (replicate i ' ') 
 
-- Modified version of Text.CSV.printCSV
printSemicolonSeparated :: CSV -> String
printSemicolonSeparated records = unlines (printRecord `map` records)
    where printRecord = concat . intersperse ";" . map printField
          printField f = "\"" ++ concatMap escape f ++ "\""
          escape '"' = "\"\""
          escape x = [x]
 