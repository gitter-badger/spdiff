#############################################################################
# Configuration section
#############################################################################

-include Makefile.config

VERSION=$(shell cat globals/config.ml |grep version |perl -p -e 's/.*"(.*)".*/$$1/;')

##############################################################################
# Variables
##############################################################################
TARGET=spatch

SRC=flag_cocci.ml cocci.ml testing.ml test.ml main.ml


ifeq ($(FEATURE_PYTHON),1)
PYCMA=pycaml/pycaml.cma
PYDIR=pycaml
PYLIB=dllpycaml_stubs.so
# the following is essential for Coccinelle to compile under gentoo (wierd)
OPTLIBFLAGS=-cclib dllpycaml_stubs.so
else
PYCMA=
PYDIR=
PYLIB=
OPTLIBFLAGS=
endif


SYSLIBS=str.cma unix.cma
LIBS=commons/commons.cma globals/globals.cma\
     ctl/ctl.cma \
     parsing_cocci/cocci_parser.cma parsing_c/parsing_c.cma \
     engine/cocciengine.cma popl09/popl.cma \
     extra/extra.cma $(PYCMA) python/coccipython.cma

MAKESUBDIRS=commons globals menhirlib $(PYDIR) ctl parsing_cocci parsing_c \
 engine popl09 extra python
INCLUDEDIRS=commons commons/ocamlextra globals menhirlib $(PYDIR) ctl \
 parsing_cocci parsing_c engine popl09 extra python

##############################################################################
# Generic variables
##############################################################################

INCLUDES=$(INCLUDEDIRS:%=-I %)

OBJS=    $(SRC:.ml=.cmo)
OPTOBJS= $(SRC:.ml=.cmx)

EXEC=$(TARGET)

##############################################################################
# Generic ocaml variables
##############################################################################

OCAMLCFLAGS= -g -dtypes # -w A

# for profiling add  -p -inline 0
# but 'make forprofiling' below does that for you.
# This flag is also used in subdirectories so don't change its name here.
OPTFLAGS=
# the following is essential for Coccinelle to compile under gentoo
# but is now defined above in this file
#OPTLIBFLAGS=-cclib dllpycaml_stubs.so

# the OPTBIN variable is here to allow to use ocamlc.opt instead of
# ocaml, when it is available, which speeds up compilation. So
# if you want the fast version of the ocaml chain tools, set this var
# or setenv it to ".opt" in your startup script.
OPTBIN= #.opt

OCAMLC=ocamlc$(OPTBIN) $(OCAMLCFLAGS)  $(INCLUDES)
OCAMLOPT=ocamlopt$(OPTBIN) $(OPTFLAGS) $(INCLUDES)
OCAMLLEX=ocamllex #-ml # -ml for debugging lexer, but slightly slower
OCAMLYACC=ocamlyacc -v
OCAMLDEP=ocamldep $(INCLUDES)
OCAMLMKTOP=ocamlmktop -g -custom $(INCLUDES)

# can also be set via 'make static'
STATIC= #-ccopt -static

# can also be unset via 'make purebytecode'
BYTECODE_STATIC=-custom

##############################################################################
# Top rules
##############################################################################
.PHONY: all all.opt opt top clean configure
.PHONY: $(MAKESUBDIRS) $(MAKESUBDIRS:%=%.opt) subdirs subdirs.opt

all:
	$(MAKE) subdirs
	$(MAKE) $(EXEC)

opt:
	$(MAKE) subdirs.opt
	$(MAKE) $(EXEC).opt

all.opt: opt
top: $(EXEC).top

subdirs:
	+for D in $(MAKESUBDIRS); do $(MAKE) $$D ; done

subdirs.opt:
	+for D in $(MAKESUBDIRS); do $(MAKE) $$D.opt ; done

$(MAKESUBDIRS):
	$(MAKE) -C $@ OCAMLCFLAGS="$(OCAMLCFLAGS)" all

$(MAKESUBDIRS:%=%.opt):
	$(MAKE) -C $(@:%.opt=%) OCAMLCFLAGS="$(OCAMLCFLAGS)" all.opt

