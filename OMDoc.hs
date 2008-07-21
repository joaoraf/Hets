{- |
Module      :  $Id: CASL.hs 9333 2007-12-07 10:45:32Z maeder $
Description :  basics of the common algebraic specification language
Copyright   :  (c) Christian Maeder and DFKI Lab Bremen 2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  
Stability   :  provisional
Portability :  portable

The "OMDoc" folder contains the import and epxort functions from CASL to OMDoc
(see <http://www.omdoc.org>).

There is also an instance of "Logic.Logic" (the data for this is
assembled in "OMDoc.Logic_OMDoc"), but this is not complete yet.

The files "OMDocInput.hs" and "OMDocOutput.hs" are the main files responsible for the export and, respectively, import of the CASL files to OMDoc format. These are the central files, which are characterized by the following hierarchical absrtact layers:  

1. CASL Abstract Syntax (which embeddes also the "CASL Text") is the lowest level, responsible for interpreting CASL concepts and syntax.

2. OMDoc Abstract Syntax ( defined in "OMDocInterface.hs" ) is responsbile for representing the OMDoc's logic in an abstract way (with no XML tag deliminters). The communication channel between these 2 first layers is fortified by "OMDocDefs.hs" (deals exclusively with OMDoc namings) and "HetsDefs.hs" (deals with CASL data structures). This layer also communicates with "ATerms" layer via "ATerm.hs"  and "ATC_OMDoc.der.hs" (see "Logic_OMDoc.hs" for details) 

3. XML Abstract Syntax is a middle layer, which adds/removes the OMDoc tag-elements, while preserving and sending the OMDoc contents to the lower layer (via "OMDocXML.hs" which is responsible for XML conversion for OMDoc model (in/out)).

4. OMDoc XML is the top layer, which takes care of the final OMDoc input/or output files. It parses the OMDoc documents via an XML handler (see "XmlHandling.hs" and HXT package for details). 

The "OMDoc" folder also contains some additional files, which are as well used in the transformation: 
"Container.hs" and "Util.hs" - utility functions
"HetsInterface.hspp"  - is a Test function
"KeyDebug.hs" - used in debugging

The "Basic" subdirectory contains the CASL's basic transformation in OMDoc format.

-}

module OMDoc where
