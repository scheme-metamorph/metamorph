module Parser (
    parseScheme,
    Token(..),
    MetaNode(..)
) 
where

import Control.Monad.State.Lazy
import Data.Data
import Data.Complex

data Token  = Lambda | If | Set | POpen | PClose | Identifier String | Quote | ShortQuote | Integral Int | Rational Int Int
            | Real Double | String String | Complex (Complex Double)  | Bool Bool | Char Char
            | Point | QuasiQuote | ShortQuasiQuote | Unquote | ShortUnquote | UnquoteSplice 
            | ShortUnquoteSplice | Label Integer | LabelRef Integer | Define deriving (Eq, Show) 

data MetaNode = LambdaNode [MetaNode] MetaNode MetaNode 
            | ListNode [MetaNode] | RealAtom Double | IntegralAtom Int | RationalAtom Int Int 
            | StringAtom String | ComplexAtom (Complex Double) | BoolAtom Bool | CharAtom Char 
            | IdentifierAtom String | ApplicationNode MetaNode [MetaNode] 
            | IfNode MetaNode MetaNode MetaNode | SetNode MetaNode MetaNode | DefineNode MetaNode MetaNode 
            deriving (Eq, Show)


parseScheme :: [Token] -> MetaNode
parseScheme st = case runState (parseExpression "Scheme Program")  st of
    (mn, []) -> mn
    (_, t:_) -> error $ "Unexpected token " ++ show t ++  " not allowed in current context"

push :: Token -> State [Token] ()
push t = do
    ts <- get
    put (t:ts)

pull :: String -> State [Token] Token
pull context = do
    ts <- get
    case ts of 
        (t:ts) -> do
            put ts
            return t
        _ -> error $ "Unexpected end of token stream in " ++ context

pullEq :: String -> Token -> State [Token] ()
pullEq context c = do
    ts <- get
    case ts of
        (t:ts) -> do
            put ts
            if  t ==  c then
                return ()
            else
                error $ (show c) ++ "in " ++ context ++ " expected, but not found"
        _ -> error $ "Unexpected end of token stream in " ++ context

peek :: String -> State [Token] Token
peek context = do
    ts <- get
    case ts of
        (t:ts) -> return t 
        _ -> error $ "Unexpected end of token stream in " ++ context 

parseExpression :: String -> State [Token] MetaNode
parseExpression context = do
    t <- peek context
    case t of
        POpen -> parseSyntax
        ShortQuote -> do
            pullEq "Datum" ShortQuote
            parseQuotedDatum
        ShortQuasiQuote -> do
            pullEq "Quasiquoted Datum" ShortQuasiQuote
            parseQuasiQuotedDatum
        _ -> parseAtom

parseSyntax :: State [Token] MetaNode
parseSyntax = do
    pullEq "Syntactic construct" POpen 
    t <- peek "Syntactic construct"
    case t of
        Lambda -> parseLambda
        Define -> parseDefine
        Quote -> parseQuote
        QuasiQuote -> parseQuasiQuote
        If -> parseIf
        Set -> parseSet
        _ -> parseApplication

parseAtom :: State [Token] MetaNode
parseAtom = do 
    t <- pull "Atom"
    case t of  
        Bool b -> return $ BoolAtom b
        String s -> return $ StringAtom s
        Real n -> return $ RealAtom n
        Integral n -> return $ IntegralAtom n
        Rational n m -> return $ RationalAtom n m
        Complex c -> return $ ComplexAtom c
        Identifier i -> return $ IdentifierAtom i
        Quote -> return $ IdentifierAtom "quote"
        Unquote -> return $ IdentifierAtom "unquote"
        QuasiQuote -> return $ IdentifierAtom "quasiquote"
        Set  -> return $ IdentifierAtom "set!"
        Define  -> return $ IdentifierAtom "define"
        _ -> error $ "Unexpected token " ++ show t ++ " not allowed in current context"

parseQuote :: State [Token] MetaNode
parseQuote = do
    pullEq "Quote" Quote
    d <- parseQuotedDatum
    pullEq "Quote" PClose
    return d

parseQuasiQuote :: State [Token] MetaNode
parseQuasiQuote = do
    pullEq "Quasiquote" QuasiQuote
    d <- parseQuasiQuotedDatum
    pullEq "Quasiquote" PClose
    return d

parseLambda :: State [Token] MetaNode
parseLambda = do
    pullEq "Lambda" Lambda
    (c, l) <- parseFormalParameters
    e <- parseExpression "Lambda Body"
    pullEq "Lambda" PClose
    return (LambdaNode c l e) 

parseIf :: State [Token] MetaNode
parseIf = do
    pullEq "If" If
    p <- parseExpression "If Condition"
    a <- parseExpression "If Then Branch"
    b <- parseExpression "If Else Branch"
    pullEq "If" PClose
    return (IfNode p a b)  