# commons:
# globals:
# menhirlib:
# parsing_cocci:globals menhirlib
# parsing_c:parsing_cocci
# ctl:globals commons
# engine: parsing_cocci parsing_c ctl
# popl09:engine
# extra: parsing_cocci parsing_c ctl
# pycaml:
# python:pycaml parsing_cocci parsing_c
#
# commons.opt:
# globals.opt:
# menhirlib.opt:
# parsing_cocci.opt:globals.opt menhirlib.opt
# parsing_c.opt:parsing_cocci.opt
# ctl.opt:globals.opt commons.opt
# engine.opt: parsing_cocci.opt parsing_c.opt ctl.opt
# popl09.opt:engine.opt
# extra.opt: parsing_cocci.opt parsing_c.opt ctl.opt
# pycaml.opt:
# python.opt:pycaml.opt parsing_cocci.opt parsing_c.opt

clean::
	set -e; for i in $(MAKESUBDIRS); do $(MAKE) -C $$i clean; done

configure:
	./configure

$(LIBS): $(MAKESUBDIRS)
$(LIBS:.cma=.cmxa): $(MAKESUBDIRS:%=%.opt)

$(OBJS):$(LIBS)
$(OPTOBJS):$(LIBS:.cma=.cmxa)

$(EXEC): $(LIBS) $(OBJS)
	$(OCAMLC) $(BYTECODE_STATIC) -o $@ $(SYSLIBS)  $^

$(EXEC).opt: $(LIBS:.cma=.cmxa) $(OPTOBJS)
	$(OCAMLOPT) $(STATIC) -o $@ $(SYSLIBS:.cma=.cmxa) $(OPTLIBFLAGS)  $^

$(EXEC).top: $(LIBS) $(OBJS)
	$(OCAMLMKTOP) -custom -o $@ $(SYSLIBS) $^

clean::
	rm -f $(TARGET) $(TARGET).opt $(TARGET).top

clean::
	rm -f dllpycaml_stubs.so


.PHONY: tools all configure

tools:
	$(MAKE) -C tools
clean::
	$(MAKE) -C tools clean


static:
	rm -f spatch.opt spatch
	$(MAKE) STATIC="-ccopt -static" spatch.opt
	cp spatch.opt spatch

purebytecode:
	rm -f spatch.opt spatch
	$(MAKE) BYTECODE_STATIC="" spatch


##############################################################################
# Install
##############################################################################

# don't remove DESTDIR, it can be set by package build system like ebuild
install: all
	mkdir -p $(DESTDIR)$(BINDIR)
	mkdir -p $(DESTDIR)$(LIBDIR)
	mkdir -p $(DESTDIR)$(SHAREDIR)
	mkdir -p $(DESTDIR)$(MANDIR)/man1
	cp spatch $(DESTDIR)$(SHAREDIR)
	cp standard.h $(DESTDIR)$(SHAREDIR)
	cp standard.iso $(DESTDIR)$(SHAREDIR)
	cp docs/spatch.1 $(DESTDIR)$(MANDIR)/man1/
	mkdir -p $(DESTDIR)$(SHAREDIR)/python
	cp -a python/coccilib $(DESTDIR)$(SHAREDIR)/python
	cp -f dllpycaml_stubs.so $(DESTDIR)$(LIBDIR)
	cat scripts/spatch.sh | sed "s|SHAREDIR|$(DESTDIR)$(SHAREDIR)|g" > $(DESTDIR)$(BINDIR)/spatch
	@echo ""
	@echo "You can also install spatch by copying the program spatch"
	@echo "(available in this directory) anywhere you want and"
	@echo "give it the right options to find its configuration files."

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/spatch
	rm -f $(DESTDIR)$(LIBDIR)/dllpycaml_stubs.so
	rm -f $(DESTDIR)$(SHAREDIR)/standard.h
	rm -f $(DESTDIR)$(SHAREDIR)/standard.iso
	rm -rf $(DESTDIR)$(SHAREDIR)/python/coccilib
	rm -f $(DESTDIR)$(MANDIR)/man1/spatch.1



