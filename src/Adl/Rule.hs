{-# OPTIONS_GHC -Wall #-}
module Adl.Rule    ( Rule(..),Rules
                   , RuleType(..)
                   , consequent, antecedent, ruleType, normExpr, multRules, rulefromProp, isaRule, ruleviolations)     
where
   import Adl.FilePos                   ( FilePos(..),Numbered(..))
   import Adl.Concept                   ( Concept(..)
                                        , Association(..)
                                        , MorphicId(..),Morphic(..))
   import Adl.MorphismAndDeclaration    ( Morphism(..),Declaration(..),mIs)
   import Adl.Expression                ( Expression(..),notCp)
   import Adl.Pair                      ( Pairs)
   import Adl.Prop
   import Classes.Populated
   import CommonClasses                 ( Identified(..)
                                        , Explained(explain))
                                           
   type Rules = [Rule]
   data Rule =
  -- Ru c antc p cons expla sgn nr pn
        Ru { rrsrt    :: RuleType          -- ^ One of the following:
                                           --    | Implication if this is an implication;
                                           --    | Equivalence if this is an equivalence;
                                           --    | Truth  if this is an ALWAYS expression.
           , rrant    :: Expression        -- ^ Antecedent
           , rrfps    :: FilePos           -- ^ Position in the ADL file
           , rrcon    :: Expression        -- ^ Consequent
--           , r_cpu :: Expressions       -- ^ This is a list of subexpressions, which must be computed.
           , rrxpl    :: String            -- ^ Explanation
           , rrtyp    :: (Concept,Concept) -- ^ Sign of this rule
           , rrdcl    :: Maybe (Prop,Declaration)  -- ^ The property, if this rule originates from a property on a Declaration
           , runum    :: Int               -- ^ Rule number
           , r_pat    :: String            -- ^ Name of pattern in which it was defined.
           , r_usr    :: Bool              -- ^ True if this rule was specified explicitly as a rule in the ADL-script; False if it follows implicitly from the ADL-script and generated by a computer
           , r_sgl    :: Bool              -- ^ True if this is a signal; False if it is an ALWAYS rule
           , srrel    :: Declaration       -- ^ the signal relation
           } deriving (Eq)
   data RuleType = Implication | Equivalence | Truth | Generalization deriving (Eq,Show)

   isaRule :: Rule -> Bool    -- tells whether this rule was declared as an ISA rule
   isaRule Ru{rrfps=FilePos(_,_,str)} = str == "ISA"
   isaRule _ = False

   instance Ord Rule where
    compare r r' = compare (runum r) (runum r')

   instance Show Rule where
    showsPrec _ x =
       case x of
          Ru{rrsrt = Implication   } -> showString$ show(rrant x) ++ " |- " ++ (show$rrcon x)
          Ru{rrsrt = Equivalence   } -> showString$ show(rrant x) ++ " = "  ++ (show$rrcon x)
          Ru{rrsrt = Truth         } -> showString$ show(rrcon x)
          Ru{rrsrt = Generalization} -> showString ""
        
   instance Numbered Rule where
    pos r = rrfps r
    nr r  = runum r

   instance Identified Rule where
    name r = if null (name (srrel r)) then "Rule"++show (runum r) else name (srrel r)
    
   instance Association Rule where
    source r  = fst (rrtyp r)
    target r  = snd (rrtyp r)

   instance Explained Rule where
    explain _ r = rrxpl r         -- TODO: to allow explainations in multiple languages, change to:  explain options d@Sgn{} = etc...

   instance MorphicId Rule where
    isIdent r = isIdent (normExpr r)

   instance Morphic Rule where
    multiplicities _  = []
    flp r = r{rrant = if rrsrt r == Truth
                      then error ("!Fatal (module Rule 110): illegal call to antecedent in flp ("++show r++")")
                      else flp (rrant r)
             ,rrcon = flp (rrcon r)
             ,rrtyp = (target (rrtyp r),source (rrtyp r))
             }
  --  isIdent r = error ("!Fatal (module Rule 116): isIdent not applicable to any rule:\n "++showHS "" r)
    typeUniq r | ruleType r==Truth = typeUniq (antecedent r)
               | otherwise       = typeUniq (antecedent r) && typeUniq (consequent r)
--    isIdent r = isIdent (normExpr r)
    isProp r  = isProp (normExpr r)

    isTrue r  = case ruleType r of
                 Truth       -> isTrue (consequent r)
                 Implication -> isFalse (antecedent r) || isTrue (consequent r)
                 Equivalence -> antecedent r == consequent r
                 Generalization -> error ("!Fatal (module Rule 88): isTrue not defined for a Generalisation.")
    isFalse r = case ruleType r of
                 Truth       -> isFalse (consequent r)
                 Implication -> isTrue (antecedent r) && isFalse (consequent r)
                 Equivalence -> notCp (antecedent r) == consequent r
                 Generalization -> error ("!Fatal (module Rule 93): isFalse not defined for a Generalisation.")
    isNot r   | ruleType r==Truth = isNot (consequent r)
              | otherwise         = False  -- TODO: check correctness!
    isSignal r = r_sgl r

   normExpr :: Rule -> Expression
   normExpr rule
