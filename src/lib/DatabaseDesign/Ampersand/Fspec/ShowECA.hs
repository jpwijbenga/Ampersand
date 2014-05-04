{-# OPTIONS_GHC -Wall #-}
module DatabaseDesign.Ampersand.Fspec.ShowECA (showECA) where
   import DatabaseDesign.Ampersand.Fspec.Fspec
--   import DatabaseDesign.Ampersand.Fspec.ShowADL            (ShowADL(..), showPAclause, showREL)

   class ECA a where 
    showECA :: String -> a -> String

   instance ECA ECArule where
    showECA indent er = showECA indent (ecaTriggr er)++ " EXECUTE    -- (ECA rule "
                                                     ++ show (ecaNum er)
                                                     ++ ")"
                                                     ++
                        indent++showECA indent (ecaAction er)
   instance ECA Event where
    showECA _ (On Ins rel) = "ON INSERT Delta IN " ++ showREL rel
    showECA _ (On Del rel) = "ON DELETE Delta FROM " ++ showREL rel

   instance ECA PAclause where
    showECA indent = showPAclause indent