version:
	@echo $(VERSION)


##############################################################################
# Package rules
##############################################################################

PACKAGE=coccinelle-$(VERSION)

BINSRC=spatch env.sh env.csh standard.h standard.iso \
       *.txt docs/* \
       demos/foo.* demos/simple.*
#      $(PYLIB) python/coccilib/ demos/printloc.*
BINSRC2=$(BINSRC:%=$(PACKAGE)/%)

TMP=/tmp
OCAMLVERSION=$(shell ocaml -version |perl -p -e 's/.*version (.*)/$$1/;')

# Procedure to do first time:
#  cd ~/release
#  cvs checkout coccinelle
#  cd coccinelle
#  cvs update -d -P
#  touch **/*
#  make licensify
#  remember to comment the -g -dtypes in this Makefile

# Procedure to do each time:
#  cvs update
#  make sure that ocaml is the distribution ocaml of /usr/bin, not ~pad/...
#  modify globals/config.ml
#  cd globals/; cvs commit -m"new version"  (do not commit from the root!)
#  ./configure --without-python
#  make package
#  make website
# Check that run an ocaml in /usr/bin

# To test you can try compile and run spatch from different instances
# like my ~/coccinelle, ~/release/coccinelle, and the /tmp/coccinelle-0.X
# downloaded from the website.

# For 'make srctar' it must done from a clean
# repo such as ~/release/coccinelle. It must also be a repo where
# the scripts/licensify has been run at least once.
# For the 'make bintar' I can do it from my original repo.


package:
	make srctar
	make bintar
	make staticbintar
	make bytecodetar

# I currently pre-generate the parser so the user does not have to
# install menhir on his machine. I also do a few cleanups like 'rm todo_pos'.
# You may have first to do a 'make licensify'.
srctar:
	make clean
	cp -a .  $(TMP)/$(PACKAGE)
	cd $(TMP)/$(PACKAGE); cd parsing_cocci/; make parser_cocci_menhir.ml
	cd $(TMP)/$(PACKAGE); rm todo_pos
	cd $(TMP); tar cvfz $(PACKAGE).tgz --exclude-vcs $(PACKAGE)
	rm -rf  $(TMP)/$(PACKAGE)


bintar: all
	rm -f $(TMP)/$(PACKAGE)
	ln -s `pwd` $(TMP)/$(PACKAGE)
	cd $(TMP); tar cvfz $(PACKAGE)-bin-x86.tgz --exclude-vcs $(BINSRC2)
	rm -f $(TMP)/$(PACKAGE)

staticbintar: all.opt
	rm -f $(TMP)/$(PACKAGE)
	ln -s `pwd` $(TMP)/$(PACKAGE)
	make static
	cd $(TMP); tar cvfz $(PACKAGE)-bin-x86-static.tgz --exclude-vcs $(BINSRC2)
	rm -f $(TMP)/$(PACKAGE)

# add ocaml version in name ?
bytecodetar: all
	rm -f $(TMP)/$(PACKAGE)
	ln -s `pwd` $(TMP)/$(PACKAGE)
	make purebytecode
	cd $(TMP); tar cvfz $(PACKAGE)-bin-bytecode-$(OCAMLVERSION).tgz --exclude-vcs $(BINSRC2)
	rm -f $(TMP)/$(PACKAGE)

clean::
	rm -f $(PACKAGE)
	rm -f $(PACKAGE)-bin-x86.tgz
	rm -f $(PACKAGE)-bin-x86-static.tgz
	rm -f $(PACKAGE)-bin-bytecode-$(OCAMLVERSION).tgz



TOLICENSIFY=ctl engine parsing_cocci popl popl09 python
licensify:
	ocaml tools/licensify.ml
	set -e; for i in $(TOLICENSIFY); do cd $$i; ocaml ../tools/licensify.ml; cd ..; done

# When checking out the source from diku sometimes I have some "X in the future"
# error messages.
fixdates:
	echo do 'touch **/*.*'