parseSet :: State [Token] MetaNode
parseSet = do
    pullEq "Set" Set
    t <- pull "Set"
    case t of 
        (Identifier str) -> do
            e <- parseExpression "Set Body"
            pullEq "Set" PClose
            return (SetNode (IdentifierAtom str) e)
        _ -> error "Expected Identifier as first argument of set"

parseDefine :: State [Token] MetaNode
parseDefine = do
    pullEq "Define" Define
    t <- pull "Define"
    case t of 
        (Identifier str) -> do
            e <- parseExpression "Define Body"
            pullEq "Define" PClose
            return (DefineNode (IdentifierAtom str) e)
        _ -> error "Expected Identifier as first argument of define"


parseApplication :: State [Token] MetaNode
parseApplication = do
    f <- parseExpression "Application"
    arg <- parseArgumentList
    return (ApplicationNode f arg)

parseQuotedDatum :: State [Token] MetaNode
parseQuotedDatum = do
    t <- peek "Datum"
    case t of        
        POpen -> do
            pullEq "Compound Datum" POpen
            ListNode <$> parseQuotedCompoundDatum
        ShortQuote -> parseQuotedShortForm
        ShortUnquote -> parseQuotedShortForm
        ShortQuasiQuote -> parseQuotedShortForm
        _ -> parseAtom

parseQuotedCompoundDatum :: State [Token] [MetaNode]
parseQuotedCompoundDatum = do
    t <- peek "Compound Datum"
    case t of 
        PClose -> do
            pullEq "Compound Datum" PClose
            return []
        _ -> do
            e <- parseQuotedDatum
            es <- parseQuotedCompoundDatum
            return (e:es)

parseQuotedShortForm :: State [Token] MetaNode
parseQuotedShortForm = do
    t <- pull "Quoted Shortform"
    ListNode <$> ((\x -> [(IdentifierAtom (show t)),x]) <$> parseQuotedDatum)

parseQuasiQuotedDatum :: State [Token] MetaNode
parseQuasiQuotedDatum = do
    t <- peek "Quasiquoted Datum"
    case t of        
        POpen -> do
            pullEq "Quasiquoted Datum" POpen 
            t <- peek "Quasiquoted Datum"
            case t of
                Unquote -> parseUnquotedExpression
                _ -> ListNode <$> parseQuasiQuotedCompoundDatum
        ShortUnquote -> do
            pullEq "Unquoted Expression" ShortUnquote
            parseExpression "Unquoted Expression"
        ShortQuote -> parseQuasiQuotedShortForm
        ShortQuasiQuote -> parseQuasiQuotedShortForm
        _ -> parseAtom

parseQuasiQuotedCompoundDatum :: State [Token] [MetaNode]
parseQuasiQuotedCompoundDatum = do
    t <- peek "Quasiquoted Compound Datum"
    case t of 
        PClose -> do
            pullEq "Quasiquoted Compound Datum" PClose
            return []
        _ -> do
            e <- parseQuasiQuotedDatum
            es <- parseQuasiQuotedCompoundDatum
            return (e:es)

parseQuasiQuotedShortForm :: State [Token] MetaNode
parseQuasiQuotedShortForm = do
    t <- pull "Quasiquoted Shortform"
    ListNode <$> ((\x -> [(IdentifierAtom (show t)),x]) <$> parseQuasiQuotedDatum)

parseUnquotedExpression :: State [Token] MetaNode
parseUnquotedExpression = do
    pullEq "Unquoted Expression" Unquote 
    e <- parseExpression "Unquoted Expression"
    pullEq "Unquoted Expression" PClose
    return e

parseArgumentList :: State [Token] [MetaNode]
parseArgumentList = do
    t <- peek "Argumentlist"
    case t of 
        PClose -> do
            pullEq "Argumentlist" PClose
            return []
        _ -> do
            e <- parseExpression "Argument"
            es <- parseArgumentList
            return (e:es)

parseFormalParameters :: State [Token] ([MetaNode], MetaNode)
parseFormalParameters = do
    t <- pull "Formal Paramters"
    case t of
        POpen -> parseFormalParameterList
        Identifier s -> return ([],IdentifierAtom s)  
        _ -> error "Expected parameter list or single parameter in lambda definition"

parseFormalParameterList :: State [Token] ([MetaNode], MetaNode)
parseFormalParameterList = do 
    t <- pull "Formal Paramters"
    case t of 
        PClose -> do
            return ([], IdentifierAtom "")
        Point -> do
            t <- pull "Formal Paramters"
            case t of 
                Identifier str -> do
                    pullEq "Formal Paramters" PClose
                    return ([], IdentifierAtom str)
                _ -> error $ "Expected parameter list or single parameter in lambda definition, not token " ++ show t
        Identifier str -> do
            (is, i) <- parseFormalParameterList
            return ((IdentifierAtom str):is, i)
        _ -> error $ "Expected parameter list or single parameter in lambda definition, not token " ++ show t
                