--    | isSignal rule      = v (sign rule)   -- obsolete (seems silly, in retrospect. normExpr should simply produce the expression.)
    | ruleType rule==Truth = consequent rule
    | ruleType rule==Implication = Fu [Cp (antecedent rule), consequent rule]
    | ruleType rule==Equivalence = Fi [ Fu [    antecedent rule , Cp (consequent rule)]
                                      , Fu [Cp (antecedent rule),     consequent rule ]]
    | otherwise          = error("!Fatal (module Rule 138): Cannot make an expression of "++show rule)

   ruleType :: Rule -> RuleType
   ruleType r = rrsrt r

   antecedent :: Rule -> Expression
   antecedent r = case r of
                   Ru{rrsrt = Truth} -> error ("!Fatal (module Rule 148): illegal call to antecedent of rule "++show r)
                   Ru{} -> rrant r
                   
   consequent :: Rule -> Expression
   consequent r = rrcon r

   ruleviolations :: Rule -> Pairs
   ruleviolations (Ru{rrsrt=rtyp,rrant=ant,rrcon=con,rrtyp=t}) 
       | rtyp==Truth = con `contentsnotin` (Tm (V [] t) (-1))  --everything not in con
       | rtyp==Implication = ant `contentsnotin` con 
       | rtyp==Equivalence = ant `contentsnotin` con ++ con `contentsnotin` ant 
       where
       contentsnotin x y = [p|p<-contents x, not$elem p (contents y)]
   ruleviolations _ = []

   multRules :: Declaration -> Rules 
   multRules d@(Sgn{})
     = [rulefromProp p d | p<-multiplicities d, p `elem` [Uni,Tot,Inj,Sur,Sym,Asy,Trn,Rfx]
                         , if source d==target d || p `elem` [Uni,Tot,Inj,Sur] then True else
                           error ("!Fatal (module Rule 120): Property "++show p++" requires equal source and target domains (you specified "++name (source d)++" and "++name (target d)++").") ]
   multRules d = error ("!Fatal (module Rule 121): illegal call to multRules ("++show d++").")
 
   rulefromProp :: Prop -> Declaration -> Rule
   rulefromProp prp d@(Sgn{})
      = Ru { rrsrt = case prp of
                        Uni-> Implication
                        Tot-> Implication
                        Inj-> Implication
                        Sur-> Implication
                        Sym-> Equivalence
                        Asy-> Implication
                        Trn-> Implication
                        Rfx-> Implication
           , rrant = case prp of
                        Uni-> F [flp r,r] 
                        Tot-> i$sign$F [r,flp r]
                        Inj-> F [r,flp r]
                        Sur-> i$sign$F [flp r,r]
                        Sym-> r
                        Asy-> Fi [flp r,r]
                        Trn-> F [r,r]
                        Rfx-> i$sign r 
           , rrfps = pos d
           , rrcon = case prp of
                        Uni-> i$sign$F [flp r,r]
                        Tot-> F [r,flp r]
                        Inj-> i$sign$F [r,flp r]
                        Sur-> F [flp r,r]
                        Sym-> flp r
                        Asy-> i$sign$Fi [flp r,r]
                        Trn-> r
                        Rfx-> r
           , rrxpl = case prp of
                        Sym-> name d++"["++name (source d)++"*"++name (source d)++"] is symmetric."    
                        Asy-> name d++"["++name (source d)++"*"++name (source d)++"] is antisymmetric."
                        Trn-> name d++"["++name (source d)++"*"++name (source d)++"] is transitive."
                        Rfx-> name d++"["++name (source d)++"*"++name (source d)++"] is reflexive."
                        Uni-> name d++"["++name (source d)++"*"++name (target d)++"] is univalent"
                        Sur-> name d++"["++name (source d)++"*"++name (target d)++"] is surjective"
                        Inj-> name d++"["++name (source d)++"*"++name (target d)++"] is injective"
                        Tot-> name d++"["++name (source d)++"*"++name (target d)++"] is total"
           , rrtyp = case prp of
                        Uni-> sign$F [flp r,r]
                        Tot-> sign$F [r,flp r]
                        Inj-> sign$F [r,flp r]
                        Sur-> sign$F [flp r,r]
                        Sym-> h$sign r
                        Asy-> h$sign r
                        Trn-> h$sign r
                        Rfx-> h$sign r
           , rrdcl = Just (prp,d)         -- For traceability: The original property and declaration.
           , runum = 0                    -- Rules will be renumbered after enriching the context
           , r_pat = decpat d             -- For traceability: The name of the pattern. Unknown at this position but it may be changed by the environment.
           , r_usr = False                
           , r_sgl = False                
           , srrel = d{decnm=show prp++name d}
           }
          where
           i (x,y) | x==y = Tm ( mIs x) (-1)
                   | otherwise = error ("!Fatal (module Rule 182): Bad multiplicity rule, the identity must be homogeneous.")
           h (x,y) | x==y = (x,y)
                   | otherwise = error ("!Fatal (module Rule 184): Bad homogeneous rule, the relation must be homogeneous.")
           r = Tm (Mph (name d) (pos d) [] (source d,target d) True d) (-1)
   rulefromProp _ _ = error ("!Fatal (module Rule 186): Properties can only be set on user-defined Declarations.")

{- TODO -> Wordt de isa rule gehandhaaft? Zie ook functie isaRule in Rule.hs
  rulefromgen :: Gen -> Rule
  rulefromgen g
    = Left$Ru
         Implication    -- Implication of Equivalence
         (Tm (mIs spc)(-1)) -- left hand side (antecedent)
         (genfp g)      -- position in source file
         (Tm (mIs gen)(-1)) -- right hand side (consequent)
         []             -- explanation
         (gen,gen)      -- The type
         Nothing        -- This rule was not generated from a property of some declaration.
         0              -- Rule number. Will be assigned after enriching the context
         (genpat g)     -- For traceability: The name of the pattern. Unknown at this position but it may be changed by the environment.
         False          -- This rule was not specified as a rule in the ADL-script, but has been generated by a computer
         False          -- This is not a signal rule
         (Sgn (name gen++"ISA"++name spc) gen gen [] "" "" "" [] "" (genfp g) 0 False False "")        
    where
    spc = (genspc g)
    gen = (gengen g) 
-}