#fixCVS:
#	cvs update -d -P
#	echo do 'rm -rf **/CVS'

ocamlversion:
	@echo $(OCAMLVERSION)


##############################################################################
# Pad specific rules
##############################################################################

#TOP=/home/pad/mobile/project-coccinelle
WEBSITE=/home/pad/mobile/homepage/software/project-coccinelle

website:
	cp $(TMP)/$(PACKAGE).tgz                $(WEBSITE)
	cp $(TMP)/$(PACKAGE)-bin-x86.tgz        $(WEBSITE)
	cp $(TMP)/$(PACKAGE)-bin-x86-static.tgz $(WEBSITE)
	cp $(TMP)/$(PACKAGE)-bin-bytecode-$(OCAMLVERSION).tgz   $(WEBSITE)
	rm -f $(WEBSITE)/LATEST* $(WEBSITE)/coccinelle-latest.tgz
	cd $(WEBSITE); touch LATEST_IS_$(VERSION); ln -s $(PACKAGE).tgz coccinelle-latest.tgz


#TXT=$(wildcard *.txt)
syncwiki:
#	unison ~/public_html/wiki/wiki-LFS/data/pages/ docs/wiki/
#	set -e; for i in $(TXT); do unison $$i docs/wiki/$$i; done

darcsweb:
#	@echo pull from ~/public_html/darcs/c-coccinelle and c-commons and lib-xxx

DARCSFORESTS=commons \
 parsing_c parsing_cocci engine

update_darcs:
	darcs pull
	set -e; for i in $(DARCSFORESTS); do cd $$i; darcs pull; cd ..; done

#darcs diff -u
diff_darcs:
	set -e; for i in $(DARCSFORESTS); do cd $$i; darcs diff -u; cd ..; done


##############################################################################
# Developer rules
##############################################################################

test: $(TARGET)
	./$(TARGET) -testall

testparsing:
	./$(TARGET) -D standard.h -parse_c -dir tests/



# -inline 0  to see all the functions in the profile.
# Can also use the profile framework in commons/ and run your program
# with -profile.
forprofiling:
	$(MAKE) OPTFLAGS="-p -inline 0 " opt

clean::
	rm -f gmon.out

tags:
	otags -no-mli-tags -r  .

dependencygraph:
	find  -name "*.ml" |grep -v "scripts" | xargs ocamldep -I commons -I globals -I ctl -I parsing_cocci -I parsing_c -I engine -I popl09 -I extra > /tmp/dependfull.depend
	ocamldot -lr /tmp/dependfull.depend > /tmp/dependfull.dot
	dot -Tps /tmp/dependfull.dot > /tmp/dependfull.ps
	ps2pdf /tmp/dependfull.ps /tmp/dependfull.pdf

##############################################################################
# Misc rules
##############################################################################

# each member of the project can have its own test.ml. this file is
# not under CVS.
test.ml:
	echo "let foo_ctl () = failwith \"there is no foo_ctl formula\"" \
	  > test.ml

beforedepend:: test.ml


#INC=$(dir $(shell which ocaml))
#INCX=$(INC:/=)
#INCY=$(dir $(INCX))
#INCZ=$(INCY:/=)/lib/ocaml
#
#prim.o: prim.c
#	gcc -c -o prim.o -I $(INCZ) prim.c


##############################################################################
# Generic ocaml rules
##############################################################################

.SUFFIXES: .ml .mli .cmo .cmi .cmx

.ml.cmo:
	$(OCAMLC)    -c $<
.mli.cmi:
	$(OCAMLC)    -c $<
.ml.cmx:
	$(OCAMLOPT)  -c $<

.ml.mldepend:
	$(OCAMLC) -i $<

clean::
	rm -f *.cm[iox] *.o *.annot

clean::
	rm -f *~ .*~ *.exe #*#

beforedepend::

depend:: beforedepend
	$(OCAMLDEP) *.mli *.ml > .depend
	set -e; for i in $(MAKESUBDIRS); do $(MAKE) -C $$i depend; done

-include .depend
