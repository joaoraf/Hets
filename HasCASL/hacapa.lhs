#!/home/maeder/bin/runhugs

HetCATS/HasCASL/hacapa.lhs
$Id$
Authors: Christian Maeder
Year:    2002
   
test some parsers (and printers)

\begin{code}
module Main where

import ParseItem
import ParseTerm
import PrintAs
import HToken
import RunParsers
import RunStaticAna

main :: IO ()
main = exec lineParser fileParser

lineParser, fileParser :: [(String, HetParser)]
lineParser = [
 ("MixIds", HetParser uninstOpId),
 ("Typenames", HetParser typeId),
 ("Types", HetParser parseType),
 ("Terms", HetParser term),
 ("Typepattern", HetParser typePattern),
 ("Pattern", HetParser pattern),
 ("BasicItems", HetParser basicItems),
 ("Items", HetParser basicSpec)]

fileParser = [("BasicSpec", HetParser basicSpec),
	     ("analysis", HetParser anaParser)]
\end{code}
