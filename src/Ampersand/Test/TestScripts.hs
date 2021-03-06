{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Ampersand.Test.TestScripts (getTestScripts,testAmpersandScripts) where


import Ampersand.Basics
--endswith :: String -> String -> Bool
--endswith a b = drop (length a - length b) a == b



getTestScripts :: RIO env [FilePath]
getTestScripts =
--        fs <- getFiles ".adl" "ArchitectureAndDesign"
--        ss <- getFiles ".adl" $ ".." </> "ampersand-models" </> "Tests" </> "ShouldSucceed"
--        ds <- getFiles ".adl" $ "AmpersandData" </> "FormalAmpersand"
        return [] --enabling these test as a single testcase will stop the sentinel from working. Was: fs ++ ss ++ ds -- ++ models



--data DirContent = DirList [FilePath] [FilePath]  -- files and directories in a directory
--                | DirError IOException               
--data DirData = DirData FilePath DirContent       -- path and content of a directory

testAmpersandScripts :: HasLogFunc env => RIO env ()
testAmpersandScripts = do
    logInfo "Testscripts of this kind are not available."
{-
testAmpersandScripts' :: IO ()
testAmpersandScripts'
 = do 
    walk baseDir $$ myVisitor
 where
    baseDir = ".." </> "ampersand-models"

-- Produces directory data
walk :: FilePath -> Source IO DirData
walk path = do 
    result <- lift $ tryIOError listdir
    case result of
        Right dl
            -> case dl of 
                DirList subdirs _
                 -> do
                     yield (DirData path dl)
                     forM_ subdirs (walk . (path </>))
                DirError err 
                 -> yield (DirData path (DirError err))
        Left err
            -> yield (DirData path (DirError err))

  where
    listdir = do
        entries <- getDirectoryContents path >>= filterHidden
        subdirs <- filterM isDir entries
        files <- filterM isFile entries
        return $ DirList subdirs (filter isRelevant files)
        where 
            isFile entry = doesFileExist (path </> entry)
            isDir entry = doesDirectoryExist (path </> entry)
            filterHidden paths = return $ filter (not.isHidden) paths
            isRelevant f = map toUpper (takeExtension f) `elem` [".ADL"]  
            isHidden dir = head dir == '.'
            
-- Consume directories
myVisitor :: Sink DirData IO ()
myVisitor = addCleanup (\_ -> logInfo "Finished.") $ loop 1
  where
    loop :: Int -> ConduitM DirData a IO ()
    loop n = do
        lift $ say $ ">> " ++ show n
        mr <- await
        case mr of
            Nothing     -> return ()
            Just r      -> lift (process r) >> loop (n + 1)
    process :: DirData -> IO ()
    process (DirData path (DirError err)) = do
        logInfo $ "I've tried to look in " ++ path ++ "."
        logInfo $ "    There was an error: "
        logInfo $ "       " ++ show err

    process (DirData path (DirList dirs files)) = do
        logInfo $ path ++ ". ("++ show (length dirs) ++ " directorie(s) and " ++ show (length files) ++ " relevant file(s):"
        forM_ files (runATest path) 
     
runATest :: FilePath -> FilePath -> IO()
runATest path file =
  catch (runATest' path file) showError
   where 
     showError :: SomeException -> IO()
     showError err
       = do logInfo "***** ERROR: Fatal error was thrown: *****"
            logInfo $ (path </> file)
            logInfo $ show err
            logInfo "******************************************"
        
runATest' :: FilePath -> FilePath -> IO()
runATest' path file = do
       [errs] <- ampersand [path </> file]
       logInfo 
         ( file ++": "++
           case (shouldFail,errs) of
                  (False, []) -> "OK.  => Pass"
                  (False, _ ) -> "Fail => NOT PASSED:"
                  (True , []) -> "Ok.  => NOT PASSED"
                  (True , _ ) -> "Fail => Pass"
         )
       unless shouldFail $ mapM_ logInfo (map show (take 1 errs))  --for now, only show the first error
    where shouldFail = "SHOULDFAIL" `isInfixOf` map toUpper (path </> file)
-} 
