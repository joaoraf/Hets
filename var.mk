# to be included by Makefile

## check-programatica convenience target helper vars:
# The URL of the programatica source archive to download if missing. It must be
# a gzippid tar archive, which can be get using wget!
# Don't quote! Space and other shell metcharacters are not allowed!
PROGRAMATICA_SRC_URL ?= \
	http://theo.cs.uni-magdeburg.de/downloads/hets/src/programatica-1.0.0.5.tar.gz
# As an alternative, if you have a local copy of the programatica source
# archive to use.
# Don't quote! Space and other shell metcharacters are not allowed!
PROGRAMATICA_SRC_FILE ?= \
	/data/src/develop/programatica-1.0.0.5.tar.gz
# The local file gets tried first, and if not usable the remote on gets fetched.
# If both are unset or set to an empty string, programatica support is skipped.

GHCVERSION := $(shell ghc --numeric-version)
ifneq ($(findstring 7., $(GHCVERSION)),)
GHC7RTSOPTS := -rtsopts
endif

OSNAME := $(shell uname -s)
OSVERS := $(shell uname -v 2>/dev/null)

ifneq ($(findstring SunOS, $(OSNAME)),)
  TAR = gtar
  PATCH = gpatch
    ifneq ($(findstring Generic, $(OSVERS)),)
      SUNRUNPATH = -optl-R/opt/csw/lib
      FIXED_GLADE = 0
    else
      FIXED_GLADE = 1
    endif
else
  TAR = tar
  PATCH = patch
endif

HC = ghc -optl-s -XTemplateHaskell -threaded $(GHC7RTSOPTS)

HCPKG := ghc-pkg

HAXMLVERSION = $(shell $(HCPKG) latest HaXml)
ifneq ($(findstring HaXml-1.2, $(HAXMLVERSION)),)
HAXML_PACKAGE = -DHAXML
endif
ifneq ($(findstring HaXml-1.20, $(HAXMLVERSION)),)
HAXML_PACKAGE_COMPAT = -DHAXML_COMPAT
endif

TARVERSION = $(shell $(HCPKG) latest tar)
ifneq ($(findstring 0., $(TARVERSION)),)
TAR_PACKAGE = -DTAR_PACKAGE
endif

UNIXVERSION = $(shell $(HCPKG) latest unix)
ifneq ($(findstring 2., $(UNIXVERSION)),)
UNIX_PACKAGE = -DUNIX
endif

GLADEVERSION = $(shell $(HCPKG) latest glade)
ifneq ($(findstring 0.12, $(GLADEVERSION)),)
  GLADE_PACKAGE = -DGTKGLADE $(SUNRUNPATH)
  ifneq ($(FIXED_GLADE),1)
    GLADE_PACKAGE += -DGTK12
  endif
endif
ifneq ($(findstring 0.13, $(GLADEVERSION)),)
GLADE_PACKAGE = -DGTKGLADE $(SUNRUNPATH)
endif

HASKELINEVERSION = $(shell $(HCPKG) latest haskeline)
ifneq ($(findstring 0.6, $(HASKELINEVERSION)),)
HASKELINE_PACKAGE = -DHASKELINE
endif
ifneq ($(findstring 0.7, $(HASKELINEVERSION)),)
HASKELINE_PACKAGE = -DHASKELINE
endif

HEXPATVERSION = $(shell $(HCPKG) latest hexpat)
ifneq ($(findstring 0., $(HEXPATVERSION)),)
HEXPAT_PACKAGE = -DHEXPAT
endif

HTTPVERSION = $(shell $(HCPKG) latest HTTP)
ifneq ($(findstring 4000., $(HTTPVERSION)),)
else
HTTP_PACKAGE = -DNOHTTP
endif

UNIVERSION = $(shell $(HCPKG) latest uni-uDrawGraph)
ifneq ($(findstring 2., $(UNIVERSION)),)
UNI_PACKAGE = -DUNI_PACKAGE
endif

PFE_SETUP_FILE := programatica/tools/Setup.hs
# If programatica src, i.e. Setup.hs et. al. is there ...
PFE_SETUP := $(shell ls -1 $(PFE_SETUP_FILE) 2>/dev/null )
ifneq ($(PFE_SETUP),)
# check for haskell programatica module ...
PROGRAMATICAVERSION = $(shell $(HCPKG) latest programatica)
ifneq ($(findstring 1.0, $(PROGRAMATICAVERSION)),)
# and enable programatica support
PFE_FLAGS := -package programatica -DPROGRAMATICA
else
PFE_FLAGS :=
endif
endif

WAIEXTVERSION = $(shell $(HCPKG) latest wai-extra)
WARPVERSION = $(shell $(HCPKG) latest warp)
HTTPTYPESVERSION = $(shell $(HCPKG) latest http-types)
ifneq ($(findstring -1., $(WARPVERSION)),)
  ifneq ($(findstring -1., $(WAIEXTVERSION)),)
    ifneq ($(findstring .8, $(HTTPTYPESVERSION)),)
      SERVER_FLAG = -DSERVER -DWARP1
    else
      SERVER_FLAG = -DSERVER -DWARP1 -DHTTPTYPES
    endif
  endif
endif
ifneq ($(findstring -2., $(WARPVERSION)),)
  ifneq ($(findstring -2., $(WAIEXTVERSION)),)
  SERVER_FLAG = -DSERVER
  endif
endif
ifneq ($(findstring -3., $(WARPVERSION)),)
  ifneq ($(findstring -3., $(WAIEXTVERSION)),)
  SERVER_FLAG = -DSERVER -DWARP3
  endif
endif

ifneq ($(strip $(UNI_PACKAGE)),)
  ifeq ($(strip $(HTTP_PACKAGE)),)
  TESTTARGETFILES += SoftFOL/tests/CMDL_tests.hs
  endif
endif

ifneq ($(findstring Darwin, $(OSNAME)),)
HASKELINE_PACKAGE :=
GLADE_PACKAGE :=
endif

HC_OPTS_WITHOUTGLADE = $(PARSEC_FLAG) \
  $(TIME_PACKAGE) $(TAR_PACKAGE) $(HTTP_PACKAGE) $(UNIX_PACKAGE) \
  $(UNI_PACKAGE) $(HASKELINE_PACKAGE) $(HEXPAT_PACKAGE) \
  $(PFE_FLAGS) $(SERVER_FLAG) $(HAXML_PACKAGE) $(HAXML_PACKAGE_COMPAT) \
  -DRDFLOGIC -DCASLEXTENSIONS

# for profiling (or a minimal hets) comment out the previous two package lines
# and the $(GLADE_PACKAGE) below

HC_OPTS = $(HC_OPTS_WITHOUTGLADE) $(GLADE_PACKAGE)
