# MK for Apple IIGS / ORCA

## What is MK?
MK is a simple tool for the Apple IIGS that works in the ORCA shell environment to assist with building your code.

It reads a file (that you write) that describes the relationships between the various files in your codebase (typically called "makefile") and uses that, and the instructions contained therein to decide how to build the code.

It uses the rules in the make file to determine which files have been modified since the last build, so that only those files that need to be built, are built.

## Line Endings
The text and source files in this repository originally used CR line endings, as usual for Apple II text files, but they have been converted to use LF line endings because that is the format expected by Git. If you wish to move them to a real or emulated Apple II and build them there, you will need to convert them back to CR line endings.

If you wish, you can configure Git to perform line ending conversions as files are checked in and out of the Git repository. With this configuration, the files in your local working copy will contain CR line endings suitable for use on an Apple II. To set this up, perform the following steps in your local copy of the Git repository (these should be done when your working copy has no uncommitted changes):

1. Add the following lines at the end of the `.git/config` file:
```
[filter "crtext"]
	clean = LC_CTYPE=C tr \\\\r \\\\n
	smudge = LC_CTYPE=C tr \\\\n \\\\r
```

2. Add the following line to the `.git/info/attributes` file, creating it if necessary:
```
* filter=crtext
```

3. Run the following commands to convert the existing files in your working copy:
```
rm .git/index
git checkout HEAD -- .
```

Alternatively, you can keep the LF line endings in your working copy of the Git repository, but convert them when you copy the files to an Apple II. There are various tools to do this.  One option is `udl`, which is [available][udl] both as a IIGS shell utility and as C code that can be built and used on modern systems.

Another option, if you are using the [GSPlus emulator](https://apple2.gs/plus/) is to host your local repository in a directory that is visible on both your host computer, and the emulator via the excellent [Host FST](https://github.com/ksherlock/host-fst).

[udl]: http://ftp.gno.org/pub/apple2/gs.specific/gno/file.convert/udl.114.shk

## File Types
In addition to converting the line endings, you will also have to set the files to the appropriate file types before building on a IIGS.

So, once you have the files from the repository on your IIGS (or emulator), within the ORCA/M shell, execute the following command on each `build` scripts:

    filetype build src

## Building
To build the library, you will need the ORCA/M environment present.

The shell script "build", once it has the correct filetype, can be executed to build MK in its entirety.

## Installing
One you've build MK, to use it within the ORCA shell easily, you need to do the following:

 1. Copy "mk" to 17/ which is the prefix ORCA uses normally for all of the utility applications.
 2. Copy "mk.doc" to 17/help/mk.  This places the help file in the place ORCA expects to find it when you type in "help mk".
 3. Edit the 15/syscmd file and add the line:

<!-- end of the list -->

    MK         U                Make tool

## Executing
Assuming you've installed it as per the instructions, once you restart the shell, all you should need to do is enter "mk" and it will do the rest.  If you choose not to install it, you can just run the command manually.

## MK Command Description  
  
'MK' takes a file of dependencies (a 'makefile') and decides what commands have to be executed to bring the files up to date.  
  
Syntax:  

    make [-v[ersion]] [-a[ll]] [-e[xecute]] [-noe[xecute]] [-c[ommandfile] filename]  
         [-i[gnore]] [-noi[gnore]] [-t[arget] targetname] [-l[ist]] [filename] [-d] [-o pipeName] [makefilename]

-version  Display version information.  
  
-all  Force MK to 'build' all targets.  All targets are built regardless of whether the time/date information requires it.  
  
-execute  Execute build commands.  Any commands that MK decides must be executed, will be executed.  This switch is on by default.  It is advised that you specify this switch in any case when ever you require this function, as in the future the default setting may change.  
  
-noexecute  Negates the -execute switch.  Prevents any build commands from being executed.  
  
-commandfile  All commands are written to the specified file, and not executed.  Note that this switch negates the -execute switch.  The generated command file will be given the SRC filetype and EXEC auxtype so that it can be executed in the shell easily.
  
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

Comments may be placed in the MAKEFILE at any time, simply be preceding the command with an Semicolon (;).



