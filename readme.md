﻿# MK for Apple IIGS / ORCA

## MK Command Description  
  
'MK' takes a file of dependencies (a 'makefile') and decides what commands have to be executed to bring the files up to date.  
  
Syntax:  

    make [-v[ersion]] [-a[ll]] [-e[xecute]] [-noe[xecute]] [-c[ommandfile] filename]  
         [-i[gnore]] [-noi[gnore]] [-t[arget] targetname] [-l[ist]] [filename] [-d] [-o pipeName] [makefilename]

-version  Display version information.  
  
-all  Force MK to 'build' all targets.  All targets are built regardless of whether the time/date information requires it.  
  
-execute  Execute build commands.  Any commands that MK decides must be executed, will be executed.  This switch is on by default.  It is advised that you specify this switch in any case when ever you require this function, as in the future the default setting may change.  
  
-noexecute  Negates the -execute switch.  Prevents any build commands from being executed.  
  
-commandfile  All commands are written to the specified file, and not executed.  Note that this switch negates the -execute switch.  
  
-ignore  Normally, MK will abort a build whenever an error occurs, however by using this switch you may ask MK to ignore any errors that occur as a result of a NON-COMPILE command. Currently, MK recognises a command containing any of the following strings as a compile command:  
  
    COMPILE, CMPL, CMPLG, ASSEMBLE, ASML, ASMLG, ASM  

By default, this switch is set to on, and may only be turned off by the -noignore switch.  It is advised that you specify this switch in any case when ever you require this function, as in the future the default setting may change.  
  
-noignore  Turns off the function invoked by the -ignore switch.  
  
-target  Asks MK to 'MAKE' the specified target.  Note that the target name is case sensitive.  This switch may be used repetitively on the command line.
  
-list  This switch must be used in conjunction with the -target switch.  It asks MK to produce a dependency list for each of the targets specified using the -target switch.

-d  Causes MK to output a bunch of debug information as it does it's work.

-o Tells MK to pipe all output to the specified file.

makefilename  This parameter names the file from which MK reads the target list and the dependencies.  If no value is given to this parameter, then MK will look for the file MAKEFILE in the current directory.

The makefile must be either TXT or SRC.

## MK MakeFile Description  

The 'MakeFile' contains a list of dependencies.  Each dependency has 3 parts, as follows:  

**Target**  The target is the name of a file that is to be the result of one or more commands.  A target has one or more depencencies or sources.
  
**Source**  The source is a file that is associated with a *target* in that whenever MK finds a *Source* with a time/date stamp that is later than the *Target*, MK will flag that *target* as one to be built.  
  
**Commands**  When MK decides to build a *target*, it executes one or more commands that are specified as a part of the dependency.

Commands can cross line boundaries.  This is done by placing a hyphen (-) character at the end of a line.  By doing this MK will concatenate the contents of the next line to the command that was broken.

The syntax of a Dependency is as follows:  
  
    Target Source1 [Source1...SourceN] [= Single Command]|[{ Several Commands }]  
  
For example, the following dependencies form the MAKEFILE for MK itself:
  
    ! A make file to make MK.
	obj/mk
		obj/mk.a {
				link obj/mk obj/ezconst obj/ezmisc obj/ezdates obj/ezstring obj/ezasm keep=obj/mk
			   }
	obj/ezasm.a
	  asm/ezasm.asm
		{ assemble asm/ezasm.asm
		  move -C ezasm.a obj
		  move -C ezasm.root obj
		}
	obj/ezconst.a
	  pas/ezconst.unit
		{ assemble pas/ezconst.unit
		  move -C ezconst.int int
		  move -C ezconst.a obj
		}
	obj/ezstring.a
	  pas/ezstring.unit
		{ assemble pas/ezstring.unit
		  move -C ezstring.int int
		  move -C ezstring.a obj
		}
	obj/ezmisc.a
	  pas/ezmisc.unit
	  obj/ezconst.a
		{ assemble pas/ezmisc.unit
		  move -C ezmisc.int int
		  move -C ezmisc.a obj
		}
	obj/ezdates.a
	  pas/ezdates.unit
	  obj/ezmisc.a
	  obj/ezconst.a
		{ assemble pas/ezdates.unit
		  move -C ezdates.int int
		  move -C ezdates.a obj
		}
	obj/mk.a
	  obj/ezconst.a
	  obj/ezmisc.a
	  obj/ezstring.a
	  obj/ezdates.a
	  obj/ezasm.a
	  pas/mk.pas
		{ assemble pas/mk.pas
		  move -C mk.a obj
		  move -C mk.root obj
		}

The dependencies may be in any order, as MK reads them all in before doing any time/date checking.  
  
Before processing any line of text in the MAKEFILE, MK will trim any leading or trailing spaces from the line, and convert any TAB characters to spaces.  

Comments may be placed in the MAKEFILE at any time, simply be preceding the command with an Exclamation mark (!).

